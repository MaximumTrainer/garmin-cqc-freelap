using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #19, "Store the full split log on
// the watch and expose it for export".
//
// This log exists because the FIT file is not enough on its own: Garmin
// Connect rounds floats in its UI, and getting at the raw developer fields
// needs a desktop and the FIT SDK. The stored log is the athlete's copy, at
// full microsecond precision, independent of any of that - which only holds if
// it survives the app closing.

(:test)
function testEverySplitOfTheSessionIsStored(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tickUntilIdle(rig.recorder, 20);

    var log = rig.recorder.log();
    Test.assertEqualMessage(log.size(), 4, "one row per crossing");
    return true;
}

(:test)
function testAStoredRowCarriesEveryColumnTheExporterExpects(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");
    engine.onRepBurst(TestSupport.workedRep(), 30000);

    var row = engine.lastRep.events[1].toArray();

    // The column order tools/splits_to_csv.py reads. If this changes, that
    // list changes with it or every row is silently dropped as the wrong width.
    Test.assertEqualMessage(row.size(), 10, "ten columns");
    Test.assertEqualMessage(row[0], 1, "rep");
    Test.assertEqualMessage(row[1], 1, "tx index");
    Test.assertEqualMessage(row[2], TxCode.LAP, "tx code");
    Test.assertEqualMessage(row[3], 4120000, "cumulative us");
    Test.assertEqualMessage(row[4], 4120000, "split us");
    Test.assertEqualMessage(row[5], 30.0, "cumulative distance");
    Test.assertEqualMessage(row[6], 30.0, "split distance");
    TestSupport.assertClose(row[7], 7.282, 0.001, "velocity");
    Test.assertEqualMessage(row[8], 12040, "estimated ms into the session");
    Test.assertEqualMessage(row[9], false, "estimate not clamped");
    return true;
}

(:test)
function testMicrosecondsAreStoredExactlyNotRounded(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);

    var rows = rig.recorder.log().rows;
    Test.assertEqualMessage(rows[1][4], 4120000, "split 1, to the microsecond");
    Test.assertEqualMessage(rows[3][3], 11930000, "and the rep total");
    return true;
}

// ---------------------------------------------------------------------------
// Surviving a restart
// ---------------------------------------------------------------------------

(:test)
function testTheLogSurvivesTheAppClosing(logger as Test.Logger) as Lang.Boolean {
    var storage = new FakeStorage();
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.recorder.log().flush(storage, "lastSessionSplits");

    // The app closes. A new SplitLog, on a fresh start, reads it back.
    var restored = new SplitLog();

    Test.assertMessage(restored.restore(storage, "lastSessionSplits"), "something was there");
    Test.assertEqualMessage(restored.size(), 4, "all four splits");
    Test.assertEqualMessage(restored.rows[1][4], 4120000, "with their microseconds intact");
    return true;
}

(:test)
function testRestoringWhenNothingWasStoredIsNotAnError(logger as Test.Logger) as Lang.Boolean {
    var log = new SplitLog();

    Test.assertMessage(!log.restore(new FakeStorage(), "lastSessionSplits"), "nothing to restore");
    Test.assertEqualMessage(log.size(), 0, "and the log is still empty, not broken");
    return true;
}

(:test)
function testAFullSessionOfFortyRepsFitsInOneStoredValue(logger as Test.Logger) as Lang.Boolean {
    var storage = new FakeStorage();
    var rig = TestSupport.recorderOn(new QuietSession(), "S:0;L:25;L:50;L:75;F:100");

    // Issue #19 sizes for 40 reps x 5 splits.
    TestSupport.runRepsOf(rig, 40, 5);

    var log = rig.recorder.log();
    Test.assertEqualMessage(log.seen, 200, "40 reps of 5 crossings");
    Test.assertMessage(log.complete(), "none dropped, so the export is the whole session");
    Test.assertMessage(log.size() <= SplitLog.MAX_ROWS, "inside the cap");

    log.flush(storage, "lastSessionSplits");
    Test.assertEqualMessage(storage.writes, 1, "and it goes in one value, not chunked");
    return true;
}

// ---------------------------------------------------------------------------
// The dump format
// ---------------------------------------------------------------------------

(:test)
function testARowDumpsAsAJsonArray(logger as Test.Logger) as Lang.Boolean {
    var log = new SplitLog();
    log.add([1, 0, 1, 0, 0, 0.0, 0.0, 0.0, 7920, false]);

    // tools/splits_to_csv.py parses each line with json.loads.
    Test.assertEqualMessage(log.rowAsJson(0),
        "[1,0,1,0,0,0.0000000,0.0000000,0.0000000,7920,false]", "row 0");
    return true;
}

(:test)
function testABooleanDumpsAsJsonTrueNotAsANumber(logger as Test.Logger) as Lang.Boolean {
    var log = new SplitLog();
    log.add([1, 0, 1, 0, 0, 0.0, 0.0, 0.0, 0, true]);

    Test.assertMessage(log.rowAsJson(0).find("true") != null,
        "a clamped estimate must survive as a boolean: " + log.rowAsJson(0));
    return true;
}

(:test)
function testAVelocityDumpsWithEnoughPrecisionToBeUseful(logger as Test.Logger) as Lang.Boolean {
    var log = new SplitLog();
    log.add([1, 1, 2, 4120000, 4120000, 30.0, 30.0, 7.2815533, 12040, false]);

    var json = log.rowAsJson(0);
    Test.assertMessage(json.find("7.28155") != null,
        "two decimals would throw away what the microseconds bought: " + json);
    return true;
}
