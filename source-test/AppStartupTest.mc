using Toybox.Lang;
using Toybox.Test;

// Issue #1, "Build the skeleton with the Connect IQ SDK and fix compile
// errors". The last acceptance criterion — "app launches in the simulator,
// shows the 'Scanning for chip…' state, and START creates a session without
// exception" — is automated here rather than clicked, so a regression is
// caught by `monkeydo /t` instead of by someone remembering to look.
//
// Note on the BLE tests: the simulator's BLE profile registry outlives an
// AppBase instance, and the harness restarts the app once per test, so
// whether *this* app instance got a profile depends on how many tests have
// run before it. Nothing below asserts on that. What is asserted is the
// contract that used to be broken: construction never throws, a delegate
// without a profile refuses to pretend it is scanning, and repeated
// construction registers at most once.

(:test)
function testConstructingABleDelegateNeverThrows(logger as Test.Logger) as Lang.Boolean {
    // This is the regression. Registration used to happen unconditionally in
    // initialize(), so the third construction in a VM threw an unhandled
    // ProfileRegistrationException ("Too Many Profiles") straight out of
    // FreelapApp.onStart and took the app down. Reaching the assertion at all
    // is the test.
    var first = new FreelapBleDelegate();
    var second = new FreelapBleDelegate();
    var third = new FreelapBleDelegate();
    var fourth = new FreelapBleDelegate();

    Test.assertMessage(fourth != null, "a fourth delegate is constructible");

    first.stop(); second.stop(); third.stop(); fourth.stop();
    return true;
}

(:test)
function testRepeatedConstructionRegistersTheProfileAtMostOnce(logger as Test.Logger) as Lang.Boolean {
    var before = FreelapBleDelegate.profileRegistrations;

    var a = new FreelapBleDelegate();
    var b = new FreelapBleDelegate();
    var c = new FreelapBleDelegate();

    Test.assertEqualMessage(FreelapBleDelegate.profileRegistrations, before,
        "the profile is already registered for this app instance; do not spend another slot");

    a.stop(); b.stop(); c.stop();
    return true;
}

(:test)
function testADelegateWithoutAProfileDoesNotPretendToScan(logger as Test.Logger) as Lang.Boolean {
    var ble = new FreelapBleDelegate();
    ble.profileError = true;

    ble.startScan();

    Test.assertEqualMessage(ble.state, BleState.IDLE,
        "with no profile there is nothing to scan for; MainView shows the error instead");
    return true;
}

(:test)
function testStartScanEntersTheScanningState(logger as Test.Logger) as Lang.Boolean {
    var ble = new FreelapBleDelegate();
    if (ble.profileError) {
        // The simulator's profile registry is full because of earlier tests.
        // That is the case above, not this one.
        return true;
    }

    ble.startScan();

    Test.assertEqualMessage(ble.state, BleState.SCANNING, "startScan() enters the SCANNING state");

    ble.stop();
    return true;
}

(:test)
function testStartCreatesAnActivitySessionWithoutException(logger as Test.Logger) as Lang.Boolean {
    var course = new Course("S:0;L:30;F:100", "startup");
    var recorder = new FitRecorder();
    var engine = new SplitEngine(course, recorder, 150);

    recorder.start(engine);

    Test.assertMessage(recorder.session != null, "START created a session");
    Test.assertMessage(recorder.recording, "the session is recording");

    recorder.discard();
    Test.assertMessage(recorder.session == null, "discard() releases the session");
    return true;
}
