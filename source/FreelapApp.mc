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
        recorder = new FitRecorder();
        engine = SplitEngine.fromSettings(course, recorder);
        ble = new FreelapBleDelegate();
        ble.engine = engine;
        ble.startScan();
    }

    function onStop(state as Lang.Dictionary?) as Void {
        if (ble != null) { ble.stop(); }
        if (recorder != null && recorder.session != null) { recorder.discard(); }
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
