"""Reading splits out of a FIT file as CSV (issue #29).

Garmin Connect rounds floats in its UI, so the microseconds this app exists to
preserve are only visible by reading the file directly. That is what this tool
is for, and what these tests hold it to.

The reference FIT here has the field *declarations* but no split values — there
is no way to inject BLE crossings into the simulator, so no recorded session
has any (see `tools/tests/data/README.md`). The value-level assertions
therefore run against a synthetic message stream rather than the file; the file
is what proves the column names are the ones really in it.
"""
import io

import pytest

from conftest import REPO_ROOT
import fit_splits
from fit_splits import (LAP_COLUMNS, SESSION_COLUMNS, SPLIT_COLUMNS,
                        UNMATCHED_TX, write_csv)

pytest.importorskip("fitdecode")

FIXTURE = REPO_ROOT / "tools" / "tests" / "data" / "reference-session.fit"


# ---------------------------------------------------------------------------
# The column mapping
# ---------------------------------------------------------------------------

def test_every_source_field_exists_in_a_real_fit_file():
    from fit_fields import developer_fields

    declared = {f["name"] for f in developer_fields(FIXTURE)}
    mapped = {src for src, _ in SPLIT_COLUMNS + LAP_COLUMNS + SESSION_COLUMNS}

    # A typo in a source name would silently produce a column of empty cells.
    assert mapped <= declared, f"not in the file: {sorted(mapped - declared)}"


def test_the_split_columns_line_up_with_the_on_watch_export():
    from splits_to_csv import COLUMNS as WATCH_COLUMNS

    fit_names = {dst for _, dst in SPLIT_COLUMNS}

    # Issue #29 asks for a round trip against the on-watch log. That only works
    # if the two exports agree on what each column is called.
    shared = fit_names & set(WATCH_COLUMNS)
    assert {"rep", "tx_index", "tx_code", "cum_us", "split_us",
            "velocity_mps", "est_ms"} <= shared


def test_the_microsecond_columns_are_the_ones_that_matter():
    names = [dst for _, dst in SPLIT_COLUMNS]

    assert "cum_us" in names and "split_us" in names
    assert "rep_time_us" in [dst for _, dst in LAP_COLUMNS]
    assert "best_rep_us" in [dst for _, dst in SESSION_COLUMNS]


# ---------------------------------------------------------------------------
# Reading a file
# ---------------------------------------------------------------------------

def test_the_session_summary_reads_from_a_real_file():
    got = fit_splits.summary(FIXTURE)

    # The reference session had no chip, so the values are the empty-session
    # ones - but they are present, which is what proves the mapping works.
    assert set(got) == {"reps", "best_rep_us", "total_dist_m", "chip_id"}
    assert got["chip_id"] == "unknown"


def test_a_file_with_no_split_values_yields_no_split_rows():
    # The reference session has the declarations but no crossings.
    assert fit_splits.splits(FIXTURE) == []


def test_a_file_with_nothing_to_export_reports_it_rather_than_writing_an_empty_csv(capsys):
    # The reference session has declarations but no crossings, so there is
    # nothing to export - and an empty CSV would look like a successful run.
    code = fit_splits.main([str(FIXTURE)])

    assert code == 1
    assert "no Freelap developer fields with values" in capsys.readouterr().err


# ---------------------------------------------------------------------------
# Turning messages into rows
# ---------------------------------------------------------------------------

def fake_messages(monkeypatch, messages):
    monkeypatch.setattr(fit_splits, "field_values", lambda path: messages)


def test_splits_come_out_in_the_order_they_were_run(monkeypatch):
    fake_messages(monkeypatch, [
        ("record", {"fl_rep": 1, "fl_tx_idx": 0, "fl_split_us": 0, "fl_cum_us": 0}),
        ("record", {"fl_rep": 1, "fl_tx_idx": 1, "fl_split_us": 4120000, "fl_cum_us": 4120000}),
        ("record", {"fl_rep": 1, "fl_tx_idx": 2, "fl_split_us": 3360000, "fl_cum_us": 7480000}),
    ])

    rows = fit_splits.splits("ignored")

    assert [r["split_us"] for r in rows] == [0, 4120000, 3360000]
    assert [r["cum_us"] for r in rows] == [0, 4120000, 7480000]


def test_a_blanked_record_is_not_a_split(monkeypatch):
    fake_messages(monkeypatch, [
        ("record", {"fl_rep": 1, "fl_tx_idx": 1, "fl_split_us": 4120000, "fl_cum_us": 4120000}),
        # What clearAfterWrite writes on the record after the last split.
        ("record", {"fl_rep": 0, "fl_tx_idx": 255, "fl_split_us": 0, "fl_cum_us": 0}),
    ])

    rows = fit_splits.splits("ignored")

    # Exporting the blanking write as a split would put a 0.00 s row between
    # every rep.
    assert len(rows) == 1


def test_the_start_crossing_is_kept_even_though_its_times_are_zero(monkeypatch):
    fake_messages(monkeypatch, [
        # The START of a rep: split and cumulative time are both legitimately
        # 0, and only fl_rep separates it from the blanking write.
        ("record", {"fl_rep": 1, "fl_tx_idx": 0, "fl_split_us": 0, "fl_cum_us": 0}),
        ("record", {"fl_rep": 0, "fl_tx_idx": 255, "fl_split_us": 0, "fl_cum_us": 0}),
    ])

    rows = fit_splits.splits("ignored")

    assert len(rows) == 1
    assert rows[0]["tx_index"] == 0


def test_an_unmatched_crossing_loses_its_transmitter_number(monkeypatch):
    fake_messages(monkeypatch, [
        ("record", {"fl_rep": 1, "fl_tx_idx": UNMATCHED_TX, "fl_split_us": 4000000,
                    "fl_cum_us": 12000000}),
    ])

    # Left as 255 it is a plausible-looking transmitter index.
    assert fit_splits.splits("ignored")[0]["tx_index"] == ""


def test_lap_status_is_named_rather_than_numbered(monkeypatch):
    fake_messages(monkeypatch, [
        ("lap", {"fl_rep_time_us": 11930000, "fl_rep_splits": 4, "fl_rep_status": 0}),
        ("lap", {"fl_rep_time_us": 8000000, "fl_rep_splits": 3, "fl_rep_status": 2}),
    ])

    rows = fit_splits.laps("ignored")

    # "2" in a spreadsheet column called rep_status is not information.
    assert [r["rep_status"] for r in rows] == ["ok", "partial"]


def test_lap_rows_keep_microsecond_rep_times(monkeypatch):
    fake_messages(monkeypatch, [
        ("lap", {"fl_rep_time_us": 11930000, "fl_rep_dist_m": 100.0, "fl_rep_splits": 4}),
    ])

    assert fit_splits.laps("ignored")[0]["rep_time_us"] == 11930000


# ---------------------------------------------------------------------------
# The CSV
# ---------------------------------------------------------------------------

def test_the_csv_has_a_header_and_one_row_per_split():
    rows = [{"rep": 1, "tx_index": 0, "split_us": 0},
            {"rep": 1, "tx_index": 1, "split_us": 4120000}]
    out = io.StringIO()

    write_csv(rows, SPLIT_COLUMNS, out)
    lines = out.getvalue().strip().split("\n")

    assert lines[0].startswith("rep,tx_index,tx_code,cum_us,split_us")
    assert len(lines) == 3


def test_microseconds_are_written_as_integers_not_floats():
    out = io.StringIO()
    write_csv([{"split_us": 4120000, "cum_us": 11930000}], SPLIT_COLUMNS, out)

    body = out.getvalue().strip().split("\n")[1]
    assert "4120000" in body and "4120000.0" not in body
