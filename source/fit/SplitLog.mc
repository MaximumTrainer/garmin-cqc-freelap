using Toybox.Lang;

// Every split of the session, kept for export (issue #19) and written to
// Application.Storage once, at save.
//
// It has to be bounded, for the same reason CaptureLog does and one more:
//
//   * memory. A two-hour session is 60-plus reps; unbounded growth on a device
//     with a 64 KB app budget is how a session ends in an out-of-memory crash
//     two hours in, which is the worst possible moment.
//   * a stored value has a size limit (around 8 KB for the whole app on API
//     3.1 devices). Writing 60 reps' worth of ten-element rows past that limit
//     does not warn - the write simply fails, and the export the athlete is
//     relying on is not there.
//
// When the cap is reached the *oldest* rows go. The last reps of a session are
// the ones being looked at afterwards, and a truncated tail would be silent
// where a truncated head is visible in the rep numbers.
//
// Nothing here touches Toybox beyond Lang.
class SplitLog {
    // 60 reps of 5 crossings, which is more than the two-hour session issue
    // #26 sizes for. At ten values a row that is 3000 values, comfortably
    // inside an 8 KB allowance.
    static const MAX_ROWS = 300;

    var rows = [] as Lang.Array;
    var seen = 0;      // splits ever recorded, including dropped
    var dropped = 0;   // rows aged out

    function initialize() {}

    function add(row as Lang.Array) as Void {
        seen++;
        rows.add(row);
        while (rows.size() > MAX_ROWS) {
            rows = rows.slice(1, null);
            dropped++;
        }
    }

    function size() as Lang.Number { return rows.size(); }

    function clear() as Void {
        rows = [] as Lang.Array;
        seen = 0;
        dropped = 0;
    }

    function complete() as Lang.Boolean { return dropped == 0; }

    // One write, to whatever answers setValue(key, value).
    function flush(sink, key as Lang.String) as Lang.Boolean {
        if (rows.size() == 0) { return false; }
        sink.setValue(key, rows);
        return true;
    }

    // Replace the log with what was stored, so a dump after an app restart
    // shows the last session rather than an empty log.
    function restore(source, key as Lang.String) as Lang.Boolean {
        var stored = source.getValue(key);
        if (stored == null || !(stored instanceof Lang.Array)) { return false; }
        rows = stored as Lang.Array;
        seen = rows.size();
        dropped = 0;   // unknown after a restart; the count did not survive
        return true;
    }

    // One row as a JSON array, for the console dump. Printed a row at a time
    // rather than assembled into one string: 300 rows would be a 15 KB
    // allocation on a device where that matters.
    function rowAsJson(index as Lang.Number) as Lang.String {
        var row = rows[index] as Lang.Array;
        var out = "[";
        for (var i = 0; i < row.size(); i++) {
            if (i > 0) { out += ","; }
            out += valueAsJson(row[i]);
        }
        return out + "]";
    }

    hidden function valueAsJson(value) as Lang.String {
        if (value instanceof Lang.Boolean) { return value ? "true" : "false"; }
        if (value instanceof Lang.Float || value instanceof Lang.Double) {
            return value.format("%.7f");
        }
        return value.toString();
    }
}
