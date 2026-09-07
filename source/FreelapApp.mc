using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

class FreelapApp extends Application.AppBase {
    var ble = null;
    var engine = null;
    var recorder = null;
    var course = null;

    // A short message drawn over the activity screen - "No splits" when the
    // lap button had nothing to end. WatchUi.showToast needs API 4.0 and
    // minApiLevel here is 3.1, so MainView draws it instead.
    var notice = "";
    var noticeUntilMs = 0;
    static const NOTICE_MS = 2000;

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

    // A sync from Garmin Connect lands here. Everything the athlete can change
    // is re-read and applied now, so nothing needs the app relaunched.
    //
    // The course is the exception: changing it while a session is running would
    // silently re-derive the distances of splits already written, so a
    // mid-session change is refused and the athlete told why (issue #22).
    function onSettingsChanged() as Void {
        applySettings();

        if (recording()) {
            setNotice(WatchUi.loadResource(Rez.Strings.CourseLocked));
        } else {
            course = Course.loadActive();
            if (engine != null) { engine.course = course; }
        }
        WatchUi.requestUpdate();
    }

    // Settings that are safe to change at any moment, session or not.
    function applySettings() as Void {
        if (engine != null) { engine.bleLatencyMs = Settings.bleLatencyMs(); }
        if (recorder != null) {
            recorder.clearAfterWrite = Settings.clearAfterWrite();
            recorder.lapPerCrossing = Settings.lapPerCrossing();
        }
        if (ble != null) { ble.captureMode = Settings.captureMode(); }
    }

    function recording() as Lang.Boolean {
        return recorder != null && recorder.session != null;
    }

    function setNotice(text as Lang.String) as Void {
        notice = text;
        noticeUntilMs = System.getTimer() + NOTICE_MS;
        WatchUi.requestUpdate();
    }

    function clearNotice() as Void {
        notice = "";
        noticeUntilMs = 0;
    }

    // The notice to draw right now, or "" once it has timed out.
    function activeNotice() as Lang.String {
        if (notice.equals("") || System.getTimer() > noticeUntilMs) { return ""; }
        return notice;
    }

    function getInitialView() {
        return [ new MainView(), new MainDelegate() ];
    }
}
