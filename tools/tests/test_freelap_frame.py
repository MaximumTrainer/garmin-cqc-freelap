"""The broadcast frame codec (#7).

There are two kinds of test here and the difference matters.

**Ground truth.** Freelap's document contains one fully worked example: a real
frame with every decoded value printed beside it. That is the only evidence we
have that this code is right rather than merely self-consistent, and everything
else in this file could pass with the byte offsets shifted by two. It lives in
a fixture that is *not committed*, because the document was shared in confidence
(#8), so these tests skip in CI and run for anyone holding the document. The
skip message says how to produce it.

**Everything else.** Round-trips, red cases and arithmetic, which need no
document and run everywhere. A round-trip alone proves the encoder and decoder
agree, not that either matches a chip -- which is exactly why the fixture above
is not optional for anyone changing the layout.
"""
import json

import pytest

from conftest import REPO_ROOT
import freelap_frame as ff

VENDOR = REPO_ROOT / "tools" / "tests" / "data" / "vendor_frame_example.json"

NEEDS_DOC = pytest.mark.skipif(
    not VENDOR.exists(),
    reason=("needs tools/tests/data/vendor_frame_example.json, which is not "
            "committed -- see the note at the top of this file and #8. Build "
            "it from the worked example in Freelap's frame document."))


@pytest.fixture(scope="module")
def vendor():
    return json.loads(VENDOR.read_text(encoding="utf-8"))


def hexbytes(text):
    return bytes.fromhex(text.replace("0x", "").replace(",", " "))


# ---------------------------------------------------------------------------
# Ground truth: the vendor's own worked example
# ---------------------------------------------------------------------------

@NEEDS_DOC
def test_the_documented_advertisement_decodes_to_the_documented_values(vendor):
    advertisement = ff.decode_advertisement(hexbytes(vendor["advertisement"]))
    assert advertisement is not None

    expected = vendor["decoded"]
    assert advertisement.chip == expected["chip"]
    assert advertisement.lap_number == expected["lap_number"]
    assert advertisement.offset == expected["offset"]
    assert advertisement.from_lap == expected["from_lap"]
    assert advertisement.block == expected["block"]


@NEEDS_DOC
def test_the_documented_scan_response_decodes_to_the_documented_laps(vendor):
    laps = ff.decode_scan_response(hexbytes(vendor["scan_response"]))

    assert laps == vendor["decoded"]["laps"]


@NEEDS_DOC
def test_the_documented_segment_and_split_times_are_reproduced(vendor):
    advertisement = ff.decode_advertisement(hexbytes(vendor["advertisement"]))
    laps = ff.decode_scan_response(hexbytes(vendor["scan_response"]))
    expected = vendor["decoded"]

    # The document truncates; see to_centiseconds.
    assert [ff.format_time(ff.to_centiseconds(t, "truncate"))
            for t in ff.segments(advertisement, laps)] == expected["lap_times"]
    assert [ff.format_time(ff.to_centiseconds(t, "truncate"))
            for t in ff.cumulative(advertisement, laps)] == expected["split_times"]


@NEEDS_DOC
def test_the_two_candidate_masks_agree_on_the_documented_frame(vendor):
    advertisement = ff.decode_advertisement(hexbytes(vendor["advertisement"]))

    # They do, which is precisely why the example cannot settle #6: the
    # counters in it are far too small to reach the bits where the masks
    # differ. Asserting it stops anyone citing this example as evidence.
    assert advertisement.split(ff.MASK_NARROW) == advertisement.split(ff.MASK_WIDE)


@NEEDS_DOC
def test_rebuilding_the_documented_frame_reproduces_it_byte_for_byte(vendor):
    advertisement = ff.decode_advertisement(hexbytes(vendor["advertisement"]))

    rebuilt = ff.build_advertisement(
        advertisement.prefix, advertisement.chip_id, advertisement.lap_number,
        advertisement.offset, advertisement.from_lap, advertisement.block,
        hex_version=advertisement.hex_version,
        ble_version=advertisement.ble_version,
        battery=advertisement.battery,
        api_version=advertisement.api_version)

    assert rebuilt == hexbytes(vendor["advertisement"])


# ---------------------------------------------------------------------------
# Round-trips
# ---------------------------------------------------------------------------

def test_an_advertisement_survives_the_round_trip():
    payload = ff.build_advertisement("BC", 9636, 3, 3585, 6231, 14337)

    advertisement = ff.decode_advertisement(payload)

    assert advertisement.chip == "BC-9636"
    assert advertisement.lap_number == 3
    assert (advertisement.offset, advertisement.from_lap, advertisement.block) \
        == (3585, 6231, 14337)


def test_a_scan_response_survives_the_round_trip():
    laps = [6231, 8611, 10668]

    assert ff.decode_scan_response(ff.build_scan_response(laps)) == laps


def test_a_scan_response_with_no_intermediates_is_empty_not_an_error():
    # A start and a finish is a perfectly good course.
    assert ff.decode_scan_response(ff.build_scan_response([])) == []


def test_a_full_scan_response_round_trips():
    laps = [1000 * (i + 1) for i in range(ff.MAX_LAPS)]

    assert ff.decode_scan_response(ff.build_scan_response(laps)) == laps


def test_more_laps_than_fit_is_refused_rather_than_truncated():
    with pytest.raises(ValueError):
        ff.build_scan_response([100 * (i + 1) for i in range(ff.MAX_LAPS + 1)])


def test_the_payload_is_the_length_the_layout_requires():
    payload = ff.build_advertisement("BC", 9636, 0, 1, 2, 3)

    # The advertising data length byte is fixed, so a payload of the wrong
    # size would not be a decoding bug, it would be an unsendable frame.
    assert len(payload) == ff.AD_PAYLOAD_LEN


# ---------------------------------------------------------------------------
# Rejection. Every one of these is a frame we will actually see on a track.
# ---------------------------------------------------------------------------

def test_another_manufacturers_beacon_is_ignored():
    payload = bytearray(ff.build_advertisement("BC", 9636, 0, 1, 2, 3))
    payload[0] = 0x4C  # Apple

    assert ff.decode_advertisement(bytes(payload)) is None


def test_a_freelap_frame_of_another_type_is_ignored():
    payload = bytearray(ff.build_advertisement("BC", 9636, 0, 1, 2, 3))
    payload[2] = ord("Y")

    # Freelap sell more than one product under this company identifier, so
    # matching the company alone is not enough to call something a lap.
    assert ff.decode_advertisement(bytes(payload)) is None


@pytest.mark.parametrize("length", [0, 1, 2, 3, 10, ff.AD_PAYLOAD_LEN - 1])
def test_a_truncated_advertisement_is_rejected_not_misread(length):
    payload = ff.build_advertisement("BC", 9636, 0, 1, 2, 3)[:length]

    assert ff.decode_advertisement(payload) is None


def test_nothing_at_all_is_rejected():
    assert ff.decode_advertisement(None) is None
    assert ff.decode_advertisement(b"") is None
    assert ff.decode_scan_response(None) is None


def test_a_non_ascii_chip_prefix_is_rejected():
    payload = bytearray(ff.build_advertisement("BC", 9636, 0, 1, 2, 3))
    payload[4] = 0xFF

    assert ff.decode_advertisement(bytes(payload)) is None


def test_decoding_does_not_mutate_the_payload():
    payload = ff.build_advertisement("BC", 9636, 0, 1, 2, 3)
    before = bytes(payload)

    ff.decode_advertisement(payload)
    ff.decode_advertisement(payload)

    assert payload == before


# ---------------------------------------------------------------------------
# The company-identifier shape question (#60)
# ---------------------------------------------------------------------------

def test_a_payload_without_the_company_prefix_still_decodes():
    payload = ff.build_advertisement("BC", 9636, 0, 3585, 3585, 14337)

    # Connect IQ may hand us the manufacturer data with or without the two
    # bytes it matched on; the SDK does not say. Being two bytes out on every
    # field would decode to plausible nonsense, so both shapes are accepted.
    stripped = ff.decode_advertisement(payload[2:], require_company_id=False)

    assert stripped is not None
    assert stripped.chip == "BC-9636"


def test_a_scan_response_without_the_company_prefix_still_decodes():
    laps = [6231, 8611]
    payload = ff.build_scan_response(laps)

    assert ff.decode_scan_response(payload[2:], require_company_id=False) == laps


# ---------------------------------------------------------------------------
# Arithmetic
# ---------------------------------------------------------------------------

def test_the_segments_of_a_rep_sum_to_its_total():
    advertisement = ff.decode_advertisement(
        ff.build_advertisement("BC", 9636, 0, 3585, 3585, 14337))
    laps = [6231, 8611, 10668]

    # The cheapest possible check that a frame was read correctly: the legs of
    # a rep have to add up to the rep.
    assert sum(ff.segments(advertisement, laps)) == advertisement.split()


def test_a_rep_with_no_intermediates_has_one_segment():
    advertisement = ff.decode_advertisement(
        ff.build_advertisement("BC", 9636, 0, 3585, 3585, 14337))

    assert ff.segments(advertisement, []) == [10752]


def test_the_final_segment_comes_from_the_advertisement_not_the_scan_response():
    advertisement = ff.decode_advertisement(
        ff.build_advertisement("BC", 9636, 0, 3585, 3585, 14337))

    # The scan response holds crossings, and the finish is not one of them.
    # Forgetting this loses the last leg of every rep, which would look like a
    # course misconfiguration rather than a decoding bug.
    assert ff.segments(advertisement, [6231, 8611, 10668])[-1] == 14337 - 10668


def test_cumulative_times_are_measured_from_the_offset():
    advertisement = ff.decode_advertisement(
        ff.build_advertisement("BC", 9636, 0, 3585, 3585, 14337))

    assert ff.cumulative(advertisement, [6231]) == [6231 - 3585, 14337 - 3585]


def test_the_masks_diverge_once_the_high_bits_are_set():
    wide = ff.decode_advertisement(
        ff.build_advertisement("BC", 1, 0, 0x00FF0000, 0, 0x01FF0000))

    # This is the case the vendor's example cannot reach and #6 has to settle.
    # If these ever compare equal, the ambiguity has stopped mattering and #6
    # should be reread rather than this test relaxed.
    assert wide.split(ff.MASK_NARROW) != wide.split(ff.MASK_WIDE)


@pytest.mark.parametrize("ticks,truncated,rounded", [
    (10752, 1050, 1050),   # exact
    (2646, 258, 258),      # agree
    (2057, 200, 201),      # the segment that disagrees in the vendor document
    (5026, 490, 491),
    (0, 0, 0),
])
def test_truncation_and_rounding_differ_where_the_document_and_the_app_differ(
        ticks, truncated, rounded):
    assert ff.to_centiseconds(ticks, "truncate") == truncated
    assert ff.to_centiseconds(ticks, "round") == rounded


def test_an_unknown_rounding_mode_is_refused():
    # Silently falling back to one of them would make a mismatch against
    # MyFreelap (#25) look like a decoding error.
    with pytest.raises(ValueError):
        ff.to_centiseconds(1000, "nearest")


@pytest.mark.parametrize("centiseconds,text", [
    (1050, "00:10.50"),
    (258, "00:02.58"),
    (0, "00:00.00"),
    (6000, "01:00.00"),
    (36000, "06:00.00"),
    (5999, "00:59.99"),
])
def test_times_render_the_way_myfreelap_shows_them(centiseconds, text):
    assert ff.format_time(centiseconds) == text


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

def test_the_chip_renders_as_the_id_printed_on_its_face():
    advertisement = ff.decode_advertisement(
        ff.build_advertisement("BC", 9636, 0, 1, 2, 3))

    assert advertisement.chip == "BC-9636"


def test_a_low_chip_id_is_padded_to_four_digits():
    advertisement = ff.decode_advertisement(
        ff.build_advertisement("AA", 42, 0, 1, 2, 3))

    # Whether the chip's case actually reads AA-0042 is an open question on
    # #63. Padding is the assumption; this test is where it is recorded, so
    # that hardware contradicting it fails here rather than confusing an
    # athlete whose watch disagrees with the thing in their hand.
    assert advertisement.chip == "AA-0042"


def test_two_chips_decode_independently():
    one = ff.decode_advertisement(ff.build_advertisement("BC", 9636, 1, 0, 0, 100))
    two = ff.decode_advertisement(ff.build_advertisement("ZZ", 1234, 7, 0, 0, 200))

    assert (one.chip, one.lap_number) == ("BC-9636", 1)
    assert (two.chip, two.lap_number) == ("ZZ-1234", 7)


@pytest.mark.parametrize("prefix,chip_id", [("B", 1), ("ABC", 1), ("BC", 0x10000)])
def test_an_impossible_identity_is_refused_at_build_time(prefix, chip_id):
    with pytest.raises(ValueError):
        ff.build_advertisement(prefix, chip_id, 0, 1, 2, 3)
