#!/usr/bin/env python3
"""Turn a dumped on-watch split log into CSV.

The watch keeps every split of the last session in `Application.Storage`,
independently of the FIT file and at full microsecond precision (issue #19).
**Dump splits** in the idle menu prints it to the Connect IQ console as one
JSON array per line:

    --- freelap splits: 8 row(s), 0 dropped of 8 seen
    [1,0,1,0,0,0.0,0.0,0.0,7920,false]
    [1,1,2,4120000,4120000,30.0,30.0,7.2815,12040,false]
    --- end

Paste that into a file and:

    splits_to_csv.py dump.txt > splits.csv
    splits_to_csv.py dump.txt --out splits.csv

Lines outside the log are ignored, so the console banner, timestamps and
anything else the simulator interleaves can be left in.

Why line-delimited rather than one JSON document: the watch prints a row at a
time instead of building a 200-row string in memory, on a device where that
matters.
"""
import argparse
import csv
import json
import sys

# The columns of SplitEvent.toArray(), in order. Changing that method means
# changing this list, and tools/tests/test_splits_to_csv.py asserts the width.
COLUMNS = [
    "rep",
    "tx_index",
    "tx_code",
    "cum_us",
    "split_us",
    "cum_dist_m",
    "split_dist_m",
    "velocity_mps",
    "est_ms",
    "est_clamped",
]

# fl_tx_idx uses 255 for "the course could not place this crossing"; -1 is what
# the engine holds. Both mean unmatched.
UNMATCHED = {-1, 255}


def parse_dump(lines):
    """Every split row in a console dump, in order.

    A row is a line that is a JSON array of the right width. Anything else -
    the banner, a timestamp, a stray blank - is skipped rather than failing the
    whole file, because a console dump is copied by hand and always has some.
    """
    rows = []
    for line in lines:
        text = line.strip()
        if not text.startswith("["):
            continue
        try:
            row = json.loads(text)
        except ValueError:
            continue
        if isinstance(row, list) and len(row) == len(COLUMNS):
            rows.append(row)
    return rows


def to_records(rows):
    """Rows as dicts, with the awkward values made explicit."""
    out = []
    for row in rows:
        record = dict(zip(COLUMNS, row))
        # An unmatched crossing has no place on the course; leaving 255 in a
        # spreadsheet column called tx_index invites it being averaged.
        if record["tx_index"] in UNMATCHED:
            record["tx_index"] = ""
        # est_ms of 0 means "could not be placed" when the clamp flag is set,
        # and "at session start" when it is not. Only one of those is a time.
        if record["est_clamped"]:
            record["est_ms"] = ""
        record["est_clamped"] = "true" if record["est_clamped"] else "false"
        out.append(record)
    return out


def write_csv(records, handle):
    writer = csv.DictWriter(handle, fieldnames=COLUMNS, lineterminator="\n")
    writer.writeheader()
    for record in records:
        writer.writerow(record)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dump", help="a file containing the console dump")
    parser.add_argument("--out", help="write here instead of stdout")
    args = parser.parse_args(argv)

    with open(args.dump) as handle:
        rows = parse_dump(handle)
    if not rows:
        print(f"no split rows found in {args.dump}", file=sys.stderr)
        return 1

    records = to_records(rows)
    if args.out:
        with open(args.out, "w", newline="") as handle:
            write_csv(records, handle)
        print(f"{len(records)} split(s) -> {args.out}", file=sys.stderr)
    else:
        write_csv(records, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
