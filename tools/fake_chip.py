#!/usr/bin/env python3
"""Fake FxChip BLE, for testing the watch app without a chip or transmitters.

    fake_chip.py --print                            frames as hex, no radio
    fake_chip.py --print --reps 60 \\
                 --course S:0;L:30;L:60;F:100       a whole session
    fake_chip.py --vectors                          Monkey C test vectors
    fake_chip.py --advertise                        broadcast for real (Linux)
    fake_chip.py --replay captures/<date>/adv.tsv   a real capture

The frames come from `freelap_frame.py`, which is also what the watch's decoder
has to agree with -- so the fake cannot drift into agreeing with a decoder that
is wrong, which is the rule in AGENTS.md and the reason the builders live there
rather than here.

The chip broadcasts and never accepts a connection (#8), so this advertises; it
does not serve a GATT profile. Everything except `advertise()` is pure and
tested in `tools/tests/test_fake_chip.py`, and `--print` needs no Bluetooth at
all, which is the mode most of the app's development can use.

**`--advertise` has never been run.** It needs Linux, BlueZ and root, none of
which this was written on. See #27.
"""
import argparse
import sys

import freelap_frame as ff

# The chip's tick is 1/1024 s -- which is why the conversion to hundredths is
# 10.24 rather than a round number. Deriving it here rather than hard-coding
# 1024 keeps the two definitions from drifting apart. Freelap publish the
# chip's *accuracy* as 1/100 s, which is a different and coarser thing.
TICKS_PER_SECOND = 100 * ff.TICKS_PER_CENTISECOND

DEFAULT_COURSE = "S:0;L:30;L:60;F:100"
DEFAULT_PREFIX = "BC"
DEFAULT_CHIP_ID = 9636

# An arbitrary chip uptime for the first crossing of a session. Non-zero on
# purpose: a decoder that forgot to subtract an origin would look perfect with
# a session that started at tick 0.
DEFAULT_EPOCH = 3585

CODE_START, CODE_LAP, CODE_FINISH = 1, 2, 3


def parse_course(spec):
    """"S:0;L:30;F:100" -> [(code, metres), ...].

    Deliberately permissive in the same places Course.mc is: a segment without
    a colon is skipped. Unlike Course.mc it does not validate ordering - the
    point of this tool is to be able to send a *wrong* course on purpose.
    """
    codes = {"S": CODE_START, "L": CODE_LAP, "F": CODE_FINISH}
    out = []
    for segment in spec.split(";"):
        if ":" not in segment:
            continue
        letter, _, distance = segment.partition(":")
        letter = letter.strip().upper()
        if letter not in codes:
            raise ValueError("unknown transmitter code %r in %r" % (letter, spec))
        out.append((codes[letter], float(distance)))
    if len(out) < 2:
        raise ValueError("a course needs at least two transmitters: %r" % (spec,))
    return out


def check_against_the_chip(course, speed_mps):
    """Refuse a course or a speed the real chip could not produce.

    A fake that generates what hardware cannot is worse than no fake: every
    test built on it passes and none of them mean anything. All three limits
    below are Freelap's own, published in the FxChip BLE manual and the FAQ.
    """
    if len(course) > ff.MAX_TRANSMITTERS:
        raise ValueError(
            "%d transmitters; the chip stores ten intermediate times, so a "
            "track holds at most %d" % (len(course), ff.MAX_TRANSMITTERS))

    for i in range(1, len(course)):
        gap = course[i][1] - course[i - 1][1]
        if gap < ff.MIN_GAP_M:
            raise ValueError(
                "%.3g m between transmitters %d and %d; the minimum is %g m"
                % (gap, i - 1, i, ff.MIN_GAP_M))
        if speed_mps > 0 and gap / speed_mps < ff.MIN_LEG_SECONDS:
            raise ValueError(
                "%.3g m at %.3g m/s is %.3gs between transmitters %d and %d; "
                "the minimum is %gs"
                % (gap, speed_mps, gap / speed_mps, i - 1, i,
                   ff.MIN_LEG_SECONDS))


def crossing_ticks(course, speed_mps=8.0, jitter=0.0, index=0, epoch=DEFAULT_EPOCH):
    """Absolute chip ticks for each crossing of one rep.

    `jitter` varies the speed per rep so that 60 reps are not 60 identical
    timestamps -- a decoder bug that keys off "the value changed" would sail
    through otherwise.
    """
    speed = speed_mps + jitter * ((index % 5) - 2) * 0.1
    check_against_the_chip(course, speed)
    return [epoch + int(round(metres / speed * TICKS_PER_SECOND))
            for _code, metres in course]


def rep_frames(course, speed_mps=8.0, jitter=0.0, index=0, epoch=DEFAULT_EPOCH,
               prefix=DEFAULT_PREFIX, chip_id=DEFAULT_CHIP_ID, lap_number=0):
    """One rep as (advertisement, scan_response) manufacturer payloads.

    The first crossing is the start, the last is the finish, and everything
    between them goes in the scan response. OFFSET and FROMLAP are both set to
    the start: that is what the vendor's worked example shows for a first lap,
    and whether a real chip accumulates them across reps instead is #5 run C.
    """
    ticks = crossing_ticks(course, speed_mps, jitter, index, epoch)
    start, finish, intermediates = ticks[0], ticks[-1], ticks[1:-1]
    advertisement = ff.build_advertisement(
        prefix, chip_id, lap_number,
        offset=start, from_lap=start, block=finish)
    return advertisement, ff.build_scan_response(intermediates)


def synthetic_session(course, reps, speed_mps=8.0, jitter=1.0, rest_s=3.0,
                      prefix=DEFAULT_PREFIX, chip_id=DEFAULT_CHIP_ID,
                      epoch=DEFAULT_EPOCH):
    """`reps` reps, each starting where the last one finished plus a rest.

    Returns [(advertisement, scan_response), ...]. The chip's counters run on
    across the session even though each rep measures from its own start, which
    is what stops a decoder getting away with assuming an origin of zero.
    """
    out = []
    at = epoch
    for index in range(reps):
        advertisement, scan_response = rep_frames(
            course, speed_mps, jitter, index, at, prefix, chip_id,
            lap_number=index % 256)
        out.append((advertisement, scan_response))
        decoded = ff.decode_advertisement(advertisement)
        at = decoded.block + int(round(rest_s * TICKS_PER_SECOND))
    return out


def describe(advertisement, scan_response, rounding="round"):
    """A human-readable line per rep: what a correct decoder should see."""
    decoded = ff.decode_advertisement(advertisement)
    laps = ff.decode_scan_response(scan_response)
    legs = [ff.format_time(ff.to_centiseconds(t, rounding))
            for t in ff.segments(decoded, laps)]
    total = ff.format_time(ff.to_centiseconds(decoded.split(), rounding))
    return "%s  lap#%-3d total %s  legs %s" % (
        decoded.chip, decoded.lap_number, total, " ".join(legs))


def as_hex(payload):
    return " ".join("%02x" % b for b in payload)


def print_session(session, rounding="round", stream=None):
    """Frames as hex plus the values they decode to, one rep per block.

    `stream` defaults late rather than in the signature: binding sys.stdout at
    import time writes to whatever stdout was then, which ignores any later
    redirect and makes this untestable.
    """
    if stream is None:
        stream = sys.stdout
    for advertisement, scan_response in session:
        stream.write("# %s\n" % describe(advertisement, scan_response, rounding))
        stream.write("AD %s\n" % as_hex(advertisement))
        stream.write("SR %s\n\n" % as_hex(scan_response))


def monkeyc_vectors(session, name="SESSION"):
    """The same frames as Monkey C byte-array literals, for #7's unit tests.

    Generated rather than typed because a vector transcribed by hand is a
    vector that can disagree with the encoder it is meant to check.
    """
    lines = ["// Generated by tools/fake_chip.py --vectors. Do not edit by hand."]
    for index, (advertisement, scan_response) in enumerate(session):
        lines.append("const %s_AD_%d = [%s]b;"
                     % (name, index, ",".join("0x%02x" % b for b in advertisement)))
        lines.append("const %s_SR_%d = [%s]b;"
                     % (name, index, ",".join("0x%02x" % b for b in scan_response)))
    return "\n".join(lines)


# ------------------------------------------------------------------ replay

def parse_capture(lines):
    """A capture export -> [(arrival_seconds, payload), ...].

    Accepts "<time>\\t<something>\\t<hex>", which is what tshark exports, what
    `tools/decode_capture.py` reads and what the watch's own capture dump
    prints. Blank rows, header rows and rows with no payload are skipped
    rather than failing the whole replay -- a real export has plenty of each.
    """
    out = []
    for line in lines:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or not parts[2].strip():
            continue
        try:
            when = float(parts[0])
        except ValueError:
            continue          # a header row
        payload = parts[2].replace(":", "").replace(" ", "").strip()
        try:
            data = bytes.fromhex(payload)
        except ValueError:
            continue
        out.append((when, data))
    return out


def replay_schedule(capture):
    """[(delay_before_this_frame_seconds, payload), ...].

    The first frame goes out immediately; every later one waits the gap the
    capture recorded, so the watch sees the chip's original advertising rate
    and window rather than a burst as fast as the loop can run. That rate is
    exactly what #9 has to cope with.
    """
    schedule = []
    previous = None
    for when, data in capture:
        delay = 0.0 if previous is None else max(0.0, when - previous)
        schedule.append((delay, data))
        previous = when
    return schedule


# ---------------------------------------------------------------- the radio

def advertise(session, window_s=10.0, interval_s=0.1, rest_s=3.0):
    """Broadcast each rep for its advertising window. Linux, BlueZ, root.

    NOT RUN. This is the one part of this tool that needs a radio, and it was
    written on a machine without one. Treat it as a starting point, not as
    working code, and see #27.

    macOS cannot do this at all: CoreBluetooth will not let a process set
    arbitrary manufacturer data or a custom scan response.
    """
    try:
        import dbus  # noqa: F401
    except ImportError:
        raise SystemExit(
            "--advertise needs Linux, BlueZ and python-dbus. On any other "
            "machine use --print, which needs no radio.")
    raise NotImplementedError(
        "The BlueZ LEAdvertisement registration is #27. The frames are ready: "
        "use --print to see exactly what has to go out, as manufacturer data "
        "under company 0x%04x, repeated every %.2gs for %.4gs after each rep."
        % (ff.COMPANY_ID, interval_s, window_s))


# ------------------------------------------------------------------- cli

def build_parser():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--print", dest="show", action="store_true",
                        help="print frames as hex and stop (no Bluetooth needed)")
    parser.add_argument("--vectors", action="store_true",
                        help="print the frames as Monkey C byte arrays")
    parser.add_argument("--advertise", action="store_true",
                        help="actually broadcast (Linux + BlueZ + root)")
    parser.add_argument("--replay", metavar="CAP.TSV",
                        help="replay advertisements from a capture")
    parser.add_argument("--reps", type=int, default=1, help="reps to generate")
    parser.add_argument("--course", default=DEFAULT_COURSE,
                        help="course spec, e.g. %s" % DEFAULT_COURSE)
    parser.add_argument("--speed", type=float, default=8.0, help="m/s")
    parser.add_argument("--jitter", type=float, default=1.0,
                        help="per-rep speed variation; 0 for identical reps")
    parser.add_argument("--rest", type=float, default=3.0,
                        help="seconds between reps")
    parser.add_argument("--chip", default="%s-%d" % (DEFAULT_PREFIX, DEFAULT_CHIP_ID),
                        help="chip id to advertise as, e.g. BC-9636")
    parser.add_argument("--rounding", choices=["round", "truncate"], default="round",
                        help="how to convert ticks for display (see #6)")
    return parser


def parse_chip(text):
    """"BC-9636" -> ("BC", 9636)."""
    prefix, _, digits = text.partition("-")
    if len(prefix) != 2 or not digits.isdigit():
        raise ValueError("a chip id is two letters and a number, e.g. BC-9636: %r"
                         % (text,))
    return prefix.upper(), int(digits)


def main(argv=None):
    args = build_parser().parse_args(argv)
    prefix, chip_id = parse_chip(args.chip)
    course = parse_course(args.course)
    session = synthetic_session(course, args.reps, args.speed, args.jitter,
                                args.rest, prefix, chip_id)

    if args.vectors:
        print(monkeyc_vectors(session))
        return 0
    if args.advertise:
        advertise(session, rest_s=args.rest)
        return 0
    if args.replay:
        with open(args.replay, encoding="utf-8") as handle:
            schedule = replay_schedule(parse_capture(handle))
        print("%d frames to replay; --advertise is #27" % len(schedule))
        return 0

    print_session(session, args.rounding)
    return 0


if __name__ == "__main__":
    sys.exit(main())
