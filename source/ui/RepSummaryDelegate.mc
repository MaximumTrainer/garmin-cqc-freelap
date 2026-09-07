using Toybox.Lang;
using Toybox.WatchUi;

// Any key or tap closes the rep summary early; UP/DOWN scroll it when there
// are more splits than fit. An athlete on a start line should never have to
// negotiate with a screen, so nothing here can fail to dismiss it - the app
// also times it out.
class RepSummaryDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onSelect() as Lang.Boolean { return dismiss(); }
    function onBack() as Lang.Boolean { return dismiss(); }
    function onTap(evt as WatchUi.ClickEvent) as Lang.Boolean { return dismiss(); }
    function onNextPage() as Lang.Boolean { return scroll(1); }
    function onPreviousPage() as Lang.Boolean { return scroll(-1); }

    hidden function dismiss() as Lang.Boolean {
        (Application.getApp() as FreelapApp).dismissRepOverlay();
        return true;
    }

    // Scrolling keeps the overlay up; dismissing on UP/DOWN would make a long
    // rep impossible to read.
    hidden function scroll(direction as Lang.Number) as Lang.Boolean {
        var app = Application.getApp() as FreelapApp;
        if (app.repOverlay == null) { return dismiss(); }
        app.repOverlay.offset += direction;
        if (app.repOverlay.offset < 0) { app.repOverlay.offset = 0; }
        WatchUi.requestUpdate();
        return true;
    }
}
