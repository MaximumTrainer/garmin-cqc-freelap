using Toybox.Lang;
using Toybox.Test;

// Tests for source/model/SplitEngine.mc and source/model/SplitEvent.mc.
//
// Driven by the acceptance criteria of issue #14, "Split engine: derive
// split/cumulative time (µs), distance, velocity, speed and pace".
//
// The worked example the issue specifies, and the arithmetic behind every
// expected value below:
//
//   course  S:0;L:30;L:60;F:100     (30 m, 30 m, 40 m)
//   chip     0.000  4.120  7.480  11.930 s
//
//   split 1   4.120 s over 30 m   30 / 4.120  = 7.28155 m/s   1000/v = 137.33 s/km
//   split 2   3.360 s over 30 m   30 / 3.360  = 8.92857 m/s
//   split 3   4.450 s over 40 m   40 / 4.450  = 8.98876 m/s
//   rep      11.930 s over 100 m  100 / 11.930 = 8.38223 m/s, peak = 8.98876

(:test)
const WORKED_COURSE = "S:0;L:30;L:60;F:100";

// ---------------------------------------------------------------------------
// Times: integer microseconds, no rounding anywhere
// ---------------------------------------------------------------------------

(:test)
function testSplitTimesAreExactMicroseconds(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[0].splitTimeUs, 0,       "START has no split before it");
    Test.assertEqualMessage(e[1].splitTimeUs, 4120000, "split 1");
    Test.assertEqualMessage(e[2].splitTimeUs, 3360000, "split 2");
    Test.assertEqualMessage(e[3].splitTimeUs, 4450000, "split 3");
    return true;
}

(:test)
function testCumulativeTimesAreExactMicroseconds(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[0].cumTimeUs, 0,        "START is the rep origin");
    Test.assertEqualMessage(e[1].cumTimeUs, 4120000,  "cumulative at LAP 1");
    Test.assertEqualMessage(e[2].cumTimeUs, 7480000,  "cumulative at LAP 2");
    Test.assertEqualMessage(e[3].cumTimeUs, 11930000, "cumulative at FINISH");
    return true;
}

// ---------------------------------------------------------------------------
// Distances come from the course, not from the chip
// ---------------------------------------------------------------------------

(:test)
function testDistancesComeFromTheCourse(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[1].cumDistM, 30.0,   "cumulative at LAP 1");
    Test.assertEqualMessage(e[3].cumDistM, 100.0,  "cumulative at FINISH");
    Test.assertEqualMessage(e[1].splitDistM, 30.0, "split 1 is 30 m");
    Test.assertEqualMessage(e[2].splitDistM, 30.0, "split 2 is 30 m");
    Test.assertEqualMessage(e[3].splitDistM, 40.0, "split 3 is 40 m");
    return true;
}

// ---------------------------------------------------------------------------
// Derived metrics, against the hand-computed values in the issue
// ---------------------------------------------------------------------------

(:test)
function testVelocitiesMatchTheHandComputedValues(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var e = engine.lastRep.events;
    TestSupport.assertClose(e[1].velocityMps, 7.282, 0.001, "split 1 velocity");
    TestSupport.assertClose(e[2].velocityMps, 8.929, 0.001, "split 2 velocity");
    TestSupport.assertClose(e[3].velocityMps, 8.989, 0.001, "split 3 velocity");
    return true;
}

(:test)
function testSpeedIsVelocityInKilometresPerHour(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var e = engine.lastRep.events;
    TestSupport.assertClose(e[1].speedKmh, 26.214, 0.01, "split 1 speed (7.28155 * 3.6)");
    TestSupport.assertClose(e[3].speedKmh, 32.360, 0.01, "split 3 speed (8.98876 * 3.6)");
    return true;
}

(:test)
function testPaceIsSecondsPerKilometre(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var e = engine.lastRep.events;
    TestSupport.assertClose(e[1].paceSecPerKm, 137.3, 0.1, "split 1 pace");
    return true;
}

// ---------------------------------------------------------------------------
// Long chip uptime. The FxChip timestamps with its own clock, which may be an
// absolute uptime well past what a 32-bit Number holds. decodeNumber(UINT32)
// gives a Long for exactly this reason; the rep origin has to be subtracted
// before anything narrows.
// ---------------------------------------------------------------------------

(:test)
function testAbsoluteChipUptimeBeyond32BitsDoesNotOverflow(logger as Test.Logger) as Lang.Boolean {
    var base = 3000000000l;   // 3e9 µs of uptime; 2^31 is 2147483648
    var engine = TestSupport.engineFor(WORKED_COURSE);

    engine.onRepBurst(TestSupport.burst(
        [base, base + 4120000l, base + 7480000l, base + 11930000l],
        [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]), 1000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[3].cumTimeUs, 11930000, "relative time is unaffected by the origin");
    Test.assertEqualMessage(e[1].splitTimeUs, 4120000, "and so is the first split");
    Test.assertEqualMessage(engine.lastRep.timeUs, 11930000, "and the rep total");
    TestSupport.assertClose(e[1].velocityMps, 7.282, 0.001, "and the derived velocity");
    return true;
}

(:test)
function testStreamingModeAlsoHandlesAbsoluteChipUptime(logger as Test.Logger) as Lang.Boolean {
    var base = 4000000000l;   // past 2^31, and past 2^32/2
    var engine = TestSupport.engineFor(WORKED_COURSE);

    engine.onCrossing(new Crossing(base, TxCode.START, "T"), 1000);
    engine.onCrossing(new Crossing(base + 4120000l, TxCode.LAP, "T"), 5120);

    Test.assertEqualMessage(engine.lastEvent.cumTimeUs, 4120000, "relative to the rep's START");
    return true;
}

// ---------------------------------------------------------------------------
// Degenerate splits. A transmitter that double-fires, or a course whose
// distance the crossing could not be matched to, must not divide by zero.
// ---------------------------------------------------------------------------

(:test)
function testZeroDurationSplitProducesZeroesAndNoException(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;F:100");

    // Two crossings on the same chip timestamp.
    engine.onRepBurst(TestSupport.burst([0l, 0l, 4000000l],
                                        [TxCode.START, TxCode.LAP, TxCode.FINISH]), 1000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[1].splitTimeUs, 0,    "no time passed");
    Test.assertEqualMessage(e[1].velocityMps, 0.0,  "velocity is zero, not infinity");
    Test.assertEqualMessage(e[1].speedKmh, 0.0,     "speed is zero");
    Test.assertEqualMessage(e[1].paceSecPerKm, 0.0, "pace is zero, not a division by zero");
    return true;
}

(:test)
function testZeroDistanceSplitProducesZeroesAndNoException(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;F:100");

    // A fourth crossing the course cannot place carries the previous
    // crossing's distance, so its split distance is zero.
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l, 12000000l],
                                        [TxCode.START, TxCode.LAP, TxCode.FINISH, TxCode.FINISH]), 1000);

    var e = engine.lastRep.events;
    Test.assertEqualMessage(e[3].splitDistM, 0.0,   "no distance covered by an unplaceable crossing");
    Test.assertEqualMessage(e[3].velocityMps, 0.0,  "velocity is zero, not a fabricated number");
    Test.assertEqualMessage(e[3].paceSecPerKm, 0.0, "pace is zero");
    return true;
}

(:test)
function testAnEmptyBurstIsIgnored(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);

    engine.onRepBurst([], 1000);

    Test.assertEqualMessage(engine.repNumber, 0, "an empty burst does not start a rep");
    Test.assertEqualMessage(engine.repsDone, 0, "and does not finish one");
    return true;
}

(:test)
function testASingleCrossingBurstProducesOneEventAndNoSplit(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);

    engine.onRepBurst(TestSupport.burst([1000000l], [TxCode.START]), 1000);

    Test.assertEqualMessage(engine.lastRep.splits, 1, "one crossing recorded");
    Test.assertEqualMessage(engine.lastRep.timeUs, 0, "a rep of one crossing has no duration");
    Test.assertEqualMessage(engine.lastRep.avgVelMps, 0.0, "and no average velocity");
    return true;
}

// ---------------------------------------------------------------------------
// Rep totals
// ---------------------------------------------------------------------------

(:test)
function testRepTotalsForTheWorkedExample(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    var rep = engine.lastRep;
    Test.assertEqualMessage(rep.rep, 1, "first rep");
    Test.assertEqualMessage(rep.timeUs, 11930000, "rep time in exact microseconds");
    Test.assertEqualMessage(rep.distM, 100.0, "rep distance");
    Test.assertEqualMessage(rep.splits, 4, "four crossings");
    Test.assertEqualMessage(rep.status, RepStatus.OK, "complete rep");
    TestSupport.assertClose(rep.avgVelMps, 8.382, 0.001, "average velocity over the whole rep");
    TestSupport.assertClose(rep.peakVelMps, 8.989, 0.001, "peak is the fastest split, not the average");
    return true;
}

(:test)
function testBestRepIgnoresRepsThatAreNotOk(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);

    // Rep 1: complete, 11.930 s.
    engine.onRepBurst(TestSupport.workedRep(), 1000);
    // Rep 2: faster, but the athlete missed a transmitter — 3 crossings on a
    // 4-transmitter course, so PARTIAL. A "best" of 8 s the athlete never ran
    // would be worse than useless.
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l],
                                        [TxCode.START, TxCode.LAP, TxCode.LAP]), 20000);

    Test.assertEqualMessage(engine.lastRep.status, RepStatus.PARTIAL, "rep 2 is partial");
    Test.assertEqualMessage(engine.bestRepUs, 11930000, "best rep is still the complete one");
    return true;
}

(:test)
function testBestRepTakesTheFastestOkRep(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);

    engine.onRepBurst(TestSupport.workedRep(), 1000);
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 7000000l, 11000000l],
                                        [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]), 20000);
    engine.onRepBurst(TestSupport.burst([0l, 4200000l, 7600000l, 12100000l],
                                        [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]), 40000);

    Test.assertEqualMessage(engine.bestRepUs, 11000000, "the fastest of the three complete reps");
    Test.assertEqualMessage(engine.repsDone, 3, "three reps done");
    return true;
}

(:test)
function testTotalDistanceSumsEveryRepIncludingPartialOnes(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);

    engine.onRepBurst(TestSupport.workedRep(), 1000);                       // 100 m
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l],
                                        [TxCode.START, TxCode.LAP, TxCode.LAP]), 20000);  // 60 m, PARTIAL

    // The athlete ran the metres whether or not the rep was clean.
    Test.assertEqualMessage(engine.totalDistM, 160.0, "distance sums all reps");
    Test.assertEqualMessage(engine.repsDone, 2, "both reps counted");
    return true;
}

(:test)
function testSessionStartResetsTheTotals(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor(WORKED_COURSE);
    engine.onRepBurst(TestSupport.workedRep(), 1000);

    engine.onSessionStart();

    Test.assertEqualMessage(engine.repsDone, 0, "reps");
    Test.assertEqualMessage(engine.totalDistM, 0.0, "distance");
    Test.assertEqualMessage(engine.bestRepUs, 0, "best rep");
    Test.assertEqualMessage(engine.repNumber, 0, "rep numbering restarts");
    return true;
}

// ---------------------------------------------------------------------------
// Construction. The engine is handed its latency rather than reading it, so
// everything above runs without settings (AGENTS.md, "Inject, don't fetch").
// ---------------------------------------------------------------------------

(:test)
function testEngineTakesItsLatencyAsAnArgument(logger as Test.Logger) as Lang.Boolean {
    var engine = new SplitEngine(new Course(WORKED_COURSE, "worked"), null, 250);

    Test.assertEqualMessage(engine.bleLatencyMs, 250, "no settings read to construct an engine");
    return true;
}

(:test)
function testFromSettingsStillWorksForTheApp(logger as Test.Logger) as Lang.Boolean {
    var engine = SplitEngine.fromSettings(new Course(WORKED_COURSE, "worked"), null);

    Test.assertMessage(engine.bleLatencyMs >= 0, "the convenience entry point reads the setting");
    return true;
}
