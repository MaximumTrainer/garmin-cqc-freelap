"""Ring 4b: the candidate-encoding search, against a synthetic capture whose
answer is known by construction (AGENTS.md, "Ring 4b - Python tools")."""
import struct

from decode_capture import candidates, matches


def test_candidates_offers_the_ms_little_endian_u32_encoding():
    found = {(u, f, n) for u, f, n in candidates(4.120)}

    assert ("ms", "u32le", struct.pack("<I", 4120)) in found


def test_matches_finds_a_u32_le_millisecond_timestamp_at_its_offset():
    # 0xA5 sync, 1 crossing, chip id 0x1234, then 4.120 s in ms as u32 LE.
    packet = bytes([0xA5, 0x01]) + struct.pack("<H", 0x1234) + struct.pack("<IB", 4120, 2)

    hits = matches(packet, 4.120)

    assert ("u32le", "ms", 4) in hits


def test_matches_reports_nothing_for_a_time_that_is_not_in_the_packet():
    packet = bytes([0xA5, 0x01]) + struct.pack("<H", 0x1234) + struct.pack("<IB", 4120, 2)

    assert matches(packet, 99.999) == []


def test_matches_finds_a_hundredths_of_a_second_encoding_too():
    packet = b"\x00\x00" + struct.pack("<H", 412) + b"\x00"

    hits = matches(packet, 4.12)

    assert ("u16le", "1/100s", 2) in hits
