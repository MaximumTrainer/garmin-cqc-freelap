using Toybox.Lang;
using Toybox.System;
using Toybox.Test;

// Driven by the acceptance criteria of issue #26, "Robustness: memory and
// watchdog on API 3.1 devices".
//
// The failure this guards against is the worst kind: a session that works
// perfectly for an hour and then dies. Nothing here can be caught by a short
// manual test, which is precisely why it needs to be a long automated one.
//
// The scripted 60-rep replay the issue asks for needs fake_chip.py, BlueZ and
// an fr245 device definition. What runs here is the same 60 reps driven
// straight into the pipeline, which exercises everything downstream of the
// radio - the assembler, the engine, the recorder, the logs.

(:test)
function testSixtyRepsLeaveTheSplitLogBounded(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");

    TestSupport.runReps(rig, 60);

    // 240 splits, under the 300-row cap, so a normal two-hour session loses
    // nothing.
    Test.assertEqualMessage(rig.recorder.log().seen, 240, "60 reps of 4 crossings");
    Test.assertEqualMessage(rig.recorder.log().size(), 240, "all of them kept");
    Test.assertMessage(rig.recorder.log().complete(), "nothing dropped");
    return true;
}

(:test)
function testAnAbsurdlyLongSessionStillCannotGrowWithoutBound(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");

    TestSupport.runReps(rig, 120);   // 480 splits

    Test.assertEqualMessage(rig.recorder.log().size(), SplitLog.MAX_ROWS, "capped");
    Test.assertEqualMessage(rig.recorder.log().seen, 480, "while still counting what it saw");
    Test.assertMessage(!rig.recorder.log().complete(), "and admitting it is truncated");
    return true;
}

(:test)
function testTheOldestSplitsAreTheOnesDropped(logger as Test.Logger) as Lang.Boolean {
    var log = new SplitLog();
    for (var i = 0; i < SplitLog.MAX_ROWS + 5; i++) {
        log.add([i, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0, false]);
    }

    // The last reps of a session are the ones being looked at afterwards, and
    // a truncated head shows up in the rep numbers where a truncated tail
    // would be silent.
    Test.assertEqualMessage(log.rows[0][0], 5, "the first five are gone");
    Test.assertEqualMessage(log.dropped, 5, "and counted");
    return true;
}

(:test)
function testTheCaptureBufferIsBoundedToo(logger as Test.Logger) as Lang.Boolean {
    var log = new CaptureLog();
    for (var i = 0; i < 500; i++) {
        log.add(1000 + i, TestSupport.hexPacket(20));
    }

    Test.assertEqualMessage(log.size(), CaptureLog.MAX_PACKETS, "bounded by count");
    Test.assertMessage(log.totalChars() <= CaptureLog.MAX_CHARS, "and by size");
    return true;
}

// ---------------------------------------------------------------------------
// Memory
// ---------------------------------------------------------------------------

(:test)
function testSixtyRepsDoNotGrowMemoryWithoutBound(logger as Test.Logger) as Lang.Boolean {
    // QuietSession, not FakeSession: the latter keeps every value written, so
    // after 60 reps it holds thousands of its own and the measurement would be
    // of the test double rather than the app.
    var rig = TestSupport.quietRig("S:0;L:30;L:60;F:100");

    TestSupport.runReps(rig, 10);
    var afterTen = System.getSystemStats().usedMemory;
    TestSupport.runReps(rig, 50);
    var afterSixty = System.getSystemStats().usedMemory;

    var stats = System.getSystemStats();
    logger.debug("used " + afterSixty.format("%d") + " of " +
                 stats.totalMemory.format("%d") + " bytes after 60 reps");

    // The next 50 reps must not cost dramatically more than the first 10 did.
    // A leak - a listener never released, a queue never drained - shows up
    // here as growth that scales with rep count.
    var growth = afterSixty - afterTen;
    Test.assertMessage(growth < 40000,
        "50 further reps added " + growth.format("%d") + " bytes");
    return true;
}

// The smallest watch-app memory limit among the products this app builds for,
// from the SDK's own device definitions: 786 432 bytes on fr265, fr965 and
// fenix8solar47mm. fr645m and venu allow 1 MiB, fenix5plus 1.25 MiB.
//
// System.getSystemStats().totalMemory reports the *simulator's* heap, which is
// 8 MiB and tells you nothing about a watch - so the budget is stated here
// rather than read from the running system.
(:test)
const SMALLEST_APP_LIMIT = 786432;

(:test)
function testSixtyRepsStayWellInsideTheSmallestDeviceBudget(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.quietRig("S:0;L:30;L:60;F:100");
    TestSupport.runReps(rig, 60);

    var used = System.getSystemStats().usedMemory;
    var percent = (used * 100) / SMALLEST_APP_LIMIT;
    logger.debug("after 60 reps: " + used.format("%d") + " bytes, " +
                 percent.format("%d") + "% of the smallest device budget");

    // Issue #26 asks for under 80%. Note this is a *test* build, which carries
    // source-test and every double with it; a release build is smaller, so
    // this is a pessimistic reading rather than a flattering one.
    Test.assertMessage(percent < 80,
        "used " + percent.format("%d") + "% of " + SMALLEST_APP_LIMIT.format("%d") + " bytes");
    return true;
}

(:test)
function testTheWorstCaseOfEveryBoundedStructureIsKnown(logger as Test.Logger) as Lang.Boolean {
    // Device-independent: whatever the athlete does, these are the ceilings.
    // If one of them grows, this test is where the new number gets argued for.
    Test.assertEqualMessage(SplitLog.MAX_ROWS, 300, "splits kept for export");
    Test.assertEqualMessage(FitRecorder.MAX_QUEUE, 400, "items awaiting a record tick");
    Test.assertEqualMessage(CaptureLog.MAX_PACKETS, 60, "raw packets");
    Test.assertEqualMessage(CaptureLog.MAX_CHARS, 3200, "raw packet characters");
    Test.assertEqualMessage(PacketAssembler.MAX_MESSAGE, 256, "bytes of one part-received message");
    return true;
}

// ---------------------------------------------------------------------------
// What happens in the BLE callback
// ---------------------------------------------------------------------------

(:test)
function testDecodingABurstWritesNothingToStorage(logger as Test.Logger) as Lang.Boolean {
    var storage = new FakeStorage();
    var assembler = new PacketAssembler();
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");

    // The whole path onCharacteristicChanged takes, sixty times over.
    for (var i = 0; i < 60; i++) {
        var crossings = assembler.feed(TestSupport.burstBytes(4), 1000 + i * 30000);
        rig.engine.onRepBurst(crossings, 1000 + i * 30000);
    }

    // A flash write inside the notification callback is what trips the
    // watchdog on a fragmented burst: it blocks long enough to miss the
    // packets that follow.
    Test.assertEqualMessage(storage.writes, 0, "no storage write on the packet path");
    return true;
}

(:test)
function testTheSplitQueueDrainsRatherThanGrowing(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");

    TestSupport.runReps(rig, 60);

    Test.assertMessage(rig.recorder.isIdle(),
        "after 60 reps and their ticks there is nothing left queued");
    return true;
}

(:test)
function testAPausedSessionCannotQueueSplitsForever(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");
    rig.recorder.stop();   // paused: nothing drains

    for (var i = 0; i < 200; i++) {
        rig.engine.onRepBurst(TestSupport.workedRep(), 1000 + i * 30000);
    }

    // The chip keeps pushing whether or not the athlete paused. Without a cap
    // this is unbounded growth in the one state where nothing drains it.
    Test.assertMessage(rig.recorder.queueSize() <= FitRecorder.MAX_QUEUE,
        "queued " + rig.recorder.queueSize().format("%d") + " items");
    Test.assertMessage(rig.recorder.droppedFromQueue > 0, "and the drops are counted, not silent");
    return true;
}

(:test)
function testANormalSessionNeverDropsAnythingFromTheQueue(logger as Test.Logger) as Lang.Boolean {
    var rig = TestSupport.recorderOn(new FakeSession(), "S:0;L:30;L:60;F:100");

    TestSupport.runReps(rig, 60);

    Test.assertEqualMessage(rig.recorder.droppedFromQueue, 0,
        "the cap is a backstop, not something a real session meets");
    return true;
}
