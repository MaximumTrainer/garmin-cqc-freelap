using Toybox.Application.Properties;
using Toybox.Lang;

// The one place the app reads Garmin Connect / Express settings.
//
// Everything below returns a usable value whatever is in storage: a setting
// can be absent (first run, or a property added in a later version), the wrong
// type, or out of range, and none of those should reach the domain. The
// domain objects take their configuration as arguments and never look here
// (AGENTS.md, "Inject, don't fetch"); this module is the app layer's reader.
module Settings {

    // Issue #23: up to eight courses. Slots the athlete has not filled in are
    // empty strings and are skipped by the on-watch course menu.
    const MAX_COURSES = 8;

    const DEFAULT_LATENCY_MS = 150;

    // Quick course bounds, in metres (issue #22).
    const QUICK_MIN_M = 10;
    const QUICK_MAX_M = 400;
    const QUICK_STEP_M = 5;

    // ---- normalisers -------------------------------------------------------
    //
    // Each takes the raw stored value - which may be null, or the wrong type,
    // or out of range - and returns something the app can use. They are pure
    // so the awkward cases can be tested directly: Properties.setValue will
    // not accept null, so "the property is absent" is not reachable by writing
    // to storage, only by calling these.

    function normaliseSpec(raw) as Lang.String {
        return raw == null || !(raw instanceof Lang.String) ? "" : raw;
    }

    // A value outside 1..8 means the property was written by a different
    // version of the app, or by hand. Clamping beats the alternative, which is
    // Course.loadActive reading "course0" and silently running the default.
    function normaliseCourseIndex(raw) as Lang.Number {
        if (raw == null || !(raw instanceof Lang.Number)) { return 1; }
        return clampCourseIndex(raw);
    }

    function clampCourseIndex(index as Lang.Number) as Lang.Number {
        if (index < 1) { return 1; }
        if (index > MAX_COURSES) { return MAX_COURSES; }
        return index;
    }

    // A negative latency would place crossings *after* the packet arrived.
    function normaliseLatency(raw) as Lang.Number {
        if (raw == null || !(raw instanceof Lang.Number) || raw < 0) { return DEFAULT_LATENCY_MS; }
        return raw;
    }

    function normaliseBool(raw, fallback as Lang.Boolean) as Lang.Boolean {
        if (raw == null) { return fallback; }
        return raw ? true : false;
    }

    // 0 means no quick course is in force.
    function normaliseQuick(raw) as Lang.Number {
        if (raw == null || !(raw instanceof Lang.Number) || raw <= 0) { return 0; }
        return clampQuickDistance(raw);
    }

    // Snapped to the step and held inside the bounds, so a value typed into
    // settings by hand cannot produce a course the on-watch picker could never
    // have made.
    function clampQuickDistance(metres as Lang.Number) as Lang.Number {
        var snapped = ((metres + QUICK_STEP_M / 2) / QUICK_STEP_M) * QUICK_STEP_M;
        if (snapped < QUICK_MIN_M) { return QUICK_MIN_M; }
        if (snapped > QUICK_MAX_M) { return QUICK_MAX_M; }
        return snapped;
    }

    // The spec a quick course of `metres` produces: start line to finish line.
    function quickCourseSpec(metres as Lang.Number) as Lang.String {
        return "S:0;F:" + metres.format("%d");
    }

    // ---- readers -----------------------------------------------------------

    function courseSpec(index as Lang.Number) as Lang.String {
        return normaliseSpec(Properties.getValue("course" + index.format("%d")));
    }

    // Every configured spec, in slot order. Empty slots stay in so the array
    // index matches activeCourse.
    function courseSpecs() as Lang.Array<Lang.String> {
        var out = [] as Lang.Array<Lang.String>;
        for (var i = 1; i <= MAX_COURSES; i++) {
            out.add(courseSpec(i));
        }
        return out;
    }

    function activeCourseIndex() as Lang.Number {
        return normaliseCourseIndex(Properties.getValue("activeCourse"));
    }

    function setActiveCourseIndex(index as Lang.Number) as Void {
        Properties.setValue("activeCourse", clampCourseIndex(index));
    }

    function quickDistanceM() as Lang.Number {
        return normaliseQuick(Properties.getValue("quickDistanceM"));
    }

    function setQuickDistanceM(metres as Lang.Number) as Void {
        Properties.setValue("quickDistanceM", metres <= 0 ? 0 : clampQuickDistance(metres));
    }

    function clearQuickCourse() as Void {
        Properties.setValue("quickDistanceM", 0);
    }

    function bleLatencyMs() as Lang.Number {
        return normaliseLatency(Properties.getValue("bleLatencyMs"));
    }

    function clearAfterWrite() as Lang.Boolean {
        return normaliseBool(Properties.getValue("clearAfterWrite"), true);
    }

    function lapPerCrossing() as Lang.Boolean {
        return normaliseBool(Properties.getValue("lapPerCrossing"), false);
    }

    function captureMode() as Lang.Boolean {
        return normaliseBool(Properties.getValue("captureMode"), false);
    }
}
