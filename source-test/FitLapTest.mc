using Toybox.FitContributor as Fit;
using Toybox.Lang;
using Toybox.Test;

// Tests for the lap-level half of source/fit/FitRecorder.mc.
//
// Driven by the acceptance criteria of issue #17, "FIT: one Garmin lap per
// Freelap rep with lap-level summary fields".
//
// Two ecosystem constraints shape all of this (docs/DESIGN.md §5):
//   * addLap() can only happen *now* — laps cannot be back-dated — which is
//     why one Garmin lap per Freelap rep is the design at all.
//   * setData() and addLap() in the same pass drops the lap's developer
//     fields, so the close is deferred by a tick. That deferral is load
//     bearing, not a tidiness problem to be optimised away.

// ---------------------------------------------------------------------------
// One lap per rep
// ---------------------------------------------------------------------------

(:test)
function testEachRepClosesExactlyOneLap(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    for (var i = 0; i < 5; i++) {
        rig.engine.onRepBurst(TestSupport.workedRep(), 1000 + i * 20000);
        TestSupport.tick(rig.recorder, 8);
    }

    Test.assertEqualMessage(session.countOf("addLap"), 5, "five reps, five laps");
    return true;
}

(:test)
function testRepsArrivingBackToBackStillEachGetALap(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    // Five bursts land before a single record has been drained — a short
    // course run as a set with no rest, or a chip that buffered several reps
    // and pushed them together. A single pending-lap slot loses four of them.
    for (var i = 0; i < 5; i++) {
        rig.engine.onRepBurst(TestSupport.workedRep(), 1000 + i * 20000);
    }
    TestSupport.tick(rig.recorder, 40);

    Test.assertEqualMessage(session.countOf("addLap"), 5, "no rep loses its lap to the next one");
    return true;
}

(:test)
function testALapIsCutOnlyAfterEveryOneOfItsSplitRecordsIsWritten(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 10);

    Test.assertEqualMessage(session.lapWriteCount(0, "fl_split_us"), 4,
        "all four split records were on disk before the lap closed");
    return true;
}

(:test)
function testAddLapHappensOnALaterTickThanTheLapFieldWrites(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);

    // The known FitContributor bug: setData() and addLap() with no yield
    // between them and the lap's developer fields are dropped from the file.
    var fieldsAt = -1;
    var lapAt = -1;
    for (var t = 0; t < 12; t++) {
        TestSupport.tick(rig.recorder, 1);
        if (fieldsAt < 0 && session.field("fl_rep_time_us").writes() > 0) { fieldsAt = t; }
        if (lapAt < 0 && session.countOf("addLap") > 0) { lapAt = t; }
    }

    Test.assertMessage(fieldsAt >= 0, "the lap fields were written at all");
    Test.assertMessage(lapAt >= 0, "the lap was closed at all");
    Test.assertMessage(lapAt > fieldsAt, "addLap is deferred to a tick after the setData calls");
    return true;
}

// ---------------------------------------------------------------------------
// What the lap carries
// ---------------------------------------------------------------------------

(:test)
function testTheLapCarriesAllSixDeveloperFields(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 10);

    Test.assertEqualMessage(session.lapValue(0, "fl_rep_time_us"), 11930000, "rep time, exact microseconds");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_dist_m"), 100.0, "rep distance");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_splits"), 4, "split count");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_status"), RepStatus.OK, "rep status");
    TestSupport.assertClose(session.lapValue(0, "fl_rep_avg_vel"), 8.382, 0.001, "average velocity");
    TestSupport.assertClose(session.lapValue(0, "fl_rep_peak_vel"), 8.989, 0.001, "peak velocity");
    return true;
}

(:test)
function testEachLapCarriesItsOwnRepNotTheLatestOne(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);                    // 11.930 s
    rig.engine.onRepBurst(TestSupport.burst([0l, 4000000l, 7000000l, 11000000l],
        [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]), 30000);      // 11.000 s
    TestSupport.tick(rig.recorder, 20);

    Test.assertEqualMessage(session.countOf("addLap"), 2, "two laps");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_time_us"), 11930000, "lap 1 carries rep 1");
    Test.assertEqualMessage(session.lapValue(1, "fl_rep_time_us"), 11000000, "lap 2 carries rep 2");
    return true;
}

(:test)
function testAPartialRepsLapSaysSo(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onCrossing(new Crossing(0l, TxCode.START, "T"), 1000);
    rig.engine.onCrossing(new Crossing(4000000l, TxCode.LAP, "T"), 5000);
    rig.engine.forceRepEnd();
    TestSupport.tick(rig.recorder, 10);

    Test.assertEqualMessage(session.lapValue(0, "fl_rep_status"), RepStatus.PARTIAL,
        "the lap tells you the rep never reached the finish");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_dist_m"), 30.0,
        "over the distance actually covered");
    return true;
}

// ---------------------------------------------------------------------------
// lapPerCrossing
// ---------------------------------------------------------------------------

(:test)
function testLapPerCrossingCutsALapForEveryCrossing(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.lapPerCrossing = true;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 12);

    Test.assertEqualMessage(session.countOf("addLap"), 4, "four crossings, four laps");
    return true;
}

(:test)
function testLapPerCrossingLapsCarryTheSplitsOwnValues(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.lapPerCrossing = true;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 12);

    // Lap 1 is the second crossing: 4.120 s over 30 m.
    Test.assertEqualMessage(session.lapValue(1, "fl_rep_time_us"), 4120000, "the split's own time");
    Test.assertEqualMessage(session.lapValue(1, "fl_rep_dist_m"), 30.0, "the split's own distance");
    Test.assertEqualMessage(session.lapValue(1, "fl_rep_splits"), 1, "a lap of one crossing");
    TestSupport.assertClose(session.lapValue(1, "fl_rep_avg_vel"), 7.282, 0.001, "the split's velocity");
    return true;
}

(:test)
function testLapPerCrossingDoesNotAlsoCutALapAtTheEndOfTheRep(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.lapPerCrossing = true;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 20);

    Test.assertEqualMessage(session.countOf("addLap"), 4, "four, not five");
    return true;
}

// ---------------------------------------------------------------------------
// Save
// ---------------------------------------------------------------------------

(:test)
function testSaveClosesALapThatIsStillPending(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    // Save immediately after the FINISH burst, with nothing drained yet.
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.recorder.save();

    Test.assertEqualMessage(session.countOf("addLap"), 1, "the rep still got its lap");
    Test.assertEqualMessage(session.lapValue(0, "fl_rep_time_us"), 11930000, "with its fields");
    Test.assertEqualMessage(session.lapWriteCount(0, "fl_split_us"), 4,
        "and all four split records went in first");
    return true;
}

(:test)
function testSaveClosesEveryPendingLapNotJustTheLast(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.engine.onRepBurst(TestSupport.workedRep(), 30000);
    rig.engine.onRepBurst(TestSupport.workedRep(), 60000);
    rig.recorder.save();

    Test.assertEqualMessage(session.countOf("addLap"), 3, "three reps, three laps");
    return true;
}
