using Toybox.Lang;

// One transmitter crossing, fully derived. All times are integers in
// microseconds so nothing is rounded before it reaches the FIT file.
class SplitEvent {
    var rep = 0;             // 1-based rep number
    var txIndex = -1;        // index into Course (0 = START), -1 unmatched
    var txCode = 0;          // TxCode
    var chipId = "";         // chip identifier, for multi-athlete extension

    var cumTimeUs = 0;       // chip time since START of this rep (us)
    var splitTimeUs = 0;     // since previous crossing (us); 0 for START
    var cumDistM = 0.0;      // cumulative distance from course (m)
    var splitDistM = 0.0;    // distance since previous crossing (m)

    var velocityMps = 0.0;   // split velocity m/s
    var speedKmh = 0.0;      // split speed km/h
    var paceSecPerKm = 0.0;  // split pace s/km

    var estSessionMs = 0;    // estimated crossing time, ms since session start
    var estClamped = false;  // the estimate landed before the session started
    var arrivalTimerMs = 0;  // System.getTimer() when the packet carrying it arrived

    function initialize() {}

    function derive(prev as SplitEvent?) as Void {
        if (prev == null) {
            splitTimeUs = 0;
            splitDistM = 0.0;
        } else {
            splitTimeUs = cumTimeUs - prev.cumTimeUs;
            splitDistM = cumDistM - prev.cumDistM;
        }
        if (splitTimeUs > 0 && splitDistM > 0) {
            velocityMps = splitDistM / (splitTimeUs / 1000000.0);
            speedKmh = velocityMps * 3.6;
            paceSecPerKm = 1000.0 / velocityMps;
        } else {
            velocityMps = 0.0; speedKmh = 0.0; paceSecPerKm = 0.0;
        }
    }

    // Compact array for Application.Storage.
    //
    // estClamped travels with the row because fl_est_ms is a uint32 and 0 is a
    // legitimate value: without the flag, "the crossing happened at the moment
    // the session started" and "we could not place this crossing" are the same
    // number.
    function toArray() as Lang.Array {
        return [rep, txIndex, txCode, cumTimeUs, splitTimeUs, cumDistM, splitDistM,
                velocityMps, estSessionMs, estClamped];
    }

    function formatSplit() as Lang.String {
        var s = splitTimeUs / 1000000;
        var frac = (splitTimeUs % 1000000) / 10000; // hundredths for display only
        return s.format("%d") + "." + frac.format("%02d");
    }
}
