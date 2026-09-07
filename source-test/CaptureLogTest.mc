using Toybox.Application;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #12, "Capture mode: on-watch raw
// packet logger".
//
// This is the tool for working out what the chip actually sends, on a track,
// without a laptop. If it silently drops packets or blocks the BLE callback
// writing to flash, it is worse than not having it - the packets it loses are
// exactly the ones being investigated.

(:test)
function testTheLogHoldsSixtyPackets(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();

    for (var i = 0; i < 60; i++) {
        log.add(1000 + i * 30, TestSupport.hexPacket(20));
    }

    Test.assertEqualMessage(log.size(), 60, "issue #12 asks for at least 60");
    Test.assertEqualMessage(log.dropped, 0, "and none of them dropped");
    return true;
}

(:test)
function testSixtyFullPacketsStayInsideTheStorageBudget(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();
    for (var i = 0; i < 60; i++) {
        log.add(1000 + i * 30, TestSupport.hexPacket(20));   // a full BLE notification
    }

    // 60 x 20 bytes = 2400 hex characters. The cap leaves room for the arrival
    // stamps and array overhead inside an API 3.1 device's ~8 KB allowance.
    Test.assertEqualMessage(log.totalChars(), 2400, "60 full notifications");
    Test.assertMessage(log.totalChars() <= CaptureLog.MAX_CHARS, "within the character budget");
    return true;
}

(:test)
function testTheOldestPacketIsDroppedOnceTheWindowIsFull(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();
    for (var i = 0; i < 65; i++) {
        log.add(1000 + i, "AA");
    }

    Test.assertEqualMessage(log.size(), CaptureLog.MAX_PACKETS, "the window is bounded");
    Test.assertEqualMessage(log.dropped, 5, "and says how many it lost");
    Test.assertEqualMessage(log.seen, 65, "while remembering how many it saw");
    Test.assertEqualMessage(log.rows[0][0], 1005, "the surviving packets are the newest");
    return true;
}

(:test)
function testAChipThatFragmentsHardCannotBlowTheCharacterBudget(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();

    // Sixty is a packet count, not a size. A chip sending long notifications
    // would sail past the storage limit while still under the count cap, so
    // the character budget has to bite first.
    for (var i = 0; i < 60; i++) {
        log.add(1000 + i, TestSupport.hexPacket(60));
    }

    Test.assertMessage(log.totalChars() <= CaptureLog.MAX_CHARS,
        "trimmed by size: " + log.totalChars().format("%d") + " chars");
    Test.assertMessage(log.dropped > 0, "which means older packets were dropped");
    return true;
}

// ---------------------------------------------------------------------------
// Flash
// ---------------------------------------------------------------------------

(:test)
function testAddingPacketsNeverWritesToStorage(logger as Test.Logger) as Lang.Boolean {
    var storage = new FakeStorage();
    var log = new CaptureLog();

    for (var i = 0; i < 60; i++) { log.add(1000 + i, "AA55"); }

    // Not "verified by code review" - asserted. A flash write inside the BLE
    // callback blocks long enough to lose the notifications that follow, and
    // a fragmented burst arrives milliseconds apart.
    Test.assertEqualMessage(storage.writes, 0, "no write happened while packets arrived");
    return true;
}

(:test)
function testFlushWritesExactlyOnce(logger as Test.Logger) as Lang.Boolean {
    var storage = new FakeStorage();
    var log = new CaptureLog();
    for (var i = 0; i < 10; i++) { log.add(1000 + i, "AA55"); }

    log.flush(storage, "capture");

    Test.assertEqualMessage(storage.writes, 1, "one write for the whole log");
    Test.assertEqualMessage((storage.get("capture") as Lang.Array).size(), 10, "carrying every packet");
    return true;
}

(:test)
function testFlushingAnEmptyLogWritesNothing(logger as Test.Logger) as Lang.Boolean {
    var storage = new FakeStorage();

    Test.assertMessage(!new CaptureLog().flush(storage, "capture"), "nothing to write");
    Test.assertEqualMessage(storage.writes, 0, "so nothing was written");
    return true;
}

// ---------------------------------------------------------------------------
// The dump format
// ---------------------------------------------------------------------------

(:test)
function testTheDumpIsTabSeparatedInTheShapeDecodeCaptureReads(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();
    log.add(1000, "A50412340000000001");
    log.add(1030, "180F0000021848");

    var tsv = log.toTsv();

    // tools/decode_capture.py splits on tabs and reads [time, handle, hex].
    Test.assertEqualMessage(tsv,
        "1.000\t0x0000\tA50412340000000001\n" +
        "1.030\t0x0000\t180F0000021848\n",
        "arrival seconds, handle, hex");
    return true;
}

(:test)
function testTheDumpPadsMillisecondsSoTheColumnsLineUp(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();
    log.add(4007, "AA");

    Test.assertMessage(log.toTsv().find("4.007\t") == 0,
        "7 ms into second 4, not 4.7: " + log.toTsv());
    return true;
}

(:test)
function testAnEmptyLogDumpsNothing(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(new CaptureLog().toTsv(), "", "no packets, no lines");
    return true;
}

(:test)
function testClearEmptiesTheLogAndItsCounters(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();
    for (var i = 0; i < 70; i++) { log.add(1000 + i, "AA"); }

    log.clear();

    Test.assertEqualMessage(log.size(), 0, "rows");
    Test.assertEqualMessage(log.seen, 0, "seen");
    Test.assertEqualMessage(log.dropped, 0, "dropped");
    return true;
}

// ---------------------------------------------------------------------------
// Reaching it from the watch
// ---------------------------------------------------------------------------

(:test)
function testBackOffersTheCaptureMenuWhenCaptureModeIsOn(logger as Test.Logger) as Lang.Boolean {
    var idle = new FitRecorder(true, false);

    Test.assertEqualMessage(MainDelegate.backAction(idle, true), :captureMenu,
        "with capture mode on there is something to do besides leaving");
    Test.assertEqualMessage(MainDelegate.backAction(idle, false), :exit,
        "and without it, BACK still just leaves");
    return true;
}

(:test)
function testCaptureModeDoesNotChangeTheControlsDuringASession(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;F:100");

    // Mid-rep is the worst possible moment to repurpose the lap button.
    Test.assertEqualMessage(MainDelegate.backAction(rig.recorder, true), :manualLap, "while recording");
    rig.recorder.stop();
    Test.assertEqualMessage(MainDelegate.backAction(rig.recorder, true), :saveMenu, "while paused");
    return true;
}

(:test)
function testDumpingTheCaptureSaysHowManyPacketsWent(logger as Test.Logger) as Lang.Boolean {
    var app = Application.getApp() as FreelapApp;
    if (app.ble == null) { return true; }

    var previous = app.ble.capture;
    app.ble.capture = new CaptureLog();
    app.ble.capture.add(1000, "A5041234");
    app.ble.capture.add(1030, "180F0000");
    app.clearNotice();

    new MainDelegate().dumpCapture();

    Test.assertEqualMessage(app.activeNotice(), "2 packets dumped",
        "the watch confirms it, since the console is not visible from a track");

    app.ble.capture = previous;
    app.clearNotice();
    return true;
}
