using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Test;

// Issue #2: "MainView text does not clip or overlap on any of the listed
// resolutions".
//
// Screenshots prove it for the resolution you happened to look at. These run
// the real onUpdate() against a real Dc at whatever resolution the simulator
// is started with, and assert the two things a screenshot is being used to
// check by eye:
//
//   * no line is wider than the room available at its height (on a round face
//     that is the chord, not the diameter)
//   * no line overlaps the one above it, and none runs off the bottom
//
// Run them on each target device to cover the list:
//   monkeydo bin/freelap-test.prg fr55   /t   (round 208x208)
//   monkeydo bin/freelap-test.prg fr645m /t   (round 240x240)
//   monkeydo bin/freelap-test.prg fenix6 /t   (round 260x260)
//   monkeydo bin/freelap-test.prg fr265  /t   (round 416x416)

(:test)
function testIdleScreenFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainView(null, false);

    Test.assertMessage(trace.size() >= 2, "the idle screen draws a status line and a headline");
    TestSupport.assertLayoutIsSane(trace, "idle screen");
    return true;
}

(:test)
function testIdleScreenWithACourseProblemFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var previous = app.course;
    // The longest thing the idle screen can be asked to show: a rejected
    // course, so the summary carries "(default)" and a red reason sits below.
    app.course = Course.fromSpec("S:0;L:60;F:30", "Course 1");

    var trace = TestSupport.traceMainView(null, false);

    Test.assertEqualMessage(trace.size(), 4, "status, headline, course summary, problem");
    TestSupport.assertLayoutIsSane(trace, "idle screen with a course problem");

    app.course = previous;
    return true;
}

(:test)
function testLiveScreenWithASplitFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    Test.assertEqualMessage(trace.size(), 4, "status, velocity, split detail, rep line");
    TestSupport.assertLayoutIsSane(trace, "live screen with a split");
    return true;
}

(:test)
function testPausedLiveScreenFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), true);

    Test.assertEqualMessage(trace.size(), 5, "and a PAUSED line under it");
    TestSupport.assertLayoutIsSane(trace, "paused live screen");
    return true;
}

(:test)
function testTheBigNumberIsNotShrunkAwayOnALargeDisplay(logger as Test.Logger) as Lang.Boolean {
    var height = System.getDeviceSettings().screenHeight;
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    // The velocity readout is the reason to look at the watch mid-session. It
    // is allowed to shrink to fit, but it must still be the tallest line.
    var big = trace[1] as Lang.Dictionary;
    var detail = trace[2] as Lang.Dictionary;
    Test.assertMessage((big.get(:height) as Lang.Number) > (detail.get(:height) as Lang.Number),
        "the velocity readout is bigger than the detail under it");
    return true;
}

(:test)
function testANoticeFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    app.setNotice("No splits");

    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    Test.assertEqualMessage(trace.size(), 5, "status, velocity, detail, rep line, notice");
    TestSupport.assertLayoutIsSane(trace, "live screen with a notice");
    var notice = trace[4] as Lang.Dictionary;
    Test.assertEqualMessage(notice.get(:text), "No splits", "the notice is the last line");

    app.clearNotice();
    return true;
}

(:test)
function testCaptureModeLineFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var ble = app.ble;
    if (ble == null) { return true; }

    var previousMode = ble.captureMode;
    var previousHex = ble.lastPacketHex;
    ble.captureMode = true;
    // A full 20-byte notification, which is the widest this line ever gets.
    ble.lastPacketHex = "A50412340000000001180F0000021848";

    var trace = TestSupport.traceMainView(null, false);

    TestSupport.assertLayoutIsSane(trace, "capture mode");
    var last = trace[trace.size() - 1] as Lang.Dictionary;
    Test.assertMessage((last.get(:text) as Lang.String).find("#") == 0,
        "the packet line is the last thing drawn");

    ble.captureMode = previousMode;
    ble.lastPacketHex = previousHex;
    return true;
}
