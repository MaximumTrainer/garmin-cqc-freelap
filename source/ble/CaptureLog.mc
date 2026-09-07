using Toybox.Lang;

// The rolling raw-packet log behind the captureMode setting.
//
// Its whole reason to exist is reverse-engineering the chip in the field
// without a laptop: run a rep, look at the hex on the watch, dump it later.
// Two constraints shape it:
//
//   * Application.Storage is flash. Writing per packet would burn the flash
//     and, worse, block long enough to drop the notifications that follow -
//     a fragmented burst arrives a few milliseconds apart. Nothing here
//     writes; flush() does, once, and the delegate calls it on stop().
//   * A stored value has a size limit (the whole app allowance is around 8 KB
//     on API 3.1 devices). The log is bounded by packet count *and* by total
//     characters, because a chip that fragments hard produces many more, and
//     smaller, packets than the 60-packet cap assumes.
//
// Nothing here touches Toybox beyond Lang, so it tests without a radio.
class CaptureLog {
    // Issue #12 asks for at least 60 packets.
    static const MAX_PACKETS = 60;
    // 60 full 20-byte notifications is 2400 hex characters; this leaves room
    // for the arrival stamps and the array overhead inside an 8 KB allowance.
    static const MAX_CHARS = 3200;

    // The handle column in the TSV. Real captures carry the ATT handle the
    // notification arrived on; the watch does not expose it, so this is a
    // placeholder that keeps the column count right for decode_capture.py.
    static const HANDLE = "0x0000";

    var rows = [] as Lang.Array;   // [arrivalMs, hex] oldest first
    var seen = 0;                  // packets ever offered, including dropped
    var dropped = 0;               // packets aged out of the window

    function initialize() {}

    function add(arrivalMs as Lang.Number, hex as Lang.String) as Void {
        seen++;
        rows.add([arrivalMs, hex]);
        trim();
    }

    function size() as Lang.Number { return rows.size(); }

    function totalChars() as Lang.Number {
        var n = 0;
        for (var i = 0; i < rows.size(); i++) {
            n += (rows[i][1] as Lang.String).length();
        }
        return n;
    }

    function clear() as Void {
        rows = [] as Lang.Array;
        seen = 0;
        dropped = 0;
    }

    // One write, to whatever answers setValue(key, value). The delegate passes
    // an adapter over Application.Storage; a test passes a counter.
    function flush(sink, key as Lang.String) as Lang.Boolean {
        if (rows.size() == 0) { return false; }
        sink.setValue(key, rows);
        return true;
    }

    // The shape tools/decode_capture.py reads: arrival, handle, hex, tab
    // separated, one notification per line. Arrival is the watch's monotonic
    // millisecond timer rendered as seconds, not a wall-clock epoch - relative
    // gaps between packets are what the decoder actually uses.
    function toTsv() as Lang.String {
        var out = "";
        for (var i = 0; i < rows.size(); i++) {
            var arrival = rows[i][0] as Lang.Number;
            out += (arrival / 1000).format("%d") + "." +
                   (arrival % 1000).format("%03d") + "\t" +
                   HANDLE + "\t" + rows[i][1] + "\n";
        }
        return out;
    }

    hidden function trim() as Void {
        while (rows.size() > MAX_PACKETS || (rows.size() > 1 && totalChars() > MAX_CHARS)) {
            rows = rows.slice(1, null);
            dropped++;
        }
    }
}
