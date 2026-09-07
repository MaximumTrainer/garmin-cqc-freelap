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
    var repNumber = 0;
    var current = [];            // SplitEvents of the rep in progress
    var listener;                // object with onSplit(ev) and onRepComplete(rep)
    var sessionStartTimerMs = 0; // System.getTimer() at session start
    var bleLatencyMs = 150;
    var bestRepUs = 0;
    var totalDistM = 0.0;
    var repsDone = 0;
    var repStartChipUs = 0l;     // chip time (Long) of the START crossing (streaming mode)
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
        repNumber++;
        current = [];
        var t0 = crossings[0].timeUs;
        var tLast = crossings[crossings.size() - 1].timeUs;
        var repTimeUs = (tLast - t0).toNumber();   // Long -> Number once relative
        // Estimated wall-clock of FINISH, in ms since session start.
        var finishEstMs = (arrivalTimerMs - bleLatencyMs) - sessionStartTimerMs;

        var prev = null as SplitEvent?;
        for (var i = 0; i < crossings.size(); i++) {
            var cr = crossings[i];
            var ev = new SplitEvent();
            ev.rep = repNumber;
            ev.txCode = cr.code;
            ev.chipId = cr.chipId;
            ev.txIndex = course.matchCrossing(i, cr.code);
            ev.cumTimeUs = (cr.timeUs - t0).toNumber();
            ev.cumDistM = ev.txIndex >= 0 ? course.distances[ev.txIndex] : (prev != null ? prev.cumDistM : 0.0);
            ev.arrivalTimerMs = arrivalTimerMs;
            // Work back from the FINISH: every earlier crossing sits its own
            // split before it, so the gaps between estimates are the chip's
            // durations rather than an even spread.
            placeEstimate(ev, finishEstMs - ((repTimeUs - ev.cumTimeUs) / 1000));
            ev.derive(prev);
            current.add(ev);
            prev = ev;
            lastEvent = ev;
            if (listener != null) { listener.onSplit(ev); }
        }
        finishRep();
    }

    // Streaming variant: one crossing at a time (if the chip notifies per
    // crossing). A START code, or a FINISH, delimits reps.
    function onCrossing(cr, arrivalTimerMs as Lang.Number) as Void {
        if (cr.code == TxCode.START || current.size() == 0) {
            if (current.size() > 0) { finishRep(); }
            repNumber++;
            current = [];
            repStartChipUs = cr.timeUs;
        }
        var prev = current.size() > 0 ? current[current.size() - 1] : null;
        var ev = new SplitEvent();
        ev.rep = repNumber;
        ev.txCode = cr.code;
        ev.chipId = cr.chipId;
        ev.txIndex = course.matchCrossing(current.size(), cr.code);
        ev.cumTimeUs = (cr.timeUs - repStartChipUs).toNumber();
        ev.cumDistM = ev.txIndex >= 0 ? course.distances[ev.txIndex] : (prev != null ? prev.cumDistM : 0.0);
        ev.arrivalTimerMs = arrivalTimerMs;
        placeEstimate(ev, (arrivalTimerMs - bleLatencyMs) - sessionStartTimerMs);
        ev.derive(prev);
        current.add(ev);
        lastEvent = ev;
        if (listener != null) { listener.onSplit(ev); }
        if (cr.code == TxCode.FINISH) { finishRep(); }
    }

    // Returns true when a rep was actually closed, so the caller can tell the
    // athlete that the button did nothing rather than leaving them pressing it.
    function finishRep() as Lang.Boolean {
        if (current.size() == 0) { return false; }
        var r = new RepSummary();
        r.rep = repNumber;
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
        current = [];
        lastRep = r;
        if (listener != null) { listener.onRepComplete(r); }
        return true;
    }

    // Manual lap button: close the rep with what we have.
    function forceRepEnd() as Lang.Boolean { return finishRep(); }
}
