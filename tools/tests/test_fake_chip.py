"""The fake chip (#27).

Its whole purpose is to stand in for hardware nobody has yet, so the thing
worth testing is that what it emits **decodes back to what it meant** -- using
the same decoder the watch will use. A fake that only agreed with itself would
let a wrong layout look right in every test we own, which is why the frame
builders live in `freelap_frame.py` and are round-tripped here rather than
re-implemented.
"""
import io

import pytest

import fake_chip
import freelap_frame as ff

COURSE = fake_chip.parse_course("S:0;L:30;L:60;F:100")


# ---------------------------------------------------------------------------
# Course specs
# ---------------------------------------------------------------------------

def test_parse_course_reads_the_same_spec_the_watch_does():
    assert fake_chip.parse_course("S:0;L:30;F:100") == [
        (fake_chip.CODE_START, 0.0),
        (fake_chip.CODE_LAP, 30.0),
        (fake_chip.CODE_FINISH, 100.0),
    ]


def test_parse_course_skips_a_segment_without_a_colon():
    assert len(fake_chip.parse_course("S:0;;L:30;F:100")) == 3


def test_parse_course_rejects_an_unknown_code():
    with pytest.raises(ValueError):
        fake_chip.parse_course("S:0;X:30;F:100")


def test_parse_course_rejects_a_single_transmitter():
    with pytest.raises(ValueError):
        fake_chip.parse_course("S:0")


# ---------------------------------------------------------------------------
# Frames
# ---------------------------------------------------------------------------

def test_a_rep_decodes_back_to_the_times_it_was_built_from():
    advertisement, scan_response = fake_chip.rep_frames(COURSE, speed_mps=10.0,
                                                        jitter=0.0)

    decoded = ff.decode_advertisement(advertisement)
    laps = ff.decode_scan_response(scan_response)
    legs = ff.segments(decoded, laps)

    # 100 m at 10 m/s is 10.00 s, split 30/30/40.
    assert ff.to_centiseconds(decoded.split()) == 1000
    assert [ff.to_centiseconds(t) for t in legs] == [300, 300, 400]


def test_the_intermediates_go_in_the_scan_response_and_the_finish_does_not():
    _advertisement, scan_response = fake_chip.rep_frames(COURSE, jitter=0.0)

    # Four transmitters, so two intermediates. Putting the finish in here too
    # would produce a phantom fifth leg of zero.
    assert len(ff.decode_scan_response(scan_response)) == 2


def test_a_two_transmitter_course_has_an_empty_scan_response():
    course = fake_chip.parse_course("S:0;F:60")

    _advertisement, scan_response = fake_chip.rep_frames(course, jitter=0.0)

    assert ff.decode_scan_response(scan_response) == []


def test_a_rep_does_not_start_at_tick_zero():
    advertisement, _scan_response = fake_chip.rep_frames(COURSE, jitter=0.0)

    # A decoder that forgot to subtract an origin would be perfect on a
    # session starting at zero and wrong on every real one.
    assert ff.decode_advertisement(advertisement).offset != 0


def test_the_chip_identity_reaches_the_frame():
    advertisement, _ = fake_chip.rep_frames(COURSE, prefix="ZZ", chip_id=1234)

    assert ff.decode_advertisement(advertisement).chip == "ZZ-1234"


def test_a_faster_athlete_gets_shorter_times():
    slow, _ = fake_chip.rep_frames(COURSE, speed_mps=5.0, jitter=0.0)
    fast, _ = fake_chip.rep_frames(COURSE, speed_mps=10.0, jitter=0.0)

    assert ff.decode_advertisement(fast).split() < ff.decode_advertisement(slow).split()


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

def test_a_session_produces_one_frame_pair_per_rep():
    session = fake_chip.synthetic_session(COURSE, 5)

    assert len(session) == 5
    assert all(len(pair) == 2 for pair in session)


def test_reps_are_not_all_identical():
    session = fake_chip.synthetic_session(COURSE, 5, jitter=1.0)

    totals = {ff.decode_advertisement(ad).split() for ad, _ in session}

    # A decoder bug that keys off "the value changed" sails through a session
    # of identical reps.
    assert len(totals) > 1


def test_the_chip_counter_runs_on_across_the_session():
    session = fake_chip.synthetic_session(COURSE, 4, rest_s=3.0)

    starts = [ff.decode_advertisement(ad).offset for ad, _ in session]

    assert starts == sorted(starts)
    assert len(set(starts)) == 4


def test_each_rep_measures_from_its_own_start():
    session = fake_chip.synthetic_session(COURSE, 3, jitter=0.0)

    for advertisement, scan_response in session:
        decoded = ff.decode_advertisement(advertisement)
        laps = ff.decode_scan_response(scan_response)
        # However far into the session, a rep is still ~100 m of running and
        # its legs still add up to it.
        assert sum(ff.segments(decoded, laps)) == decoded.split()


def test_the_lap_number_advances_with_the_reps():
    session = fake_chip.synthetic_session(COURSE, 3)

    assert [ff.decode_advertisement(ad).lap_number for ad, _ in session] == [0, 1, 2]


def test_a_long_session_stays_inside_the_field_widths():
    # 400 reps of 100 m with rests is a couple of hours of chip uptime; the
    # 24-bit lap timestamps are the narrowest field and the first to overflow.
    session = fake_chip.synthetic_session(COURSE, 400)

    for _advertisement, scan_response in session:
        assert len(scan_response) == 2 + 3 * ff.MAX_LAPS


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def test_the_printed_block_carries_both_frames_and_the_decoded_times():
    session = fake_chip.synthetic_session(COURSE, 1, jitter=0.0)
    out = io.StringIO()

    fake_chip.print_session(session, stream=out)
    text = out.getvalue()

    assert "AD " in text and "SR " in text
    assert "BC-9636" in text


def test_the_description_reports_a_leg_per_transmitter_gap():
    advertisement, scan_response = fake_chip.rep_frames(COURSE, speed_mps=10.0,
                                                        jitter=0.0)

    line = fake_chip.describe(advertisement, scan_response)

    assert "00:10.00" in line
    assert line.count("00:0") >= 3


def test_monkeyc_vectors_are_byte_arrays_the_compiler_accepts():
    session = fake_chip.synthetic_session(COURSE, 2, jitter=0.0)

    text = fake_chip.monkeyc_vectors(session, name="REP")

    assert "const REP_AD_0 = [0x63,0x03" in text
    assert "]b;" in text
    assert text.count("const ") == 4


def test_generated_vectors_decode_back(tmp_path):
    session = fake_chip.synthetic_session(COURSE, 1, jitter=0.0)
    text = fake_chip.monkeyc_vectors(session)

    # Pull the bytes back out of the generated Monkey C and check they are
    # still the frame. A vector that is pretty but wrong is worse than none.
    literal = text.split("[")[1].split("]")[0]
    recovered = bytes(int(b, 16) for b in literal.split(","))

    assert recovered == session[0][0]


# ---------------------------------------------------------------------------
# Chip ids
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("text,expected", [
    ("BC-9636", ("BC", 9636)),
    ("bc-9636", ("BC", 9636)),
    ("ZZ-1", ("ZZ", 1)),
])
def test_a_chip_id_is_parsed_the_way_it_is_printed(text, expected):
    assert fake_chip.parse_chip(text) == expected


@pytest.mark.parametrize("text", ["9636", "B-9636", "BCD-9636", "BC-", "BC-xy"])
def test_a_malformed_chip_id_is_refused(text):
    with pytest.raises(ValueError):
        fake_chip.parse_chip(text)


# ---------------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------------

def test_parse_capture_reads_the_export_shape():
    rows = fake_chip.parse_capture([
        "1700000000.0\t0x0025\t6303580042\n",
        "1700000000.5\t0x0025\t63:03:58:00:43\n",
    ])

    assert [when for when, _ in rows] == [1700000000.0, 1700000000.5]
    assert rows[0][1] == bytes.fromhex("6303580042")


def test_parse_capture_skips_rows_a_real_export_is_full_of():
    rows = fake_chip.parse_capture([
        "frame.time_epoch\tbtatt.handle\tbtatt.value\n",   # header
        "\n",                                              # blank
        "1700000000.0\t0x0025\t\n",                        # no payload
        "1700000000.0\t0x0025\tnothex\n",                  # not hex
        "1700000001.0\t0x0025\t630358\n",                  # the only good row
    ])

    assert len(rows) == 1


def test_replay_preserves_the_gaps_between_frames():
    schedule = fake_chip.replay_schedule([
        (100.0, b"\x01"), (100.5, b"\x02"), (103.0, b"\x03")])

    # The advertising rate is what #9 has to cope with, so replaying it as a
    # burst would test the easy case only.
    assert [round(delay, 3) for delay, _ in schedule] == [0.0, 0.5, 2.5]


def test_replay_never_waits_a_negative_time():
    schedule = fake_chip.replay_schedule([(100.0, b"\x01"), (99.0, b"\x02")])

    assert all(delay >= 0 for delay, _ in schedule)


def test_replay_of_an_empty_capture_is_an_empty_schedule():
    assert fake_chip.replay_schedule([]) == []


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def test_the_cli_defaults_match_the_documented_invocation():
    args = fake_chip.build_parser().parse_args([])

    assert args.course == fake_chip.DEFAULT_COURSE
    assert args.reps == 1
    assert args.rounding == "round"
    assert not args.advertise


def test_print_and_vectors_are_both_reachable_from_the_cli(capsys):
    assert fake_chip.main(["--print", "--reps", "2"]) == 0
    assert "AD " in capsys.readouterr().out

    assert fake_chip.main(["--vectors", "--reps", "1"]) == 0
    assert "]b;" in capsys.readouterr().out


def test_the_cli_can_be_told_which_chip_to_be(capsys):
    fake_chip.main(["--print", "--chip", "ZZ-1234"])

    assert "ZZ-1234" in capsys.readouterr().out


def test_advertising_says_what_it_needs_rather_than_failing_obscurely():
    session = fake_chip.synthetic_session(COURSE, 1)

    # It has never been run; #27. Whichever way it fails, it has to explain
    # itself, because the person hitting this has a chip and a Linux box and
    # is trying to do the most valuable thing left in the project.
    with pytest.raises((SystemExit, NotImplementedError)) as caught:
        fake_chip.advertise(session)

    assert str(caught.value)


# ---------------------------------------------------------------------------
# Limits the real chip imposes
# ---------------------------------------------------------------------------

def eleven_transmitters():
    spec = ";".join(["S:0"] + ["L:%d" % (i * 20) for i in range(1, 10)] + ["F:200"])
    return fake_chip.parse_course(spec)


def test_the_documented_maximum_number_of_transmitters_is_allowed():
    course = eleven_transmitters()
    assert len(course) == ff.MAX_TRANSMITTERS

    advertisement, scan_response = fake_chip.rep_frames(course, speed_mps=8.0,
                                                        jitter=0.0)

    # Nine intermediate crossings is exactly what the scan response holds, and
    # the ten legs between eleven transmitters are the "10 intermediate times"
    # Freelap's manual quotes. The two sources agreeing is the point.
    laps = ff.decode_scan_response(scan_response)
    assert len(laps) == ff.MAX_LAPS
    assert len(ff.segments(ff.decode_advertisement(advertisement), laps)) == 10


def test_a_twelfth_transmitter_is_refused():
    spec = ";".join(["S:0"] + ["L:%d" % (i * 20) for i in range(1, 11)] + ["F:220"])

    with pytest.raises(ValueError, match="transmitters"):
        fake_chip.rep_frames(fake_chip.parse_course(spec), jitter=0.0)


def test_transmitters_closer_than_the_minimum_are_refused():
    course = fake_chip.parse_course("S:0;L:5;F:30")

    # Below ten metres the chip may not detect the second transmitter at all,
    # so a fake that happily produced a split there would be testing the
    # decoder against something hardware cannot send.
    with pytest.raises(ValueError, match="minimum is 10"):
        fake_chip.rep_frames(course, jitter=0.0)


def test_a_leg_the_athlete_covers_too_quickly_is_refused():
    course = fake_chip.parse_course("S:0;L:10;F:40")

    # Ten metres is a legal gap, but not at 20 m/s: the chip needs 0.7 s
    # between transmitters, and that depends on the athlete, not the course.
    with pytest.raises(ValueError, match="0.7"):
        fake_chip.rep_frames(course, speed_mps=20.0, jitter=0.0)


def test_the_same_leg_at_a_realistic_speed_is_fine():
    course = fake_chip.parse_course("S:0;L:10;F:40")

    advertisement, _ = fake_chip.rep_frames(course, speed_mps=8.0, jitter=0.0)

    assert ff.decode_advertisement(advertisement) is not None


# ---------------------------------------------------------------------------
# Holding the lap-number byte still (issue #80)
# ---------------------------------------------------------------------------
#
# No vendor document says the lap-number byte increments per rep; it is 0 in
# the only worked example. The fake incremented it anyway, and RepTracker
# keyed on it, so the two agreed for no reason at all. This mode lets a session
# be generated the way the chip might actually behave, so the watch can be
# shown to cope.

def test_a_session_can_hold_the_lap_number_constant():
    session = fake_chip.synthetic_session(COURSE, 4, jitter=0.0, lap_number=0)

    numbers = [ff.decode_advertisement(ad).lap_number for ad, _ in session]
    finishes = [ff.decode_advertisement(ad).block for ad, _ in session]

    assert numbers == [0, 0, 0, 0]
    # ...while the finish timestamps still advance, which is what makes them
    # four reps rather than one repeated four times.
    assert finishes == sorted(finishes) and len(set(finishes)) == 4


def test_the_default_still_increments_so_existing_vectors_are_unchanged():
    session = fake_chip.synthetic_session(COURSE, 3, jitter=0.0)

    assert [ff.decode_advertisement(ad).lap_number for ad, _ in session] == [0, 1, 2]


def test_the_cli_exposes_the_constant_lap_number_mode(capsys):
    fake_chip.main(["--print", "--reps", "3", "--lap-number", "7"])

    out = capsys.readouterr().out
    assert out.count("lap#7") == 3
