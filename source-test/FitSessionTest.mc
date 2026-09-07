using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;

// Tests for the session-level half of source/fit/FitRecorder.mc and for the
// save/discard/exit paths.
//
// Driven by the acceptance criteria of issue #18, "FIT: session summary fields
// and correct save/discard behaviour".
//
// The thing worth being careful about here is that every one of these paths is
// irreversible from the athlete's point of view. A session that is discarded
// when it should have been saved is a training session that never happened.

// ---------------------------------------------------------------------------
// Session summary fields
// ---------------------------------------------------------------------------

(:test)
function testSessionSummaryCarriesTheFourFieldsForAThreeRepSession(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);                     // 11.930 s
    TestSupport.tickUntilIdle(rig.recorder, 20);
    rig.engine.onRepBurst(TestSupport.burst([0l, 4000000l, 7000000l, 11000000l],
        [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]), 30000);       // 11.000 s
    TestSupport.tickUntilIdle(rig.recorder, 20);
    rig.engine.onRepBurst(TestSupport.burst([0l, 4200000l, 7600000l, 12100000l],
        [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]), 60000);       // 12.100 s
    TestSupport.tickUntilIdle(rig.recorder, 20);

    rig.recorder.save();

    Test.assertEqualMessage(session.field("fl_reps").last(), 3, "three reps");
    Test.assertEqualMessage(session.field("fl_best_rep_us").last(), 11000000,
        "the fastest of the three, in exact microseconds");
    Test.assertEqualMessage(session.field("fl_total_dist_m").last(), 300.0, "three times 100 m");
    Test.assertEqualMessage(session.field("fl_chip_id").last(), "TEST", "the chip that reported them");
    return true;
}

(:test)
function testChipIdFallsBackToUnknownWhenNoChipEverReported(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;F:100");

    rig.recorder.save();

    // fl_chip_id is a fixed-width string field; leaving it unset is worse than
    // saying so, because a decoder cannot tell "no chip" from "field dropped".
    Test.assertEqualMessage(session.field("fl_chip_id").last(), "unknown", "fl_chip_id");
    return true;
}

(:test)
function testSessionSummaryIsWrittenBeforeTheSessionIsSaved(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);

    rig.recorder.save();

    // If save() ran first the four fields would never reach the file.
    Test.assertEqualMessage(session.field("fl_reps").writes(), 1, "the summary was written");
    Test.assertMessage(session.saved, "and then the session was saved");
    return true;
}

(:test)
function testBestRepInTheSummaryIgnoresRepsThatAreNotOk(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);                    // complete, 11.930 s
    rig.engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l],
        [TxCode.START, TxCode.LAP, TxCode.LAP]), 30000);                     // partial, 8.000 s
    rig.recorder.save();

    Test.assertEqualMessage(session.field("fl_best_rep_us").last(), 11930000,
        "a best the athlete never actually ran would be worse than useless");
    Test.assertEqualMessage(session.field("fl_total_dist_m").last(), 160.0,
        "but the distance counts, because the metres were run");
    return true;
}

// ---------------------------------------------------------------------------
// Save immediately after a FINISH
// ---------------------------------------------------------------------------

(:test)
function testSaveRightAfterAFinishBurstKeepsEveryRecordAndTheLap(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    // The athlete crosses the line and immediately reaches for save.
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.recorder.save();

    TestSupport.assertArrayEquals(session.valuesOf("fl_split_us"),
        [0, 4120000, 3360000, 4450000], "all four records");
    Test.assertEqualMessage(session.countOf("addLap"), 1, "and the rep's lap");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_time_us"), 11930000, "with its fields");
    Test.assertEqualMessage(session.field("fl_reps").last(), 1, "and the session summary");
    return true;
}

(:test)
function testSaveWorksFromAPausedSession(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.recorder.stop();          // the athlete pauses, then saves from the menu
    rig.recorder.save();

    // A stopped session cannot be written to, so save() has to restart it
    // before flushing or the whole rep is lost.
    Test.assertEqualMessage(session.field("fl_split_us").writes(), 4, "the queued splits still landed");
    Test.assertMessage(session.saved, "and the session saved");
    return true;
}

// ---------------------------------------------------------------------------
// Discard
// ---------------------------------------------------------------------------

(:test)
function testDiscardNeverSaves(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);

    rig.recorder.discard();

    Test.assertMessage(session.discarded, "the session was discarded");
    Test.assertMessage(!session.saved, "and nothing was saved");
    Test.assertEqualMessage(session.countOf("save"), 0, "save() was never called");
    return true;
}

(:test)
function testDiscardAfterASaveIsANoOp(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);

    rig.recorder.save();
    rig.recorder.discard();

    // The saved activity must not be thrown away by a later discard - this is
    // the path FreelapApp.onStop used to take on every exit.
    Test.assertEqualMessage(session.countOf("discard"), 0, "the saved session was left alone");
    Test.assertEqualMessage(session.countOf("save"), 1, "and saved exactly once");
    return true;
}

(:test)
function testSavingTwiceSavesOnce(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.recorder.save();
    rig.recorder.save();

    Test.assertEqualMessage(session.countOf("save"), 1, "the second save has nothing to save");
    return true;
}

// ---------------------------------------------------------------------------
// Exiting the app
// ---------------------------------------------------------------------------

(:test)
function testOnStopSavesAnActiveSessionRatherThanDiscardingIt(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var app = Application.getApp() as FreelapApp;
    var previous = app.recorder;

    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    app.recorder = rig.recorder;

    app.onStop(null);

    // onStop cannot ask - there is no view stack left by then - and the
    // athlete never said "throw this away". Losing the session is the worse
    // of the two mistakes.
    Test.assertMessage(session.saved, "an unfinished session is saved on exit");
    Test.assertMessage(!session.discarded, "not discarded");
    Test.assertEqualMessage(session.field("fl_split_us").writes(), 4, "with its records");

    app.recorder = previous;
    return true;
}

(:test)
function testOnStopLeavesAnAlreadySavedSessionAlone(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var app = Application.getApp() as FreelapApp;
    var previous = app.recorder;

    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.recorder.save();
    app.recorder = rig.recorder;

    app.onStop(null);

    Test.assertEqualMessage(session.countOf("save"), 1, "not saved a second time");
    Test.assertEqualMessage(session.countOf("discard"), 0, "and not discarded");

    app.recorder = previous;
    return true;
}

(:test)
function testOnStopWithNoSessionDoesNothing(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    var previous = app.recorder;
    app.recorder = new FitRecorder(true, false);

    app.onStop(null);   // reaching the next line is the test

    Test.assertMessage(true, "exiting without ever starting a session is not an error");
    app.recorder = previous;
    return true;
}

// ---------------------------------------------------------------------------
// What the BACK button means. Extracted from MainDelegate so the decision is
// testable without a view stack.
// ---------------------------------------------------------------------------

(:test)
function testBackExitsWhenThereIsNoSession(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(MainDelegate.backAction(new FitRecorder(true, false)), :exit,
        "nothing to lose, so BACK leaves the app");
    Test.assertEqualMessage(MainDelegate.backAction(null), :exit, "and with no recorder at all");
    return true;
}

(:test)
function testBackIsTheLapButtonWhileRecording(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");

    Test.assertEqualMessage(MainDelegate.backAction(rig.recorder), :manualLap,
        "BACK ends the rep while the timer runs, as on any Garmin watch");
    return true;
}

(:test)
function testBackOpensTheSaveMenuOnAPausedSession(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");
    rig.recorder.stop();

    Test.assertEqualMessage(MainDelegate.backAction(rig.recorder), :saveMenu,
        "an active session is never left without asking");
    return true;
}
