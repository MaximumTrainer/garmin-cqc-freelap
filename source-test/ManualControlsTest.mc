using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.Test;

// Driven by the acceptance criteria of issue #24, "Manual controls:
// pause/resume, manual rep end, save/discard".
//
// The button and tap rules are extracted from MainDelegate as plain functions
// of the recorder's state, so they can be asserted without a view stack. That
// matters more here than anywhere else in the app: these are the only controls
// the athlete has mid-session, and two of them are irreversible.

// ---------------------------------------------------------------------------
// Manual rep end
// ---------------------------------------------------------------------------

(:test)
function testManualRepEndOnTwoMatchedCrossingsWritesAPartialLap(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onCrossing(new Crossing(0l, TxCode.START, "T"), 1000);
    rig.engine.onCrossing(new Crossing(4120000l, TxCode.LAP, "T"), 5120);
    rig.recorder.manualLap();
    TestSupport.tickUntilIdle(rig.recorder, 20);

    Test.assertEqualMessage(session.countOf("addLap"), 1, "the rep got its lap");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_status"), RepStatus.PARTIAL,
        "flagged partial: the athlete never reached the FINISH transmitter");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_splits"), 2, "two crossings");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_dist_m"), 30.0,
        "over the distance actually covered, not the course total");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_time_us"), 4120000, "and the time run");
    return true;
}

(:test)
function testManualRepEndOnAnOpenEndedCourseIsTheNormalWayToEndARep(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60");

    rig.engine.onCrossing(new Crossing(0l, TxCode.START, "T"), 1000);
    rig.engine.onCrossing(new Crossing(4120000l, TxCode.LAP, "T"), 5120);
    rig.engine.onCrossing(new Crossing(7480000l, TxCode.LAP, "T"), 8480);
    rig.recorder.manualLap();
    TestSupport.tickUntilIdle(rig.recorder, 20);

    // There is no FINISH to miss, so a rep ended by the button is complete.
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_status"), RepStatus.OK, "not partial");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_dist_m"), 60.0, "full course distance");
    return true;
}

(:test)
function testManualRepEndWithNothingPendingWritesNoLap(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;F:100");

    rig.recorder.manualLap();
    TestSupport.tickUntilIdle(rig.recorder, 20);

    // An empty lap in the FIT file is worse than no lap: it shows up in
    // Connect's lap table as a rep the athlete never ran.
    Test.assertEqualMessage(session.countOf("addLap"), 0, "no lap for no crossings");
    return true;
}

(:test)
function testManualRepEndWithNothingPendingSaysSo(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");
    app.clearNotice();

    Test.assertMessage(!rig.recorder.manualLap(), "manualLap reports that it ended nothing");

    // Through the real dispatch, because that is where the notice is raised -
    // the recorder has no business knowing about the screen.
    TestSupport.performOnApp(rig.recorder, :manualLap);

    Test.assertEqualMessage(app.activeNotice(), "No splits",
        "and the watch says why the button appeared to do nothing");
    app.clearNotice();
    return true;
}

(:test)
function testManualRepEndWithSplitsSaysNothing(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");
    app.clearNotice();

    rig.engine.onCrossing(new Crossing(0l, TxCode.START, "T"), 1000);
    TestSupport.performOnApp(rig.recorder, :manualLap);

    Test.assertEqualMessage(rig.recorder.session.countOf("addLap"), 0,
        "the lap is queued behind the rep's records, not cut immediately");
    Test.assertEqualMessage(app.activeNotice(), "",
        "a rep was ended, so there is nothing to explain");
    return true;
}

// ---------------------------------------------------------------------------
// Notices. Deliberately drawn by MainView rather than WatchUi.showToast, which
// needs API 4.0 and minApiLevel here is 3.1.
// ---------------------------------------------------------------------------

(:test)
function testANoticeExpiresOnItsOwn(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;

    app.setNotice("No splits");
    Test.assertEqualMessage(app.activeNotice(), "No splits", "shown straight away");

    app.noticeUntilMs = System.getTimer() - 1;
    Test.assertEqualMessage(app.activeNotice(), "", "and gone once it has timed out");

    app.clearNotice();
    return true;
}

// ---------------------------------------------------------------------------
// Pause and resume
// ---------------------------------------------------------------------------

(:test)
function testPauseStopsTheSessionTimerAndResumeRestartsIt(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;F:100");

    Test.assertEqualMessage(session.countOf("start"), 1, "started on entry");

    rig.recorder.stop();
    Test.assertEqualMessage(session.countOf("stop"), 1, "the FIT timer is stopped, not just our flag");
    Test.assertMessage(!rig.recorder.recording, "and we know we are paused");

    rig.recorder.resume();
    Test.assertEqualMessage(session.countOf("start"), 2, "the timer runs again");
    Test.assertMessage(rig.recorder.recording, "and we know we are recording");
    return true;
}

(:test)
function testPauseTwiceStopsTheTimerOnce(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;F:100");

    rig.recorder.stop();
    rig.recorder.stop();

    Test.assertEqualMessage(session.countOf("stop"), 1, "the second pause has nothing to stop");
    return true;
}

// ---------------------------------------------------------------------------
// What each control means, per state
// ---------------------------------------------------------------------------

(:test)
function testStartButtonStartsThenPausesThenResumes(logger as Test.Logger) as Lang.Boolean {
    var idle = new FitRecorder(true, false);
    Test.assertEqualMessage(MainDelegate.selectAction(idle), :start, "no session yet");

    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");
    Test.assertEqualMessage(MainDelegate.selectAction(rig.recorder), :pause, "while recording");

    rig.recorder.stop();
    Test.assertEqualMessage(MainDelegate.selectAction(rig.recorder), :resume, "while paused");
    return true;
}

(:test)
function testTapStartsARecordingWhenThereIsNoSession(logger as Test.Logger) as Lang.Boolean {
    var idle = new FitRecorder(true, false);

    // Anywhere on the screen: there is only one thing to do.
    Test.assertEqualMessage(MainDelegate.tapAction(idle, 20, 240), :start, "top of the screen");
    Test.assertEqualMessage(MainDelegate.tapAction(idle, 220, 240), :start, "bottom of the screen");
    return true;
}

(:test)
function testTapTopPausesAndTapBottomEndsTheRepWhileRecording(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");

    Test.assertEqualMessage(MainDelegate.tapAction(rig.recorder, 40, 240), :pause, "upper half");
    Test.assertEqualMessage(MainDelegate.tapAction(rig.recorder, 200, 240), :manualLap, "lower half");
    return true;
}

(:test)
function testTapTopResumesAndTapBottomOpensTheMenuWhilePaused(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");
    rig.recorder.stop();

    Test.assertEqualMessage(MainDelegate.tapAction(rig.recorder, 40, 240), :resume, "upper half");
    Test.assertEqualMessage(MainDelegate.tapAction(rig.recorder, 200, 240), :saveMenu, "lower half");
    return true;
}

(:test)
function testEveryControlIsReachableByTouchAlone(logger as Test.Logger) as Lang.Boolean {
    // Issue #24: "on a touch-only device all three actions are reachable".
    // Pause/resume, manual rep end and save/discard must each be produced by
    // some tap, from some state, without a physical button.
    var reachable = {};
    var idle = new FitRecorder(true, false);
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");

    var states = [idle, rig.recorder];
    for (var s = 0; s < states.size(); s++) {
        for (var y = 10; y < 240; y += 10) {
            reachable.put(MainDelegate.tapAction(states[s], y, 240), true);
        }
    }
    rig.recorder.stop();
    for (var y = 10; y < 240; y += 10) {
        reachable.put(MainDelegate.tapAction(rig.recorder, y, 240), true);
    }

    Test.assertMessage(reachable.hasKey(:start), "start is reachable by touch");
    Test.assertMessage(reachable.hasKey(:pause), "pause is reachable by touch");
    Test.assertMessage(reachable.hasKey(:resume), "resume is reachable by touch");
    Test.assertMessage(reachable.hasKey(:manualLap), "manual rep end is reachable by touch");
    Test.assertMessage(reachable.hasKey(:saveMenu), "save/discard is reachable by touch");
    return true;
}
