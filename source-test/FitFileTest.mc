using Toybox.Lang;
using Toybox.Test;

// Ring 2 for the FIT path: drive a *real* ActivityRecording session, not a
// double, and save it. The simulator writes the result to
// %TEMP%\com.garmin.connectiq\GARMIN\Activities, which is where
// tools/tests/data/reference-session.fit came from.
//
// What this proves that FitRecordFieldsTest cannot: the field declarations are
// ones the FIT writer actually accepts, and the file it produces carries a
// field_description message for each of them. What it cannot prove is the
// record cadence — the recorder drains one split per second by design, and a
// unit test cannot wait — so the one-split-per-record criterion stays at ring
// 3, and tools/tests/test_fit_fields.py asserts the descriptions in the file.
//
// Regenerate the fixture with:
//   monkeydo bin/freelap-test.prg fr265 /t testARealSessionSavesWithEveryDeveloperField
//   python tools/fit_fields.py <newest .fit under GARMIN/Activities>

(:test)
function testARealSessionSavesWithEveryDeveloperField(logger as Test.Logger) as Lang.Boolean {
    var recorder = new FitRecorder(true, false);
    var engine = new SplitEngine(new Course("S:0;L:30;L:60;F:100", "worked"), recorder, 150);

    recorder.start(engine);
    Test.assertMessage(recorder.session != null, "a real session was created");

    engine.onRepBurst(TestSupport.workedRep(), 1000);
    engine.onRepBurst(TestSupport.workedRep(), 30000);

    recorder.save();

    Test.assertMessage(recorder.session == null, "save() released the session");
    Test.assertMessage(!recorder.recording, "and stopped recording");
    return true;
}
