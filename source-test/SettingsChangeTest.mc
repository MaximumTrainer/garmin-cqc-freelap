using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Test;

// Issue #13, last acceptance criterion: "Course parse errors are shown on the
// watch when settings change (onSettingsChanged), not only in the log".
//
// "Shown on the watch" is MainView drawing app.course.problem(); what is
// testable without a Dc is that onSettingsChanged() reloads the course and
// that the reloaded course carries the problem text for the view to draw.

(:test)
function testSettingsChangeSurfacesARejectedCourse(logger as Test.Logger) as Lang.Boolean {
    var course = TestSupport.courseAfterSettingsChange("S:0;L:60;F:30");

    Test.assertMessage(!course.problem().equals(""),
        "a course whose distances go backwards reaches the watch as a problem");
    Test.assertMessage(course.valid,
        "and the app still has a usable course to record with");
    Test.assertEqualMessage(course.totalDistance(), 30.0, "which is the default course");
    return true;
}

(:test)
function testSettingsChangeSurfacesAnOpenEndedCourse(logger as Test.Logger) as Lang.Boolean {
    var course = TestSupport.courseAfterSettingsChange("S:0;L:30;L:60");

    Test.assertMessage(course.openEnded, "no FINISH transmitter");
    Test.assertMessage(!course.problem().equals(""), "which the watch is told about");
    return true;
}

(:test)
function testSettingsChangeLeavesNoProblemForAValidCourse(logger as Test.Logger) as Lang.Boolean {
    var course = TestSupport.courseAfterSettingsChange("S:0;L:30;L:60;F:100");

    Test.assertEqualMessage(course.problem(), "", "a valid course says nothing");
    Test.assertEqualMessage(course.totalDistance(), 100.0, "and is the one that was entered");
    return true;
}

(:test)
function testSettingsChangeRetargetsTheEngineAtTheNewCourse(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var course = TestSupport.courseAfterSettingsChange("S:0;L:100;L:200;L:300;F:400");

    Test.assertEqualMessage(app.engine.course.totalDistance(), 400.0,
        "the split engine derives against the course the athlete just chose");
    return true;
}
