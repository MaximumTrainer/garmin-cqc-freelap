using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #28, "Multi-athlete: Freelap
// Relay Coach BLE / several chips".
//
// The failure this prevents is subtle and would be very hard to spot after the
// fact: two athletes running alternately, numbered 1, 2, 3, 4 between them,
// with every rep attributed to whoever happened to cross next. The numbers all
// look plausible; they are just the wrong athlete's.

(:test)
function testASingleChipSessionIsUnchanged(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.workedRep(), 30000);
    engine.onRepBurst(TestSupport.workedRep(), 60000);

    Test.assertEqualMessage(engine.roster.size(), 1, "one chip");
    Test.assertEqualMessage(engine.lastRep.rep, 2, "reps numbered 1, 2");
    Test.assertEqualMessage(engine.lastRep.chipSlot, 0, "all in slot 0");
    return true;
}

(:test)
function testEachChipGetsItsOwnSlotInTheOrderItIsFirstHeard(logger as Test.Logger) as Lang.Boolean {
    var roster = new ChipRoster();

    Test.assertEqualMessage(roster.forChip("AAAA").slot, 0, "first heard");
    Test.assertEqualMessage(roster.forChip("BBBB").slot, 1, "second");
    Test.assertEqualMessage(roster.forChip("AAAA").slot, 0, "and the first keeps its slot");
    Test.assertEqualMessage(roster.size(), 2, "two chips");
    return true;
}

(:test)
function testTheRosterListsChipsInSlotOrderForTheFitFile(logger as Test.Logger) as Lang.Boolean {
    var roster = new ChipRoster();
    roster.forChip("AAAA");
    roster.forChip("BBBB");

    // fl_chip_idx on a record is an index into this.
    Test.assertEqualMessage(roster.idList(), "AAAA,BBBB", "slot order");
    Test.assertEqualMessage(roster.idOf(1), "BBBB", "and resolves back");
    return true;
}

(:test)
function testARosterOfOneReadsExactlyAsItDidBefore(logger as Test.Logger) as Lang.Boolean {
    var roster = new ChipRoster();
    roster.forChip("1234");

    Test.assertEqualMessage(roster.idList(), "1234", "no separator, no change for one athlete");
    return true;
}

(:test)
function testTheRosterRefusesToGrowWithoutBound(logger as Test.Logger) as Lang.Boolean {
    var roster = new ChipRoster();
    for (var i = 0; i < ChipRoster.MAX_CHIPS + 4; i++) {
        roster.forChip("chip" + i.format("%d"));
    }

    // A garbled chip id must not be able to grow the roster forever, and
    // fl_chip_idx is a uint8 with 255 reserved.
    Test.assertEqualMessage(roster.size(), ChipRoster.MAX_CHIPS, "capped");
    Test.assertEqualMessage(roster.overflow, 4, "and the overflow is counted");
    return true;
}

// ---------------------------------------------------------------------------
// Interleaved reps
// ---------------------------------------------------------------------------

(:test)
function testTwoChipsRunningAlternatelyKeepSeparateRepNumbers(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.burstFrom("AAAA"), 30000);   // A's rep 1
    engine.onRepBurst(TestSupport.burstFrom("BBBB"), 40000);   // B's rep 1
    engine.onRepBurst(TestSupport.burstFrom("AAAA"), 60000);   // A's rep 2
    engine.onRepBurst(TestSupport.burstFrom("BBBB"), 70000);   // B's rep 2
    engine.onRepBurst(TestSupport.burstFrom("AAAA"), 90000);   // A's rep 3

    // Numbered 1..5 between them, the FIT file would say athlete B ran reps
    // 2 and 4 of a five-rep session neither of them did.
    Test.assertEqualMessage(engine.lastRep.chipId, "AAAA", "the last rep was A's");
    Test.assertEqualMessage(engine.lastRep.rep, 3, "and it was A's third, not the session's fifth");
    Test.assertEqualMessage(engine.repsDone, 5, "five reps were run in total");
    return true;
}

(:test)
function testEverySplitCarriesTheChipItCameFrom(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.burstFrom("AAAA"), 30000);
    engine.onRepBurst(TestSupport.burstFrom("BBBB"), 40000);

    var events = engine.lastRep.events;
    for (var i = 0; i < events.size(); i++) {
        var ev = events[i] as SplitEvent;
        Test.assertEqualMessage(ev.chipId, "BBBB", "split " + i.format("%d") + " chip id");
        Test.assertEqualMessage(ev.chipSlot, 1, "split " + i.format("%d") + " slot");
    }
    return true;
}

(:test)
function testStreamingCrossingsFromTwoChipsDoNotInterleaveIntoOneRep(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;F:100");

    // Two athletes on the track at once, crossings arriving interleaved.
    engine.onCrossing(new Crossing(0l, TxCode.START, "AAAA"), 20000);
    engine.onCrossing(new Crossing(0l, TxCode.START, "BBBB"), 20100);
    engine.onCrossing(new Crossing(4000000l, TxCode.LAP, "AAAA"), 24000);
    engine.onCrossing(new Crossing(4500000l, TxCode.LAP, "BBBB"), 24600);
    engine.onCrossing(new Crossing(8000000l, TxCode.FINISH, "AAAA"), 28000);

    // A's rep must contain A's three crossings, not five from both.
    Test.assertEqualMessage(engine.lastRep.chipId, "AAAA", "A finished first");
    Test.assertEqualMessage(engine.lastRep.splits, 3, "three crossings, all A's");
    Test.assertEqualMessage(engine.lastRep.timeUs, 8000000, "and A's time, not a mixture");
    return true;
}

(:test)
function testAChipThatGoesQuietComesBackToItsOwnRepCount(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");

    engine.onRepBurst(TestSupport.burstFrom("AAAA"), 30000);
    for (var i = 0; i < 4; i++) {
        engine.onRepBurst(TestSupport.burstFrom("BBBB"), 40000 + i * 10000);
    }
    engine.onRepBurst(TestSupport.burstFrom("AAAA"), 90000);

    Test.assertEqualMessage(engine.lastRep.rep, 2, "A's second rep, after sitting out four of B's");
    return true;
}

// ---------------------------------------------------------------------------
// Reaching the FIT file
// ---------------------------------------------------------------------------

(:test)
function testEveryRecordCarriesItsChipSlot(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.clearAfterWrite = false;

    rig.engine.onRepBurst(TestSupport.burstFrom("AAAA"), 30000);
    TestSupport.tickUntilIdle(rig.recorder, 30);
    rig.engine.onRepBurst(TestSupport.burstFrom("BBBB"), 60000);
    TestSupport.tickUntilIdle(rig.recorder, 30);

    TestSupport.assertArrayEquals(session.valuesOf("fl_chip_idx"),
        [0, 0, 0, 0, 1, 1, 1, 1], "four records per chip, tagged with its slot");
    return true;
}

(:test)
function testTheSessionListsEveryChipItHeardFrom(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.burstFrom("AAAA"), 30000);
    rig.engine.onRepBurst(TestSupport.burstFrom("BBBB"), 60000);
    rig.recorder.save();

    // fl_chip_idx on a record is an index into this string.
    Test.assertEqualMessage(session.field("fl_chip_id").last(), "AAAA,BBBB", "in slot order");
    return true;
}

(:test)
function testABlankedRecordCarriesTheUnknownChipSlot(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.burstFrom("AAAA"), 30000);
    TestSupport.tickUntilIdle(rig.recorder, 30);

    // 0 is a real chip slot, so the blanking write cannot use it.
    Test.assertEqualMessage(session.field("fl_chip_idx").last(), 255, "not slot 0");
    return true;
}

(:test)
function testASingleChipSessionStillWritesOneChipId(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");

    rig.engine.onRepBurst(TestSupport.burstFrom("1234"), 30000);
    rig.recorder.save();

    Test.assertEqualMessage(session.field("fl_chip_id").last(), "1234",
        "one athlete, no separator, no change from before");
    return true;
}
