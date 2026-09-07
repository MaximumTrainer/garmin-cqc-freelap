using Toybox.Application;
using Toybox.Graphics;
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

    // Is there anything worth putting in a menu on the idle screen?
    // The idle menu always has the course items in it, so it is always worth
    // opening once there is no session running.
    static function hasIdleMenu(app) as Lang.Boolean {
        return CourseMenu.canChoose(app.recorder);
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
        } else if (action == :idleMenu) {
            openIdleMenu();
        } else if (action == :dumpCapture) {
            dumpCapture();
        } else if (action == :rescan) {
            if (app.ble != null) { app.ble.rescan(); }
        } else if (action == :courseMenu) {
            if (refuseIfRecording(app)) { return; }
            openCourseMenu();
        } else if (action == :quickCourse) {
            if (refuseIfRecording(app)) { return; }
            openQuickCoursePicker();
        } else if (action == :forgetChip) {
            if (app.ble != null) {
                app.ble.forgetChip();
                app.setNotice(WatchUi.loadResource(Rez.Strings.ChipForgotten));
            }
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

    // Every matching chip in range, strongest first, so the athlete can pick
    // when the automatic choice is wrong.
    // The course belongs to the session once one is running: changing it now
    // would re-derive the distances of splits already written.
    hidden function refuseIfRecording(app) as Lang.Boolean {
        if (CourseMenu.canChoose(app.recorder)) { return false; }
        app.setNotice(WatchUi.loadResource(Rez.Strings.CourseLocked));
        WatchUi.requestUpdate();
        return true;
    }

    function openCourseMenu() as Void {
        var entries = CourseMenu.entries();
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.ChooseCourse) });
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as CourseEntry;
            menu.addItem(new WatchUi.MenuItem(entry.label(), entry.detail(), entry.index, null));
        }
        WatchUi.pushView(menu, new CourseMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function openQuickCoursePicker() as Void {
        var start = Settings.quickDistanceM();
        if (start <= 0) { start = 30; }
        WatchUi.pushView(new QuickCourseView(start), new QuickCourseDelegate(), WatchUi.SLIDE_UP);
    }

    hidden function openChooseChipMenu() as Void {
        var app = Application.getApp();
        if (app.ble == null) { return; }
        var menu = new WatchUi.Menu2({ :title => WatchUi.loadResource(Rez.Strings.ChooseChip) });
        var sorted = ChipChooser.sortByStrength(app.ble.candidates);
        for (var i = 0; i < sorted.size(); i++) {
            var candidate = sorted[i] as ChipCandidate;
            menu.addItem(new WatchUi.MenuItem(candidate.name,
                                              candidate.rssi.format("%d") + " dBm",
                                              candidate.name, null));
        }
        WatchUi.pushView(menu, new ChooseChipDelegate(sorted), WatchUi.SLIDE_UP);
    }

    function openIdleMenu() as Void {
        var app = Application.getApp();
        var menu = new WatchUi.Menu2({ :title => "Freelap" });
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.ChooseCourse),
                                          app.course != null ? app.course.name : null,
                                          :course, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.QuickCourse), null,
                                          :quick, null));
        if (app.ble != null && app.ble.gaveUp) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Rescan), null, :rescan, null));
        }
        if (app.ble != null && app.ble.candidates.size() > 1) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.ChooseChip), null, :choose, null));
        }
        if (app.ble != null && !app.ble.rememberedName.equals("")) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.ForgetChip),
                                              app.ble.rememberedName, :forget, null));
        }
        if (app.ble != null && app.ble.captureMode) {
            menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.DumpCapture), null, :dump, null));
        }
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.DumpSplits), null, :dumpSplits, null));
        menu.addItem(new WatchUi.MenuItem(WatchUi.loadResource(Rez.Strings.Exit), null, :exit, null));
        WatchUi.pushView(menu, new IdleMenuDelegate(), WatchUi.SLIDE_UP);
    }

    // Prints the rolling packet log to the CIQ console in the shape
    // tools/decode_capture.py reads, so a field capture can be pasted straight
    // into the decoder. Simulator only in practice: there is no console on a
    // watch, which is why the log is also written to storage on stop().
    function openChooseChip() as Void { openChooseChipMenu(); }

    // Prints the stored split log to the CIQ console, one JSON array per row,
    // in the shape tools/splits_to_csv.py reads. Reads it back from storage
    // rather than from the live recorder, so it works after an app restart -
    // which is the case that matters, since the console is only there in the
    // simulator and the athlete gets to it after the session.
    function dumpSplits() as Void {
        var app = Application.getApp();
        var log = new SplitLog();
        if (!log.restore(new StorageSink(), SPLIT_LOG_KEY)) {
            app.setNotice(WatchUi.loadResource(Rez.Strings.NoSplitLog));
            return;
        }
        System.println("--- freelap splits: " + log.size().format("%d") + " row(s), " +
                       log.dropped.format("%d") + " dropped of " + log.seen.format("%d") + " seen");
        for (var i = 0; i < log.size(); i++) {
            System.println(log.rowAsJson(i));
        }
        System.println("--- end");
        app.setNotice(log.size().format("%d") + " splits dumped");
    }

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
    // `idleMenu` is true when there is something to offer on the idle screen
    // besides leaving - a rescan after the app gave up on the chip, or a
    // capture dump. When there is not, BACK just exits: two presses to leave an
    // app that is doing nothing would be worse than the problem.
    static function backAction(rec, idleMenu as Lang.Boolean) as Lang.Symbol {
        if (rec == null || rec.session == null) {
            return idleMenu ? :idleMenu : :exit;
        }
        if (rec.recording) { return :manualLap; }
        return :saveMenu;
    }

    function onBack() as Lang.Boolean {
        var app = Application.getApp();
        var action = backAction(app.recorder, hasIdleMenu(app));
        if (action == :exit) {
            return false;   // nothing to lose; leave the app
        }
        // While the timer runs BACK is the lap button, as on any Garmin watch.
        // Pause with START first to reach the save menu.
        perform(action);
        return true;
    }
}

class IdleMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :dump) {
            new MainDelegate().dumpCapture();
        } else if (id == :rescan) {
            new MainDelegate().perform(:rescan);
        } else if (id == :forget) {
            new MainDelegate().perform(:forgetChip);
        } else if (id == :choose) {
            new MainDelegate().openChooseChip();
            return;   // the chooser replaces this menu
        } else if (id == :dumpSplits) {
            new MainDelegate().dumpSplits();
        } else if (id == :course) {
            new MainDelegate().perform(:courseMenu);
            return;
        } else if (id == :quick) {
            new MainDelegate().perform(:quickCourse);
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// Picking a chip by hand. The item id is the chip name, so the choice needs no
// index bookkeeping between the menu and the candidate list.
class ChooseChipDelegate extends WatchUi.Menu2InputDelegate {
    hidden var _candidates;

    function initialize(candidates as Lang.Array) {
        Menu2InputDelegate.initialize();
        _candidates = candidates;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = Application.getApp();
        var name = item.getId() as Lang.String;
        for (var i = 0; i < _candidates.size(); i++) {
            var candidate = _candidates[i] as ChipCandidate;
            if (candidate.name.equals(name) && app.ble != null) {
                app.ble.connectTo(candidate);
                break;
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// Picking one of the configured courses. The item id is the settings slot.
class CourseMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = Application.getApp();
        app.applyCourse(CourseMenu.select(item.getId() as Lang.Number));
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// Dialling a quick course: START + FINISH, 10-400 m in 5 m steps.
class QuickCourseView extends WatchUi.View {
    var metres = 30;

    function initialize(startMetres as Lang.Number) {
        View.initialize();
        metres = Settings.clampQuickDistance(startMetres);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.16, Graphics.FONT_TINY,
                    WatchUi.loadResource(Rez.Strings.QuickCourse), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h / 2, Graphics.FONT_NUMBER_MEDIUM, metres.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(w / 2, h * 0.68, Graphics.FONT_SMALL, "m", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, h * 0.80, Graphics.FONT_XTINY,
                    WatchUi.loadResource(Rez.Strings.QuickHint), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class QuickCourseDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }

    hidden function step(direction as Lang.Number) as Lang.Boolean {
        var view = quickView();
        if (view != null) {
            view.metres = CourseMenu.nextQuickDistance(view.metres, direction);
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onNextPage() as Lang.Boolean { return step(-1); }
    function onPreviousPage() as Lang.Boolean { return step(1); }

    function onSelect() as Lang.Boolean {
        var view = quickView();
        if (view != null) {
            var app = Application.getApp();
            app.applyCourse(CourseMenu.selectQuick(view.metres));
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onBack() as Lang.Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    hidden function quickView() as QuickCourseView? {
        var view = WatchUi.getCurrentView()[0];
        return view instanceof QuickCourseView ? view : null;
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
