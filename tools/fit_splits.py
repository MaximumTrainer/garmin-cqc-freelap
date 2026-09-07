#!/usr/bin/env python3
"""Read a Freelap activity's splits out of a FIT file, as CSV.

The FIT file is the record of what happened. Garmin Connect rounds floats in
its UI, so the microseconds this app exists to preserve are only visible by
reading the file directly.

    fit_splits.py activity.fit                  # CSV to stdout
    fit_splits.py activity.fit --out splits.csv
    fit_splits.py activity.fit --laps           # one row per rep instead
    fit_splits.py activity.fit --summary        # the session totals

The columns are the same names `tools/splits_to_csv.py` produces from the
on-watch log, so the two exports can be diffed against each other - which is
issue #29's round-trip check.

Needs `pip install fitdecode`.
"""
import argparse
import csv
import sys

from fit_fields import field_values

# record-level fl_* fields -> the column names splits_to_csv.py uses, so a FIT
# export and an on-watch export line up column for column.
SPLIT_COLUMNS = [
    ("fl_rep", "rep"),
    ("fl_tx_idx", "tx_index"),
    ("fl_tx_code", "tx_code"),
    ("fl_cum_us", "cum_us"),
    ("fl_split_us", "split_us"),
    ("fl_dist_m", "cum_dist_m"),
    ("fl_velocity", "velocity_mps"),
    ("fl_speed", "speed_kmh"),
    ("fl_pace", "pace_s_per_km"),
    ("fl_est_ms", "est_ms"),
]

LAP_COLUMNS = [
    ("fl_rep_time_us", "rep_time_us"),
    ("fl_rep_dist_m", "rep_dist_m"),
    ("fl_rep_avg_vel", "rep_avg_vel_mps"),
    ("fl_rep_peak_vel", "rep_peak_vel_mps"),
    ("fl_rep_splits", "rep_splits"),
    ("fl_rep_status", "rep_status"),
]

SESSION_COLUMNS = [
    ("fl_reps", "reps"),
    ("fl_best_rep_us", "best_rep_us"),
    ("fl_total_dist_m", "total_dist_m"),
    ("fl_chip_id", "chip_id"),
]

# fl_tx_idx is uint8; the engine's -1 for "the course could not place this
# crossing" is written as 255.
UNMATCHED_TX = 255

# fl_rep_status, from source/model/SplitEngine.mc.
REP_STATUS = {0: "ok", 1: "unmatched", 2: "partial"}


def is_split_record(values):
    """Does this record carry a split, or is it a blank?

    `fl_rep` is the discriminator, and it has to be: the record `clearAfterWrite`
    writes after the last split of a rep sets every field to a zero *or a
    sentinel* - `fl_tx_idx` goes to 255 - so "any field is truthy" says yes to
    it. A real split always belongs to rep 1 or later; the blank is rep 0.

    It also separates a blank from the START crossing, which legitimately has
    `fl_split_us` and `fl_cum_us` of 0 and differs only in `fl_rep`.
    """
    rep = values.get("fl_rep")
    return isinstance(rep, int) and rep >= 1


def _rows(path, message, columns, keep=None):
    out = []
    for name, values in field_values(path):
        if name != message:
            continue
        if keep is not None and not keep(values):
            continue
        if not any(values.get(src) is not None for src, _ in columns):
            continue
        out.append({dst: values.get(src) for src, dst in columns})
    return out


def splits(path):
    """One row per split, in the order they were run."""
    rows = _rows(path, "record", SPLIT_COLUMNS, keep=is_split_record)
    for row in rows:
        if row.get("tx_index") == UNMATCHED_TX:
            # Left as 255 it is a plausible-looking transmitter number.
            row["tx_index"] = ""
    return rows


def laps(path):
    rows = _rows(path, "lap", LAP_COLUMNS)
    for row in rows:
        row["rep_status"] = REP_STATUS.get(row.get("rep_status"), row.get("rep_status"))
    return rows


def summary(path):
    rows = _rows(path, "session", SESSION_COLUMNS)
    return rows[0] if rows else {}


def write_csv(rows, columns, handle):
    writer = csv.DictWriter(handle, fieldnames=[dst for _, dst in columns],
                            lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("fit", help="the .FIT file")
    parser.add_argument("--laps", action="store_true", help="one row per rep")
    parser.add_argument("--summary", action="store_true", help="the session totals")
    parser.add_argument("--out", help="write here instead of stdout")
    args = parser.parse_args(argv)

    if args.summary:
        rows, columns = [summary(args.fit)], SESSION_COLUMNS
    elif args.laps:
        rows, columns = laps(args.fit), LAP_COLUMNS
    else:
        rows, columns = splits(args.fit), SPLIT_COLUMNS

    if not rows or not any(rows):
        print(f"no Freelap developer fields with values in {args.fit}", file=sys.stderr)
        return 1

    if args.out:
        with open(args.out, "w", newline="") as handle:
            write_csv(rows, columns, handle)
        print(f"{len(rows)} row(s) -> {args.out}", file=sys.stderr)
    else:
        write_csv(rows, columns, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
