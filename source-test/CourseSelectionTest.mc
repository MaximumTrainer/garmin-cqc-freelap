using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #22, "On-watch course selection
// and Quick course".
//
// The point of this is a session that starts without reaching for a phone. The
// athlete is already on the track; the course is either one they configured
// earlier or a distance they are about to dial in.

// ---------------------------------------------------------------------------
// The course menu
// ---------------------------------------------------------------------------

(:test)
function testTheMenuListsOnlyConfiguredCourses(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();
    Properties.setValue("course1", "S:0;F:30");
    Properties.setValue("course2", "S:0;L:30;L:60;F:100");
    for (var i = 3; i <= Settings.MAX_COURSES; i++) {
        Properties.setValue("course" + i.format("%d"), "");
    }

    var entries = CourseMenu.entries();

    // Six empty slots would be six menu items that do nothing.
    Test.assertEqualMessage(entries.size(), 2, "two configured courses");
    Test.assertEqualMessage((entries[0] as CourseEntry).index, 1, "slot numbers are kept");
    Test.assertEqualMessage((entries[1] as CourseEntry).index, 2, "not renumbered");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testAMenuEntryShowsItsNameAndTotalDistance(logger as Test.Logger) as Lang.Boolean {
    var entry = new CourseEntry(2, "S:0;L:30;L:60;F:100");

    Test.assertEqualMessage(entry.label(), "Course 2", "named by slot");
    Test.assertEqualMessage(entry.detail(), "100m", "with the distance to run");
    return true;
}

(:test)
function testAnInvalidCourseIsListedWithItsProblemRatherThanHidden(logger as Test.Logger) as Lang.Boolean {
    var entry = new CourseEntry(3, "S:0;L:60;F:30");

    // Hiding it would leave the athlete wondering where course 3 went. The
    // detail line is where they find out.
    Test.assertEqualMessage(entry.label(), "Course 3", "still listed");
    Test.assertMessage(entry.detail().find("increase") != null,
        "with the reason it cannot be used: " + entry.detail());
    return true;
}

(:test)
function testSkippedSlotsDoNotShiftTheOnesAfterThem(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();
    for (var i = 1; i <= Settings.MAX_COURSES; i++) {
        Properties.setValue("course" + i.format("%d"), "");
    }
    Properties.setValue("course2", "S:0;F:60");
    Properties.setValue("course7", "S:0;F:200");

    var entries = CourseMenu.entries();

    Test.assertEqualMessage(entries.size(), 2, "two configured");
    Test.assertEqualMessage((entries[0] as CourseEntry).index, 2, "the second slot");
    Test.assertEqualMessage((entries[1] as CourseEntry).index, 7, "and the seventh");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testChoosingACourseSetsAndPersistsTheActiveSlot(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();
    Properties.setValue("course4", "S:0;L:40;F:120");
    Settings.setActiveCourseIndex(1);
    Settings.setQuickDistanceM(60);   // a quick course was in force

    var chosen = CourseMenu.select(4);

    Test.assertEqualMessage(Settings.activeCourseIndex(), 4, "the slot is remembered");
    Test.assertEqualMessage(Settings.quickDistanceM(), 0,
        "and the quick course is cleared, or it would keep overriding the choice");
    Test.assertEqualMessage(chosen.totalDistance(), 120.0, "the course that comes back is slot 4's");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

// ---------------------------------------------------------------------------
// Quick course
// ---------------------------------------------------------------------------

(:test)
function testAQuickCourseIsATwoTransmitterCourseAtTheChosenDistance(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();

    var course = CourseMenu.selectQuick(60);

    Test.assertEqualMessage(course.size(), 2, "a start line and a finish line");
    Test.assertEqualMessage(course.codes[0], TxCode.START, "START");
    Test.assertEqualMessage(course.codes[1], TxCode.FINISH, "FINISH");
    Test.assertEqualMessage(course.totalDistance(), 60.0, "at the dialled distance");
    Test.assertMessage(course.valid, "and it is usable");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testAQuickCourseNamesItselfSoTheScreenShowsTheDistance(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();

    var course = CourseMenu.selectQuick(150);

    // The activity screen draws course.name; "Course 1" would be a lie here.
    Test.assertEqualMessage(course.name, "Quick 150m", "says what it is");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testAQuickCourseOverridesTheConfiguredSlotUntilCleared(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();
    Properties.setValue("course1", "S:0;L:30;L:60;F:100");
    Settings.setActiveCourseIndex(1);

    CourseMenu.selectQuick(80);
    Test.assertEqualMessage(Course.loadActive().totalDistance(), 80.0, "the quick course is in force");

    Settings.clearQuickCourse();
    Test.assertEqualMessage(Course.loadActive().totalDistance(), 100.0, "and slot 1 comes back");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testTheQuickDistancePickerRunsInFiveMetreSteps(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(Settings.QUICK_MIN_M, 10, "from 10 m");
    Test.assertEqualMessage(Settings.QUICK_MAX_M, 400, "to 400 m");
    Test.assertEqualMessage(Settings.QUICK_STEP_M, 5, "in 5 m steps");

    Test.assertEqualMessage(CourseMenu.nextQuickDistance(30, 1), 35, "up one step");
    Test.assertEqualMessage(CourseMenu.nextQuickDistance(30, -1), 25, "down one step");
    return true;
}

(:test)
function testTheQuickDistancePickerStopsAtItsEnds(logger as Test.Logger) as Lang.Boolean {
    // Wrapping from 400 m to 10 m with a long press would be a nasty surprise.
    Test.assertEqualMessage(CourseMenu.nextQuickDistance(10, -1), 10, "cannot go below 10 m");
    Test.assertEqualMessage(CourseMenu.nextQuickDistance(400, 1), 400, "cannot go above 400 m");
    return true;
}

(:test)
function testAQuickDistanceOffTheStepIsSnapped(logger as Test.Logger) as Lang.Boolean {
    // A value typed into settings by hand, or written by an older build, must
    // not produce a course the picker itself could never have made.
    Test.assertEqualMessage(Settings.clampQuickDistance(32), 30, "snapped down");
    Test.assertEqualMessage(Settings.clampQuickDistance(33), 35, "snapped up");
    Test.assertEqualMessage(Settings.clampQuickDistance(3), 10, "below the minimum");
    Test.assertEqualMessage(Settings.clampQuickDistance(9999), 400, "above the maximum");
    return true;
}

// ---------------------------------------------------------------------------
// Not mid-session
// ---------------------------------------------------------------------------

(:test)
function testTheCourseMenuIsOfferedOnlyBeforeASessionStarts(logger as Test.Logger) as Lang.Boolean {
    var idle = new FitRecorder(true, false);
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;F:30");

    Test.assertMessage(CourseMenu.canChoose(idle), "choose freely before starting");
    Test.assertMessage(!CourseMenu.canChoose(rig.recorder),
        "but not once splits are being written against a course");

    rig.recorder.stop();
    Test.assertMessage(!CourseMenu.canChoose(rig.recorder),
        "not even paused - the session still holds the course");
    return true;
}

(:test)
function testChoosingACourseMidSessionIsRefusedAndExplained(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var saved = TestSupport.saveCourseSlots();
    var previousRecorder = app.recorder;
    var previousCourse = app.course;

    Settings.clearQuickCourse();
    Properties.setValue("course1", "S:0;F:30");
    Settings.setActiveCourseIndex(1);
    app.course = Course.loadActive();
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;F:30");
    app.recorder = rig.recorder;
    app.clearNotice();

    TestSupport.performOnApp(rig.recorder, :quickCourse);

    Test.assertEqualMessage(app.course.totalDistance(), 30.0, "the session keeps its course");
    Test.assertEqualMessage(app.activeNotice(), "Course locked for session", "and says why");

    app.recorder = previousRecorder;
    app.course = previousCourse;
    app.clearNotice();
    TestSupport.restoreCourseSlots(saved);
    return true;
}
