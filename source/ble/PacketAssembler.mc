using Toybox.Lang;

// Reassembles a Freelap message from the notifications it arrives in.
//
// A BLE notification carries at most 20 bytes, so a rep of more than three
// crossings arrives fragmented. This holds the partial message between them.
//
// It is a class, and the BLE delegate owns one, rather than module state on
// FreelapProtocol. Two reasons, and the second is the one that bites:
//
//   * module-level mutable state makes test order matter - a test that leaves
//     half a message in the buffer breaks the next test, not itself;
//   * on a link drop the buffer has to be thrown away, because the tail of a
//     message from before the drop concatenated onto the head of one after it
//     decodes to plausible, wrong crossings. Owning the buffer makes
//     "reset it on disconnect" a thing that can be asserted.
//
// The framing itself still lives in FreelapProtocol, which remains the only
// file that knows the packet format.
class PacketAssembler {
    // A message longer than this is not a Freelap message, it is a desync.
    // 0xA5 can appear inside a payload, so a bad sync byte can otherwise leave
    // us waiting for bytes that never come.
    static const MAX_MESSAGE = 256;

    var buffer = []b;
    var expected = 0;
    var discarded = 0;   // messages abandoned as malformed or over-long

    function initialize() {}

    // Feed one notification. Returns an Array<Crossing> when a complete
    // message has been decoded, else null.
    function feed(value as Lang.ByteArray, arrivalTimerMs as Lang.Number) as Lang.Array? {
        if (expected == 0) {
            expected = FreelapProtocol.expectedLength(value);
            if (expected <= 0 || expected > MAX_MESSAGE) {
                // Not a message start. Drop it rather than buffering rubbish.
                if (expected > MAX_MESSAGE) { discarded++; }
                expected = 0;
                return null;
            }
            buffer = []b;
        }

        buffer = buffer.addAll(value);
        if (buffer.size() < expected) { return null; }

        var message = buffer;
        reset();
        return FreelapProtocol.decodeMessage(message, arrivalTimerMs);
    }

    // Throw away any half-received message. Called on every disconnect: a
    // fragment from before the drop must never be completed by one from after.
    function reset() as Void {
        buffer = []b;
        expected = 0;
    }

    function isAssembling() as Lang.Boolean { return expected != 0; }

    function pending() as Lang.Number { return buffer.size(); }
}
