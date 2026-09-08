using Toybox.Lang;
using Toybox.Math;

// The FxChip BLE broadcast frame (issue #7).
//
// The chip broadcasts and never accepts a connection (#8), so there is no
// stream, no notification and no fragment to reassemble. A rep arrives as two
// fixed-layout payloads carried as Bluetooth manufacturer-specific data under
// Freelap's registered company identifier:
//
//   * the advertisement - who the chip is, and the rep's running totals;
//   * the scan response - the intermediate crossing times, if any. Whether
//     Connect IQ can read that half at all is still open (#60), which is why
//     nothing here needs it: an advertisement decodes on its own.
//
// This is a mirror of `tools/freelap_frame.py` and **the two must change in
// the same commit** (AGENTS.md). That matters more than usual here, because
// the Python side is the only one that can be checked against the vendor's
// worked example - the example is confidential and cannot live in this repo,
// so the chain of trust runs: vendor document -> freelap_frame.py -> the
// vectors in ProtocolVectorTest.mc -> this file. Break the mirror and the
// far end of that chain is gone.
//
// Everything here is pure: it takes bytes and returns values, touches no BLE
// API and holds no state, so it is testable without a radio (AGENTS.md,
// "Inject, don't fetch").
module BroadcastFrame {

    // Freelap's Bluetooth SIG registered company identifier. The vendor
    // document is explicit that this must be tested to validate a frame, and
    // it is the only thing standing between us and decoding a stranger's
    // beacon as a lap time.
    const COMPANY_ID = 0x0363;

    // 'X'. Freelap sell more than one product under that company identifier,
    // so matching the company alone is not enough to call something a lap.
    const FRAME_TYPE = 0x58;

    // The chip's tick is 1/1024 s, which is why this is 10.24 and not a round
    // number. It is not a power of ten, so converting each leg before adding
    // them up accumulates error: subtract in ticks, convert once.
    const TICKS_PER_CENTISECOND = 10.24;

    // 27 bytes of scan-response payload after the company identifier, three
    // per lap.
    const MAX_LAPS = 9;

    // The advertisement payload, company identifier included.
    const AD_PAYLOAD_LEN = 26;
    const AD_BODY_LEN = 24;

    // The vendor document gives two different masks for the running totals in
    // two different places, and its worked example cannot tell them apart -
    // the counters in it are far too small to reach the bits where they
    // differ. Left as a choice rather than a guess until a capture settles it
    // (#6). MASK_WIDE is what the worked example's own arithmetic uses.
    const MASK_NARROW = 0xFFFFFFl;
    const MASK_WIDE = 0x7FFFFFFFl;

    // ---- decoding ----------------------------------------------------------

    // A decoded advertisement, or null if the payload is not one.
    //
    // Null rather than an exception on purpose: at a track the watch sees
    // every phone, watch and heart-rate strap in range, and Connect IQ has no
    // scan filter (#9), so a frame that is not Freelap's is the normal case
    // and not a fault condition.
    //
    // Accepts the payload with or without its leading company identifier. The
    // SDK does not say whether getManufacturerSpecificData() returns the two
    // bytes it was asked to match on, and being two bytes out on every field
    // would decode to plausible nonsense rather than to an error. When the
    // identifier is there it is checked; when it is not, the caller is taken
    // to have matched it already, which is what that call does. The frame type
    // is checked either way. #60 settles which shape a watch really hands us.
    function decodeAdvertisement(data) as Advertisement? {
        var body = advertisementBody(data);
        if (body == null) { return null; }
        if (body[0] != FRAME_TYPE) { return null; }

        var prefix = ascii(body, 2, 2);
        if (prefix == null) { return null; }

        var out = new Advertisement();
        out.lapNumber = body[1];
        out.prefix = prefix;
        out.chipId = u16(body, 4);
        out.offset = u32(body, 6);
        out.fromLap = u32(body, 10);
        out.block = u32(body, 14);
        out.hexVersion = body[20];
        out.bleVersion = body[21];
        out.battery = body[22];
        out.apiVersion = body[23];
        return out;
    }

    // The intermediate crossing timestamps, in ticks. Empty is not an error -
    // a start and a finish is a perfectly good course.
    function decodeScanResponse(data) as Lang.Array<Lang.Number>? {
        if (data == null || !(data instanceof Lang.ByteArray)) { return null; }

        var body = data;
        if (data.size() >= 2 && u16(data, 0) == COMPANY_ID) {
            body = data.slice(2, null);
        }

        var laps = [] as Lang.Array<Lang.Number>;
        for (var i = 0; i < MAX_LAPS; i++) {
            var at = i * 3;
            if (at + 3 > body.size()) { break; }
            var value = u24(body, at);
            // Unused entries are zeroed. A zero after a real one would be a
            // crossing at the chip's epoch, which does not happen, so stop.
            if (value == 0) { break; }
            laps.add(value);
        }
        return laps;
    }

    // ---- arithmetic --------------------------------------------------------

    // Ticks for each leg of the rep, in order, the finish included.
    //
    // The scan response holds *crossings*, not durations, and the finish is
    // not one of them - it is in the advertisement. Forgetting that loses the
    // last leg of every rep, and it looks like a misconfigured course rather
    // than a decoding bug, which is why it has its own test.
    function segments(advertisement as Advertisement, laps as Lang.Array<Lang.Number>,
                      mask as Lang.Long) as Lang.Array<Lang.Number> {
        var out = [] as Lang.Array<Lang.Number>;
        var previous = advertisement.fromLap & mask;
        for (var i = 0; i < laps.size(); i++) {
            var at = laps[i].toLong();
            out.add((at - previous).toNumber());
            previous = at;
        }
        out.add(((advertisement.block & mask) - previous).toNumber());
        return out;
    }

    // Ticks from the session origin to each crossing, the finish included.
    function cumulative(advertisement as Advertisement, laps as Lang.Array<Lang.Number>,
                        mask as Lang.Long) as Lang.Array<Lang.Number> {
        var origin = advertisement.offset & mask;
        var out = [] as Lang.Array<Lang.Number>;
        for (var i = 0; i < laps.size(); i++) {
            out.add((laps[i].toLong() - origin).toNumber());
        }
        out.add(((advertisement.block & mask) - origin).toNumber());
        return out;
    }

    // Chip ticks to hundredths of a second.
    //
    // `rounding` is a parameter because the two authorities disagree and we
    // have to match one of them: the vendor document's worked example
    // truncates, and the MyFreelap screenshot printed beside it rounds - which
    // is how the same rep is 02.00 in the text and 02.01 in the picture. Only
    // one leg in that example is near enough to a boundary to tell them apart,
    // so this is one observation rather than a proof.
    //
    // :round is what the app uses, because #25 validates the watch against
    // MyFreelap and matching what we are measured against is what that asks.
    function toCentiseconds(ticks as Lang.Number, rounding as Lang.Symbol) as Lang.Number {
        var value = ticks / TICKS_PER_CENTISECOND;
        if (rounding == :truncate) { return value.toNumber(); }
        return Math.round(value).toNumber();
    }

    // mm:ss.cc, the way MyFreelap shows it.
    function formatTime(centiseconds as Lang.Number) as Lang.String {
        var negative = centiseconds < 0;
        var cs = negative ? -centiseconds : centiseconds;
        var text = (cs / 6000).format("%02d") + ":" +
                   ((cs / 100) % 60).format("%02d") + "." +
                   (cs % 100).format("%02d");
        return negative ? "-" + text : text;
    }

    // ---- byte helpers ------------------------------------------------------
    //
    // Module functions cannot be `hidden` in Monkey C, so these are reachable.
    // They are helpers, not API; the decoders above are the way in.

    // The advertisement payload with any company identifier removed, or null
    // if this is not an advertisement at all.
    function advertisementBody(data) as Lang.ByteArray? {
        if (data == null || !(data instanceof Lang.ByteArray)) { return null; }

        if (data.size() >= AD_PAYLOAD_LEN && u16(data, 0) == COMPANY_ID) {
            return data.slice(2, null);
        }
        // No identifier: the caller matched it. There is no ambiguity between
        // the two shapes because a body begins with the frame type, which is
        // not the low byte of the company identifier.
        if (data.size() >= AD_BODY_LEN) { return data; }
        return null;
    }

    function u16(data as Lang.ByteArray, at as Lang.Number) as Lang.Number {
        return data[at] | (data[at + 1] << 8);
    }

    function u24(data as Lang.ByteArray, at as Lang.Number) as Lang.Number {
        return data[at] | (data[at + 1] << 8) | (data[at + 2] << 16);
    }

    // As a Long: a 32-bit counter with its top bit set does not fit a Monkey C
    // Number, which is signed, and would come back negative.
    function u32(data as Lang.ByteArray, at as Lang.Number) as Lang.Long {
        return data[at].toLong()
             | (data[at + 1].toLong() << 8)
             | (data[at + 2].toLong() << 16)
             | (data[at + 3].toLong() << 24);
    }

    // `length` bytes as printable ASCII, or null if any of them is not.
    function ascii(data as Lang.ByteArray, at as Lang.Number,
                          length as Lang.Number) as Lang.String? {
        var out = "";
        for (var i = 0; i < length; i++) {
            var c = data[at + i];
            if (c < 0x20 || c > 0x7E) { return null; }
            out += c.toChar().toString();
        }
        return out;
    }
}

// One decoded advertisement.
class Advertisement {

    var lapNumber as Lang.Number = 0;
    var prefix as Lang.String = "";
    var chipId as Lang.Number = 0;

    // Kept as Longs: these are 32-bit counters and a Monkey C Number is
    // signed, so a chip that has been running a while would read negative.
    var offset as Lang.Long = 0l;
    var fromLap as Lang.Long = 0l;
    var block as Lang.Long = 0l;

    // Raw and undecoded on purpose. The vendor document's worked example gives
    // readings for these that do not follow any single rule from the bytes
    // beside them - the battery byte decodes to 51 where its table shows -31 -
    // and inventing a conversion to make the numbers look tidy would be worse
    // than admitting we do not know (#6).
    var hexVersion as Lang.Number = 0;
    var bleVersion as Lang.Number = 0;
    var battery as Lang.Number = 0;
    var apiVersion as Lang.Number = 0;

    function initialize() {}

    // The identity printed on the chip's face, e.g. "BC-9636". This is what
    // the athlete types into Garmin Connect (#64) and what MyFreelap shows, so
    // it must render identically to both - Settings.normaliseChipId produces
    // the same string from what they type, and a test asserts they agree.
    //
    // Four digits, zero-padded: Freelap's FAQ gives the format as "2 letters -
    // 4 digits", and the chip's Bluetooth local name uses the same fixed-width
    // shape.
    function chip() as Lang.String {
        return prefix + "-" + chipId.format("%04d");
    }

    // The current lap, measured from FROMLAP. Not the final leg: for the first
    // lap of a rep this is the whole rep, because FROMLAP and OFFSET coincide
    // there. The last leg comes from BroadcastFrame.segments().
    function lap(mask as Lang.Long) as Lang.Number {
        return ((block & mask) - (fromLap & mask)).toNumber();
    }

    // The whole rep, measured from the session origin OFFSET.
    function split(mask as Lang.Long) as Lang.Number {
        return ((block & mask) - (offset & mask)).toNumber();
    }
}
