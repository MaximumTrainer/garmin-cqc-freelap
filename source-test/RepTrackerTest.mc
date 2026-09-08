using Toybox.Lang;
using Toybox.Test;

// Turning a stream of broadcasts into reps: the acceptance criteria of #63
// ("a second chip advertising nearby does not cause the app to record its
// reps", "when unbound the app records nothing rather than guessing") and #9
// ("duplicate frames from the same rep produce exactly one rep", "a gap in the
// frame's lap counter is detected and surfaced as a missed rep, not silently
// absorbed").
//
// Everything the old design could lean on is gone. There is no connection, so
// nothing marks the start or end of anything; the watch simply hears frames,
// most of them repeats, some of them somebody else's, and has to work out on
// its own which ones are reps and whether any are missing. That is all this
// class does, and it does it from frame content rather than from timers -
// which is what makes it testable here without a radio or a clock.
//
// Frames are built directly as Advertisement objects rather than as bytes:
// decoding is BroadcastFrameTest's job, and building frame bytes here would
// mean a second encoder in the repo.

const MINE = "BC-9636";
const THEIRS = "ZZ-1234";

// ---------------------------------------------------------------------------
// Whose chip is it
// ---------------------------------------------------------------------------

(:test)
function testAFrameFromTheBoundChipBecomesARep(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), [6657, 9729]);

    Test.assertMessage(rep != null, "our chip's frame is a rep");
    Test.assertEqualMessage(rep.chip, MINE, "and it says whose");
    return true;
}

(:test)
function testAFrameFromSomebodyElsesChipIsIgnored(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    var rep = tracker.onFrame(TestSupport.repFrame(THEIRS, 0), [6657, 9729]);

    // At a group session every athlete's chip is in range and the watch hears
    // all of them. Recording a training partner's rep produces entirely
    // plausible numbers that belong to somebody else - the failure this whole
    // binding idea exists to prevent (#63).
    Test.assertMessage(rep == null, "not ours");
    Test.assertEqualMessage(tracker.repsSeen, 0, "and nothing was counted");
    return true;
}

(:test)
function testAnotherChipDoesNotDisturbOurRepNumbering(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    tracker.onFrame(TestSupport.repFrame(MINE, 0), []);
    tracker.onFrame(TestSupport.repFrame(THEIRS, 7), []);
    tracker.onFrame(TestSupport.repFrame(THEIRS, 8), []);
    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 1), []);

    // Their lap numbers must not look like our missed reps.
    Test.assertMessage(rep != null, "our second rep");
    Test.assertEqualMessage(tracker.missedReps, 0, "we missed nothing");
    Test.assertEqualMessage(tracker.repsSeen, 2, "two reps, both ours");
    return true;
}

(:test)
function testAnUnboundWatchRecordsNothing(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker("", BroadcastFrame.MASK_WIDE);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), [6657, 9729]);

    // Guessing - taking the strongest signal, or the first chip heard - is
    // right on an empty track and wrong beside a training partner, and the
    // athlete cannot tell which happened afterwards. Recording nothing is
    // visible; recording somebody else's rep is not.
    Test.assertMessage(rep == null, "nothing recorded");
    Test.assertMessage(!tracker.isBound(), "and it knows why");
    return true;
}

// ---------------------------------------------------------------------------
// Repeats: the normal case, not an edge case
// ---------------------------------------------------------------------------

(:test)
function testTheSameRepAdvertisedManyTimesIsOneRep(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    var accepted = 0;

    // A chip repeats its frame throughout its advertising window, so a watch
    // that scans continuously sees a rep tens of times. This is what the
    // window looks like from the watch's side.
    for (var i = 0; i < 40; i++) {
        if (tracker.onFrame(TestSupport.repFrame(MINE, 3), [6657, 9729]) != null) {
            accepted++;
        }
    }

    Test.assertEqualMessage(accepted, 1, "forty frames, one rep");
    Test.assertEqualMessage(tracker.repsSeen, 1, "counted once");
    return true;
}

(:test)
function testConsecutiveRepsAreBothKept(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    var first = tracker.onFrame(TestSupport.repFrame(MINE, 0), []);
    var second = tracker.onFrame(TestSupport.repFrame(MINE, 1), []);

    // Dedup that was too eager would silently drop every second rep, and the
    // athlete would only find out at the end.
    Test.assertMessage(first != null && second != null, "two separate reps");
    Test.assertEqualMessage(tracker.repsSeen, 2, "both counted");
    return true;
}

(:test)
function testARepeatArrivingAfterTheNextRepIsStillARepeat(
        logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 0), []);
    tracker.onFrame(TestSupport.repFrame(MINE, 1), []);

    var late = tracker.onFrame(TestSupport.repFrame(MINE, 0), []);

    // Advertising windows overlap in the air and scan results arrive batched,
    // so an older frame can turn up after a newer one. Accepting it would
    // duplicate a rep and, worse, look like the athlete ran it twice.
    Test.assertMessage(late == null, "already had that one");
    Test.assertEqualMessage(tracker.repsSeen, 2, "still two");
    Test.assertEqualMessage(tracker.missedReps, 0, "and not a gap");
    return true;
}

// ---------------------------------------------------------------------------
// Missed windows
// ---------------------------------------------------------------------------

(:test)
function testAGapInTheLapCounterIsReportedAsAMissedRep(
        logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 0), []);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 2), []);

    // The window is bounded and there is no reconnect, so a rep the watch did
    // not hear is gone for good. An athlete who is told can run it again; one
    // who is not finds a hole in the data that evening.
    Test.assertMessage(rep != null, "rep 2 still counts");
    Test.assertEqualMessage(tracker.missedReps, 1, "and one was missed");
    return true;
}

(:test)
function testSeveralMissedRepsAreAllCounted(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 4), []);

    tracker.onFrame(TestSupport.repFrame(MINE, 8), []);

    Test.assertEqualMessage(tracker.missedReps, 3, "5, 6 and 7");
    return true;
}

(:test)
function testTheFirstRepHeardIsNeverAGap(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    // The watch usually starts recording partway through a chip's life - it
    // has been counting since it was last charged. Rep 37 being the first one
    // heard does not mean 37 were missed.
    tracker.onFrame(TestSupport.repFrame(MINE, 37), []);

    Test.assertEqualMessage(tracker.missedReps, 0, "nothing was missed yet");
    Test.assertEqualMessage(tracker.repsSeen, 1, "one rep");
    return true;
}

(:test)
function testTheLapCounterWrappingIsNotTwoHundredMissedReps(
        logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 255), []);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), []);

    // The counter is one byte. Treating the wrap as arithmetic would report
    // 255 missed reps at the exact moment everything was working.
    Test.assertMessage(rep != null, "the next rep");
    Test.assertEqualMessage(tracker.missedReps, 0, "no gap");
    return true;
}

(:test)
function testAChipThatRestartsIsNotHundredsOfMissedReps(
        logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 40), []);

    // A chip charged or reset mid-session starts counting again from zero.
    // Read as a gap that is 216 missed reps; read as what it is, it is a
    // restart and nothing was missed.
    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), []);

    Test.assertMessage(rep != null, "still a rep");
    Test.assertEqualMessage(tracker.missedReps, 0, "a restart, not a hole");
    return true;
}

// ---------------------------------------------------------------------------
// What a rep carries
// ---------------------------------------------------------------------------

(:test)
function testARepCarriesEveryLegAndTheTotal(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), [6657, 9729]);

    TestSupport.assertArrayEquals(rep.segments, [3072, 3072, 4096], "legs in ticks");
    TestSupport.assertArrayEquals(rep.cumulative, [3072, 6144, 10240], "cumulative");
    Test.assertEqualMessage(rep.totalTicks, 10240, "the whole rep");
    return true;
}

(:test)
function testARepWithNoIntermediatesIsStillARep(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), []);

    // A start and a finish is a perfectly good course, and it is what the app
    // still gets if the scan response turns out to be unreadable (#60).
    Test.assertMessage(rep != null, "a rep");
    Test.assertEqualMessage(rep.segments.size(), 1, "one leg");
    Test.assertEqualMessage(rep.totalTicks, 10240, "and the total is intact");
    return true;
}

(:test)
function testTheLegsOfAnAcceptedRepAddUpToIt(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), [6657, 9729]);
    var total = 0;
    for (var i = 0; i < rep.segments.size(); i++) { total += rep.segments[i]; }

    Test.assertEqualMessage(total, rep.totalTicks, "legs sum to the rep");
    return true;
}

// ---------------------------------------------------------------------------
// Rubbish in
// ---------------------------------------------------------------------------

(:test)
function testANullFrameIsIgnoredRatherThanThrowing(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    // decodeAdvertisement returns null for every frame that is not ours, and
    // at a track that is most of them. This is the common path, not an error.
    Test.assertMessage(tracker.onFrame(null, []) == null, "no frame, no rep");
    Test.assertEqualMessage(tracker.repsSeen, 0, "nothing counted");
    return true;
}

(:test)
function testMissingLapsAreTreatedAsNoIntermediates(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);

    // If the watch cannot read scan responses at all (#60), every rep arrives
    // with no lap array. The rep total still works, and that is the product
    // that survives a "no" on that issue.
    var rep = tracker.onFrame(TestSupport.repFrame(MINE, 0), null);

    Test.assertMessage(rep != null, "still a rep");
    Test.assertEqualMessage(rep.totalTicks, 10240, "with its total");
    return true;
}

// ---------------------------------------------------------------------------
// Rebinding and reset
// ---------------------------------------------------------------------------

(:test)
function testRebindingToAnotherChipStartsAgain(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 5), []);

    // The athlete fixed a typo in Garmin Connect mid-warm-up (#64). The old
    // chip's lap numbers must not be carried over as missed reps on the new
    // one, and its reps are not ours.
    tracker.bindTo(THEIRS);
    var rep = tracker.onFrame(TestSupport.repFrame(THEIRS, 90), []);

    Test.assertMessage(rep != null, "the new chip's rep");
    Test.assertEqualMessage(tracker.missedReps, 0, "no inherited gap");
    Test.assertMessage(tracker.onFrame(TestSupport.repFrame(MINE, 6), []) == null,
                       "and the old chip is now a stranger");
    return true;
}

(:test)
function testResetForgetsTheSession(logger as Test.Logger) as Lang.Boolean {
    var tracker = new RepTracker(MINE, BroadcastFrame.MASK_WIDE);
    tracker.onFrame(TestSupport.repFrame(MINE, 0), []);
    tracker.onFrame(TestSupport.repFrame(MINE, 4), []);

    tracker.reset();

    Test.assertEqualMessage(tracker.repsSeen, 0, "no reps");
    Test.assertEqualMessage(tracker.missedReps, 0, "no gaps");
    // And the first frame after a reset is a first frame, not a gap.
    tracker.onFrame(TestSupport.repFrame(MINE, 9), []);
    Test.assertEqualMessage(tracker.missedReps, 0, "still none");
    return true;
}
