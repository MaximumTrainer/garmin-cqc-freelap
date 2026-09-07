using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.WatchUi;

// The table shown for a few seconds after a rep finishes: one row per split,
// then the rep total.
//
// Two things this must not do, and both shaped it:
//
//   * it must not interfere with recording. It is a view, nothing more - the
//     1 Hz FIT tick, the BLE callbacks and the split engine all keep running
//     underneath, because none of them are driven by the view stack. A second
//     rep arriving while it is up replaces its contents rather than pushing a
//     second overlay.
//   * it must not need dismissing. It times itself out; any key or tap also
//     closes it, because an athlete standing on a start line does not want to
//     negotiate with a screen.
class RepSummaryView extends WatchUi.View {
    // Issue #21: five seconds, then it goes.
    static const SHOW_MS = 5000;

    var rep = null;            // RepSummary
    var shownAtMs = 0;
    var offset = 0;            // first split row visible, for scrolling
    var trace = null;          // set by the layout tests; see MainView

    hidden var _rowsVisible = 0;

    function initialize(summary, nowMs as Lang.Number) {
        View.initialize();
        show(summary, nowMs);
    }

    // Take a new rep without being torn down and rebuilt: a second rep can
    // finish while this one is still up.
    function show(summary, nowMs as Lang.Number) as Void {
        rep = summary;
        shownAtMs = nowMs;
        offset = 0;
    }

    function expired(nowMs as Lang.Number) as Lang.Boolean {
        return nowMs - shownAtMs >= SHOW_MS;
    }

    function splitCount() as Lang.Number {
        return rep == null ? 0 : rep.events.size();
    }

    // How many split rows fit between the title and the total line. Measured
    // rather than assumed: six on a 240px face is the issue's number, but the
    // same code has to do something sensible on 208 and on 454.
    //
    // One row is given back to the "3-9 / 12" marker when there is more than
    // fits, because otherwise the marker is drawn on top of the last split -
    // which is what the layout test caught.
    function rowsThatFit(dc as Graphics.Dc) as Lang.Number {
        var capacity = regionCapacity(dc);
        if (splitCount() > capacity) { capacity -= 1; }
        return capacity < 1 ? 1 : capacity;
    }

    hidden function regionCapacity(dc as Graphics.Dc) as Lang.Number {
        var rowHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var top = dc.getHeight() * 0.22;
        var bottom = dc.getHeight() * 0.80;      // the total line sits below
        var fits = ((bottom - top) / rowHeight).toNumber();
        return fits < 1 ? 1 : fits;
    }

    // The window of splits currently on screen.
    function visibleRange(dc as Graphics.Dc) as Lang.Array {
        var fits = rowsThatFit(dc);
        var count = splitCount();
        if (count <= fits) { return [0, count]; }
        var start = offset;
        if (start > count - fits) { start = count - fits; }
        if (start < 0) { start = 0; }
        return [start, start + fits];
    }

    function scroll(direction as Lang.Number, fits as Lang.Number) as Lang.Boolean {
        var count = splitCount();
        if (count <= fits) { return false; }
        var next = offset + direction;
        if (next < 0) { next = 0; }
        if (next > count - fits) { next = count - fits; }
        if (next == offset) { return false; }
        offset = next;
        return true;
    }

    // One row: the transmitter, its split time, its velocity.
    function rowText(index as Lang.Number) as Lang.String {
        var ev = rep.events[index] as SplitEvent;
        var name = ev.txIndex < 0 ? "?" : ev.txIndex.format("%d");
        return name + "   " + ev.formatSplit() + "s   " + ev.velocityMps.format("%.2f");
    }

    function totalText() as Lang.String {
        return (rep.timeUs / 1000000.0).format("%.2f") + "s   " +
               rep.distM.format("%.0f") + "m";
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (rep == null) { return; }

        var w = dc.getWidth();
        var h = dc.getHeight();
        if (trace != null) { trace = []; }

        var title = WatchUi.loadResource(Rez.Strings.Rep) + " " + rep.rep.format("%d");
        if (!rep.chipId.equals("") && !rep.chipId.equals("TEST")) {
            title = rep.chipId + "  " + title;
        }
        drawRow(dc, h * 0.10, [Graphics.FONT_TINY, Graphics.FONT_XTINY], title,
                rep.status == RepStatus.OK ? Graphics.COLOR_WHITE : Graphics.COLOR_YELLOW);

        var range = visibleRange(dc);
        var rowHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = h * 0.22;
        for (var i = range[0]; i < range[1]; i++) {
            drawRow(dc, y, [Graphics.FONT_XTINY], rowText(i), Graphics.COLOR_WHITE);
            y += rowHeight;
        }

        // A scroll marker in the row reserved for it, so "there are more
        // splits than this" is visible rather than a silent truncation.
        if (splitCount() > rowsThatFit(dc)) {
            drawRow(dc, y, [Graphics.FONT_XTINY],
                    (range[0] + 1).format("%d") + "-" + range[1].format("%d") +
                    " / " + splitCount().format("%d"), Graphics.COLOR_WHITE);
        }

        // The total is the widest line and sits low, where a round face has
        // least room: a long rep on a big course ("44.00s   330m") does not fit
        // FONT_SMALL there.
        drawRow(dc, h * 0.82, [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY],
                totalText(), Graphics.COLOR_WHITE);
    }

    // Largest candidate font that fits the chord at this height, then
    // truncate. Same rule as MainView, for the same reason.
    hidden function drawRow(dc as Graphics.Dc, top as Lang.Numeric, candidates as Lang.Array,
                            text as Lang.String, color) as Void {
        var font = candidates[candidates.size() - 1];
        for (var i = 0; i < candidates.size(); i++) {
            var candidate = candidates[i];
            var middle = top + dc.getFontHeight(candidate) / 2.0;
            if (dc.getTextWidthInPixels(text, candidate) <= usableWidth(dc, middle)) {
                font = candidate;
                break;
            }
        }

        var usable = usableWidth(dc, top + dc.getFontHeight(font) / 2.0);
        var shown = text;
        while (shown.length() > 1 && dc.getTextWidthInPixels(shown + "…", font) > usable) {
            shown = shown.substring(0, shown.length() - 1);
        }
        if (!shown.equals(text)) { shown += "…"; }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, top, font, shown, Graphics.TEXT_JUSTIFY_CENTER);
        if (trace != null) {
            trace.add({ :text => shown, :top => top, :height => dc.getFontHeight(font),
                        :width => dc.getTextWidthInPixels(shown, font), :usable => usable });
        }
    }

    // Same chord rule as MainView: on a round face the room at a given height
    // is not the display width.
    hidden function usableWidth(dc as Graphics.Dc, y as Lang.Numeric) as Lang.Float {
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (System.getDeviceSettings().screenShape != System.SCREEN_SHAPE_ROUND) {
            return w * 0.96;
        }
        var r = w / 2.0;
        var dy = (y - h / 2.0).abs();
        if (dy >= r) { return 0.0; }
        return 2.0 * Math.sqrt(r * r - dy * dy) * 0.94;
    }
}
