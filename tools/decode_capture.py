#!/usr/bin/env python3
"""Read a capture of FxChip advertisements and say what the chip reported.

Input: a capture export with one advertisement per line,

    <epoch>\t<anything>\t<hex payload>

which is what tshark produces, what `tools/fake_chip.py --replay` reads, and
what the watch's own capture dump prints.

Usage:
    decode_capture.py adv.tsv                decode every Freelap frame
    decode_capture.py adv.tsv 3.42 6.87      also hunt for these times

With no times given it decodes each frame at the documented offsets and prints
the rep -- which is what #6 needs: the values MyFreelap displayed have to come
back out of the bytes.

Given times, it also brute-forces every offset where each one could be encoded
as u16/u24/u32, LE/BE, in several units. That search is what this tool was
originally *for*, back when the layout was unknown. It is kept because it is
the honest way to investigate a frame that does not decode: rather than
assuming our offsets are right and the chip is odd, it asks where the number
actually is. If it ever finds a time at an offset the decoder does not use,
the decoder is wrong.
"""
import struct
import sys

import freelap_frame as ff

UNITS = {"us": 1_000_000, "ms": 1000, "1/100s": 100, "1/10ms": 10_000}
FMTS = {"u16le": "<H", "u16be": ">H", "u32le": "<I", "u32be": ">I", "u24le": None}


def candidates(seconds):
    for uname, mult in UNITS.items():
        v = round(seconds * mult)
        for fname, fmt in FMTS.items():
            if fmt is None:  # u24 little endian
                if v < 1 << 24:
                    yield uname, fname, v.to_bytes(3, "little")
            else:
                size = struct.calcsize(fmt)
                if v < 1 << (8 * size):
                    yield uname, fname, struct.pack(fmt, v)


def matches(data, seconds):
    """Every (format, unit, offset) at which `seconds` is encoded in `data`.

    Pure, so the candidate search is testable against a synthetic capture
    whose answer is known by construction (see tools/tests/).
    """
    hits = []
    for uname, fname, needle in candidates(seconds):
        off = data.find(needle)
        while off != -1:
            hits.append((fname, uname, off))
            off = data.find(needle, off + 1)
    return hits


def decode_line(data):
    """One capture payload -> a human-readable rep, or None if not ours."""
    advertisement = ff.decode_advertisement(data)
    if advertisement is None:
        return None
    return "%s lap#%-3d block=%-10d split=%s" % (
        advertisement.chip, advertisement.lap_number, advertisement.block,
        ff.format_time(ff.to_centiseconds(advertisement.split())))


def read_rows(handle):
    """[(epoch, payload), ...], skipping the rows a real export is full of."""
    rows = []
    for line in handle:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or not parts[2].strip():
            continue
        try:
            when = float(parts[0])
            data = bytes.fromhex(parts[2].replace(":", "").replace(" ", "").strip())
        except ValueError:
            continue
        rows.append((when, data))
    return rows


def main(argv=None):
    argv = sys.argv if argv is None else argv
    if len(argv) < 2:
        print(__doc__)
        return 0
    times = [float(x) for x in argv[2:]]

    with open(argv[1], encoding="utf-8") as handle:
        rows = read_rows(handle)

    previous = None
    ours = 0
    for when, data in rows:
        delta = "" if previous is None else "+%.0fms" % ((when - previous) * 1000)
        previous = when
        decoded = decode_line(data)
        if decoded is not None:
            ours += 1
        print("%.3f %9s len=%2d  %s" % (when, delta, len(data), data.hex(" ")))
        if decoded is not None:
            print("        %s" % decoded)
        for seconds in times:
            for fname, uname, off in matches(data, seconds):
                print("        %ss as %s %6s at offset %d" % (seconds, fname, uname, off))

    print("")
    print("%d frame(s), %d from a Freelap chip" % (len(rows), ours))
    return 0


if __name__ == "__main__":
    sys.exit(main())
