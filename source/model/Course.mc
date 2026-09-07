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
//
// Validation is deliberately all-or-nothing: a spec the athlete got wrong
// yields *no* transmitters rather than the prefix that happened to parse.
// Half a course is worse than none, because every split derived from it would
// be over the wrong distance and would still look plausible in the FIT file.
//
//   valid == false   rejected. codes/distances are empty and `error` says why.
//   warning != ""    parsed, but worth telling the athlete: a segment was
//                    dropped, there is no FINISH, or this is the fallback.
//   openEnded        parsed, but the last transmitter is not a FINISH.
//
// Nothing here touches Toybox beyond Lang, apart from loadActive(), so the
// whole thing runs under `monkeydo /t` without settings or a radio.
class Course {
    // The course used when the setting is empty or cannot be parsed.
    static const DEFAULT_SPEC = "S:0;F:30";

    var codes = [] as Lang.Array<Lang.Number>;      // TxCode per transmitter
    var distances = [] as Lang.Array<Lang.Float>;   // cumulative metres
    var name = "";
    var valid = false;
    var error = "";
    var warning = "";
    var openEnded = false;
    // True when this is DEFAULT_SPEC standing in for a spec that was rejected.
    // The athlete needs to know the course on screen is not the one they typed.
    var usingFallback = false;

    function initialize(spec as Lang.String, courseName as Lang.String) {
        name = courseName;
        parse(spec);
    }

    function parse(spec as Lang.String) as Void {
        codes = [] as Lang.Array<Lang.Number>;
        distances = [] as Lang.Array<Lang.Float>;
        valid = true;
        error = "";
        warning = "";
        openEnded = false;

        if (spec == null || spec.length() == 0) {
            reject("course is empty");
            return;
        }

        var dropped = 0;
        var parts = splitString(spec, ";");
        for (var i = 0; i < parts.size(); i++) {
            var segment = parts[i];
            if (segment.length() == 0) { continue; }

            var kv = splitString(segment, ":");
            if (kv.size() != 2) {
                // Not "code:distance" at all. One fat-fingered separator should
                // not throw away a course the athlete otherwise typed correctly,
                // so drop the segment and say so.
                dropped++;
                continue;
            }

            var letter = kv[0].toUpper();
            var code = codeFor(letter);
            if (code == null) {
                reject("unknown code '" + kv[0] + "'");
                return;
            }

            var d = kv[1].toFloat();
            if (d == null) {
                reject("'" + kv[1] + "' is not a number");
                return;
            }
            if (d < 0) {
                reject("negative distance " + kv[1]);
                return;
            }
            if (distances.size() > 0 && d <= distances[distances.size() - 1]) {
                // Equal distances give a zero-length split, and a divide by
                // zero downstream; decreasing ones give a negative one.
                reject("distances must increase");
                return;
            }

            codes.add(code);
            distances.add(d);
        }

        if (codes.size() < 2) {
            reject("needs 2+ transmitters");
            return;
        }

        if (dropped > 0) {
            addWarning(dropped.format("%d") + " segment(s) ignored");
        }
        if (codes[codes.size() - 1] != TxCode.FINISH) {
            openEnded = true;
            addWarning("no FINISH transmitter");
        }
    }

    // The one line to put on the screen after a settings change: the reason
    // the course was rejected, or the caveat about the one in force. Empty
    // when there is nothing to say.
    function problem() as Lang.String {
        if (!error.equals("")) { return error; }
        return warning;
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

    // ---- internals --------------------------------------------------------

    hidden function reject(why as Lang.String) as Void {
        codes = [] as Lang.Array<Lang.Number>;
        distances = [] as Lang.Array<Lang.Float>;
        valid = false;
        openEnded = false;
        error = why;
    }

    function addWarning(text as Lang.String) as Void {
        warning = warning.equals("") ? text : warning + "; " + text;
    }

    hidden static function codeFor(letter as Lang.String) as Lang.Number? {
        if (letter.equals("S")) { return TxCode.START; }
        if (letter.equals("L")) { return TxCode.LAP; }
        if (letter.equals("F")) { return TxCode.FINISH; }
        return null;
    }

    // Monkey C has no String.split in 3.1; minimal implementation.
    static function splitString(s as Lang.String, sep as Lang.String) as Lang.Array<Lang.String> {
        var out = [] as Lang.Array<Lang.String>;
        var str = s;
        while (true) {
            var idx = str.find(sep);
            if (idx == null) { out.add(str); break; }
            out.add(str.substring(0, idx));
            str = str.substring(idx + sep.length(), str.length());
        }
        return out;
    }

    // The seam the app uses: always returns a course that can record, and
    // carries the reason in `warning` when that course is the fallback rather
    // than the one the athlete typed. Free of Toybox settings on purpose.
    static function fromSpec(spec as Lang.String?, courseName as Lang.String) as Course {
        var wanted = new Course(spec == null ? "" : spec, courseName);
        if (wanted.valid) { return wanted; }

        var fallback = new Course(DEFAULT_SPEC, courseName);
        fallback.usingFallback = true;
        // Only the reason goes in the warning: it is drawn on a watch face,
        // and "the default is in force" is already visible as the distance.
        fallback.addWarning(wanted.error);
        return fallback;
    }

    static function loadActive() as Course {
        // A quick course dialled on the watch overrides the configured slot
        // until it is cleared (issue #22).
        var quick = Settings.quickDistanceM();
        if (quick > 0) {
            return fromSpec(Settings.quickCourseSpec(quick),
                            "Quick " + quick.format("%d") + "m");
        }
        var n = Settings.activeCourseIndex();
        return fromSpec(Settings.courseSpec(n), "Course " + n.format("%d"));
    }
}
