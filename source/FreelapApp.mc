using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

class FreelapApp extends Application.AppBase {
    var ble = null;
    var engine = null;
    var recorder = null;
    var course = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Lang.Dictionary?) as Void {
        course = Course.loadActive();
        recorder = FitRecorder.fromSettings();
        engine = SplitEngine.fromSettings(course, recorder);
        ble = new FreelapBleDelegate();
        ble.engine = engine;
        ble.startScan();
    }

    // onStop cannot ask anything: the view stack is gone by the time it runs.
    // An active session here was never explicitly discarded by the athlete -
    // the watch closed the app, or the battery did - so it is saved, not
    // thrown away. Losing a training session is much the worse of the two
    // mistakes, and a stray activity can be deleted in Garmin Connect.
    // A session already saved through the menu has recorder.session == null
    // and is left alone.
    function onStop(state as Lang.Dictionary?) as Void {
        if (ble != null) { ble.stop(); }
        if (recorder != null && recorder.session != null) { recorder.save(); }
    }

    function onSettingsChanged() as Void {
        course = Course.loadActive();
        if (engine != null) { engine.course = course; }
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        return [ new MainView(), new MainDelegate() ];
    }
}
