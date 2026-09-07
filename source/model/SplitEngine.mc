using Toybox.Lang;
using Toybox.System;

// Rep status values written to fl_rep_status.
module RepStatus {
    const OK        = 0;
    const UNMATCHED = 1;
    const PARTIAL   = 2;
}

// A completed rep (START..FINISH) with totals.
class RepSummary {
    var rep = 0;
    var chipId = "";
    var chipSlot = 0;
    var timeUs = 0;
    var distM = 0.0;
    var avgVelMps = 0.0;
    var peakVelMps = 0.0;
    var splits = 0;
    var status = RepStatus.OK;
    var events = [];  // Array<SplitEvent>
}

// Turns decoded crossings into SplitEvents and reps.
// Input: FreelapProtocol.Crossing objects (chip-relative time in us + code).
// Output: callbacks onSplit(SplitEvent) and onRepComplete(RepSummary).
class SplitEngine {
    // Used when the setting is missing; mirrors properties.xml.
    static const DEFAULT_LATENCY_MS = 150;

    var course;
    var repNumber = 0;           // the most recently *started* rep, any chip
    var current = [];            // SplitEvents of the rep in progress (last chip heard)
    var roster = new ChipRoster();
    var listener;                // object with onSplit(ev) and onRepComplete(rep)
    // An optional second listener for the UI. Always notified *after* the
    // recorder: the FIT file matters more than the screen, so nothing the
    // screen does can come between a rep finishing and its splits being
    // queued for the file.
    var observer = null;
    var sessionStartTimerMs = 0; // System.getTimer() at session start
    var bleLatencyMs = 150;
    var bestRepUs = 0;
    var totalDistM = 0.0;
    var repsDone = 0;
    var lastEvent = null;        // for the UI
    var lastRep = null;
    var clampedEstimates = 0;    // crossings that could not be placed on the timeline

    // The primary constructor: everything the engine needs is passed in, so
    // the whole class runs under `monkeydo /t` with no settings and no radio
    // (AGENTS.md, "Inject, don't fetch").
    function initialize(c as Course, l, latencyMs as Lang.Number) {
        course = c;
        listener = l;
        bleLatencyMs = latencyMs;
    }

    // The convenience entry point the app layer uses.
    static function fromSettings(c as Course, l) as SplitEngine {
        return new SplitEngine(c, l, Settings.bleLatencyMs());
    }

    function onSessionStart() as Void {
        onSessionStartAt(System.getTimer());
    }

    // The testable form. System.getTimer() is the one clock this class reads,
    // and reading it makes every estimate below untestable, so the app layer
    // passes it in and onSessionStart() is the convenience that fetches it
    // (AGENTS.md, "Inject, don't fetch").
    function onSessionStartAt(timerMs as Lang.Number) as Void {
        sessionStartTimerMs = timerMs;
        repNumber = 0; current = []; bestRepUs = 0; totalDistM = 0.0; repsDone = 0;
        clampedEstimates = 0;
        roster.clear();
    }

    // Place a crossing on the session timeline, or admit that we cannot.
    //
    // A negative offset is not a time. It happens for real: the chip buffers,
    // so starting the watch part-way through a rep gives crossings that
    // genuinely predate the session. Clamping to 0 keeps fl_est_ms a valid
    // uint32; the flag is what stops that 0 being read as a measurement.
    hidden function placeEstimate(ev as SplitEvent, estMs as Lang.Number) as Void {
        if (estMs < 0) {
            ev.estSessionMs = 0;
            ev.estClamped = true;
            clampedEstimates++;
        } else {
            ev.estSessionMs = estMs;
            ev.estClamped = false;
        }
    }

    // A burst of crossings for one rep, delivered together (the FxChip BLE
    // pushes the whole rep at FINISH). Crossings must be in chip-time order.
    // arrivalTimerMs = System.getTimer() when the packet arrived.
    function onRepBurst(crossings as Lang.Array, arrivalTimerMs as Lang.Number) as Void {
        if (crossings.size() == 0) { return; }

        // Rep numbering is per chip: with a Relay Coach, two athletes running
        // alternately would otherwise be numbered 1, 2, 3, 4 between them and
        // every rep attributed to whoever crossed next.
        var chip = roster.forChip(crossings[0].chipId);
        if (chip == null) { return; }   // roster full; see ChipRoster.MAX_CHIPS
        chip.repNumber++;
        chip.current = [];
        repNumber = chip.repNumber;
        current = chip.current;
        var t0 = crossings[0].timeUs;
        var tLast = crossings[crossings.size() - 1].timeUs;
        var repTimeUs = (tLast - t0).toNumber();   // Long -> Number once relative
        // Estimated wall-clock of FINISH, in ms since session start.
        var finishEstMs = (arrivalTimerMs - bleLatencyMs) - sessionStartTimerMs;

        var prev = null as SplitEvent?;
        for (var i = 0; i < crossings.size(); i++) {
            var cr = crossings[i];
            var ev = new SplitEvent();
            ev.rep = chip.repNumber;
            ev.txCode = cr.code;
            ev.chipId = cr.chipId;
            ev.chipSlot = chip.slot;
            ev.txIndex = course.matchCrossing(i, cr.code);
            ev.cumTimeUs = (cr.timeUs - t0).toNumber();
            ev.cumDistM = ev.txIndex >= 0 ? course.distances[ev.txIndex] : (prev != null ? prev.cumDistM : 0.0);
            ev.arrivalTimerMs = arrivalTimerMs;
            // Work back from the FINISH: every earlier crossing sits its own
            // split before it, so the gaps between estimates are the chip's
            // durations rather than an even spread.
            placeEstimate(ev, finishEstMs - ((repTimeUs - ev.cumTimeUs) / 1000));
            ev.derive(prev);
            chip.current.add(ev);
            prev = ev;
            lastEvent = ev;
            if (listener != null) { listener.onSplit(ev); }
        }
        current = chip.current;
        finishRep(chip);
    }

    // Streaming variant: one crossing at a time (if the chip notifies per
    // crossing). A START code, or a FINISH, delimits reps.
    function onCrossing(cr, arrivalTimerMs as Lang.Number) as Void {
        var chip = roster.forChip(cr.chipId);
        if (chip == null) { return; }

        if (cr.code == TxCode.START || chip.current.size() == 0) {
            if (chip.current.size() > 0) { finishRep(chip); }
            chip.repNumber++;
            chip.current = [];
            chip.repStartChipUs = cr.timeUs;
        }
        repNumber = chip.repNumber;

        var prev = chip.current.size() > 0 ? chip.current[chip.current.size() - 1] : null;
        var ev = new SplitEvent();
        ev.rep = chip.repNumber;
        ev.txCode = cr.code;
        ev.chipId = cr.chipId;
        ev.chipSlot = chip.slot;
        ev.txIndex = course.matchCrossing(chip.current.size(), cr.code);
        ev.cumTimeUs = (cr.timeUs - chip.repStartChipUs).toNumber();
        ev.cumDistM = ev.txIndex >= 0 ? course.distances[ev.txIndex] : (prev != null ? prev.cumDistM : 0.0);
        ev.arrivalTimerMs = arrivalTimerMs;
        placeEstimate(ev, (arrivalTimerMs - bleLatencyMs) - sessionStartTimerMs);
        ev.derive(prev);
        chip.current.add(ev);
        current = chip.current;
        lastEvent = ev;
        if (listener != null) { listener.onSplit(ev); }
        if (cr.code == TxCode.FINISH) { finishRep(chip); }
    }

    // Returns true when a rep was actually closed, so the caller can tell the
    // athlete that the button did nothing rather than leaving them pressing it.
    // Close the rep in progress for `chip`. With one chip this is the only rep
    // there is; with several, each has its own.
    function finishRep(chip as ChipState?) as Lang.Boolean {
        if (chip == null) { return false; }
        var current = chip.current;
        if (current.size() == 0) { return false; }
        var r = new RepSummary();
        r.rep = chip.repNumber;
        r.chipId = chip.id;
        r.chipSlot = chip.slot;
        r.events = current;
        r.splits = current.size();
        var last = current[current.size() - 1];
        r.timeUs = last.cumTimeUs;
        // The rep's distance is the last transmitter the course could actually
        // place. A trailing crossing the course does not know about (an extra
        // lap, a stray transmitter) carries no distance of its own, and must
        // not be allowed to invent one for the rep.
        r.distM = 0.0;
        r.peakVelMps = 0.0;
        var unmatched = false;
        for (var i = 0; i < current.size(); i++) {
            if (current[i].velocityMps > r.peakVelMps) { r.peakVelMps = current[i].velocityMps; }
            if (current[i].txIndex < 0) { unmatched = true; }
            else { r.distM = current[i].cumDistM; }
        }
        r.avgVelMps = r.timeUs > 0 ? r.distM / (r.timeUs / 1000000.0) : 0.0;

        var endsOnFinish = course.size() > 0 && course.codes[course.size() - 1] == TxCode.FINISH;
        if (unmatched) { r.status = RepStatus.UNMATCHED; }
        else if (endsOnFinish && last.txCode != TxCode.FINISH) { r.status = RepStatus.PARTIAL; }
        else if (current.size() < course.size()) { r.status = RepStatus.PARTIAL; }

        repsDone++;
        totalDistM += r.distM;
        if (r.status == RepStatus.OK && (bestRepUs == 0 || r.timeUs < bestRepUs)) { bestRepUs = r.timeUs; }
        chip.current = [];
        current = chip.current;
        lastRep = r;
        if (listener != null) { listener.onRepComplete(r); }
        if (observer != null) { observer.onRepComplete(r); }
        return true;
    }

    // Manual lap button: close whichever rep is in progress. With several
    // chips this is the one the last crossing belonged to - the athlete
    // pressing the button is the one who just ran.
    function forceRepEnd() as Lang.Boolean {
        return finishRep(chipOfLastCrossing());
    }

    hidden function chipOfLastCrossing() as ChipState? {
        if (lastEvent == null) { return roster.at(0); }
        return roster.at(lastEvent.chipSlot);
    }
}
