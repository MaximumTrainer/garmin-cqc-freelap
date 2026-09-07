"""The developer field table, asserted against a FIT file a watch really wrote.

`data/reference-session.fit` came out of the Connect IQ simulator (fr265) by
starting the app, recording, and choosing Save — see the file's README. It is
the evidence for issue #16's "FitCSVTool shows field_description messages for
all 10 record fields with the documented names, types and units", turned into
something CI re-checks on every push instead of a claim in a PR.

If these names, numbers, types or units change, every consumer of the file
breaks silently: Garmin Connect stops charting, and a decoder reads the wrong
column while still producing numbers.
"""
import pytest

from conftest import REPO_ROOT
from fit_fields import developer_fields, field_values

fitdecode = pytest.importorskip("fitdecode")

FIXTURE = REPO_ROOT / "tools" / "tests" / "data" / "reference-session.fit"

# docs/DESIGN.md §5. (number, name, type, units, message)
EXPECTED = [
    (0, "fl_split_us", "uint32", "us", "record"),
    (1, "fl_cum_us", "uint32", "us", "record"),
    (2, "fl_dist_m", "float32", "m", "record"),
    (3, "fl_velocity", "float32", "m/s", "record"),
    (4, "fl_speed", "float32", "km/h", "record"),
    (5, "fl_pace", "float32", "s/km", "record"),
    (6, "fl_tx_idx", "uint8", None, "record"),
    (7, "fl_tx_code", "uint8", None, "record"),
    (8, "fl_rep", "uint16", None, "record"),
    (9, "fl_est_ms", "uint32", "ms", "record"),
    (10, "fl_chip_idx", "uint8", None, "record"),
    (20, "fl_rep_time_us", "uint32", "us", "lap"),
    (21, "fl_rep_dist_m", "float32", "m", "lap"),
    (22, "fl_rep_avg_vel", "float32", "m/s", "lap"),
    (23, "fl_rep_peak_vel", "float32", "m/s", "lap"),
    (24, "fl_rep_splits", "uint8", None, "lap"),
    (25, "fl_rep_status", "uint8", None, "lap"),
    (40, "fl_reps", "uint16", None, "session"),
    (41, "fl_best_rep_us", "uint32", "us", "session"),
    (42, "fl_total_dist_m", "float32", "m", "session"),
    (43, "fl_chip_id", "string", None, "session"),
]

RECORD_FIELDS = [row for row in EXPECTED if row[4] == "record"]


@pytest.fixture(scope="module")
def declared():
    return {f["name"]: f for f in developer_fields(FIXTURE)}


def test_the_fixture_exists():
    assert FIXTURE.exists(), "regenerate with the recipe in data/README.md"


def test_every_developer_field_is_declared(declared):
    assert sorted(declared) == sorted(name for _, name, _, _, _ in EXPECTED)


def test_all_eleven_record_fields_are_declared(declared):
    on_record = {name for name, f in declared.items() if f["mesg"] == "record"}
    assert on_record == {name for _, name, _, _, _ in RECORD_FIELDS}
    assert len(on_record) == 11


@pytest.mark.parametrize("number,name,base_type,units,mesg", EXPECTED,
                         ids=[row[1] for row in EXPECTED])
def test_field_declaration_matches_the_design_table(declared, number, name, base_type, units, mesg):
    field = declared[name]
    assert field["number"] == number, "field number"
    assert field["type"] == base_type, "FIT base type"
    assert field["units"] == units, "units"
    assert field["mesg"] == mesg, "message the field is attached to"


def test_microsecond_fields_are_integers_not_floats(declared):
    # A float32 carries 24 bits of mantissa: 11 930 000 µs already costs
    # precision, and rounding the durations is the one thing this app must not
    # do. Every *_us field has to be uint32.
    for name, field in declared.items():
        if name.endswith("_us"):
            assert field["type"] == "uint32", f"{name} must be uint32"
            assert field["units"] == "us", f"{name} must be in microseconds"


def test_session_summary_fields_are_written_to_the_file(declared):
    # Not just declared — the session message actually carries them. Lap and
    # session developer fields are the ones the SDK drops if setData() and
    # save() run without a yield between them (docs/DESIGN.md §5).
    session_values = [v for name, v in field_values(FIXTURE) if name == "session"]
    assert len(session_values) == 1
    assert set(session_values[0]) == {"fl_reps", "fl_best_rep_us", "fl_total_dist_m", "fl_chip_id"}


def test_the_reference_session_is_a_track_run():
    # Issue #18: sport/sub-sport must be Running / Track.
    with fitdecode.FitReader(FIXTURE) as fit:
        sessions = [f for f in fit
                    if getattr(f, "frame_type", None) == fitdecode.FIT_FRAME_DATA
                    and f.name == "session"]
    assert len(sessions) == 1
    values = {f.name: f.value for f in sessions[0].fields}
    assert values["sport"] == "running"
    assert values["sub_sport"] == "track"
