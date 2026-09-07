using Toybox.FitContributor as Fit;
using Toybox.Lang;
using Toybox.Test;

// Tests for the record-level half of source/fit/FitRecorder.mc.
//
// Driven by the acceptance criteria of issue #16, "FIT: record-level developer
// fields for every split", against the field table in docs/DESIGN.md §5.
//
// The recorder drains one split per 1 Hz tick on purpose — one FIT record
// carries one split — so the tests tick it by hand rather than waiting on a
// Timer. `TestSupport.recorderOn(session, spec)` wires a recorder, an engine
// and a course together over a FakeSession.

// ---------------------------------------------------------------------------
// The field table itself. If these names, ids, types or units drift, every
// consumer of the FIT file breaks silently — Garmin Connect just stops showing
// the chart, and a decoder reads the wrong column.
// ---------------------------------------------------------------------------

(:test)
function testAllTenRecordFieldsAreDeclared(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    TestSupport.recorderOn(session, "S:0;L:30;F:100");

    var expected = ["fl_split_us", "fl_cum_us", "fl_dist_m", "fl_velocity", "fl_speed",
                    "fl_pace", "fl_tx_idx", "fl_tx_code", "fl_rep", "fl_est_ms"];
    for (var i = 0; i < expected.size(); i++) {
        var f = session.field(expected[i]);
        Test.assertMessage(f != null, expected[i] + " is declared");
        Test.assertEqualMessage(f.fieldId, i, expected[i] + " has field id " + i.format("%d"));
        Test.assertEqualMessage(f.mesgType(), Fit.MESG_TYPE_RECORD, expected[i] + " is a record field");
    }
    return true;
}

(:test)
function testRecordFieldTypesMatchTheDesignTable(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    TestSupport.recorderOn(session, "S:0;L:30;F:100");

    // Microsecond durations are uint32, not float: a float would round the
    // very thing the app exists to preserve.
    Test.assertEqualMessage(session.field("fl_split_us").dataType, Fit.DATA_TYPE_UINT32, "fl_split_us");
    Test.assertEqualMessage(session.field("fl_cum_us").dataType, Fit.DATA_TYPE_UINT32, "fl_cum_us");
    Test.assertEqualMessage(session.field("fl_est_ms").dataType, Fit.DATA_TYPE_UINT32, "fl_est_ms");
    Test.assertEqualMessage(session.field("fl_dist_m").dataType, Fit.DATA_TYPE_FLOAT, "fl_dist_m");
    Test.assertEqualMessage(session.field("fl_velocity").dataType, Fit.DATA_TYPE_FLOAT, "fl_velocity");
    Test.assertEqualMessage(session.field("fl_speed").dataType, Fit.DATA_TYPE_FLOAT, "fl_speed");
    Test.assertEqualMessage(session.field("fl_pace").dataType, Fit.DATA_TYPE_FLOAT, "fl_pace");
    Test.assertEqualMessage(session.field("fl_tx_idx").dataType, Fit.DATA_TYPE_UINT8, "fl_tx_idx");
    Test.assertEqualMessage(session.field("fl_tx_code").dataType, Fit.DATA_TYPE_UINT8, "fl_tx_code");
    Test.assertEqualMessage(session.field("fl_rep").dataType, Fit.DATA_TYPE_UINT16, "fl_rep");
    return true;
}

(:test)
function testRecordFieldUnitsMatchTheDesignTable(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    TestSupport.recorderOn(session, "S:0;L:30;F:100");

    Test.assertEqualMessage(session.field("fl_split_us").units(), "us", "fl_split_us");
    Test.assertEqualMessage(session.field("fl_cum_us").units(), "us", "fl_cum_us");
    Test.assertEqualMessage(session.field("fl_dist_m").units(), "m", "fl_dist_m");
    Test.assertEqualMessage(session.field("fl_velocity").units(), "m/s", "fl_velocity");
    Test.assertEqualMessage(session.field("fl_speed").units(), "km/h", "fl_speed");
    Test.assertEqualMessage(session.field("fl_pace").units(), "s/km", "fl_pace");
    Test.assertEqualMessage(session.field("fl_est_ms").units(), "ms", "fl_est_ms");
    return true;
}

// ---------------------------------------------------------------------------
// One split per record, in order
// ---------------------------------------------------------------------------

(:test)
function testAFourCrossingRepWritesExactlyFourRecords(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 4);

    Test.assertEqualMessage(session.field("fl_split_us").writes(), 4, "four records, one per crossing");
    TestSupport.assertArrayEquals(session.valuesOf("fl_tx_idx"), [0, 1, 2, 3], "transmitter index 0..3, in order");
    TestSupport.assertArrayEquals(session.valuesOf("fl_rep"), [1, 1, 1, 1], "all four records carry rep 1");
    return true;
}

(:test)
function testSplitMicrosecondsReachTheFitFileUnchanged(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 4);

    // The engine's values, byte for byte. Nothing rounds on the way out.
    TestSupport.assertArrayEquals(session.valuesOf("fl_split_us"), [0, 4120000, 3360000, 4450000], "fl_split_us");
    TestSupport.assertArrayEquals(session.valuesOf("fl_cum_us"), [0, 4120000, 7480000, 11930000], "fl_cum_us");
    return true;
}

(:test)
function testTransmitterCodesAreWrittenAsTheCourseSawThem(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 4);

    TestSupport.assertArrayEquals(session.valuesOf("fl_tx_code"), [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH], "fl_tx_code");
    return true;
}

(:test)
function testAnUnmatchedCrossingIsWrittenAs255NotAsANegativeIndex(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;F:100");

    // A fourth crossing on a three-transmitter course.
    rig.engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l, 12000000l],
        [TxCode.START, TxCode.LAP, TxCode.FINISH, TxCode.FINISH]), 1000);
    TestSupport.tick(rig.recorder, 4);

    // fl_tx_idx is uint8; the engine's -1 has to become the sentinel or it
    // wraps to a plausible-looking transmitter index.
    TestSupport.assertArrayEquals(session.valuesOf("fl_tx_idx"), [0, 1, 2, 255], "unmatched crossing is 255");
    return true;
}

(:test)
function testASecondRepCarriesTheNextRepNumber(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tick(rig.recorder, 6);
    rig.engine.onRepBurst(TestSupport.workedRep(), 30000);
    TestSupport.tick(rig.recorder, 4);

    var reps = session.valuesOf("fl_rep");
    Test.assertEqualMessage(reps[reps.size() - 1], 2, "the last record written is in rep 2");
    return true;
}

// ---------------------------------------------------------------------------
// clearAfterWrite
// ---------------------------------------------------------------------------

(:test)
function testClearAfterWriteBlanksTheRecordFollowingTheLastSplit(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.clearAfterWrite = true;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tickUntilIdle(rig.recorder, 20);

    Test.assertEqualMessage(session.field("fl_split_us").last(), 0,
        "the record after the last split carries no split time");
    Test.assertEqualMessage(session.field("fl_tx_idx").last(), 255,
        "and no transmitter");
    return true;
}

(:test)
function testWithoutClearAfterWriteTheLastValuesStand(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.clearAfterWrite = false;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tickUntilIdle(rig.recorder, 20);

    // No further write means the FIT record repeats what the field held.
    Test.assertEqualMessage(session.field("fl_split_us").writes(), 4, "no blanking write");
    Test.assertEqualMessage(session.field("fl_split_us").last(), 4450000, "the last split still stands");
    Test.assertEqualMessage(session.field("fl_tx_idx").last(), 3, "and the last transmitter");
    return true;
}

// ---------------------------------------------------------------------------
// Pause
// ---------------------------------------------------------------------------

(:test)
function testSplitsArrivingWhilePausedAreWrittenOnResume(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.recorder.stop();                                  // pause
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);  // chip pushes a rep anyway
    TestSupport.tick(rig.recorder, 4);

    Test.assertEqualMessage(session.field("fl_split_us").writes(), 0,
        "nothing is written to a paused session");

    rig.recorder.resume();
    TestSupport.tick(rig.recorder, 4);

    TestSupport.assertArrayEquals(session.valuesOf("fl_split_us"), [0, 4120000, 3360000, 4450000], "every split held during the pause is written, in order");
    return true;
}

(:test)
function testSplitsQueuedAtSaveAreFlushedRatherThanDropped(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    // Save immediately after a FINISH burst, before any tick has drained it.
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    rig.recorder.save();

    Test.assertEqualMessage(session.field("fl_split_us").writes(), 4,
        "all four splits reached the file");
    Test.assertMessage(session.saved, "and the session was saved");
    return true;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

(:test)
function testRecorderTakesItsFlagsAsArguments(logger as Test.Logger) as Lang.Boolean {
    var recorder = new FitRecorder(false, true);

    Test.assertEqualMessage(recorder.clearAfterWrite, false, "clearAfterWrite injected");
    Test.assertEqualMessage(recorder.lapPerCrossing, true, "lapPerCrossing injected");
    return true;
}

(:test)
function testRecorderFromSettingsStillWorksForTheApp(logger as Test.Logger) as Lang.Boolean {
    var recorder = FitRecorder.fromSettings();

    Test.assertMessage(recorder != null, "the convenience entry point reads the settings");
    return true;
}
