using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;

// Single activity screen: chip status, last split velocity/pace, rep time,
// rep count. In capture mode the bottom shows the last raw packet.
//
// Layout rule (issue #2): nothing here hard-codes a font size for a screen
// size. Every line asks for the largest font from a preference list that
// actually fits the room available at its height, and lines are stacked by
// measured font height rather than by fractions of the display, so they cannot
// overlap. On a round face the room available is the *chord* at that height,
// not the diameter — a line near the rim has far less width than one across
// the middle, which is what made the status line clip on a 416x416 display.
class MainView extends WatchUi.View {
    // Largest first. The first one that fits wins.
    hidden var BIG      = [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
                           Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL];
    hidden var HEADLINE = [Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY];
    hidden var LINE     = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
    hidden var DETAIL   = [Graphics.FONT_TINY, Graphics.FONT_XTINY];
    hidden var SMALLEST = [Graphics.FONT_XTINY];

    hidden var _cursorY = 0;

    // When non-null, every line drawn is also recorded here as
    // {:text, :top, :height, :width, :usable}. Set by the layout tests, which
    // assert that nothing is wider than the room at its height and that no two
    // lines overlap — on a real Dc, at whatever resolution the simulator is
    // running. Left null in normal use, so this costs a null check per line.
    var trace = null;

    function initialize() { View.initialize(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var app = Application.getApp();
        var ble = app.ble;
        var rec = app.recorder;
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawChipStatus(dc, ble, h);

        if (rec == null || rec.session == null) {
            drawIdle(dc, app, h);
        } else {
            drawLive(dc, app, rec, h);
        }

        drawCaptureLine(dc, ble, h);
    }

    // ---- blocks -----------------------------------------------------------

    hidden function drawChipStatus(dc as Graphics.Dc, ble, h as Lang.Number) as Void {
        var status;
        var color;
        if (ble == null) { status = "BLE?"; color = Graphics.COLOR_RED; }
        else if (ble.profileError) { status = WatchUi.loadResource(Rez.Strings.BleError); color = Graphics.COLOR_RED; }
        else if (ble.state == BleState.SUBSCRIBED) { status = WatchUi.loadResource(Rez.Strings.Connected); color = Graphics.COLOR_GREEN; }
        else if (ble.state == BleState.SCANNING) { status = WatchUi.loadResource(Rez.Strings.Scanning); color = Graphics.COLOR_YELLOW; }
        else if (ble.state == BleState.IDLE) { status = WatchUi.loadResource(Rez.Strings.NoChip); color = Graphics.COLOR_RED; }
        else { status = WatchUi.loadResource(Rez.Strings.Pairing); color = Graphics.COLOR_YELLOW; }

        beginStack(h * 0.08);
        stackLine(dc, status, DETAIL, color);
    }

    hidden function drawIdle(dc as Graphics.Dc, app, h as Lang.Number) as Void {
        beginStack(h * 0.38);
        stackLine(dc, WatchUi.loadResource(Rez.Strings.PressStart), HEADLINE, Graphics.COLOR_WHITE);

        // A course the athlete mistyped is only discoverable here: the settings
        // screen accepted it, and by the time a rep is running it is too late.
        var course = app.course;
        if (course == null) { return; }

        var summary = course.name + "  " + course.totalDistance().format("%.0f") + "m";
        if (course.usingFallback) { summary += " (default)"; }
        stackLine(dc, summary, DETAIL, Graphics.COLOR_LT_GRAY);

        var problem = course.problem();
        if (!problem.equals("")) {
            // Red when the athlete's own course was thrown away, amber for a
            // caveat about the course actually in force.
            stackLine(dc, problem, SMALLEST,
                      course.usingFallback ? Graphics.COLOR_RED : Graphics.COLOR_YELLOW);
        }
    }

    hidden function drawLive(dc as Graphics.Dc, app, rec, h as Lang.Number) as Void {
        var lastEvent = app.engine != null ? app.engine.lastEvent : null;
        var lastRep = app.engine != null ? app.engine.lastRep : null;

        var big = "--";
        var sub = "";
        if (lastEvent != null && lastEvent.splitTimeUs > 0) {
            big = lastEvent.velocityMps.format("%.2f") + " m/s";
            sub = lastEvent.formatSplit() + "s  " + lastEvent.splitDistM.format("%.0f") + "m  " +
                  formatPace(lastEvent.paceSecPerKm);
        }

        beginStack(h * 0.28);
        stackLine(dc, big, BIG, Graphics.COLOR_WHITE);
        if (!sub.equals("")) {
            stackLine(dc, sub, DETAIL, Graphics.COLOR_LT_GRAY);
        }

        var repLine = WatchUi.loadResource(Rez.Strings.Rep) + " " + app.engine.repsDone;
        if (lastRep != null) {
            repLine += "  " + (lastRep.timeUs / 1000000.0).format("%.2f") + "s";
        }
        stackLine(dc, repLine, LINE, Graphics.COLOR_WHITE);

        if (!rec.recording) {
            stackLine(dc, WatchUi.loadResource(Rez.Strings.Paused), DETAIL, Graphics.COLOR_YELLOW);
        }
    }

    hidden function drawCaptureLine(dc as Graphics.Dc, ble, h as Lang.Number) as Void {
        if (ble == null || !ble.captureMode) { return; }
        beginStack(h * 0.86);
        stackLine(dc, "#" + ble.packetCount + " " + ble.lastPacketHex, SMALLEST, Graphics.COLOR_LT_GRAY);
    }

    // ---- layout primitives ------------------------------------------------

    // Start a run of centred lines at `top`.
    hidden function beginStack(top as Lang.Numeric) as Void { _cursorY = top; }

    // Draw one centred line and advance past it. Because the cursor moves by
    // the font's measured height, two lines can never overlap however small
    // the display is.
    hidden function stackLine(dc as Graphics.Dc, text as Lang.String,
                              candidates as Lang.Array, color) as Void {
        var font = pickFont(dc, text, candidates, _cursorY);
        var height = dc.getFontHeight(font);
        var usable = usableWidth(dc, _cursorY + height / 2.0);
        var shown = fitText(dc, text, font, usable);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, _cursorY, font, shown, Graphics.TEXT_JUSTIFY_CENTER);

        if (trace != null) {
            trace.add({
                :text => shown,
                :top => _cursorY,
                :height => height,
                :width => dc.getTextWidthInPixels(shown, font),
                :usable => usable
            });
        }
        _cursorY += height;
    }

    // The largest font from `candidates` whose text fits the room at `top`.
    // Falls through to the smallest, which drawFitted then truncates.
    function pickFont(dc as Graphics.Dc, text as Lang.String,
                      candidates as Lang.Array, top as Lang.Numeric) {
        for (var i = 0; i < candidates.size(); i++) {
            var font = candidates[i];
            var middle = top + dc.getFontHeight(font) / 2.0;
            if (dc.getTextWidthInPixels(text, font) <= usableWidth(dc, middle)) {
                return font;
            }
        }
        return candidates[candidates.size() - 1];
    }

    // How much horizontal room a centred line has at height y. On a round face
    // that is the chord, not the diameter.
    function usableWidth(dc as Graphics.Dc, y as Lang.Numeric) as Lang.Float {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_ROUND) {
            return w * 0.96;
        }
        var r = w / 2.0;
        var dy = (y - h / 2.0).abs();
        if (dy >= r) { return 0.0; }
        return 2.0 * Math.sqrt(r * r - dy * dy) * 0.94;   // 6% inset off the bezel
    }

    // Truncate to what will actually fit. The course messages are written short
    // enough for a 208px round face, but the athlete types the course string,
    // so the width of whatever ends up quoted in an error is not ours to
    // assume.
    function fitText(dc as Graphics.Dc, text as Lang.String, font, maxWidth as Lang.Numeric) as Lang.String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) { return text; }
        var s = text;
        while (s.length() > 1 && dc.getTextWidthInPixels(s + "…", font) > maxWidth) {
            s = s.substring(0, s.length() - 1);
        }
        return s + "…";
    }

    function formatPace(secPerKm as Lang.Float) as Lang.String {
        if (secPerKm <= 0) { return "--:--/km"; }
        var m = (secPerKm / 60).toNumber();
        var s = (secPerKm - m * 60).toNumber();
        return m.format("%d") + ":" + s.format("%02d") + "/km";
    }
}
