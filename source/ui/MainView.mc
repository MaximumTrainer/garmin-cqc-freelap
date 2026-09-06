using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
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
        else if (ble.state == BleState.SUBSCRIBED) { status = WatchUi.loadResource(Rez.Strings.Connected); color = Graphics.COLOR_GREEN; }
        else if (ble.state == BleState.SCANNING) { status = WatchUi.loadResource(Rez.Strings.Scanning); color = Graphics.COLOR_YELLOW; }
        else if (ble.state == BleState.IDLE) { status = WatchUi.loadResource(Rez.Strings.NoChip); color = Graphics.COLOR_RED; }
        else { status = "Pairing…"; color = Graphics.COLOR_YELLOW; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.08, Graphics.FONT_TINY, status, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (rec == null || rec.session == null) {
            dc.drawText(w / 2, h / 2, Graphics.FONT_MEDIUM, WatchUi.loadResource(Rez.Strings.PressStart), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

    function formatPace(secPerKm as Lang.Float) as Lang.String {
        if (secPerKm <= 0) { return "--:--/km"; }
        var m = (secPerKm / 60).toNumber();
        var s = (secPerKm - m * 60).toNumber();
        return m.format("%d") + ":" + s.format("%02d") + "/km";
    }
}
