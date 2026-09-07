using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #10, "Reconnect after link loss
// without losing crossings already received".
//
// The hardware half of those criteria - walk the chip out of range and back -
// cannot be run here. What can be, and is, is everything that decides whether
// that walk works: the backoff schedule, the point at which the app stops
// retrying, the way back from there, and the two ways a drop can corrupt data
// that has nothing to do with radios.

// ---------------------------------------------------------------------------
// Backoff
// ---------------------------------------------------------------------------

(:test)
function testRetryBackoffIsExponentialFromOneSecond(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(FreelapBleDelegate.retryDelayMs(0), 1000, "first retry");
    Test.assertEqualMessage(FreelapBleDelegate.retryDelayMs(1), 2000, "second");
    Test.assertEqualMessage(FreelapBleDelegate.retryDelayMs(2), 4000, "third");
    Test.assertEqualMessage(FreelapBleDelegate.retryDelayMs(3), 8000, "fourth");
    Test.assertEqualMessage(FreelapBleDelegate.retryDelayMs(4), 16000, "fifth");
    return true;
}

(:test)
function testTheFullBackoffSpansAboutHalfAMinute(logger as Test.Logger) as Lang.Boolean {
    var total = 0;
    for (var i = 0; i < FreelapBleDelegate.MAX_RETRIES; i++) {
        total += FreelapBleDelegate.retryDelayMs(i);
    }

    // Long enough to ride out a lap of the track; short enough that a chip
    // which is simply switched off is not hammered for the whole session.
    Test.assertEqualMessage(total, 31000, "1+2+4+8+16 s");
    return true;
}

// ---------------------------------------------------------------------------
// Giving up, and the way back
// ---------------------------------------------------------------------------

(:test)
function testAFreshDelegateHasNotGivenUp(logger as Test.Logger) as Lang.Boolean {
    var ble = new FreelapBleDelegate();

    Test.assertMessage(!ble.gaveUp, "nothing has failed yet");
    Test.assertEqualMessage(ble.retries, 0, "no attempts spent");

    ble.stop();
    return true;
}

(:test)
function testTheAppStopsRetryingAfterTheLimitAndSaysSo(logger as Test.Logger) as Lang.Boolean {
    var ble = new FreelapBleDelegate();
    ble.retries = FreelapBleDelegate.MAX_RETRIES;
    ble.state = BleState.SCANNING;

    ble.scheduleRetry();

    Test.assertMessage(ble.gaveUp, "retrying forever would flatten the battery");
    Test.assertEqualMessage(ble.state, BleState.IDLE, "and the screen says 'No chip'");

    ble.stop();
    return true;
}

(:test)
function testRescanClearsTheGiveUpAndStartsOver(logger as Test.Logger) as Lang.Boolean {
    var ble = new FreelapBleDelegate();
    ble.retries = FreelapBleDelegate.MAX_RETRIES;
    ble.gaveUp = true;

    ble.rescan();

    Test.assertMessage(!ble.gaveUp, "the athlete asked again");
    Test.assertEqualMessage(ble.retries, 0, "with a full budget of attempts");

    ble.stop();
    return true;
}

(:test)
function testRescanIsReachableFromTheIdleMenu(logger as Test.Logger) as Lang.Boolean {
    var idle = new FitRecorder(true, false);

    // With no session and nothing wrong, BACK still just leaves - two presses
    // to exit an app that is doing nothing would be worse than the problem.
    Test.assertEqualMessage(MainDelegate.backAction(idle, false), :exit, "nothing to offer");
    Test.assertEqualMessage(MainDelegate.backAction(idle, true), :idleMenu,
        "but once there is a rescan or a dump to offer, BACK opens a menu");
    return true;
}

// ---------------------------------------------------------------------------
// A drop must not corrupt what comes after it
// ---------------------------------------------------------------------------

(:test)
function testAHalfReceivedMessageIsThrownAwayOnDisconnect(logger as Test.Logger) as Lang.Boolean {
    var assembler = new PacketAssembler();

    // The first fragment of a four-crossing burst: 24 bytes expected, 20 here.
    assembler.feed(TestSupport.burstBytes(4).slice(0, 20), 1000);
    Test.assertMessage(assembler.isAssembling(), "a message is part-received");

    assembler.reset();

    Test.assertMessage(!assembler.isAssembling(), "the fragment is gone");
    Test.assertEqualMessage(assembler.pending(), 0, "and so are its bytes");
    return true;
}

(:test)
function testAFragmentFromBeforeADropCannotCompleteOneAfterIt(logger as Test.Logger) as Lang.Boolean {
    var assembler = new PacketAssembler();
    var first = TestSupport.burstBytes(4);

    assembler.feed(first.slice(0, 20), 1000);   // link drops here
    assembler.reset();

    // A complete, different burst arrives after reconnecting.
    var crossings = assembler.feed(TestSupport.burstBytes(1), 2000);

    Test.assertMessage(crossings != null, "the new message decodes on its own");
    Test.assertEqualMessage(crossings.size(), 1,
        "one crossing - not the wrong number the concatenation would have produced");
    return true;
}

(:test)
function testWithoutTheResetTheConcatenationDecodesToNonsense(logger as Test.Logger) as Lang.Boolean {
    var assembler = new PacketAssembler();

    // This is the failure the reset exists to prevent, demonstrated: feed the
    // tail of one message straight into the head of another and the decoder
    // cannot tell, because the length was fixed by the first fragment.
    assembler.feed(TestSupport.burstBytes(4).slice(0, 20), 1000);
    var crossings = assembler.feed(TestSupport.burstBytes(1), 2000);

    Test.assertMessage(crossings != null, "it completes something");
    Test.assertEqualMessage(crossings.size(), 4,
        "four crossings, three of them built from another message's bytes");
    return true;
}

(:test)
function testAnOverLongLengthIsRejectedRatherThanBuffered(logger as Test.Logger) as Lang.Boolean {
    var assembler = new PacketAssembler();

    // 0xA5 appears inside payloads too. A false sync byte claiming 255
    // crossings would otherwise leave us waiting for bytes that never come.
    var bogus = [0xA5, 0xFF, 0x34, 0x12]b;
    var out = assembler.feed(bogus, 1000);

    Test.assertMessage(out == null, "nothing decoded");
    Test.assertMessage(!assembler.isAssembling(), "and nothing left half-read");
    Test.assertEqualMessage(assembler.discarded, 1, "the desync is counted");
    return true;
}

(:test)
function testANotificationThatIsNotAMessageStartIsIgnored(logger as Test.Logger) as Lang.Boolean {
    var assembler = new PacketAssembler();

    Test.assertMessage(assembler.feed([0x00, 0x01, 0x02, 0x03]b, 1000) == null, "no sync byte");
    Test.assertMessage(assembler.feed([0xA5]b, 1000) == null, "too short to carry a length");
    Test.assertMessage(!assembler.isAssembling(), "neither started a message");
    return true;
}

// ---------------------------------------------------------------------------
// The session survives the drop
// ---------------------------------------------------------------------------

(:test)
function testRepNumberingContinuesAcrossAReconnection(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    // Off, so the record stream is the splits and nothing else; the blanking
    // write is #16's business, not this test's.
    rig.recorder.clearAfterWrite = false;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tickUntilIdle(rig.recorder, 20);

    // The link drops and comes back. The session never stopped recording, and
    // the engine has no idea anything happened - which is the point.
    rig.engine.onRepBurst(TestSupport.workedRep(), 60000);
    TestSupport.tickUntilIdle(rig.recorder, 20);

    Test.assertEqualMessage(rig.engine.repsDone, 2, "two reps");
    TestSupport.assertArrayEquals(session.valuesOf("fl_rep"), [1, 1, 1, 1, 2, 2, 2, 2],
        "the rep after the drop is rep 2, not rep 1 again");
    Test.assertEqualMessage(session.countOf("addLap"), 2, "and it got its own lap");
    return true;
}

(:test)
function testCrossingsDecodedBeforeADropAreStillInTheFile(logger as Test.Logger) as Lang.Boolean {
    var session = new FakeSession();
    var rig = TestSupport.recorderOn(session, "S:0;L:30;L:60;F:100");
    rig.recorder.clearAfterWrite = false;

    rig.engine.onRepBurst(TestSupport.workedRep(), 1000);
    TestSupport.tickUntilIdle(rig.recorder, 20);

    // Whatever the radio does next, these are already written.
    TestSupport.assertArrayEquals(session.valuesOf("fl_split_us"),
        [0, 4120000, 3360000, 4450000], "the rep before the drop is intact");
    return true;
}
