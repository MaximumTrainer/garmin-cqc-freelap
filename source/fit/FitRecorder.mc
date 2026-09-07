using Toybox.ActivityRecording;
using Toybox.Application;
using Toybox.FitContributor as Fit;
using Toybox.Lang;
using Toybox.Timer;

// Owns the ActivityRecording.Session and all developer fields.
//
// Field ids are the app's own namespace. IMPORTANT: Field objects must stay
// referenced at class scope for the life of the session, otherwise the SDK
// silently drops them (known FitContributor gotcha).
const SPLIT_LOG_KEY = "lastSessionSplits";

// fl_chip_idx on a record with no split on it. 255 rather than 0, which is a
// real chip slot.
const UNKNOWN_CHIP_SLOT = 255;

class FitRecorder {
    // A backstop, not a working limit. The queue drains at one record per
    // second and a rep is a handful of crossings, so a recording session never
    // approaches this. A *paused* session is the case that matters: nothing
    // drains while the chip keeps pushing, and without a cap that is unbounded
    // growth in the one state where nothing empties it.
    static const MAX_QUEUE = 400;

    // Record-level (per 1 Hz record)
    var fSplitUs;  var fCumUs;   var fDistM;   var fVel;   var fSpeed;
    var fPace;     var fTxIdx;   var fTxCode;  var fRep;   var fEstMs;
    var fChipIdx;
    // Lap-level (one Garmin lap per Freelap rep)
    var lRepUs;    var lRepDist; var lAvgVel;  var lPeakVel; var lSplits; var lStatus;
    // Session-level
    var sReps;     var sBestUs;  var sTotDist; var sChipId;

    var session = null;
    var recording = false;
    var clearAfterWrite = true;
    var lapPerCrossing = false;

    // Work waiting for a tick, in arrival order: SplitEvents (one FIT record
    // each) interleaved with the RepSummary that closes the rep they belong
    // to. It has to be one queue rather than a split queue plus a pending-lap
    // slot, because reps can arrive faster than records drain - a chip that
    // buffered several reps pushes them together - and a single slot silently
    // drops every lap but the last.
    var _queue = [];
    var _lapDue = false;     // lap fields are set; addLap() is owed a tick
    var droppedFromQueue = 0;
    var _tick = null;
    var _wroteThisTick = false;
    var _log = new SplitLog();   // every split, for export; bounded
    var _engine = null;

    // The primary constructor: the flags are passed in, so the recorder runs
    // under `monkeydo /t` with no settings (AGENTS.md, "Inject, don't fetch").
    function initialize(clearFieldsAfterWrite as Lang.Boolean, lapOnEveryCrossing as Lang.Boolean) {
        clearAfterWrite = clearFieldsAfterWrite;
        lapPerCrossing = lapOnEveryCrossing;
    }

    // The convenience entry point the app layer uses.
    static function fromSettings() as FitRecorder {
        return new FitRecorder(Settings.clearAfterWrite(), Settings.lapPerCrossing());
    }

    function start(engine as SplitEngine) as Void {
        startWith(ActivityRecording.createSession({
            :name => "Freelap",
            :sport => ActivityRecording.SPORT_RUNNING,      // Activity.SPORT_* needs API 3.2
            :subSport => ActivityRecording.SUB_SPORT_TRACK
        }), engine, true);
    }

    // The seam. Everything below this line works against any object answering
    // createField / start / stop / addLap / save / discard, which is what
    // source-test/fakes/FakeSession.mc is: the double stands in for the
    // session, not for Toybox.FitContributor.
    //
    // driveTimer is false under test — the drain is called by hand, one tick
    // per FIT record, rather than waiting a second per split.
    function startWith(s, engine as SplitEngine, driveTimer as Lang.Boolean) as Void {
        _engine = engine;
        session = s;
        _queue = [];
        _lapDue = false;
        _wroteThisTick = false;
        droppedFromQueue = 0;
        _log.clear();
        createFields();
        session.start();
        recording = true;
        engine.onSessionStart();
        if (driveTimer) {
            _tick = new Timer.Timer();
            _tick.start(method(:onTick), 1000, true);   // aligned to record cadence
        }
    }

    function createFields() as Void {
        var R = { :mesgType => Fit.MESG_TYPE_RECORD };
        fSplitUs = session.createField("fl_split_us", 0, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_RECORD, :units => "us" });
        fCumUs   = session.createField("fl_cum_us",   1, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_RECORD, :units => "us" });
        fDistM   = session.createField("fl_dist_m",   2, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_RECORD, :units => "m" });
        fVel     = session.createField("fl_velocity", 3, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_RECORD, :units => "m/s" });
        fSpeed   = session.createField("fl_speed",    4, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_RECORD, :units => "km/h" });
        fPace    = session.createField("fl_pace",     5, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_RECORD, :units => "s/km" });
        fTxIdx   = session.createField("fl_tx_idx",   6, Fit.DATA_TYPE_UINT8,  R);
        fTxCode  = session.createField("fl_tx_code",  7, Fit.DATA_TYPE_UINT8,  R);
        fRep     = session.createField("fl_rep",      8, Fit.DATA_TYPE_UINT16, R);
        fEstMs   = session.createField("fl_est_ms",   9, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_RECORD, :units => "ms" });
        // Which chip this split came from, as a slot into the session's
        // fl_chip_id list. A uint8 rather than the id itself: a 16-byte string
        // on every 1 Hz record would be ~115 KB of FIT file over two hours, to
        // repeat the same handful of values.
        fChipIdx = session.createField("fl_chip_idx", 10, Fit.DATA_TYPE_UINT8, R);

        lRepUs   = session.createField("fl_rep_time_us", 20, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_LAP, :units => "us" });
        lRepDist = session.createField("fl_rep_dist_m",  21, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_LAP, :units => "m" });
        lAvgVel  = session.createField("fl_rep_avg_vel", 22, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_LAP, :units => "m/s" });
        lPeakVel = session.createField("fl_rep_peak_vel",23, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_LAP, :units => "m/s" });
        lSplits  = session.createField("fl_rep_splits",  24, Fit.DATA_TYPE_UINT8,  { :mesgType => Fit.MESG_TYPE_LAP });
        lStatus  = session.createField("fl_rep_status",  25, Fit.DATA_TYPE_UINT8,  { :mesgType => Fit.MESG_TYPE_LAP });

        sReps    = session.createField("fl_reps",         40, Fit.DATA_TYPE_UINT16, { :mesgType => Fit.MESG_TYPE_SESSION });
        sBestUs  = session.createField("fl_best_rep_us",  41, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_SESSION, :units => "us" });
        sTotDist = session.createField("fl_total_dist_m", 42, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_SESSION, :units => "m" });
        // Comma-separated, in slot order, so fl_chip_idx on a record resolves
        // to a chip. One chip reads exactly as it did before.
        sChipId  = session.createField("fl_chip_id",      43, Fit.DATA_TYPE_STRING, { :mesgType => Fit.MESG_TYPE_SESSION, :count => 64 });
    }

    // ---- SplitEngine listener --------------------------------------------
    function onSplit(ev as SplitEvent) as Void {
        enqueue(ev);
        _log.add(ev.toArray());
    }

    function onRepComplete(r as RepSummary) as Void {
        // Queued behind the rep's own splits, so the lap cannot be cut before
        // every one of its records is on disk.
        enqueue(r);
    }

    // Oldest first out, so what survives is what has not been written yet.
    hidden function enqueue(item) as Void {
        _queue.add(item);
        while (_queue.size() > MAX_QUEUE) {
            _queue = _queue.slice(1, null);
            droppedFromQueue++;
        }
    }

    function queueSize() as Lang.Number { return _queue.size(); }

    function log() as SplitLog { return _log; }

    // ---- 1 Hz tick: drain one split per record --------------------------
    // Exactly one of three things happens per tick, in this order: close a lap
    // that is owed one, write the next record, or blank the record fields.
    function onTick() as Void {
        if (!recording) { return; }

        if (_lapDue) {
            // The lap's fields were set on an earlier tick. The gap is the
            // whole point: setData() and addLap() in one pass and the lap's
            // developer fields never reach the file (DESIGN.md §5).
            session.addLap();
            _lapDue = false;
            return;
        }

        if (_queue.size() > 0) {
            drainOne();
            return;
        }

        if (_wroteThisTick && clearAfterWrite) {
            clearRecord();
            _wroteThisTick = false;
        }
    }

    // Nothing left to write, no lap owed, nothing left to blank.
    function isIdle() as Lang.Boolean {
        return _queue.size() == 0 && !_lapDue && !(_wroteThisTick && clearAfterWrite);
    }

    hidden function drainOne() as Void {
        var item = _queue[0];
        _queue = _queue.slice(1, null);

        if (item instanceof RepSummary) {
            armLapForRep(item as RepSummary);
            return;
        }

        var ev = item as SplitEvent;
        writeRecord(ev);
        _wroteThisTick = true;

        if (lapPerCrossing) {
            armLapForSplit(ev);
            return;
        }

        // If this split is the last of its rep, set the lap fields in the same
        // pass as the record. Only addLap() has to wait for a tick, and doing
        // it here means a rep does not cost an extra, duplicate record.
        if (_queue.size() > 0 && _queue[0] instanceof RepSummary) {
            var rep = _queue[0] as RepSummary;
            _queue = _queue.slice(1, null);
            armLapForRep(rep);
        }
    }

    hidden function armLapForRep(r as RepSummary) as Void {
        if (lapPerCrossing) { return; }   // a lap was already cut per crossing
        lRepUs.setData(r.timeUs);
        lRepDist.setData(r.distM);
        lAvgVel.setData(r.avgVelMps);
        lPeakVel.setData(r.peakVelMps);
        lSplits.setData(r.splits);
        lStatus.setData(r.status);
        _lapDue = true;
    }

    // With lapPerCrossing the lap *is* the split, so the rep-level fields
    // carry that split's own numbers rather than the previous rep's leftovers.
    hidden function armLapForSplit(ev as SplitEvent) as Void {
        lRepUs.setData(ev.splitTimeUs);
        lRepDist.setData(ev.splitDistM);
        lAvgVel.setData(ev.velocityMps);
        lPeakVel.setData(ev.velocityMps);
        lSplits.setData(1);
        lStatus.setData(ev.txIndex < 0 ? RepStatus.UNMATCHED : RepStatus.OK);
        _lapDue = true;
    }

    function writeRecord(ev as SplitEvent) as Void {
        fSplitUs.setData(ev.splitTimeUs);
        fCumUs.setData(ev.cumTimeUs);
        fDistM.setData(ev.cumDistM);
        fVel.setData(ev.velocityMps);
        fSpeed.setData(ev.speedKmh);
        fPace.setData(ev.paceSecPerKm);
        fTxIdx.setData(ev.txIndex < 0 ? 255 : ev.txIndex);
        fTxCode.setData(ev.txCode);
        fRep.setData(ev.rep);
        fChipIdx.setData(ev.chipSlot);
        fEstMs.setData(ev.estSessionMs);   // already clamped by the engine
    }

    function clearRecord() as Void {
        fSplitUs.setData(0); fCumUs.setData(0); fDistM.setData(0.0);
        fVel.setData(0.0); fSpeed.setData(0.0); fPace.setData(0.0);
        fTxIdx.setData(255); fTxCode.setData(0); fRep.setData(0); fEstMs.setData(0);
        fChipIdx.setData(UNKNOWN_CHIP_SLOT);
    }

    // ---- manual lap (BACK/LAP button) -----------------------------------
    // False when there was nothing to end. The caller says so on screen: a
    // button that silently does nothing gets pressed again, and again.
    function manualLap() as Lang.Boolean {
        if (_engine == null) { return false; }
        return _engine.forceRepEnd();
    }

    // ---- stop / save -----------------------------------------------------
    function stop() as Void {
        if (session != null && recording) { session.stop(); }
        recording = false;
    }

    function resume() as Void {
        if (session != null && !recording) { session.start(); recording = true; }
    }

    // Flush any queued splits, write the session summary and save.
    // Session-level developer fields are flushed by save() itself; record
    // fields queued but not yet ticked out are written in a final burst here.
    function save() as Void {
        if (session == null) { return; }
        if (_tick != null) { _tick.stop(); }
        if (!recording) { session.start(); recording = true; }   // must be running to write
        // Drain everything still queued. There is no further tick to yield on
        // here, so the lap fields and addLap() go in one pass - the documented
        // risk in DESIGN.md §5, taken deliberately because the alternative is
        // losing the rep altogether.
        while (_queue.size() > 0) {
            drainOne();
            if (_lapDue) { session.addLap(); _lapDue = false; }
        }
        if (_lapDue) { session.addLap(); _lapDue = false; }
        if (_engine != null) {
            sReps.setData(_engine.repsDone);
            sBestUs.setData(_engine.bestRepUs);
            sTotDist.setData(_engine.totalDistM);
        }
        var chips = _engine != null ? _engine.roster.idList() : "";
        sChipId.setData(chips.equals("") ? "unknown" : chips);
        _log.flush(new StorageSink(), SPLIT_LOG_KEY);
        session.stop();
        session.save();
        session = null;
        recording = false;
    }

    function discard() as Void {
        if (_tick != null) { _tick.stop(); }
        if (session != null) { session.discard(); session = null; }
        recording = false;
    }
}
