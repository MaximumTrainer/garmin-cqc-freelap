using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

// Buttons: START/ENTER toggles recording; BACK/LAP forces a rep end while
// recording; long-press or BACK while paused opens the save/discard menu.
class MainDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    // What START means right now. Extracted for the same reason as
    // backAction: these are the only controls the athlete has mid-session.
    static function selectAction(rec) as Lang.Symbol {
        if (rec == null || rec.session == null) { return :start; }
        return rec.recording ? :pause : :resume;
    }

    // What a tap at `y` means, on a screen `height` tall. Touch-only devices
    // have to reach every control without a physical button, so the screen is
    // split: the upper half is the START button, the lower half is BACK.
    static function tapAction(rec, y as Lang.Numeric, height as Lang.Numeric) as Lang.Symbol {
        if (rec == null || rec.session == null) { return :start; }
        if (y < height / 2) {
            return rec.recording ? :pause : :resume;
        }
        return rec.recording ? :manualLap : :saveMenu;
    }

    function onSelect() as Lang.Boolean {
        perform(selectAction(Application.getApp().recorder));
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Lang.Boolean {
        var app = Application.getApp();
        var coords = evt.getCoordinates();
        perform(tapAction(app.recorder, coords[1], System.getDeviceSettings().screenHeight));
        return true;
    }

    // One place where an action becomes a side effect, so the button, the tap
    // and any future control cannot drift apart. Public because it is the
    // thing worth testing: the mapping functions above are pure, this is
    // where the session is actually changed.
    function perform(action as Lang.Symbol) as Void {
        var app = Application.getApp();
        var rec = app.recorder;

        if (action == :start) {
            rec.start(app.engine);
        } else if (action == :pause) {
            rec.stop();
        } else if (action == :resume) {
            rec.resume();
        } else if (action == :manualLap) {
            if (!rec.manualLap()) {
                app.setNotice(WatchUi.loadResource(Rez.Strings.NoSplits));
            }
        } else if (action == :saveMenu) {
            openSaveMenu();
        } else if (action == :captureMenu) {
            openCaptureMenu();
        } else if (action == :dumpCapture) {
            dumpCapture();
        }
        WatchUi.requestUpdate();
    }

    hidden function openSaveMenu() as Void {
        var app = Application.getApp();
        var menu = new WatchUi.Menu2({ :title => "Freelap" });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Save), null, :save, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Discard), null, :discard, null));
        if (app.ble != null && app.ble.captureMode) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.DumpCapture), null, :dump, null));
        }
        WatchUi.pushView(menu, new SaveMenuDelegate(), WatchUi.SLIDE_UP);
    }

    hidden function openCaptureMenu() as Void {
        var menu = new WatchUi.Menu2({ :title => "Freelap" });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.DumpCapture), null, :dump, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Exit), null, :exit, null));
        WatchUi.pushView(menu, new CaptureMenuDelegate(), WatchUi.SLIDE_UP);
    }

    // Prints the rolling packet log to the CIQ console in the shape
    // tools/decode_capture.py reads, so a field capture can be pasted straight
    // into the decoder. Simulator only in practice: there is no console on a
    // watch, which is why the log is also written to storage on stop().
    function dumpCapture() as Void {
        var app = Application.getApp();
        if (app.ble == null) { return; }
        var log = app.ble.capture;
        System.println("--- freelap capture: " + log.size().format("%d") + " packet(s), " +
                       log.dropped.format("%d") + " dropped of " + log.seen.format("%d") + " seen");
        System.print(log.toTsv());
        System.println("--- end");
        app.setNotice(log.size().format("%d") + " packets dumped");
    }

    // What BACK means right now, as a plain function of the recorder's state.
    // Extracted so the decision is testable without a view stack: the rule
    // that an active session is never left without asking is the one thing
    // here that costs an athlete a session if it regresses.
    static function backAction(rec, captureMode as Lang.Boolean) as Lang.Symbol {
        if (rec == null || rec.session == null) {
            // With capture mode on there is something to do here besides
            // leaving: dump the packets that were just collected. Exit is the
            // second item, so BACK never traps the athlete in a menu.
            return captureMode ? :captureMenu : :exit;
        }
        if (rec.recording) { return :manualLap; }
        return :saveMenu;
    }

    function onBack() as Lang.Boolean {
        var app = Application.getApp();
        var action = backAction(app.recorder, app.ble != null && app.ble.captureMode);
        if (action == :exit) {
            return false;   // nothing to lose; leave the app
        }
        // While the timer runs BACK is the lap button, as on any Garmin watch.
        // Pause with START first to reach the save menu.
        perform(action);
        return true;
    }
}

class CaptureMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :dump) {
            new MainDelegate().dumpCapture();
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class SaveMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = Application.getApp();
        if (item.getId() == :dump) {
            new MainDelegate().dumpCapture();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
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
