using Toybox.Lang;

// One entry in the on-watch course list.
class CourseEntry {
    var index = 0;         // the settings slot, 1..8
    var spec = "";
    hidden var _course = null;

    function initialize(slot as Lang.Number, courseSpec as Lang.String) {
        index = slot;
        spec = courseSpec;
        _course = new Course(courseSpec, "Course " + slot.format("%d"));
    }

    function course() as Course { return _course; }

    function label() as Lang.String { return _course.name; }

    // The line under the name: the distance to run, or the reason this course
    // cannot be used. An unusable course stays in the list rather than being
    // hidden - a slot that silently vanishes just leaves the athlete
    // wondering where it went.
    function detail() as Lang.String {
        if (!_course.valid) { return _course.error; }
        var text = _course.totalDistance().format("%.0f") + "m";
        if (!_course.warning.equals("")) { text += "  " + _course.warning; }
        return text;
    }

    function usable() as Lang.Boolean { return _course.valid; }
}

// Choosing a course on the watch, without reaching for a phone.
//
// The rules live here rather than in the menu delegate so they can be tested
// without a view stack; the delegate is the thin part that draws them.
module CourseMenu {

    // Every slot the athlete has actually filled in. Slot numbers are kept, so
    // an empty slot 3 does not renumber slots 4 upwards - the number on screen
    // is the one in Garmin Connect.
    function entries() as Lang.Array {
        var out = [];
        var specs = Settings.courseSpecs();
        for (var i = 0; i < specs.size(); i++) {
            var spec = specs[i] as Lang.String;
            if (spec.equals("")) { continue; }
            out.add(new CourseEntry(i + 1, spec));
        }
        return out;
    }

    // Choose a configured slot. Clears any quick course, which would otherwise
    // keep overriding the choice the athlete just made.
    function select(slot as Lang.Number) as Course {
        Settings.setActiveCourseIndex(slot);
        Settings.clearQuickCourse();
        return Course.loadActive();
    }

    // Choose a quick course: a start line and a finish line, `metres` apart.
    function selectQuick(metres as Lang.Number) as Course {
        Settings.setQuickDistanceM(metres);
        return Course.loadActive();
    }

    // One step of the distance picker. Stops at the ends rather than wrapping:
    // going from 400 m to 10 m on a long press would be a nasty surprise.
    function nextQuickDistance(metres as Lang.Number, direction as Lang.Number) as Lang.Number {
        return Settings.clampQuickDistance(metres + direction * Settings.QUICK_STEP_M);
    }

    // The course belongs to the session once one is running: changing it would
    // re-derive the distances of splits already written. True while there is
    // no session, including after a save.
    function canChoose(recorder) as Lang.Boolean {
        return recorder == null || recorder.session == null;
    }
}
