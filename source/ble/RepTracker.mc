using Toybox.Lang;

// One rep, as the chip reported it.
class BroadcastRep {

    var chip as Lang.String = "";
    var lapNumber as Lang.Number = 0;

    // Ticks. Converted once, by whoever displays or records them - converting
    // early and adding up the results accumulates error, because the chip's
    // tick is not a decimal fraction of a second.
    var segments as Lang.Array<Lang.Number> = [];
    var cumulative as Lang.Array<Lang.Number> = [];
    var totalTicks as Lang.Number = 0;

    function initialize() {}

    // Microseconds per tick is 1000000/1024 = 15625/16. Exact when the tick
    // count is a multiple of 16; otherwise the sub-microsecond residue is
    // truncated, as docs/EXPORT.md records. In a Long, because ticks * 15625
    // overflows a Number long before the counters do. tools/scenarios.py does
    // this identical integer arithmetic, which is what lets the scenario suite
    // assert the FIT values byte for byte rather than approximately.
    static function ticksToUs(ticks as Lang.Number) as Lang.Long {
        return ticks.toLong() * 15625l / 16l;
    }

    // The rep as the split engine consumes it: one Crossing per transmitter,
    // in chip-time order, START at the origin.
    //
    // The frame carries no transmitter codes - a lap number and an ordered
    // array of times, nothing that says which transmitter produced one - so
    // matching is ordinal: the first crossing is the START, the last is the
    // FINISH, everything between is a LAP. That is the physical model behind
    // the course spec and the LED colours the chip shows, applied by position
    // (#13). A missed transmitter therefore misattributes every later split;
    // the count of crossings against the configured course is the only check
    // available, and Course.matchCrossing surfaces a mismatch as an unmatched
    // index rather than a guess.
    function toCrossings() as Lang.Array {
        var out = [] as Lang.Array;
        if (cumulative.size() == 0) { return out; }     // no finish, no rep
        out.add(new Crossing(0l, TxCode.START, chip));
        var last = cumulative.size() - 1;
        for (var i = 0; i <= last; i++) {
            var code = (i == last) ? TxCode.FINISH : TxCode.LAP;
            out.add(new Crossing(ticksToUs(cumulative[i]), code, chip));
        }
        return out;
    }
}

// Which broadcasts are reps, and whose (issues #9 and #63).
//
// Under the connection model something told the app when a rep began and
// ended. Nothing does now. The watch hears a stream of advertisements - most
// of them repeats of a rep it already has, some of them other athletes' chips -
// and has to work out on its own which are reps and whether any are missing.
//
// Every decision here is made from frame content rather than from a clock,
// which is both more robust and the reason this is testable without a radio.
// The chip is inject-not-fetched (AGENTS.md): the app layer passes the bound
// id in, so a test can bind to anything without touching settings.
class RepTracker {

    // How many recently accepted finish timestamps to remember. Advertising
    // windows overlap in the air and Connect IQ delivers scan results in
    // batches, so a frame from the previous rep can arrive after the current
    // one has been recorded; without this, that older frame reads as a new
    // rep or a chip restart.
    //
    // Small on purpose. This runs in the scan callback, which at a track fires
    // constantly (#9, #26), and an unbounded history of a 60-rep session is
    // exactly the kind of quiet growth #19 was opened for.
    static const RECENT = 8;

    var boundChipId as Lang.String;
    var mask as Lang.Long;

    var repsSeen as Lang.Number = 0;
    var missedReps as Lang.Number = 0;

    // Frames from our chip that carried no rep: zeroed counters, or a finish
    // that is not after its start. A shaken chip in discoverable mode sends
    // exactly this (#81). Counted so that "heard, but idle" and "never heard"
    // can be told apart on screen - they call for different advice (#9).
    var idleFrames as Lang.Number = 0;

    hidden var lastLap = null;                     // Number, or null before the first
    hidden var recent as Lang.Array<Lang.Long> = [];   // finish timestamps

    function initialize(chipId as Lang.String, laneMask as Lang.Long) {
        boundChipId = chipId;
        mask = laneMask;
    }

    function isBound() as Lang.Boolean {
        return !boundChipId.equals("");
    }

    // Point the tracker at a different chip and forget the old one's counters.
    // A Garmin Connect sync can rebind mid-session (#64), and the previous
    // chip's lap numbers must not surface as gaps on the new one.
    function bindTo(chipId as Lang.String) as Void {
        boundChipId = chipId;
        reset();
    }

    function reset() as Void {
        repsSeen = 0;
        missedReps = 0;
        idleFrames = 0;
        lastLap = null;
        recent = [];
    }

    // A decoded advertisement and its scan-response laps in, a rep out - or
    // null, which is the common case and never an error. `laps` may be null:
    // if the watch turns out not to be able to read scan responses at all
    // (#60), every rep arrives with only its total, and that still works.
    function onFrame(advertisement, laps) as BroadcastRep? {
        if (advertisement == null) { return null; }
        if (!isBound()) { return null; }
        if (!advertisement.chip().equals(boundChipId)) { return null; }

        // A rep is a finish that comes after a start. Zero counters are the
        // discoverable-mode frame; a finish before its start is a wrapped
        // counter. Neither is a rep, and neither may touch the sequence
        // tracking below - a shaken chip between two reps is not a repeat, a
        // gap or a restart. This guard is deliberate and lives here, at the
        // decision, rather than being an accident of the decoder's identity
        // check (#81).
        if (advertisement.block == 0l || advertisement.split(mask) <= 0) {
            idleFrames++;
            return null;
        }

        // What makes two frames the same rep is the finish timestamp. It is
        // chip uptime: identical across every repeat of a rep's window,
        // different for every new crossing of the line, and it needs no
        // assumption about any other field (#80).
        //
        // It is deliberately NOT the lap-number byte. No vendor document says
        // what that byte counts - it is 0 in the only worked example - and a
        // tracker keyed on it would, if the byte never incremented, drop every
        // rep after the first of a session as a repeat, with the first one
        // looking perfect.
        var finish = advertisement.block;
        if (isRecent(finish)) { return null; }

        var lapNumber = advertisement.lapNumber;
        countTheGapBefore(lapNumber);          // advisory only - see below
        remember(finish);
        lastLap = lapNumber;
        repsSeen++;

        var found = laps == null ? [] : laps;
        var out = new BroadcastRep();
        out.chip = advertisement.chip();
        out.lapNumber = lapNumber;
        out.segments = BroadcastFrame.segments(advertisement, found, mask);
        out.cumulative = BroadcastFrame.cumulative(advertisement, found, mask);
        out.totalTicks = advertisement.split(mask);
        return out;
    }

    // Reps the watch never heard - as suggested by the lap-number byte.
    //
    // ADVISORY. This count is reported on screen and decides nothing: whether
    // a frame is accepted rests on its finish timestamp above, never on this.
    // It assumes the byte increments once per rep, which no document states;
    // if #5 run C shows otherwise, this becomes noise and should be removed
    // rather than trusted.
    //
    // Not necessarily lost: Freelap's manual says the chip keeps its latest
    // time in memory and re-sends it when shaken, until it sleeps, is charged,
    // or another rep replaces it. So the most recent miss can be asked for
    // again - which makes surfacing this far more useful than it looked. The
    // athlete can act on it, rather than only finding a hole that evening.
    //
    // Older misses are still gone; only one rep is held. Counted and surfaced
    // either way, never absorbed.
    hidden function countTheGapBefore(lapNumber as Lang.Number) as Void {
        if (lastLap == null) {
            // The chip has been counting since it was last charged, so the
            // first rep heard is routinely rep 37. That is not 37 missed.
            return;
        }

        var expected = (lastLap + 1) % 256;
        if (lapNumber == expected) { return; }

        if (lapNumber < lastLap) {
            // Backwards, and not a number we have seen recently: the chip was
            // charged or reset and is counting again from zero. Read as
            // arithmetic this is hundreds of missed reps, at the moment
            // everything is working.
            return;
        }

        missedReps += lapNumber - expected;
    }

    hidden function isRecent(finish as Lang.Long) as Lang.Boolean {
        for (var i = 0; i < recent.size(); i++) {
            if (recent[i] == finish) { return true; }
        }
        return false;
    }

    hidden function remember(finish as Lang.Long) as Void {
        recent.add(finish);
        if (recent.size() > RECENT) {
            recent = recent.slice(recent.size() - RECENT, null);
        }
    }
}
