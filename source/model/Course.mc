using Toybox.Application;
using Toybox.Lang;

// Transmitter codes as they will be stored in the FIT file.
module TxCode {
    const UNKNOWN = 0;
    const START   = 1;
    const LAP     = 2;
    const FINISH  = 3;
}

// A course is an ordered list of transmitters with cumulative distance (m).
// Parsed from the settings string "S:0;L:30;L:60;F:100".
class Course {
    var codes = [];      // Array<Number> of TxCode
    var distances = [];  // Array<Float> cumulative metres
    var name = "";

    function initialize(spec as Lang.String, courseName as Lang.String) {
        name = courseName;
        parse(spec);
    }

    function parse(spec as Lang.String) as Void {
        codes = [];
        distances = [];
        var parts = splitString(spec, ";");
        for (var i = 0; i < parts.size(); i++) {
            var kv = splitString(parts[i], ":");
            if (kv.size() != 2) { continue; }
            var c = kv[0].toUpper();
            var code = TxCode.UNKNOWN;
            if (c.equals("S")) { code = TxCode.START; }
            else if (c.equals("L")) { code = TxCode.LAP; }
            else if (c.equals("F")) { code = TxCode.FINISH; }
            var d = kv[1].toFloat();
            if (d == null) { continue; }
            codes.add(code);
            distances.add(d);
        }
    }

    function size() as Lang.Number { return codes.size(); }

    function totalDistance() as Lang.Float {
        return codes.size() > 0 ? distances[codes.size() - 1] : 0.0;
    }

    // Returns the course index for the n-th crossing of a rep with the given
    // transmitter code, or -1 if it cannot be matched. Strategy: sequence
    // match by code (START must be index 0; FINISH must be last; LAPs in
    // order); fall back to plain index order when the chip gives no codes.
    function matchCrossing(crossingIdx as Lang.Number, code as Lang.Number) as Lang.Number {
        if (crossingIdx >= codes.size()) { return -1; }
        if (code == TxCode.UNKNOWN) { return crossingIdx; }
        if (codes[crossingIdx] == code) { return crossingIdx; }
        if (code == TxCode.FINISH && codes[codes.size() - 1] == TxCode.FINISH) {
            return codes.size() - 1;  // finished early: partial rep
        }
        return -1;
    }

    // Monkey C has no String.split in 3.1; minimal implementation.
    static function splitString(s as Lang.String, sep as Lang.String) as Lang.Array {
        var out = [];
        var str = s;
        while (true) {
            var idx = str.find(sep);
            if (idx == null) { out.add(str); break; }
            out.add(str.substring(0, idx));
            str = str.substring(idx + sep.length(), str.length());
        }
        return out;
    }

    static function loadActive() as Course {
        var app = Application.getApp();
        var n = app.getProperty("activeCourse");
        if (n == null) { n = 1; }
        var spec = app.getProperty("course" + n);
        if (spec == null || spec.equals("")) { spec = "S:0;F:30"; }
        return new Course(spec, "Course " + n);
    }
}
