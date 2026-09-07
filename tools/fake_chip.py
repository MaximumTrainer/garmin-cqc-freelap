#!/usr/bin/env python3
"""Fake FxChip BLE peripheral, for testing the watch app without transmitters.

Three modes:

    fake_chip.py                                    one rep on Enter (default)
    fake_chip.py --synthetic --reps 60 \\
                 --course S:0;L:30;L:60;F:100       unattended, N reps
    fake_chip.py --replay captures/<date>/cap.tsv   a real capture, original timing

The packet layout here is the mirror of `FreelapProtocol.expectedLength` /
`decodeMessage`. **Change them in the same commit** (AGENTS.md): drift between
the two is a silent test hole, because the fake would keep agreeing with itself.

Everything except the actual advertising is pure and tested in
`tools/tests/test_fake_chip.py`; only `serve()` needs a radio.

Requires Linux + BlueZ and `pip install bless`. macOS cannot do this: CoreBluetooth
will not let a process advertise a custom GATT service with a chosen UUID, so the
watch has nothing to discover. Use a Linux box or a Raspberry Pi.
"""
import argparse
import asyncio
import struct
import sys

# bless is only needed to actually advertise; the packet builders below are
# imported by tools/tests/ on machines (and in CI) that have no BlueZ.
try:
    from bless import BlessServer, GATTCharacteristicProperties, GATTAttributePermissions
except ImportError:
    BlessServer = None

SERVICE = "6E400001-B5A3-F393-E0A9-E50E24DCC9E6"
NOTIFY = "6E400003-B5A3-F393-E0A9-E50E24DCC9E6"
COMMAND = "6E400002-B5A3-F393-E0A9-E50E24DCC9E6"
NAME = "FxChip-TEST"

# One rep on a S:0;L:30;L:60;F:100 course, chip ticks in ms.
REP = [(0, 1), (4120, 2), (7480, 2), (11930, 3)]

CODE_START, CODE_LAP, CODE_FINISH = 1, 2, 3


def build_packet(rep, chip_id=0x1234):
    body = bytes([0xA5, len(rep)]) + struct.pack("<H", chip_id)
    for ticks, code in rep:
        body += struct.pack("<IB", ticks, code)
    return body


def fragments(data, mtu=20):
    return [data[i : i + mtu] for i in range(0, len(data), mtu)]


# ---------------------------------------------------------------- synthetic

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
            raise ValueError(f"unknown transmitter code {letter!r} in {spec!r}")
        out.append((codes[letter], float(distance)))
    if len(out) < 2:
        raise ValueError(f"a course needs at least two transmitters: {spec!r}")
    return out


def synthetic_rep(course, speed_mps=8.0, jitter=0.0, index=0):
    """One rep over `course` at `speed_mps`, as [(ticks_ms, code), ...].

    `jitter` varies the speed per rep so 60 reps are not 60 identical
    timestamps - a decoder bug that keys off "the value changed" would sail
    through otherwise.
    """
    speed = speed_mps + jitter * ((index % 5) - 2) * 0.1
    out = []
    for code, metres in course:
        out.append((int(round(metres / speed * 1000)), code))
    return out


def synthetic_session(course, reps, speed_mps=8.0, jitter=1.0):
    """`reps` packets, each a complete rep."""
    return [build_packet(synthetic_rep(course, speed_mps, jitter, i)) for i in range(reps)]


# ------------------------------------------------------------------ replay

def parse_capture(lines):
    """A tshark TSV export -> [(arrival_seconds, hex), ...].

    Accepts what `tools/decode_capture.py` reads and what the watch's own
    "Dump capture" prints: <time>\\t<handle>\\t<hex>. Lines that are blank, or
    have no payload, are skipped rather than failing the whole replay - a real
    export has plenty of both.
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
    """[(delay_before_this_packet_seconds, bytes), ...].

    The first packet goes out immediately; every later one waits the gap the
    capture recorded, so the watch sees the chip's original fragmentation and
    inter-packet timing rather than a burst as fast as the loop can run.
    """
    schedule = []
    previous = None
    for when, data in capture:
        delay = 0.0 if previous is None else max(0.0, when - previous)
        schedule.append((delay, data))
        previous = when
    return schedule


# ------------------------------------------------------------------ serving

async def notify(server, data, mtu=20, gap=0.03):
    for fragment in fragments(data, mtu):
        server.get_characteristic(NOTIFY).value = bytearray(fragment)
        server.update_value(SERVICE, NOTIFY)
        await asyncio.sleep(gap)


async def serve(args):
    if BlessServer is None:
        sys.exit("pip install bless (and run on Linux with BlueZ)")

    server = BlessServer(name=NAME)
    await server.add_new_service(SERVICE)
    await server.add_new_characteristic(
        SERVICE, NOTIFY,
        GATTCharacteristicProperties.notify | GATTCharacteristicProperties.read,
        None, GATTAttributePermissions.readable)
    await server.add_new_characteristic(
        SERVICE, COMMAND,
        GATTCharacteristicProperties.write, None, GATTAttributePermissions.writeable)
    await server.start()

    if args.replay:
        with open(args.replay) as handle:
            schedule = replay_schedule(parse_capture(handle))
        print(f"Advertising as {NAME}. Replaying {len(schedule)} packet(s) from {args.replay}.")
        for delay, data in schedule:
            await asyncio.sleep(delay)
            await notify(server, data, args.mtu, 0.0)
            print("sent", data.hex(" "))
        print("replay complete")
        return

    if args.synthetic:
        course = parse_course(args.course)
        packets = synthetic_session(course, args.reps, args.speed)
        print(f"Advertising as {NAME}. Sending {len(packets)} rep(s), "
              f"{args.rest}s apart, over {args.course}.")
        for i, packet in enumerate(packets):
            await notify(server, packet, args.mtu)
            print(f"rep {i + 1}/{len(packets)}", packet.hex(" "))
            await asyncio.sleep(args.rest)
        print("session complete")
        return

    print(f"Advertising as {NAME}. Press Enter to send a rep, Ctrl-C to quit.")
    loop = asyncio.get_event_loop()
    while True:
        await loop.run_in_executor(None, sys.stdin.readline)
        packet = build_packet(REP)
        await notify(server, packet, args.mtu)
        print("sent", packet.hex(" "))


def build_parser():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--replay", metavar="CAP.TSV",
                        help="replay a tshark TSV capture with its original timing")
    parser.add_argument("--synthetic", action="store_true",
                        help="send generated reps unattended")
    parser.add_argument("--reps", type=int, default=10, help="reps to send (--synthetic)")
    parser.add_argument("--course", default="S:0;L:30;L:60;F:100",
                        help="course to generate reps over (--synthetic)")
    parser.add_argument("--speed", type=float, default=8.0,
                        help="metres per second (--synthetic)")
    parser.add_argument("--rest", type=float, default=3.0,
                        help="seconds between reps (--synthetic)")
    parser.add_argument("--mtu", type=int, default=20,
                        help="bytes per notification; 20 is the BLE limit")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    asyncio.run(serve(args))


if __name__ == "__main__":
    main()
