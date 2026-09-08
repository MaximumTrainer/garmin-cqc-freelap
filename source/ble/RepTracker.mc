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

    // How many recently accepted lap numbers to remember. Advertising windows
    // overlap in the air and Connect IQ delivers scan results in batches, so a
    // frame from the previous rep can arrive after the current one has been
    // recorded; without this, that older frame reads as a chip restart.
    //
    // Small on purpose. This runs in the scan callback, which at a track fires
    // constantly (#9, #26), and an unbounded history of a 60-rep session is
    // exactly the kind of quiet growth #19 was opened for.
    static const RECENT = 8;

    var boundChipId as Lang.String;
    var mask as Lang.Long;

    var repsSeen as Lang.Number = 0;
    var missedReps as Lang.Number = 0;

    hidden var lastLap = null;                     // Number, or null before the first
    hidden var recent as Lang.Array<Lang.Number> = [];

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

        var lapNumber = advertisement.lapNumber;
        if (isRecent(lapNumber)) { return null; }

        countTheGapBefore(lapNumber);
        remember(lapNumber);
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

    // Reps the watch never heard.
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

    hidden function isRecent(lapNumber as Lang.Number) as Lang.Boolean {
        for (var i = 0; i < recent.size(); i++) {
            if (recent[i] == lapNumber) { return true; }
        }
        return false;
    }

    hidden function remember(lapNumber as Lang.Number) as Void {
        recent.add(lapNumber);
        if (recent.size() > RECENT) {
            recent = recent.slice(recent.size() - RECENT, null);
        }
    }
}
