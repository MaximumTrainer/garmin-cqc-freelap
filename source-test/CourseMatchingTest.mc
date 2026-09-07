using Toybox.Lang;
using Toybox.Test;

// Issue #13, the two acceptance criteria that are about what a *rep* looks
// like once the course has matched its crossings:
//
//   "A rep with an extra crossing (more than the course has) yields
//    txIndex = -1 for the extra and RepStatus.UNMATCHED"
//   "A rep that ends before FINISH (manual lap or chip timeout) yields
//    RepStatus.PARTIAL with distance = last matched transmitter's distance"
//
// Those live in SplitEngine, so they are driven through it. The engine's own
// arithmetic is issue #14; nothing here asserts on times.

(:test)
function testRepWithAnExtraCrossingIsFlaggedUnmatched(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;F:100");

    // Four crossings on a three-transmitter course.
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l, 12000000l],
                            [TxCode.START, TxCode.LAP, TxCode.FINISH, TxCode.FINISH]), 1000);

    var rep = engine.lastRep;
    Test.assertEqualMessage(rep.splits, 4, "all four crossings are kept");
    Test.assertEqualMessage(rep.events[3].txIndex, -1, "the extra crossing has no course index");
    Test.assertEqualMessage(rep.status, RepStatus.UNMATCHED, "and the rep is flagged UNMATCHED");
    return true;
}

(:test)
function testRepEndedByTheManualLapButtonIsPartial(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;L:60;F:100");

    // START and one LAP arrive, then the athlete presses the lap button.
    engine.onCrossing(new Crossing(0l, TxCode.START, "TEST"), 1000);
    engine.onCrossing(new Crossing(4000000l, TxCode.LAP, "TEST"), 5000);
    engine.forceRepEnd();

    var rep = engine.lastRep;
    Test.assertEqualMessage(rep.status, RepStatus.PARTIAL, "a rep that never reached FINISH is PARTIAL");
    Test.assertEqualMessage(rep.distM, 30.0, "distance is the last matched transmitter's distance");
    Test.assertEqualMessage(rep.splits, 2, "two crossings recorded");
    return true;
}

(:test)
function testPartialRepDistanceIgnoresTrailingUnmatchedCrossings(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;F:100");

    // A fourth crossing the course cannot place must not drag the rep
    // distance to something invented.
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l, 12000000l],
                            [TxCode.START, TxCode.LAP, TxCode.FINISH, TxCode.FINISH]), 1000);

    Test.assertEqualMessage(engine.lastRep.distM, 100.0,
        "distance is the last *matched* transmitter's distance, not the unmatched one's");
    return true;
}

(:test)
function testCompleteRepIsOk(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;F:100");

    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l],
                            [TxCode.START, TxCode.LAP, TxCode.FINISH]), 1000);

    Test.assertEqualMessage(engine.lastRep.status, RepStatus.OK, "every transmitter matched, ends on FINISH");
    Test.assertEqualMessage(engine.lastRep.distM, 100.0, "full course distance");
    return true;
}

(:test)
function testRepOnAnOpenEndedCourseIsNotPartial(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineFor("S:0;L:30;L:60");

    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l],
                            [TxCode.START, TxCode.LAP, TxCode.LAP]), 1000);

    // There is no FINISH to miss, so crossing every transmitter is a full rep.
    Test.assertEqualMessage(engine.lastRep.status, RepStatus.OK,
        "an open-ended course cannot produce a PARTIAL by missing a FINISH it does not have");
    return true;
}
