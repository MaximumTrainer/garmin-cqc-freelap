using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #15, "Estimated wall-clock
// placement of crossings (BLE latency model)".
//
// The chip's durations are exact; where those durations sit on the watch's
// timeline is a guess, and the whole point of fl_est_ms is to be honest about
// which is which. The arithmetic, with the numbers every test below uses:
//
//   session starts at   t = 10 000 ms   (watch monotonic clock)
//   burst arrives at    t = 30 000 ms
//   assumed BLE latency         150 ms
//   rep                 0 / 4.120 / 7.480 / 11.930 s
//
//   FINISH  = (30 000 - 150) - 10 000            = 19 850 ms into the session
//   LAP 2   = 19 850 - (11.930 - 7.480) * 1000   = 15 400
//   LAP 1   = 19 850 - (11.930 - 4.120) * 1000   = 12 040
//   START   = 19 850 -  11.930 * 1000            =  7 920
//
// i.e. START is FINISH minus the rep time, and the gaps between the estimates
// are the chip's own splits.

(:test)
function testFinishIsPlacedAtArrivalMinusLatency(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 30000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[3].estSessionMs, 19850,
        "the FINISH crossing happened one latency before the packet arrived");
    return true;
}

(:test)
function testStartIsFinishMinusTheRepTime(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 30000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[0].estSessionMs, 7920, "START");
    Test.assertEqualMessage(e[3].estSessionMs - e[0].estSessionMs, 11930,
        "the gap between them is the rep time, exactly");
    return true;
}

(:test)
function testIntermediateCrossingsArePlacedByTheirOwnSplits(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 30000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[1].estSessionMs, 12040, "LAP 1");
    Test.assertEqualMessage(e[2].estSessionMs, 15400, "LAP 2");

    // The gaps between estimates are the chip's splits, not an even spread.
    Test.assertEqualMessage(e[1].estSessionMs - e[0].estSessionMs, 4120, "split 1");
    Test.assertEqualMessage(e[2].estSessionMs - e[1].estSessionMs, 3360, "split 2");
    Test.assertEqualMessage(e[3].estSessionMs - e[2].estSessionMs, 4450, "split 3");
    return true;
}

(:test)
function testChangingTheLatencyShiftsEveryEstimateByExactlyTheDelta(logger as Test.Logger) as Lang.Boolean {
    var slow = TestSupport.engineAt(10000, 250, "S:0;L:30;L:60;F:100");
    slow.onRepBurst(TestSupport.workedRep(), 30000);

    var e = slow.lastRep.events;
    // 100 ms more assumed latency puts every crossing 100 ms earlier.
    Test.assertEqualMessage(e[0].estSessionMs, 7820, "START");
    Test.assertEqualMessage(e[1].estSessionMs, 11940, "LAP 1");
    Test.assertEqualMessage(e[2].estSessionMs, 15300, "LAP 2");
    Test.assertEqualMessage(e[3].estSessionMs, 19750, "FINISH");
    return true;
}

(:test)
function testZeroLatencyPlacesFinishAtTheArrivalTime(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 0, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 30000);

    Test.assertEqualMessage(engine.lastRep.events[3].estSessionMs, 20000,
        "no latency assumed, so the packet arrived when the crossing happened");
    return true;
}

// ---------------------------------------------------------------------------
// Clamping
// ---------------------------------------------------------------------------

(:test)
function testAnEstimateBeforeTheSessionStartedIsClampedToZero(logger as Test.Logger) as Lang.Boolean {
    // The chip buffers. Start the watch five seconds into a twelve-second rep
    // and the START crossing genuinely happened before the session did.
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 15000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[0].estSessionMs, 0,
        "a negative offset into the session is not a time; it is clamped");
    Test.assertMessage(e[0].estClamped, "and flagged, so the 0 is not read as a measurement");
    return true;
}

(:test)
function testCrossingsAfterTheSessionStartedAreNotFlagged(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 15000);

    var e = engine.lastRep.events;
    // FINISH is 4850 ms into the session; only the earlier ones were clamped.
    Test.assertEqualMessage(e[3].estSessionMs, 4850, "FINISH is a real offset");
    Test.assertMessage(!e[3].estClamped, "so it is not flagged");
    return true;
}

(:test)
function testTheEngineCountsClampedEstimates(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 15000);

    // FINISH is 4850 ms into the session, so working back: LAP 2 lands at
    // +400 ms and is fine; START (-7080) and LAP 1 (-2960) are not.
    Test.assertEqualMessage(engine.clampedEstimates, 2, "two crossings could not be placed");
    Test.assertMessage(!engine.lastRep.events[2].estClamped, "LAP 2 just made it");
    return true;
}

(:test)
function testAClampedEstimateIsRecordedInTheSplitLog(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");
    engine.onRepBurst(TestSupport.workedRep(), 15000);

    var row = engine.lastRep.events[0].toArray();

    // fl_est_ms is a uint32 and 0 is a legitimate value, so the flag has to
    // travel with the row or "0" becomes indistinguishable from "unknown".
    Test.assertEqualMessage(row[row.size() - 1], true, "the log row carries the clamp flag");
    return true;
}

// ---------------------------------------------------------------------------
// Streaming mode
// ---------------------------------------------------------------------------

(:test)
function testStreamingCrossingsArePlacedAtArrivalMinusLatency(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onCrossing(new Crossing(0l, TxCode.START, "T"), 20000);
    Test.assertEqualMessage(engine.lastEvent.estSessionMs, 9850, "START");

    engine.onCrossing(new Crossing(4120000l, TxCode.LAP, "T"), 24120);
    Test.assertEqualMessage(engine.lastEvent.estSessionMs, 13970, "LAP 1");
    return true;
}

(:test)
function testStreamingEstimatesAreAlsoClamped(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;F:100");

    // A packet whose assumed send time predates the session start.
    engine.onCrossing(new Crossing(0l, TxCode.START, "T"), 10100);

    Test.assertEqualMessage(engine.lastEvent.estSessionMs, 0, "clamped");
    Test.assertMessage(engine.lastEvent.estClamped, "and flagged");
    return true;
}

// ---------------------------------------------------------------------------
// Reaching the FIT file
// ---------------------------------------------------------------------------

(:test)
function testTheEstimateReachesFlEstMsUnchanged(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var recorder = new FitRecorder(true, false);
    var engine = new SplitEngine(new Course("S:0;L:30;L:60;F:100", "test"), recorder, 150);
    recorder.startWith(session, engine, false);
    engine.onSessionStartAt(10000);

    engine.onRepBurst(TestSupport.workedRep(), 30000);
    TestSupport.tick(recorder, 4);

    TestSupport.assertArrayEquals(session.valuesOf("fl_est_ms"),
        [7920, 12040, 15400, 19850], "fl_est_ms carries the estimates as computed");
    return true;
}
