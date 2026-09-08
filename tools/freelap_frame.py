#!/usr/bin/env python3
"""The FxChip BLE broadcast frame: build one, decode one, do the arithmetic.

This is the reference implementation. `FreelapProtocol.mc` on the watch has to
agree with it byte for byte (#7), and `fake_chip.py` builds its frames from it,
so the fake and the decoder cannot drift apart into agreeing with each other
about something wrong -- the rule in AGENTS.md.

The chip broadcasts; it never accepts a connection (#8). A rep arrives as two
fixed-layout payloads, both carried as Bluetooth manufacturer-specific data
under Freelap's registered company identifier:

  * the **advertisement** -- who the chip is, and the running totals for the
    rep. Sent for a bounded window after a Finish crossing.
  * the **scan response** -- the intermediate crossing times, if there were
    any. Whether Connect IQ can read this at all is still open (#60), which is
    why `decode_advertisement` is useful on its own and never needs the other.

Two things here are deliberately *not* decided, because the evidence to decide
them does not exist yet. Both are parameters rather than constants, and both
are #6's job to settle against a real capture:

  * `mask` -- the vendor document gives two different masks for the running
    totals in two different places. They agree until a counter's top bits are
    set and then diverge silently, so this cannot be guessed.
  * OFFSET versus FROMLAP -- the two origins are *equal* in the document's
    worked example, because it is a first lap. So the example cannot show how
    they differ, and a decoder that assumed they were interchangeable would
    pass every test we can write from it and then be wrong from the second lap
    of every session onwards. Treated as distinct here: OFFSET is the session
    origin, FROMLAP the current lap's.
  * rounding -- see `to_centiseconds`.

The layout itself comes from documentation Freelap shared in confidence. It is
implemented here because implementing it is the point; it is not reproduced or
quoted. See the note on issue #8.
"""

# Freelap's Bluetooth SIG registered company identifier. The vendor document is
# explicit that this is mandatory and must be tested to validate a frame, and it
# is also the only thing standing between us and decoding a stranger's beacon
# as a lap time.
COMPANY_ID = 0x0363

# 'X'. Marks the payload as an FxChip BLE frame rather than some other Freelap
# product sharing the company identifier.
FRAME_TYPE = 0x58

# The chip counts in its own ticks; this converts them to hundredths of a
# second. It is not a power of ten, so converting early and adding up the
# results accumulates error -- do the subtraction in ticks and convert once.
TICKS_PER_CENTISECOND = 10.24

# 27 payload bytes after the company identifier, three per lap.
MAX_LAPS = 9

# The advertisement's manufacturer payload, company identifier included.
AD_PAYLOAD_LEN = 26

MASK_NARROW = 0xFFFFFF
MASK_WIDE = 0x7FFFFFFF
DEFAULT_MASK = MASK_WIDE


class Advertisement:
    """One decoded advertisement payload."""

    def __init__(self, lap_number, prefix, chip_id, offset, from_lap, block,
                 hex_version, ble_version, battery, api_version):
        self.lap_number = lap_number
        self.prefix = prefix
        self.chip_id = chip_id
        self.offset = offset
        self.from_lap = from_lap
        self.block = block
        # Exposed raw and undecoded on purpose. The vendor document's own
        # worked example disagrees with itself about how to read these -- the
        # battery byte in particular decodes to a value its table does not
        # show -- and inventing a conversion to make the numbers look tidy
        # would be worse than admitting we do not know (#6).
        self.hex_version = hex_version
        self.ble_version = ble_version
        self.battery = battery
        self.api_version = api_version

    @property
    def chip(self):
        """The identity printed on the chip's face, e.g. 'BC-9636'.

        This is what the athlete types into Garmin Connect (#64) and what
        MyFreelap displays, so it has to render identically to both.

        Four digits, zero-padded. Freelap give the format publicly as
        "2 letters - 4 digits", and the chip's Bluetooth local name uses the
        same fixed-width shape, so an id of 42 reads AA-0042.
        """
        return "%s-%04d" % (self.prefix, self.chip_id)

    def lap(self, mask=DEFAULT_MASK):
        """Ticks in the current lap, measured from FROMLAP.

        Not the final segment -- for the first lap of a rep this is the whole
        rep, because FROMLAP and OFFSET coincide there. The last leg of a rep
        comes from `segments()`, which needs the scan response.
        """
        return (self.block & mask) - (self.from_lap & mask)

    def split(self, mask=DEFAULT_MASK):
        """Ticks from the session origin, OFFSET, to the finish."""
        return (self.block & mask) - (self.offset & mask)

    def __repr__(self):
        return "<Advertisement %s lap#%d block=%d>" % (
            self.chip, self.lap_number, self.block)


def _u16(data, i):
    return data[i] | (data[i + 1] << 8)


def _u24(data, i):
    return data[i] | (data[i + 1] << 8) | (data[i + 2] << 16)


def _u32(data, i):
    return data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)


def strip_company_id(payload):
    """Return the payload after the company identifier, or None if not ours.

    Connect IQ's `getManufacturerSpecificData(companyId)` is documented only as
    returning "Manufacturer Specific Data", and whether that includes the two
    company bytes it was asked to match on is not stated anywhere in the SDK.
    Rather than guess and be silently two bytes out on every field, both
    decoders here accept either shape and this is where that is decided. The
    watch's own answer is a #60 acceptance criterion.
    """
    if payload is None or len(payload) < 2:
        return None
    if _u16(payload, 0) == COMPANY_ID:
        return payload[2:]
    return payload


def decode_advertisement(payload, require_company_id=True):
    """Decode an advertisement payload, or return None if it is not ours.

    Returning None rather than raising is deliberate: at a track the app sees
    every phone, watch and heart-rate strap in range (#9), and a frame that is
    not Freelap's is the normal case, not a fault.
    """
    if payload is None:
        return None
    if require_company_id:
        if len(payload) < 2 or _u16(payload, 0) != COMPANY_ID:
            return None
    body = strip_company_id(payload)
    if body is None or len(body) < AD_PAYLOAD_LEN - 2:
        return None
    if body[0] != FRAME_TYPE:
        return None

    try:
        prefix = bytes(body[2:4]).decode("ascii")
    except UnicodeDecodeError:
        return None

    return Advertisement(
        lap_number=body[1],
        prefix=prefix,
        chip_id=_u16(body, 4),
        offset=_u32(body, 6),
        from_lap=_u32(body, 10),
        block=_u32(body, 14),
        hex_version=body[20],
        ble_version=body[21],
        battery=body[22],
        api_version=body[23],
    )


def decode_scan_response(payload, require_company_id=True):
    """Decode the intermediate lap timestamps. Trailing zeros are absent laps.

    A rep with no intermediate transmitters yields an empty list, which is not
    an error -- a start and a finish is a valid course.
    """
    if payload is None:
        return None
    if require_company_id:
        if len(payload) < 2 or _u16(payload, 0) != COMPANY_ID:
            return None
    body = strip_company_id(payload)
    if body is None:
        return None

    laps = []
    for i in range(MAX_LAPS):
        start = i * 3
        if start + 3 > len(body):
            break
        value = _u24(body, start)
        # Unused entries are zeroed. A zero after a non-zero would mean a
        # crossing at the chip's epoch, which is not a thing, so stop.
        if value == 0:
            break
        laps.append(value)
    return laps


def build_advertisement(prefix, chip_id, lap_number, offset, from_lap, block,
                        hex_version=0xA1, ble_version=0xD2, battery=0x33,
                        api_version=0x11, unused=0x00, eof=0x0D):
    """The manufacturer payload of an advertisement, company identifier first."""
    if len(prefix) != 2:
        raise ValueError("chip prefix is two characters, got %r" % (prefix,))
    if not 0 <= chip_id <= 0xFFFF:
        raise ValueError("chip id does not fit in 16 bits: %r" % (chip_id,))

    out = bytearray()
    out += bytes([COMPANY_ID & 0xFF, (COMPANY_ID >> 8) & 0xFF])
    out += bytes([FRAME_TYPE, lap_number & 0xFF])
    out += prefix.encode("ascii")
    out += bytes([chip_id & 0xFF, (chip_id >> 8) & 0xFF])
    for value in (offset, from_lap, block):
        out += bytes([value & 0xFF, (value >> 8) & 0xFF,
                      (value >> 16) & 0xFF, (value >> 24) & 0xFF])
    out += bytes([unused, eof, hex_version, ble_version, battery, api_version])
    assert len(out) == AD_PAYLOAD_LEN, len(out)
    return bytes(out)


def build_scan_response(laps):
    """The manufacturer payload of a lap-mode scan response."""
    if len(laps) > MAX_LAPS:
        raise ValueError("at most %d laps fit in a scan response, got %d"
                         % (MAX_LAPS, len(laps)))
    out = bytearray([COMPANY_ID & 0xFF, (COMPANY_ID >> 8) & 0xFF])
    for value in laps:
        if not 0 <= value <= 0xFFFFFF:
            raise ValueError("lap timestamp does not fit in 24 bits: %r" % (value,))
        out += bytes([value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF])
    out += bytes(3 * (MAX_LAPS - len(laps)))
    return bytes(out)


def segments(advertisement, laps, mask=DEFAULT_MASK):
    """Ticks for each leg of the rep, in order, finish segment included.

    The scan response holds the *crossing* timestamps, not durations, and it
    does not hold the finish -- that is in the advertisement. So a rep with
    three intermediates has four legs, and the last one has to be derived.
    Their sum equals the rep total, which is the cheapest check there is that
    a frame was decoded correctly.
    """
    out = []
    previous = advertisement.from_lap & mask
    for value in laps:
        out.append(value - previous)
        previous = value
    out.append((advertisement.block & mask) - previous)
    return out


def cumulative(advertisement, laps, mask=DEFAULT_MASK):
    """Ticks from the start to each crossing, finish included."""
    origin = advertisement.offset & mask
    out = [value - origin for value in laps]
    out.append((advertisement.block & mask) - origin)
    return out


def to_centiseconds(ticks, rounding="round"):
    """Convert chip ticks to hundredths of a second.

    `rounding` is a parameter because the two authorities disagree, and we have
    to match one of them. The vendor document's worked example **truncates**;
    the MyFreelap screenshot printed beside it **rounds**, which is how the same
    rep is 02.00 in the text and 02.01 in the picture. Only one segment in that
    example is near enough to a boundary to tell them apart, so this is one
    observation, not a proof.

    The default is "round", because #25 validates the watch against MyFreelap
    and matching the thing we are compared to is what that criterion asks. Store
    the ticks, not the conversion, and convert once for display.
    """
    if rounding == "truncate":
        return int(ticks / TICKS_PER_CENTISECOND)
    if rounding == "round":
        return int(round(ticks / TICKS_PER_CENTISECOND))
    raise ValueError("rounding is 'round' or 'truncate', got %r" % (rounding,))


def format_time(centiseconds):
    """mm:ss.cc, the way MyFreelap shows it."""
    negative = centiseconds < 0
    centiseconds = abs(centiseconds)
    text = "%02d:%02d.%02d" % (centiseconds // 6000,
                               (centiseconds // 100) % 60,
                               centiseconds % 100)
    return "-" + text if negative else text
