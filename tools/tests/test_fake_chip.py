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
