#!/usr/bin/env python3
"""Diff BLE notification captures against known Freelap split times.

Input: a tshark/Wireshark export with one notification per line:
    tshark -r btsnoop_hci.log -Y "btatt.opcode == 0x1b" \
        -T fields -e frame.time_epoch -e btatt.handle -e btatt.value > cap.tsv

Usage:
    decode_capture.py cap.tsv 3.42 6.87
    (the numbers are the split times MyFreelap displayed, in seconds)

For every packet it prints hex, arrival delta, and every offset where one of
the given times appears encoded as u16/u32, LE/BE, in ms, 1/100 s, 1/1000 s
or us. Also flags 20-byte packets (likely fragments).
"""
import struct
import sys

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


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    path = sys.argv[1]
    times = [float(x) for x in sys.argv[2:]]
    prev_t = None
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or not parts[2]:
                continue
            t = float(parts[0])
            handle = parts[1]
            data = bytes.fromhex(parts[2].replace(":", ""))
            delta = "" if prev_t is None else f"+{(t - prev_t) * 1000:.0f}ms"
            prev_t = t
            frag = " FRAG?" if len(data) == 20 else ""
            print(f"{t:.3f} {delta:>9} h={handle} len={len(data):2d}{frag}  {data.hex(' ')}")
            for secs in times:
                for uname, fname, needle in candidates(secs):
                    off = data.find(needle)
                    while off != -1:
                        print(f"        {secs}s as {fname} {uname:>6} at offset {off}")
                        off = data.find(needle, off + 1)


if __name__ == "__main__":
    main()
