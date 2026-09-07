using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;

// Single activity screen: chip status, last split velocity/pace, rep time,
// rep count. In capture mode the bottom shows the last raw packet.
class MainView extends WatchUi.View {
    function initialize() { View.initialize(); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var app = Application.getApp();
        var ble = app.ble;
        var rec = app.recorder;
        var lastEvent = app.engine != null ? app.engine.lastEvent : null;
        var lastRep = app.engine != null ? app.engine.lastRep : null;
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Chip status line
        var status;
        var color;
        if (ble == null) { status = "BLE?"; color = Graphics.COLOR_RED; }
        else if (ble.profileError) { status = "BLE profile error"; color = Graphics.COLOR_RED; }
        else if (ble.state == BleState.SUBSCRIBED) { status = WatchUi.loadResource(Rez.Strings.Connected); color = Graphics.COLOR_GREEN; }
        else if (ble.state == BleState.SCANNING) { status = WatchUi.loadResource(Rez.Strings.Scanning); color = Graphics.COLOR_YELLOW; }
        else if (ble.state == BleState.IDLE) { status = WatchUi.loadResource(Rez.Strings.NoChip); color = Graphics.COLOR_RED; }
        else { status = "Pairing…"; color = Graphics.COLOR_YELLOW; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawFitted(dc, h * 0.08, Graphics.FONT_TINY, status);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (rec == null || rec.session == null) {
            dc.drawText(w / 2, h * 0.44, Graphics.FONT_MEDIUM, WatchUi.loadResource(Rez.Strings.PressStart), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // A course the athlete mistyped is only discoverable here: the
            // settings screen accepted it, and by the time a rep is running it
            // is too late. Shown before recording starts, not just logged.
            var course = app.course;
            if (course != null) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                var summary = course.name + "  " + course.totalDistance().format("%.0f") + "m";
                if (course.usingFallback) { summary += " (default)"; }
                drawFitted(dc, h * 0.56, Graphics.FONT_XTINY, summary);
                var problem = course.problem();
                if (!problem.equals("")) {
                    // Red when the athlete's own course was thrown away,
                    // amber for a caveat about the course actually in force.
                    dc.setColor(course.usingFallback ? Graphics.COLOR_RED : Graphics.COLOR_YELLOW,
                                Graphics.COLOR_TRANSPARENT);
                    drawFitted(dc, h * 0.66, Graphics.FONT_XTINY, problem);
                }
            }
        } else {
            var big = "--";
            var sub = "";
            if (lastEvent != null && lastEvent.splitTimeUs > 0) {
                big = lastEvent.velocityMps.format("%.2f") + " m/s";
                sub = lastEvent.formatSplit() + "s  " + lastEvent.splitDistM.format("%.0f") + "m  " + formatPace(lastEvent.paceSecPerKm);
            }
            dc.drawText(w / 2, h * 0.36, Graphics.FONT_NUMBER_MEDIUM, big, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(w / 2, h * 0.55, Graphics.FONT_TINY, sub, Graphics.TEXT_JUSTIFY_CENTER);

            var repLine = WatchUi.loadResource(Rez.Strings.Rep) + " " + app.engine.repsDone;
            if (lastRep != null) {
                repLine += "  " + (lastRep.timeUs / 1000000.0).format("%.2f") + "s";
            }
            dc.drawText(w / 2, h * 0.68, Graphics.FONT_SMALL, repLine, Graphics.TEXT_JUSTIFY_CENTER);
            if (!rec.recording) {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w / 2, h * 0.80, Graphics.FONT_TINY, "PAUSED", Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        if (ble != null && ble.captureMode) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            var hx = ble.lastPacketHex;
            if (hx.length() > 24) { hx = hx.substring(0, 24) + "…"; }
            dc.drawText(w / 2, h * 0.88, Graphics.FONT_XTINY, "#" + ble.packetCount + " " + hx, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Draw a centred line at `top`, truncated to the room actually available
    // at that height. Every centred line in this view goes through here.
    function drawFitted(dc as Graphics.Dc, top as Lang.Numeric, font as Graphics.FontDefinition, text as Lang.String) as Void {
        var middle = top + dc.getFontHeight(font) / 2.0;
        dc.drawText(dc.getWidth() / 2, top, font,
                    fitText(dc, text, font, usableWidth(dc, middle)),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // How much horizontal room a centred line actually has at height y. On a
    // round face that is the chord, not the diameter: a line near the top or
    // bottom has far less room than one across the middle, which is why the
    // status line clipped at both ends on a 416x416 display.
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

    // Truncate to what will actually fit. The course messages are written
    // short enough for a 240px round face, but the athlete types the course
    // string, so the width of whatever ends up quoted in an error is not ours
    // to assume.
    function fitText(dc as Graphics.Dc, text as Lang.String, font as Graphics.FontDefinition, maxWidth as Lang.Numeric) as Lang.String {
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
