"""Converting a dumped on-watch split log to CSV (issue #19).

The dump is copied out of a console by hand, so the parser has to be
unbothered by whatever else is in the paste, and the conversion has to keep
the two values that mean "no answer" distinguishable from the numbers they
look like.
"""
import io

from splits_to_csv import COLUMNS, parse_dump, to_records, write_csv

# One rep of the worked example: S:0;L:30;L:60;F:100 at 4.120 / 7.480 / 11.930.
DUMP = """\
--- freelap splits: 4 row(s), 0 dropped of 4 seen
[1,0,1,0,0,0.0,0.0,0.0,7920,false]
[1,1,2,4120000,4120000,30.0,30.0,7.2815533,12040,false]
[1,2,2,7480000,3360000,60.0,30.0,8.9285714,15400,false]
[1,3,3,11930000,4450000,100.0,40.0,8.9887640,19850,false]
--- end
"""


def test_a_clean_dump_yields_one_row_per_split():
    assert len(parse_dump(DUMP.splitlines())) == 4


def test_the_banner_and_footer_are_not_rows():
    rows = parse_dump(DUMP.splitlines())

    assert all(isinstance(row, list) for row in rows)
    assert rows[0][0] == 1, "the first row is the first split, not the banner"


def test_noise_around_the_dump_is_ignored():
    noisy = [
        "Connecting to simulator...",
        "",
        "--- freelap splits: 1 row(s), 0 dropped of 1 seen",
        "[1,0,1,0,0,0.0,0.0,0.0,7920,false]",
        "--- end",
        "[not json",
        '{"a": 1}',
        "[1,2,3]",           # right shape, wrong width
    ]

    rows = parse_dump(noisy)

    # A console dump is pasted by hand and always has some of this in it;
    # failing the whole file over a stray line would be useless.
    assert len(rows) == 1


def test_an_empty_dump_yields_nothing_rather_than_failing():
    assert parse_dump([]) == []
    assert parse_dump(["--- freelap splits: 0 row(s), 0 dropped of 0 seen", "--- end"]) == []


def test_the_column_list_matches_the_watchs_row_width():
    rows = parse_dump(DUMP.splitlines())

    # SplitEvent.toArray() decides this. If it grows, the parser silently drops
    # every row until COLUMNS grows with it - hence the assertion.
    assert len(COLUMNS) == 10
    assert all(len(row) == len(COLUMNS) for row in rows)


def test_microseconds_survive_the_conversion_exactly():
    records = to_records(parse_dump(DUMP.splitlines()))

    # The whole point of the app. A float here would round the very thing it
    # exists to preserve.
    assert [r["split_us"] for r in records] == [0, 4120000, 3360000, 4450000]
    assert [r["cum_us"] for r in records] == [0, 4120000, 7480000, 11930000]


def test_an_unmatched_crossing_has_no_transmitter_index():
    records = to_records([[1, -1, 3, 12000000, 4000000, 100.0, 0.0, 0.0, 19850, False],
                          [1, 255, 3, 12000000, 4000000, 100.0, 0.0, 0.0, 19850, False]])

    # -1 on the watch, 255 in the FIT file, both meaning "the course could not
    # place this". Left as a number, a spreadsheet will happily average it.
    assert records[0]["tx_index"] == ""
    assert records[1]["tx_index"] == ""


def test_a_clamped_estimate_is_blank_rather_than_zero():
    records = to_records([[1, 0, 1, 0, 0, 0.0, 0.0, 0.0, 0, True],
                          [1, 0, 1, 0, 0, 0.0, 0.0, 0.0, 0, False]])

    # est_ms of 0 means "could not be placed" when the flag is set and "at
    # session start" when it is not. Only one of those is a time.
    assert records[0]["est_ms"] == ""
    assert records[0]["est_clamped"] == "true"
    assert records[1]["est_ms"] == 0
    assert records[1]["est_clamped"] == "false"


def test_the_csv_has_a_header_row():
    out = io.StringIO()
    write_csv(to_records(parse_dump(DUMP.splitlines())), out)
    lines = out.getvalue().strip().split("\n")

    assert lines[0] == ",".join(COLUMNS)
    assert len(lines) == 5, "a header and four splits"


def test_the_csv_rows_are_in_the_order_they_were_run():
    out = io.StringIO()
    write_csv(to_records(parse_dump(DUMP.splitlines())), out)
    body = out.getvalue().strip().split("\n")[1:]

    assert [line.split(",")[3] for line in body] == ["0", "4120000", "7480000", "11930000"]


# ---------------------------------------------------------------------------
# Cross-check against what the watch actually prints
# ---------------------------------------------------------------------------

def test_the_exact_row_the_watch_emits_parses():
    # Byte-for-byte the string asserted by
    # source-test/SplitLogTest.mc::testARowDumpsAsAJsonArray. If SplitLog's
    # formatting changes, one of the two tests fails rather than the export
    # quietly producing nothing.
    from_watch = "[1,0,1,0,0,0.0000000,0.0000000,0.0000000,7920,false]"

    rows = parse_dump([from_watch])

    assert rows == [[1, 0, 1, 0, 0, 0.0, 0.0, 0.0, 7920, False]]


def test_the_watchs_seven_decimal_velocity_survives():
    rows = parse_dump(["[1,1,2,4120000,4120000,30.0000000,30.0000000,7.2815533,12040,false]"])

    assert rows[0][7] == 7.2815533, "the precision the microseconds bought"


def test_a_whole_dump_in_the_watchs_own_format_converts():
    watch_output = [
        "--- freelap splits: 4 row(s), 0 dropped of 4 seen",
        "[1,0,1,0,0,0.0000000,0.0000000,0.0000000,7920,false]",
        "[1,1,2,4120000,4120000,30.0000000,30.0000000,7.2815533,12040,false]",
        "[1,2,2,7480000,3360000,60.0000000,30.0000000,8.9285714,15400,false]",
        "[1,3,3,11930000,4450000,100.0000000,40.0000000,8.9887640,19850,false]",
        "--- end",
    ]

    out = io.StringIO()
    write_csv(to_records(parse_dump(watch_output)), out)
    lines = out.getvalue().strip().split("\n")

    assert lines[0].startswith("rep,tx_index,tx_code,cum_us,split_us")
    assert lines[1] == "1,0,1,0,0,0.0,0.0,0.0,7920,false"
    assert lines[4] == "1,3,3,11930000,4450000,100.0,40.0,8.988764,19850,false"
