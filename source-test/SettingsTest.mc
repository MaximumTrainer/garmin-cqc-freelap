using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #23, "Settings via Garmin Connect
// / Express: courses, latency, flags".
//
// Most of this is about what happens when a setting is *not* what the code
// expects: absent on first run, absent because the property was added in a
// later version of the app, the wrong type, or out of range because it was
// written by hand. None of those should reach the domain, and none of them
// should need the app relaunched.
//
// The awkward cases go through the pure normalisers rather than through
// storage, because Properties.setValue will not accept null - "the property is
// absent" is not a state a test can create by writing.

// ---------------------------------------------------------------------------
// Normalisers
// ---------------------------------------------------------------------------

(:test)
function testAnAbsentCourseSpecReadsAsEmptyNotNull(logger as Test.Logger) as Lang.Boolean {
    // The course menu skips empty slots; a null would crash it instead.
    Test.assertEqualMessage(Settings.normaliseSpec(null), "", "absent");
    Test.assertEqualMessage(Settings.normaliseSpec(42), "", "wrong type");
    Test.assertEqualMessage(Settings.normaliseSpec("S:0;F:30"), "S:0;F:30", "a real spec");
    return true;
}

(:test)
function testAnActiveCourseOutsideTheRangeIsClamped(logger as Test.Logger) as Lang.Boolean {
    // Without this, Course.loadActive reads "course0" or "course99", finds
    // nothing, and silently runs the default course.
    Test.assertEqualMessage(Settings.normaliseCourseIndex(0), 1, "0 clamps up");
    Test.assertEqualMessage(Settings.normaliseCourseIndex(-3), 1, "negative clamps up");
    Test.assertEqualMessage(Settings.normaliseCourseIndex(99), 8, "99 clamps down");
    Test.assertEqualMessage(Settings.normaliseCourseIndex(null), 1, "absent");
    Test.assertEqualMessage(Settings.normaliseCourseIndex("2"), 1, "wrong type");
    Test.assertEqualMessage(Settings.normaliseCourseIndex(5), 5, "a real slot");
    return true;
}

(:test)
function testANegativeOrMissingLatencyFallsBackToTheDefault(logger as Test.Logger) as Lang.Boolean {
    // A negative latency would place crossings *after* the packet arrived.
    Test.assertEqualMessage(Settings.normaliseLatency(-50), 150, "negative");
    Test.assertEqualMessage(Settings.normaliseLatency(null), 150, "absent");
    Test.assertEqualMessage(Settings.normaliseLatency("fast"), 150, "wrong type");
    Test.assertEqualMessage(Settings.normaliseLatency(0), 0, "zero is a legitimate choice");
    Test.assertEqualMessage(Settings.normaliseLatency(275), 275, "a real value");
    return true;
}

(:test)
function testMissingFlagsFallBackToThePropertiesXmlDefaults(logger as Test.Logger) as Lang.Boolean {
    // A property added in a later app version reads as absent on a watch that
    // has not synced yet.
    Test.assertEqualMessage(Settings.normaliseBool(null, true), true, "clearAfterWrite default");
    Test.assertEqualMessage(Settings.normaliseBool(null, false), false, "lapPerCrossing default");
    Test.assertEqualMessage(Settings.normaliseBool(true, false), true, "an explicit true");
    Test.assertEqualMessage(Settings.normaliseBool(false, true), false, "an explicit false");
    return true;
}

// ---------------------------------------------------------------------------
// Eight courses
// ---------------------------------------------------------------------------

(:test)
function testEightCourseSlotsAreAvailable(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(Settings.MAX_COURSES, 8, "issue #23 asks for eight");
    Test.assertEqualMessage(Settings.courseSpecs().size(), 8, "and all eight are readable");
    return true;
}

(:test)
function testEveryCourseSlotIsReachableThroughSettings(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();
    for (var i = 1; i <= Settings.MAX_COURSES; i++) {
        Properties.setValue("course" + i.format("%d"), "S:0;F:" + (i * 10).format("%d"));
    }

    var specs = Settings.courseSpecs();
    for (var i = 0; i < specs.size(); i++) {
        Test.assertEqualMessage(specs[i], "S:0;F:" + ((i + 1) * 10).format("%d"),
            "slot " + (i + 1).format("%d"));
    }

    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testTheActiveCourseIsTheOneLoaded(logger as Test.Logger) as Lang.Boolean {
    var saved = TestSupport.saveCourseSlots();
    Settings.clearQuickCourse();
    Properties.setValue("course5", "S:0;L:80;F:150");
    Settings.setActiveCourseIndex(5);

    var course = Course.loadActive();

    Test.assertEqualMessage(course.name, "Course 5", "named for its slot");
    Test.assertEqualMessage(course.totalDistance(), 150.0, "and carrying that slot's spec");

    TestSupport.restoreCourseSlots(saved);
    return true;
}

// ---------------------------------------------------------------------------
// Flags and latency, without a relaunch
// ---------------------------------------------------------------------------

(:test)
function testChangedFlagsTakeEffectWithoutRelaunching(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var savedLatency = Properties.getValue("bleLatencyMs") as Lang.Number;
    var savedClear = Properties.getValue("clearAfterWrite") as Lang.Boolean;
    var savedLap = Properties.getValue("lapPerCrossing") as Lang.Boolean;
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");
    var previousEngine = app.engine;
    var previousRecorder = app.recorder;
    app.engine = rig.engine;
    app.recorder = rig.recorder;

    Properties.setValue("bleLatencyMs", 275);
    Properties.setValue("clearAfterWrite", false);
    Properties.setValue("lapPerCrossing", true);

    app.applySettings();

    Test.assertEqualMessage(rig.engine.bleLatencyMs, 275, "the engine picked up the new latency");
    Test.assertEqualMessage(rig.recorder.clearAfterWrite, false, "and the recorder its flags");
    Test.assertEqualMessage(rig.recorder.lapPerCrossing, true, "both of them");

    Properties.setValue("bleLatencyMs", savedLatency);
    Properties.setValue("clearAfterWrite", savedClear);
    Properties.setValue("lapPerCrossing", savedLap);
    app.engine = previousEngine;
    app.recorder = previousRecorder;
    return true;
}

(:test)
function testApplySettingsSurvivesBeingCalledBeforeAnythingIsBuilt(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var previousEngine = app.engine;
    var previousRecorder = app.recorder;
    var previousBle = app.ble;
    app.engine = null;
    app.recorder = null;
    app.ble = null;

    // A sync can land before onStart has finished wiring things up.
    app.applySettings();

    Test.assertMessage(true, "no null dereference");
    app.engine = previousEngine;
    app.recorder = previousRecorder;
    app.ble = previousBle;
    return true;
}

// ---------------------------------------------------------------------------
// Changing the course mid-session
// ---------------------------------------------------------------------------

(:test)
function testACourseChangeDuringASessionIsRefusedAndExplained(logger as Test.Logger) as Lang.Boolean {
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

    // The athlete edits the course in Garmin Connect mid-workout.
    Properties.setValue("course1", "S:0;L:100;F:400");
    app.onSettingsChanged();

    // Re-deriving now would change the distances of splits already written.
    Test.assertEqualMessage(app.course.totalDistance(), 30.0, "the session keeps its course");
    Test.assertEqualMessage(app.activeNotice(), "Course locked for session",
        "and the athlete is told why the edit did nothing");

    app.recorder = previousRecorder;
    app.course = previousCourse;
    app.clearNotice();
    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testACourseChangeBetweenSessionsIsAccepted(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var saved = TestSupport.saveCourseSlots();
    var previousRecorder = app.recorder;
    var previousCourse = app.course;

    Settings.clearQuickCourse();
    Settings.setActiveCourseIndex(1);
    app.recorder = new FitRecorder(true, false);   // no session
    Properties.setValue("course1", "S:0;L:100;F:400");

    app.onSettingsChanged();

    Test.assertEqualMessage(app.course.totalDistance(), 400.0, "picked up within one sync");

    app.recorder = previousRecorder;
    app.course = previousCourse;
    TestSupport.restoreCourseSlots(saved);
    return true;
}

(:test)
function testAParseErrorFromASyncReachesTheWatch(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var saved = TestSupport.saveCourseSlots();
    var previousRecorder = app.recorder;
    var previousCourse = app.course;

    Settings.clearQuickCourse();
    Settings.setActiveCourseIndex(1);
    app.recorder = new FitRecorder(true, false);
    Properties.setValue("course1", "S:0;L:60;F:30");

    app.onSettingsChanged();

    Test.assertMessage(app.course.usingFallback, "the bad course was refused");
    Test.assertMessage(app.course.problem().find("increase") != null,
        "and the reason is on the screen: " + app.course.problem());

    app.recorder = previousRecorder;
    app.course = previousCourse;
    TestSupport.restoreCourseSlots(saved);
    return true;
}
