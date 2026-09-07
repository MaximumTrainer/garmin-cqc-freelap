using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

// Buttons: START/ENTER toggles recording; BACK/LAP forces a rep end while
// recording; long-press or BACK while paused opens the save/discard menu.
class MainDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    function onSelect() as Lang.Boolean {
        var app = Application.getApp();
        var rec = app.recorder;
        if (rec.session == null) {
            rec.start(app.engine);
        } else if (rec.recording) {
            rec.stop();
        } else {
            rec.resume();
        }
        WatchUi.requestUpdate();
        return true;
    }

    // What BACK means right now, as a plain function of the recorder's state.
    // Extracted so the decision is testable without a view stack: the rule
    // that an active session is never left without asking is the one thing
    // here that costs an athlete a session if it regresses.
    static function backAction(rec) as Lang.Symbol {
        if (rec == null || rec.session == null) { return :exit; }
        if (rec.recording) { return :manualLap; }
        return :saveMenu;
    }

    function onBack() as Lang.Boolean {
        var app = Application.getApp();
        var rec = app.recorder;
        var action = backAction(rec);

        if (action == :exit) {
            return false;   // nothing to lose; leave the app
        }
        if (action == :manualLap) {
            // BACK is the lap button while the timer runs, as on any Garmin
            // watch. Pause with START first to reach the save menu.
            rec.manualLap();
            return true;
        }

        var menu = new WatchUi.Menu2({ :title => "Freelap" });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Save), null, :save, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Discard), null, :discard, null));
        WatchUi.pushView(menu, new SaveMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}

class SaveMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = Application.getApp();
        if (item.getId() == :save) {
            app.recorder.save();
        } else {
            app.recorder.discard();
        }
        app.ble.stop();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);   // exit to launcher
    }
}
