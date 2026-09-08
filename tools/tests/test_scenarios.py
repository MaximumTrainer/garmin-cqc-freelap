"""The scenario oracle, and the guard that keeps the watch's copy of it honest.

Two kinds of test. The first checks the oracle against things known
independently - the course distances, the vendor's tick, the documented
limits - so that it is not merely self-consistent. The second regenerates
`source-test/ScenarioVectors.mc` and compares it with the committed file: if
anyone changes a scenario, the generator, the frame builder or the arithmetic
without regenerating, the watch is asserting against stale expectations and
this is what says so.
"""
import pytest

from conftest import REPO_ROOT
import fake_chip
import freelap_frame as ff
import scenarios

VECTORS = REPO_ROOT / "source-test" / "ScenarioVectors.mc"


# ---------------------------------------------------------------------------
# The oracle itself
# ---------------------------------------------------------------------------

def test_ticks_to_microseconds_is_the_exact_integer_form_of_the_vendor_tick():
    # 1/1024 s per tick. The watch uses the same integer expression in a Long;
    # any float here would disagree with it on the last digit somewhere.
    for ticks in (0, 1, 15, 16, 1024, 10240, 10752, 2**24, 2**31 - 1):
        assert scenarios.ticks_to_us(ticks) == (ticks * 1000000) // 1024


def test_every_scenario_respects_the_documented_chip_limits():
    for name, (spec, speed, _chip, _reps, _lap) in scenarios.SCENARIOS.items():
        course = fake_chip.parse_course(spec)
        assert len(course) <= ff.MAX_TRANSMITTERS, name
        # fake_chip refuses gaps under 10 m or legs under 0.7 s, so simply
        # generating the frames proves each scenario is one a chip could send.
        scenarios.frames_for(name)


def test_the_maximum_scenario_really_is_the_maximum():
    spec = scenarios.SCENARIOS["MAX11"][0]
    assert len(fake_chip.parse_course(spec)) == ff.MAX_TRANSMITTERS

    ad, sr = scenarios.frames_for("MAX11")[0]
    assert len(ff.decode_scan_response(sr)) == ff.MAX_LAPS


@pytest.mark.parametrize("name", [n for n in scenarios.SCENARIOS if scenarios.SCENARIOS[n][3] == 1])
def test_expected_distances_are_the_course_and_times_add_up(name):
    ad, sr = scenarios.frames_for(name)[0]
    exp = scenarios.expected_for(name, ad, sr)
    spec = scenarios.SCENARIOS[name][0]

    assert exp["dist_m"] == [m for _c, m in fake_chip.parse_course(spec)]
    assert exp["cum_us"][0] == 0 and exp["split_us"][0] == 0
    assert sum(exp["split_us"]) == exp["cum_us"][-1]
    assert all(s > 0 for s in exp["split_us"][1:])


def test_a_walk_produces_a_rep_of_the_right_length():
    # 60 m at 2 m/s is 30 s. The point of the slow scenario is tick counts an
    # order of magnitude larger than a sprint's.
    ad, sr = scenarios.frames_for("WALK60")[0]
    exp = scenarios.expected_for("WALK60", ad, sr)
    assert exp["cum_us"][-1] == scenarios.ticks_to_us(30 * 1024)


def test_the_constant_lap_number_scenario_holds_the_byte_and_moves_the_finish():
    frames = scenarios.frames_for("CONSTLAP")
    advs = [ff.decode_advertisement(ad) for ad, _ in frames]

    assert [a.lap_number for a in advs] == [0, 0, 0]
    assert len({a.block for a in advs}) == 3


def test_the_stranger_scenario_is_a_different_chip():
    ad, _ = scenarios.frames_for("STRANGER")[0]
    assert ff.decode_advertisement(ad).chip == "ZZ-1234"


# ---------------------------------------------------------------------------
# The committed Monkey C constants match the generator
# ---------------------------------------------------------------------------

def test_the_committed_scenario_vectors_are_what_the_generator_produces():
    assert VECTORS.exists(), "run: python tools/scenarios.py --emit"
    assert VECTORS.read_text(encoding="utf-8") == scenarios.emit(), (
        "source-test/ScenarioVectors.mc is stale; regenerate it with "
        "`python tools/scenarios.py --emit` and commit the result")


def test_the_generated_header_warns_against_editing_by_hand():
    assert "Do not edit by hand" in scenarios.emit()
