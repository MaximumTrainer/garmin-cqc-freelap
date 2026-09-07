using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.Test;

// Driven by the acceptance criteria of issue #21, "Rep summary overlay after
// each FINISH".
//
// The requirement that shapes everything here is the third one: this must not
// interfere with recording. A summary screen that costs a rep is worse than no
// summary screen, and it would be an easy thing to get wrong - the obvious
// implementation makes the UI a listener and lets it run before the recorder.

(:test)
function testTheOverlayShowsEverySplitOfTheRep(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");
    engine.onRepBurst(TestSupport.workedRep(), 30000);

    var view = new RepSummaryView(engine.lastRep, 1000);

    Test.assertEqualMessage(view.splitCount(), 4, "four crossings");
    return true;
}

(:test)
function testARowCarriesTheTransmitterTheSplitAndTheVelocity(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");
    engine.onRepBurst(TestSupport.workedRep(), 30000);
    var view = new RepSummaryView(engine.lastRep, 1000);

    var row = view.rowText(3);

    Test.assertMessage(row.find("3") == 0, "the transmitter index first: " + row);
    Test.assertMessage(row.find("4.45") != null, "then the split time: " + row);
    Test.assertMessage(row.find("8.99") != null, "then the velocity: " + row);
    return true;
}

(:test)
function testAnUnmatchedCrossingIsMarkedRatherThanNumbered(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;F:100");
    engine.onRepBurst(TestSupport.burst([0l, 4000000l, 8000000l, 12000000l],
        [TxCode.START, TxCode.LAP, TxCode.FINISH, TxCode.FINISH]), 30000);
    var view = new RepSummaryView(engine.lastRep, 1000);

    Test.assertMessage(view.rowText(3).find("?") == 0,
        "a crossing the course could not place: " + view.rowText(3));
    return true;
}

(:test)
function testTheTotalLineCarriesTheRepTimeAndDistance(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");
    engine.onRepBurst(TestSupport.workedRep(), 30000);
    var view = new RepSummaryView(engine.lastRep, 1000);

    var total = view.totalText();
    Test.assertMessage(total.find("11.93") != null, "the rep time: " + total);
    Test.assertMessage(total.find("100m") != null, "and the distance: " + total);
    return true;
}

// ---------------------------------------------------------------------------
// Dismissing itself
// ---------------------------------------------------------------------------

(:test)
function testTheOverlayTimesItselfOutAfterFiveSeconds(logger as Test.Logger) as Lang.Boolean {
    var view = new RepSummaryView(TestSupport.aRep(), 10000);

    Test.assertEqualMessage(RepSummaryView.SHOW_MS, 5000, "issue #21 asks for five seconds");
    Test.assertMessage(!view.expired(11000), "still up after one second");
    Test.assertMessage(!view.expired(14999), "and just before five");
    Test.assertMessage(view.expired(15000), "gone at five");
    return true;
}

(:test)
function testASecondRepResetsTheTimeout(logger as Test.Logger) as Lang.Boolean {
    var view = new RepSummaryView(TestSupport.aRep(), 10000);

    // A second rep four seconds later must get its own five seconds, not the
    // one second left over from the first.
    view.show(TestSupport.aRep(), 14000);

    Test.assertMessage(!view.expired(18000), "four seconds into the second rep");
    Test.assertMessage(view.expired(19000), "and gone five seconds after it");
    return true;
}

// ---------------------------------------------------------------------------
// Scrolling
// ---------------------------------------------------------------------------

(:test)
function testUpToSixSplitsFitOnA240PixelDisplay(logger as Test.Logger) as Lang.Boolean {
    var dc = TestSupport.offscreenDc();
    var view = new RepSummaryView(TestSupport.aRepOf(6), 1000);

    var fits = view.rowsThatFit(dc);
    logger.debug(System.getDeviceSettings().screenHeight.format("%d") + "px fits " +
                 fits.format("%d") + " rows");

    // Issue #21 names six on 240px. The number is measured from the font, so
    // it is at least six on anything that size or bigger.
    Test.assertMessage(fits >= 6,
        "only " + fits.format("%d") + " rows fit on a " +
        System.getDeviceSettings().screenHeight.format("%d") + "px display");
    return true;
}

(:test)
function testARepThatFitsIsNotScrollable(logger as Test.Logger) as Lang.Boolean {
    var dc = TestSupport.offscreenDc();
    var view = new RepSummaryView(TestSupport.aRepOf(4), 1000);
    var fits = view.rowsThatFit(dc);

    Test.assertMessage(!view.scroll(1, fits), "nothing to scroll to");
    Test.assertEqualMessage(view.offset, 0, "so the window does not move");

    var range = view.visibleRange(dc);
    Test.assertEqualMessage(range[0], 0, "showing from the first split");
    Test.assertEqualMessage(range[1], 4, "to the last");
    return true;
}

(:test)
function testARepWithMoreSplitsThanFitScrolls(logger as Test.Logger) as Lang.Boolean {
    var dc = TestSupport.offscreenDc();
    var capacity = new RepSummaryView(TestSupport.aRepOf(4), 1000).rowsThatFit(dc);
    var view = new RepSummaryView(TestSupport.aRepOf(capacity + 3), 1000);
    // Ask the view, not the earlier one: with more splits than fit it gives a
    // row back to the scroll marker, so its window is one shorter.
    var fits = view.rowsThatFit(dc);

    Test.assertMessage(view.scroll(1, fits), "there is more to see");
    Test.assertEqualMessage(view.offset, 1, "moved one row");

    var range = view.visibleRange(dc);
    Test.assertEqualMessage(range[0], 1, "the window moved with it");
    Test.assertEqualMessage(range[1] - range[0], fits, "and is still a full window");
    return true;
}

(:test)
function testScrollingStopsAtBothEnds(logger as Test.Logger) as Lang.Boolean {
    var dc = TestSupport.offscreenDc();
    var capacity = new RepSummaryView(TestSupport.aRepOf(4), 1000).rowsThatFit(dc);
    var view = new RepSummaryView(TestSupport.aRepOf(capacity + 2), 1000);
    var fits = view.rowsThatFit(dc);

    Test.assertMessage(!view.scroll(-1, fits), "already at the top");
    for (var i = 0; i < 20; i++) { view.scroll(1, fits); }
    Test.assertEqualMessage(view.offset, view.splitCount() - fits, "and stops at the bottom");
    return true;
}

// ---------------------------------------------------------------------------
// Not interfering with recording
// ---------------------------------------------------------------------------

(:test)
function testTheRecorderIsNotifiedBeforeTheUiIs(logger as Test.Logger) as Lang.Boolean {
    var order = new CallOrder();
    var course = new Course("S:0;L:30;L:60;F:100", "test");
    var engine = new SplitEngine(course, new OrderRecordingListener(order, "recorder"), 150);
    engine.observer = new OrderRecordingListener(order, "ui");
    engine.onSessionStartAt(10000);

    engine.onRepBurst(TestSupport.workedRep(), 30000);

    // The FIT file matters more than the screen. Nothing the overlay does can
    // come between a rep finishing and its splits being queued for the file.
    Test.assertEqualMessage(order.size(), 2, "both were told");
    Test.assertEqualMessage(order.at(0), "recorder", "the recorder first");
    Test.assertEqualMessage(order.at(1), "ui", "then the screen");
    return true;
}

(:test)
function testASecondRepDuringTheOverlayIsStillRecorded(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    var view = null;

    // Rep 1 finishes and the overlay goes up.
    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    view = new RepSummaryView(rig.engine.lastRep, 10000);

    // Rep 2 arrives while it is still showing. The engine and recorder have no
    // idea a view exists, which is the whole point.
    rig.engine.onRepBurst(TestSupport.workedRep(), 30000);
    view.show(rig.engine.lastRep, 12000);
    TestSupport.tickUntilIdle(rig.recorder, 40);

    Test.assertEqualMessage(rig.engine.repsDone, 2, "both reps counted");
    Test.assertEqualMessage(session.countOf("addLap"), 2, "and both got a lap");
    Test.assertEqualMessage(session.field("fl_split_us").writes() >= 8, true,
        "with every split written");
    Test.assertEqualMessage(view.rep.rep, 2, "the overlay moved on to the second rep");
    return true;
}

(:test)
function testTheOverlayNeverHoldsOnToAnEngineOrARecorder(logger as Test.Logger) as Lang.Boolean {
    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;F:100");
    engine.onRepBurst(TestSupport.burst([0l, 4000000l], [TxCode.START, TxCode.FINISH]), 30000);

    var view = new RepSummaryView(engine.lastRep, 1000);

    // It holds a finished RepSummary, which is immutable as far as it is
    // concerned. Nothing it can do reaches back into recording.
    Test.assertMessage(view.rep != null, "it has the rep");
    Test.assertEqualMessage(view.rep.rep, 1, "by value, not by reaching for the engine");
    return true;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

(:test)
function testTheOverlayFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var view = new RepSummaryView(TestSupport.aRepOf(4), 1000);
    view.trace = [];
    view.onUpdate(TestSupport.offscreenDc());

    TestSupport.assertLayoutIsSane(view.trace, "rep summary");
    return true;
}

(:test)
function testAScrollingOverlayStillFitsThisDisplay(logger as Test.Logger) as Lang.Boolean {
    var view = new RepSummaryView(TestSupport.aRepOf(12), 1000);
    view.trace = [];
    view.onUpdate(TestSupport.offscreenDc());

    TestSupport.assertLayoutIsSane(view.trace, "rep summary, scrolling");
    return true;
}
