using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Test;

// Test-only helpers.
//
// These live inside a module rather than at file scope on purpose: the test
// runner collects *every* module-scope function annotated `(:test)` as a test
// case, so a helper written that way is run with a Logger as its first
// argument and reported as an ERROR. Inside a module it is still stripped from
// release builds by the annotation, but it is not a test.
// A recorder, the engine feeding it, and the session double underneath.
(:test)
class Rig {
    var recorder;
    var engine;
    var session;
    function initialize(r, e, s) { recorder = r; engine = e; session = s; }
}

(:test)
module TestSupport {

    // A rep's worth of Crossings from parallel time/code arrays.
    function burst(timesUs as Lang.Array, codes as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < timesUs.size(); i++) {
            out.add(new Crossing(timesUs[i], codes[i], "TEST"));
        }
        return out;
    }

    // An engine with both clocks pinned: the session start on the watch's
    // monotonic timer, and the assumed BLE latency. Everything about
    // fl_est_ms is derived from those two numbers plus the packet arrival
    // time, so with them fixed the estimates are exact.
    function engineAt(sessionStartMs as Lang.Number, latencyMs as Lang.Number,
                      spec as Lang.String) as SplitEngine {
        var engine = new SplitEngine(new Course(spec, "test"), null, latencyMs);
        engine.onSessionStartAt(sessionStartMs);
        return engine;
    }

    // The rep from the issue #14 worked example: S:0;L:30;L:60;F:100 run at
    // 4.120 / 7.480 / 11.930 s.
    function workedRep() as Lang.Array {
        return burst([0l, 4120000l, 7480000l, 11930000l],
                     [TxCode.START, TxCode.LAP, TxCode.LAP, TxCode.FINISH]);
    }

    // An engine over `spec`, with the BLE latency injected so no setting is
    // read. 150 ms is the properties.xml default, so tests that do not care
    // about latency still see production behaviour.
    function engineFor(spec as Lang.String) as SplitEngine {
        var engine = new SplitEngine(new Course(spec, "test"), null, 150);
        engine.onSessionStart();
        return engine;
    }

    // Element-wise array comparison. Test.assertEqual on two Arrays compares
    // references, so it fails for equal contents and — worse — would pass for
    // the same array compared with itself.
    function assertArrayEquals(actual as Lang.Array, expected as Lang.Array, message as Lang.String) as Void {
        Test.assertEqualMessage(actual.size(), expected.size(),
            message + ": expected " + expected.size().format("%d") +
            " values, got " + actual.size().format("%d") + " " + describe(actual));
        for (var i = 0; i < expected.size(); i++) {
            Test.assertEqualMessage(actual[i], expected[i],
                message + " at index " + i.format("%d") + " (" + describe(actual) + ")");
        }
    }

    function describe(values as Lang.Array) as Lang.String {
        var out = "[";
        for (var i = 0; i < values.size(); i++) {
            if (i > 0) { out += ", "; }
            out += values[i].toString();
        }
        return out + "]";
    }

    // Float comparison with a stated tolerance. Monkey C Floats are single
    // precision, so an exact assertEqual on a derived metric is a coin flip.
    function assertClose(actual as Lang.Float, expected as Lang.Float,
                         tolerance as Lang.Float, message as Lang.String) as Void {
        var delta = (actual - expected).abs();
        Test.assertMessage(delta <= tolerance,
            message + ": expected " + expected.format("%.4f") +
            " +/- " + tolerance.format("%.4f") +
            ", got " + actual.format("%.4f"));
    }

    // A recorder + engine + course wired together over a session double.
    // Returns a Rig so a test can reach either end.
    function recorderOn(session, spec as Lang.String) as Rig {
        var recorder = new FitRecorder(true, false);
        var engine = new SplitEngine(new Course(spec, "test"), recorder, 150);
        recorder.startWith(session, engine, false);   // no Timer under test
        return new Rig(recorder, engine, session);
    }

    // Drive the recorder's 1 Hz drain by hand, `times` records' worth.
    function tick(recorder as FitRecorder, times as Lang.Number) as Void {
        for (var i = 0; i < times; i++) { recorder.onTick(); }
    }

    // Tick until the recorder has nothing left to do. Preferred over a magic
    // tick count: how many ticks a rep costs is an implementation detail, and
    // a test that hard-codes it fails for the wrong reason.
    function tickUntilIdle(recorder as FitRecorder, maxTicks as Lang.Number) as Lang.Number {
        for (var i = 0; i < maxTicks; i++) {
            if (recorder.isIdle()) { return i; }
            recorder.onTick();
        }
        Test.assertMessage(recorder.isIdle(),
            "recorder still had work after " + maxTicks.format("%d") + " ticks");
        return maxTicks;
    }

    // Drive an action through MainDelegate's real dispatch, with `recorder`
    // installed on the app so the side effects land somewhere observable.
    function performOnApp(recorder, action as Lang.Symbol) as Void {
        var app = Application.getApp() as FreelapApp;
        var previous = app.recorder;
        app.recorder = recorder;
        new MainDelegate().perform(action);
        app.recorder = previous;
    }

    // ---- MainView layout ---------------------------------------------------

    // An off-screen Dc the size of this device's display, so a view can be
    // drawn and measured without being on screen. BufferedBitmap moved to a
    // factory in API 4; both spellings are handled.
    function offscreenDc() as Graphics.Dc {
        var settings = System.getDeviceSettings();
        var options = { :width => settings.screenWidth, :height => settings.screenHeight };
        if (Graphics has :createBufferedBitmap) {
            return Graphics.createBufferedBitmap(options).get().getDc();
        }
        return new Graphics.BufferedBitmap(options).getDc();
    }

    // Draw MainView once and hand back what it laid out. `engine` non-null
    // puts the view in its recording state; `paused` shows the PAUSED line.
    function traceMainView(engine, paused as Lang.Boolean) as Lang.Array {
        var app = Application.getApp() as FreelapApp;
        var previousEngine = app.engine;
        var previousRecorder = app.recorder;

        if (engine != null) {
            var session = new FakeSession();
            var recorder = new FitRecorder(true, false);
            recorder.startWith(session, engine, false);
            if (paused) { recorder.stop(); }
            app.engine = engine;
            app.recorder = recorder;
        }

        var view = new MainView();
        view.trace = [];
        view.onUpdate(offscreenDc());

        app.engine = previousEngine;
        app.recorder = previousRecorder;
        return view.trace;
    }

    // Draw the idle screen with the BLE delegate forced into `state`, so the
    // status line's colour can be asserted without a radio.
    function traceMainViewWithBleState(state as Lang.Number) as Lang.Array {
        var app = Application.getApp() as FreelapApp;
        var ble = app.ble;
        var previousState = ble.state;
        var previousError = ble.profileError;

        ble.state = state;
        ble.profileError = false;
        var trace = traceMainView(null, false);

        ble.state = previousState;
        ble.profileError = previousError;
        return trace;
    }

    // An engine that has already run the worked rep, so lastEvent and lastRep
    // are populated and the live screen has real numbers to draw.
    function engineWithARep() as SplitEngine {
        var engine = engineFor("S:0;L:30;L:60;F:100");
        engine.onRepBurst(workedRep(), 1000);
        return engine;
    }

    // The two things a screenshot of this screen is being used to check.
    function assertLayoutIsSane(trace as Lang.Array, what as Lang.String) as Void {
        var screenHeight = System.getDeviceSettings().screenHeight;
        var previousBottom = -1;

        for (var i = 0; i < trace.size(); i++) {
            var line = trace[i] as Lang.Dictionary;
            var text = line.get(:text) as Lang.String;
            var top = line.get(:top) as Lang.Numeric;
            var height = line.get(:height) as Lang.Numeric;
            var width = line.get(:width) as Lang.Numeric;
            var usable = line.get(:usable) as Lang.Numeric;

            Test.assertMessage(width <= usable + 1,
                what + ": \"" + text + "\" is " + width.format("%d") +
                "px wide but only " + usable.format("%d") + "px is available at y=" +
                top.format("%d"));

            Test.assertMessage(top >= previousBottom,
                what + ": \"" + text + "\" starts at y=" + top.format("%d") +
                " but the line above ends at y=" + previousBottom.format("%d"));

            Test.assertMessage(top + height <= screenHeight,
                what + ": \"" + text + "\" runs past the bottom of a " +
                screenHeight.format("%d") + "px display");

            previousBottom = top + height;
        }
    }

    // Put `spec` in the course 1 setting, push it through the app the way
    // Garmin Connect would, and hand back the course the app ended up with.
    // The previous values are restored so tests do not leak into each other.
    function courseAfterSettingsChange(spec as Lang.String) as Course {
        var previousSpec = Properties.getValue("course1");
        var previousActive = Properties.getValue("activeCourse");

        Properties.setValue("course1", spec);
        Properties.setValue("activeCourse", 1);

        var app = Application.getApp() as FreelapApp;
        app.onSettingsChanged();
        var reloaded = app.course;

        Properties.setValue("course1", previousSpec);
        Properties.setValue("activeCourse", previousActive);
        return reloaded;
    }
}
