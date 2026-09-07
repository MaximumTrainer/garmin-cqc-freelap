using Toybox.Lang;
using Toybox.Test;

// Issue #1, "Build the skeleton with the Connect IQ SDK and fix compile
// errors". The last acceptance criterion — "app launches in the simulator,
// shows the 'Scanning for chip…' state, and START creates a session without
// exception" — is automated here rather than clicked, so a regression is
// caught by `monkeydo /t` instead of by someone remembering to look.

(:test)
function testBleDelegateRegistersItsProfileAndStartsScanning(logger as Test.Logger) as Lang.Boolean {
    var ble = new FreelapBleDelegate();

    // Before the profile registration was made idempotent, constructing a
    // second delegate in the same VM threw ProfileRegistrationException
    // ("Too Many Profiles") and took the whole app down on start.
    Test.assertMessage(!ble.profileError, "BLE profile registered");

    ble.startScan();
    Test.assertEqualMessage(ble.state, BleState.SCANNING, "startScan() enters the SCANNING state");

    ble.stop();
    return true;
}

(:test)
function testConstructingASecondBleDelegateDoesNotBurnAProfileSlot(logger as Test.Logger) as Lang.Boolean {
    var first = new FreelapBleDelegate();
    var second = new FreelapBleDelegate();
    var third = new FreelapBleDelegate();
    var fourth = new FreelapBleDelegate();

    // BLE allows three profiles per app; the fourth registration is what used
    // to throw. All four must come up clean now that we register once.
    Test.assertMessage(!fourth.profileError, "fourth delegate still has its profile");

    first.stop(); second.stop(); third.stop(); fourth.stop();
    return true;
}

(:test)
function testStartCreatesAnActivitySessionWithoutException(logger as Test.Logger) as Lang.Boolean {
    var course = new Course("S:0;L:30;F:100", "startup");
    var recorder = new FitRecorder();
    var engine = new SplitEngine(course, recorder);

    recorder.start(engine);

    Test.assertMessage(recorder.session != null, "START created a session");
    Test.assertMessage(recorder.recording, "the session is recording");

    recorder.discard();
    Test.assertMessage(recorder.session == null, "discard() releases the session");
    return true;
}
