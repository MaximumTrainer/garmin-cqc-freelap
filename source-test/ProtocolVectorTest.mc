using Toybox.Lang;
using Toybox.Test;

// Decoder vectors: literal bytes in, expected crossings out.
//
// AGENTS.md, ring 4: "every capture folder under captures/ yields at least one
// vector". There are no captures yet - the chip has not been sniffed (#4, #5)
// and TICK_US, the framing and the code mapping are all still HYPOTHESIS. What
// these vectors pin instead is the agreement between the two halves that
// currently define the format:
//
//   tools/fake_chip.py builds the packets
//   source/ble/FreelapProtocol.mc decodes them
//
// If those two drift the fake chip keeps agreeing with itself and every
// end-to-end test through it stays green while the watch decodes real packets
// wrongly. That is the silent hole AGENTS.md warns about, and this file is
// what closes it.
//
// Regenerate the literals with:
//   python -c "import sys; sys.path.insert(0,'tools'); from fake_chip import *; \
//              print(build_packet(synthetic_rep(parse_course('S:0;L:30;L:60;F:100'), \
//              speed_mps=10.0, jitter=0.0)).hex(' '))"

// From: build_packet(synthetic_rep(parse_course("S:0;L:30;L:60;F:100"),
//                                  speed_mps=10.0, jitter=0.0), chip_id=0x1234)
// A 100 m course run at exactly 10 m/s: crossings at 0, 3.000, 6.000, 10.000 s.
(:test)
function testTheFakeChipsPacketDecodesToTheCrossingsItEncoded(logger as Test.Logger) as Lang.Boolean {
    var packet = [0xA5, 0x04, 0x34, 0x12,
                  0x00, 0x00, 0x00, 0x00, 0x01,
                  0xB8, 0x0B, 0x00, 0x00, 0x02,
                  0x70, 0x17, 0x00, 0x00, 0x02,
                  0x10, 0x27, 0x00, 0x00, 0x03]b;

    var crossings = new PacketAssembler().feed(packet, 1000);

    Test.assertMessage(crossings != null, "a complete message decodes");
    Test.assertEqualMessage(crossings.size(), 4, "four crossings");

    // TICK_US is 1000, so chip ticks are milliseconds and these are µs.
    Test.assertEqualMessage(crossings[0].timeUs, 0l, "START");
    Test.assertEqualMessage(crossings[1].timeUs, 3000000l, "30 m at 10 m/s");
    Test.assertEqualMessage(crossings[2].timeUs, 6000000l, "60 m at 10 m/s");
    Test.assertEqualMessage(crossings[3].timeUs, 10000000l, "100 m at 10 m/s");

    Test.assertEqualMessage(crossings[0].code, TxCode.START, "code S");
    Test.assertEqualMessage(crossings[1].code, TxCode.LAP, "code L");
    Test.assertEqualMessage(crossings[3].code, TxCode.FINISH, "code F");

    Test.assertEqualMessage(crossings[0].chipId, "1234", "chip id, little endian");
    return true;
}

// The same packet as the two notifications it actually arrives in. 24 bytes
// does not fit in one: the BLE notification limit is 20.
(:test)
function testTheSamePacketDecodesWhenItArrivesFragmented(logger as Test.Logger) as Lang.Boolean {
    var first = [0xA5, 0x04, 0x34, 0x12,
                 0x00, 0x00, 0x00, 0x00, 0x01,
                 0xB8, 0x0B, 0x00, 0x00, 0x02,
                 0x70, 0x17, 0x00, 0x00, 0x02,
                 0x10]b;
    var second = [0x27, 0x00, 0x00, 0x03]b;

    var assembler = new PacketAssembler();

    Test.assertMessage(assembler.feed(first, 1000) == null, "the first fragment is not a message");
    Test.assertMessage(assembler.isAssembling(), "it is being assembled");

    var crossings = assembler.feed(second, 1030);

    Test.assertMessage(crossings != null, "the second completes it");
    Test.assertEqualMessage(crossings.size(), 4, "the same four crossings");
    Test.assertEqualMessage(crossings[3].timeUs, 10000000l, "including the one split across the boundary");
    Test.assertMessage(!assembler.isAssembling(), "and the buffer is empty again");
    return true;
}

// A rep that fits in a single notification: 4 + 2*5 = 14 bytes.
(:test)
function testATwoCrossingRepFitsInOneNotification(logger as Test.Logger) as Lang.Boolean {
    var packet = [0xA5, 0x02, 0x34, 0x12,
                  0x00, 0x00, 0x00, 0x00, 0x01,
                  0xB8, 0x0B, 0x00, 0x00, 0x03]b;

    var crossings = new PacketAssembler().feed(packet, 1000);

    Test.assertEqualMessage(crossings.size(), 2, "START and FINISH");
    Test.assertEqualMessage(crossings[1].timeUs, 3000000l, "3.000 s");
    return true;
}

// The engine's own worked example, expressed as bytes, so the numbers in
// SplitEngineTest can be traced all the way back to a packet.
(:test)
function testTheWorkedExampleRepAsWireBytes(logger as Test.Logger) as Lang.Boolean {
    // 4.120 s = 4120 ms = 0x1018, 7.480 s = 7480 = 0x1D38, 11.930 s = 11930 = 0x2E9A
    var packet = [0xA5, 0x04, 0x34, 0x12,
                  0x00, 0x00, 0x00, 0x00, 0x01,
                  0x18, 0x10, 0x00, 0x00, 0x02,
                  0x38, 0x1D, 0x00, 0x00, 0x02,
                  0x9A, 0x2E, 0x00, 0x00, 0x03]b;

    var engine = TestSupport.engineAt(10000, 150, "S:0;L:30;L:60;F:100");
    engine.onRepBurst(new PacketAssembler().feed(packet, 30000), 30000);

    var rep = engine.lastRep;
    Test.assertEqualMessage(rep.timeUs, 11930000, "the rep time from SplitEngineTest");
    Test.assertEqualMessage(rep.events[1].splitTimeUs, 4120000, "and split 1");
    Test.assertEqualMessage(rep.status, RepStatus.OK, "a clean rep");
    TestSupport.assertClose(rep.events[3].velocityMps, 8.989, 0.001, "and the velocity");
    return true;
}

// A code the watch does not know must not be guessed at.
(:test)
function testAnUnknownTransmitterCodeDecodesAsUnknown(logger as Test.Logger) as Lang.Boolean {
    var packet = [0xA5, 0x01, 0x34, 0x12,
                  0x00, 0x00, 0x00, 0x00, 0x07]b;   // code 7

    var crossings = new PacketAssembler().feed(packet, 1000);

    Test.assertEqualMessage(crossings[0].code, TxCode.UNKNOWN,
        "an unrecognised code falls back to index-order matching, not to a guess");
    return true;
}
