using Toybox.Lang;

// One transmitter crossing as the split engine consumes it: a chip timestamp,
// which kind of transmitter, and whose chip. This is the seam between the BLE
// layer and the model - BroadcastRep.toCrossings() produces these, and
// SplitEngine.onRepBurst() takes an ordered array of them.
//
// Moved out of FreelapProtocol.mc because that file describes a protocol the
// chip does not speak and is retired in #61; this type is not going anywhere.
class Crossing {
    var timeUs = 0l;   // chip time in microseconds (Long; may be absolute chip uptime)
    var code = 0;      // TxCode
    var chipId = "";

    function initialize(t as Lang.Numeric, c as Lang.Number, id as Lang.String) {
        timeUs = t; code = c; chipId = id;
    }
}
