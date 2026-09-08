"""A real activity file, written by the simulator from a scenario rep.

`FakeSession` accepts any value on any field, so the scenario suite proves the
watch computes the right numbers but not that a real FIT writer accepts and
stores them. This file was produced by the recipe in docs/TESTING.md - the
WORKED100 scenario fed through the shipped recorder into a real
ActivityRecording.Session in the Connect IQ simulator, then saved - and these
tests read the oracle's values back out of it. It contains no athlete data:
the simulator's default profile, no GPS, no heart rate.

Two of the tests pin things the real file shows that the fake never could.
They are not the desired behaviour; they are what is true today, so that the
fix changes a test on purpose rather than by accident.
"""
import csv
import io
import subprocess
import sys

from conftest import REPO_ROOT
import scenarios

FIT = REPO_ROOT / "tools" / "tests" / "data" / "scenario-worked100.fit"
TOOL = REPO_ROOT / "tools" / "fit_splits.py"


def rows():
    """The split rows fit_splits.py prints for the file, as dicts."""
    out = subprocess.run([sys.executable, str(TOOL), str(FIT)],
                         capture_output=True, text=True, check=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def deduplicated(split_rows):
    """Consecutive identical rows collapsed - see test_the_finish_record_..."""
    kept = []
    for row in split_rows:
        if not kept or row != kept[-1]:
            kept.append(row)
    return kept


def test_the_file_exists_and_is_a_saved_session():
    assert FIT.exists()
    # A saved session carries the session-level fields; an abandoned one does
    # not (docs/DESIGN.md section 7.2).
    assert b"fl_reps" in FIT.read_bytes()


def test_the_records_carry_the_oracle_values():
    ad, sr = scenarios.frames_for("WORKED100")[0]
    expected = scenarios.expected_for("WORKED100", ad, sr)

    got = deduplicated(rows())

    assert [int(r["cum_us"]) for r in got] == expected["cum_us"]
    assert [int(r["split_us"]) for r in got] == expected["split_us"]
    assert [float(r["cum_dist_m"]) for r in got] == expected["dist_m"]


def test_every_crossing_was_matched_to_its_transmitter():
    got = deduplicated(rows())

    assert [int(r["tx_index"]) for r in got] == [0, 1, 2, 3]
    assert [int(r["tx_code"]) for r in got] == [1, 2, 2, 3]    # START LAP LAP FINISH
    assert {int(r["rep"]) for r in got} == {1}


def test_the_derived_metrics_survive_the_round_trip():
    got = deduplicated(rows())

    # 30 m, 30 m and 40 m at 10 m/s. Velocity 10.0, 36 km/h, 100 s/km; the
    # START record has no split and carries zeros.
    assert [float(r["velocity_mps"]) for r in got] == [0.0, 10.0, 10.0, 10.0]
    assert [float(r["speed_kmh"]) for r in got] == [0.0, 36.0, 36.0, 36.0]
    assert [float(r["pace_s_per_km"]) for r in got] == [0.0, 100.0, 100.0, 100.0]


# ---------------------------------------------------------------------------
# What the real writer does that the fake does not
# ---------------------------------------------------------------------------

def test_the_finish_record_appears_twice_in_the_real_file():
    # Pinned, not endorsed. The recorder writes the last split on one tick,
    # cuts the lap on the next, and only blanks the record fields on the tick
    # after that - so the simulator's own 1 Hz record between the two repeats
    # the finish values. The recorder's comment claims a rep costs no
    # duplicate record; the file says otherwise. Fixing it changes this test.
    raw = rows()
    assert len(raw) == 5
    assert raw[3] == raw[4]
    assert int(raw[4]["tx_code"]) == 3
