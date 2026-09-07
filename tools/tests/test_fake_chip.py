"""Ring 4b: the fake chip's packet builder. This layout is the mirror of
FreelapProtocol.feed() and must change in lock-step with it (AGENTS.md)."""
from fake_chip import build_packet, fragments


def test_build_packet_writes_the_sync_byte_count_and_chip_id():
    pkt = build_packet([(0, 1), (4120, 2)], chip_id=0x1234)

    assert pkt[0] == 0xA5
    assert pkt[1] == 2
    assert pkt[2:4] == b"\x34\x12"          # chip id, little endian
    assert len(pkt) == 4 + 2 * 5


def test_build_packet_writes_each_crossing_as_u32_le_ticks_plus_code():
    pkt = build_packet([(4120, 2)], chip_id=0)

    assert pkt[4:8] == b"\x18\x10\x00\x00"  # 4120 little endian
    assert pkt[8] == 2


def test_fragments_splits_on_the_20_byte_ble_write_limit():
    pkt = build_packet([(i * 1000, 2) for i in range(6)])   # 4 + 30 = 34 bytes

    frags = fragments(pkt)

    assert [len(f) for f in frags] == [20, 14]
    assert b"".join(frags) == pkt


# ---------------------------------------------------------------------------
# Synthetic sessions (issue #27)
# ---------------------------------------------------------------------------

def test_parse_course_reads_the_same_spec_the_watch_does():
    from fake_chip import parse_course, CODE_START, CODE_LAP, CODE_FINISH

    assert parse_course("S:0;L:30;L:60;F:100") == [
        (CODE_START, 0.0), (CODE_LAP, 30.0), (CODE_LAP, 60.0), (CODE_FINISH, 100.0)]


def test_parse_course_skips_a_segment_without_a_colon():
    from fake_chip import parse_course

    # Course.mc drops these rather than rejecting the whole spec; the fake
    # chip has to agree or the two disagree about what a course even is.
    assert len(parse_course("S:0;garbage;F:100")) == 2


def test_parse_course_rejects_an_unknown_code():
    import pytest as _pytest
    from fake_chip import parse_course

    with _pytest.raises(ValueError, match="X"):
        parse_course("S:0;X:30;F:100")


def test_parse_course_rejects_a_single_transmitter():
    import pytest as _pytest
    from fake_chip import parse_course

    with _pytest.raises(ValueError, match="two transmitters"):
        parse_course("S:0")


def test_a_synthetic_rep_places_crossings_by_distance_over_speed():
    from fake_chip import parse_course, synthetic_rep, CODE_START, CODE_FINISH

    rep = synthetic_rep(parse_course("S:0;L:30;F:100"), speed_mps=10.0, jitter=0.0)

    assert rep[0] == (0, CODE_START)        # 0 m at 10 m/s
    assert rep[1] == (3000, 2)              # 30 m at 10 m/s = 3.000 s
    assert rep[2] == (10000, CODE_FINISH)   # 100 m = 10.000 s


def test_a_synthetic_session_sends_one_packet_per_rep():
    from fake_chip import parse_course, synthetic_session

    packets = synthetic_session(parse_course("S:0;L:30;L:60;F:100"), reps=60)

    assert len(packets) == 60
    assert all(p[0] == 0xA5 and p[1] == 4 for p in packets)


def test_synthetic_reps_are_not_all_identical():
    from fake_chip import parse_course, synthetic_session

    # 60 byte-identical reps would let a decoder bug that keys off "the value
    # changed" pass a 60-rep soak test.
    packets = synthetic_session(parse_course("S:0;L:30;F:100"), reps=10)

    assert len(set(packets)) > 1, "every rep has the same timings"


def test_synthetic_reps_survive_the_round_trip_through_the_fragmenter():
    from fake_chip import parse_course, synthetic_session, fragments

    packet = synthetic_session(parse_course("S:0;L:30;L:60;F:100"), reps=1)[0]

    assert len(packet) == 4 + 4 * 5
    assert b"".join(fragments(packet)) == packet
    assert [len(f) for f in fragments(packet)] == [20, 4]   # genuinely fragmented


# ---------------------------------------------------------------------------
# Replaying a real capture (issue #27)
# ---------------------------------------------------------------------------

def test_parse_capture_reads_the_decode_capture_tsv_shape():
    from fake_chip import parse_capture

    rows = parse_capture([
        "1.000\t0x0012\tA5041234\n",
        "1.030\t0x0012\t180F0000\n",
    ])

    assert rows == [(1.0, bytes.fromhex("A5041234")), (1.03, bytes.fromhex("180F0000"))]


def test_parse_capture_accepts_colon_separated_hex_from_tshark():
    from fake_chip import parse_capture

    assert parse_capture(["2.5\t0x0012\ta5:04:12:34\n"]) == [(2.5, bytes.fromhex("A5041234"))]


def test_parse_capture_skips_rows_a_real_export_is_full_of():
    from fake_chip import parse_capture

    rows = parse_capture([
        "\n",                                   # blank
        "frame.time_epoch\thandle\tvalue\n",    # a header
        "1.000\t0x0012\t\n",                    # no payload
        "1.100\t0x0012\tnothex\n",              # not hex
        "1.200\t0x0012\tA5\n",                  # the only real one
    ])

    assert rows == [(1.2, b"\xa5")]


def test_replay_preserves_the_gaps_between_packets():
    from fake_chip import replay_schedule

    schedule = replay_schedule([(10.0, b"\x01"), (10.03, b"\x02"), (12.53, b"\x03")])
    delays = [round(d, 6) for d, _ in schedule]

    # The first goes out immediately; the rest wait exactly what the capture
    # recorded, so the watch sees the chip's own fragmentation timing.
    assert delays == [0.0, 0.03, 2.5]


def test_replay_never_waits_a_negative_time():
    from fake_chip import replay_schedule

    # Out-of-order rows happen in exports that merge two interfaces.
    delays = [d for d, _ in replay_schedule([(5.0, b"\x01"), (4.0, b"\x02")])]

    assert all(d >= 0 for d in delays)


def test_replay_of_an_empty_capture_is_an_empty_schedule():
    from fake_chip import replay_schedule

    assert replay_schedule([]) == []


# ---------------------------------------------------------------------------
# The CLI
# ---------------------------------------------------------------------------

def test_the_cli_defaults_match_the_documented_invocation():
    from fake_chip import build_parser

    args = build_parser().parse_args(["--synthetic", "--reps", "60",
                                      "--course", "S:0;L:30;L:60;F:100"])

    assert args.synthetic and args.reps == 60
    assert args.course == "S:0;L:30;L:60;F:100"
    assert args.mtu == 20, "20 bytes is the BLE notification limit, not a preference"


def test_replay_and_synthetic_are_both_reachable_from_the_cli():
    from fake_chip import build_parser

    assert build_parser().parse_args(["--replay", "cap.tsv"]).replay == "cap.tsv"
    assert build_parser().parse_args([]).replay is None
