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
class FitRecorder {
    // Record-level (per 1 Hz record)
    var fSplitUs;  var fCumUs;   var fDistM;   var fVel;   var fSpeed;
    var fPace;     var fTxIdx;   var fTxCode;  var fRep;   var fEstMs;
    // Lap-level (one Garmin lap per Freelap rep)
    var lRepUs;    var lRepDist; var lAvgVel;  var lPeakVel; var lSplits; var lStatus;
    // Session-level
    var sReps;     var sBestUs;  var sTotDist; var sChipId;

    var session = null;
    var recording = false;
    var clearAfterWrite = true;
    var lapPerCrossing = false;

    var _queue = [];         // SplitEvents waiting to be written, one per record tick
    var _pendingLap = null;  // RepSummary whose lap fields are set, awaiting addLap()
    var _tick = null;
    var _wroteThisTick = false;
    var _log = [];           // all SplitEvent arrays for storage export
    var _chipId = "";
    var _engine = null;

    function initialize() {
        var app = Application.getApp();
        var c = app.getProperty("clearAfterWrite");
        if (c != null) { clearAfterWrite = c; }
        var l = app.getProperty("lapPerCrossing");
        if (l != null) { lapPerCrossing = l; }
    }

    function start(engine as SplitEngine) as Void {
        _engine = engine;
        session = ActivityRecording.createSession({
            :name => "Freelap",
            :sport => ActivityRecording.SPORT_RUNNING,      // Activity.SPORT_* needs API 3.2
            :subSport => ActivityRecording.SUB_SPORT_TRACK
        });
        createFields();
        session.start();
        recording = true;
        engine.onSessionStart();
        _tick = new Timer.Timer();
        _tick.start(method(:onTick), 1000, true);   // aligned to record cadence
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

        lRepUs   = session.createField("fl_rep_time_us", 20, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_LAP, :units => "us" });
        lRepDist = session.createField("fl_rep_dist_m",  21, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_LAP, :units => "m" });
        lAvgVel  = session.createField("fl_rep_avg_vel", 22, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_LAP, :units => "m/s" });
        lPeakVel = session.createField("fl_rep_peak_vel",23, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_LAP, :units => "m/s" });
        lSplits  = session.createField("fl_rep_splits",  24, Fit.DATA_TYPE_UINT8,  { :mesgType => Fit.MESG_TYPE_LAP });
        lStatus  = session.createField("fl_rep_status",  25, Fit.DATA_TYPE_UINT8,  { :mesgType => Fit.MESG_TYPE_LAP });

        sReps    = session.createField("fl_reps",         40, Fit.DATA_TYPE_UINT16, { :mesgType => Fit.MESG_TYPE_SESSION });
        sBestUs  = session.createField("fl_best_rep_us",  41, Fit.DATA_TYPE_UINT32, { :mesgType => Fit.MESG_TYPE_SESSION, :units => "us" });
        sTotDist = session.createField("fl_total_dist_m", 42, Fit.DATA_TYPE_FLOAT,  { :mesgType => Fit.MESG_TYPE_SESSION, :units => "m" });
        sChipId  = session.createField("fl_chip_id",      43, Fit.DATA_TYPE_STRING, { :mesgType => Fit.MESG_TYPE_SESSION, :count => 16 });
    }

    // ---- SplitEngine listener --------------------------------------------
    function onSplit(ev as SplitEvent) as Void {
        _queue.add(ev);
        _log.add(ev.toArray());
        if (!ev.chipId.equals("")) { _chipId = ev.chipId; }
    }

    function onRepComplete(r as RepSummary) as Void {
        // Lap fields are set now; addLap() is deferred to a later tick so the
        // FIT writer has flushed them (see DESIGN.md §5 caveat).
        lRepUs.setData(r.timeUs);
        lRepDist.setData(r.distM);
        lAvgVel.setData(r.avgVelMps);
        lPeakVel.setData(r.peakVelMps);
        lSplits.setData(r.splits);
        lStatus.setData(r.status);
        _pendingLap = r;
    }

    // ---- 1 Hz tick: drain one split per record --------------------------
    function onTick() as Void {
        if (!recording) { return; }
        if (_queue.size() > 0) {
            var ev = _queue[0];
            _queue = _queue.slice(1, null);
            writeRecord(ev);
            _wroteThisTick = true;
            if (lapPerCrossing) { session.addLap(); }
        } else if (_wroteThisTick && clearAfterWrite) {
            clearRecord();
            _wroteThisTick = false;
        } else if (_pendingLap != null && _queue.size() == 0) {
            // All splits of the rep are on disk; close the Garmin lap.
            if (!lapPerCrossing) { session.addLap(); }
            _pendingLap = null;
        }
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
        fEstMs.setData(ev.estSessionMs < 0 ? 0 : ev.estSessionMs);
    }

    function clearRecord() as Void {
        fSplitUs.setData(0); fCumUs.setData(0); fDistM.setData(0.0);
        fVel.setData(0.0); fSpeed.setData(0.0); fPace.setData(0.0);
        fTxIdx.setData(255); fTxCode.setData(0); fRep.setData(0); fEstMs.setData(0);
    }

    // ---- manual lap (BACK/LAP button) -----------------------------------
    function manualLap() as Void {
        if (_engine != null) { _engine.forceRepEnd(); }
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
        while (_queue.size() > 0) {
            writeRecord(_queue[0]);
            _queue = _queue.slice(1, null);
        }
        if (_pendingLap != null) { session.addLap(); _pendingLap = null; }
        if (_engine != null) {
            sReps.setData(_engine.repsDone);
            sBestUs.setData(_engine.bestRepUs);
            sTotDist.setData(_engine.totalDistM);
        }
        sChipId.setData(_chipId.equals("") ? "unknown" : _chipId);
        Application.Storage.setValue("lastSessionSplits", _log);
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
