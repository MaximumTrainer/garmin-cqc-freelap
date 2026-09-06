using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Lang;
using Toybox.System;

// ============================================================================
//  THE ONLY FILE THAT KNOWS FREELAP'S PACKET FORMAT.
//
//  Everything below marked HYPOTHESIS is a placeholder until you have sniffed
//  the real chip (docs/REVERSE-ENGINEERING.md). The rest of the app only
//  depends on:
//     - SERVICE_UUID / NOTIFY_UUID / COMMAND_UUID  (for the GATT profile)
//     - matchesScanResult(scanResult)               (device discovery)
//     - getHandshakeWrites()                        (optional post-connect writes)
//     - feed(bytes, arrivalTimerMs) -> Array<Crossing> or null
//     - STREAMING                                   (per-crossing vs burst)
// ============================================================================

// A decoded transmitter crossing in chip time.
class Crossing {
    var timeUs = 0l;   // chip timestamp in microseconds (Long; may be absolute chip uptime)
    var code = 0;      // TxCode
    var chipId = "";
    function initialize(t as Lang.Numeric, c as Lang.Number, id as Lang.String) {
        timeUs = t; code = c; chipId = id;
    }
}

module FreelapProtocol {

    // HYPOTHESIS: many nRF52-based sports sensors expose a Nordic UART
    // Service. Replace with the UUIDs nRF Connect shows for the FxChip BLE.
    const SERVICE_UUID_STR = "6E400001-B5A3-F393-E0A9-E50E24DCC9E6";
    const NOTIFY_UUID_STR  = "6E400003-B5A3-F393-E0A9-E50E24DCC9E6"; // TX (chip -> us), notify
    const COMMAND_UUID_STR = "6E400002-B5A3-F393-E0A9-E50E24DCC9E6"; // RX (us -> chip), write

    // true  = chip notifies once per crossing (engine.onCrossing)
    // false = chip pushes the whole rep at FINISH (engine.onRepBurst)
    const STREAMING = false;

    // Name prefixes seen in advertising. HYPOTHESIS.
    var NAME_PREFIXES = ["FxChip", "Freelap", "FXCHIP", "Relay"];   // module var: const cannot hold an array

    // Chip timestamp unit. HYPOTHESIS: 1 ms ticks. Set from sniffing:
    //   1000 for ms, 10000 for 1/100 s, 1 for us.
    const TICK_US = 1000;

    function serviceUuid() as Ble.Uuid { return Ble.stringToUuid(SERVICE_UUID_STR); }
    function notifyUuid() as Ble.Uuid  { return Ble.stringToUuid(NOTIFY_UUID_STR); }
    function commandUuid() as Ble.Uuid { return Ble.stringToUuid(COMMAND_UUID_STR); }

    function profile() as Lang.Dictionary {
        return {
            :uuid => serviceUuid(),
            :characteristics => [
                { :uuid => notifyUuid(), :descriptors => [Ble.cccdUuid()] },
                { :uuid => commandUuid() }
            ]
        };
    }

    // Does this advertisement look like a Freelap chip?
    function matchesScanResult(sr as Ble.ScanResult, rememberedName as Lang.String?) as Lang.Boolean {
        var name = sr.getDeviceName();
        if (name != null) {
            if (rememberedName != null && !rememberedName.equals("") && name.equals(rememberedName)) { return true; }
            for (var i = 0; i < NAME_PREFIXES.size(); i++) {
                if (name.find(NAME_PREFIXES[i]) == 0) { return true; }
            }
        }
        var uuids = sr.getServiceUuids();
        if (uuids != null) {
            var target = serviceUuid();
            for (var u = uuids.next(); u != null; u = uuids.next()) {
                if (u.equals(target)) { return true; }
            }
        }
        return false;
    }

    // Writes to send after subscribing, e.g. a "start session" command.
    // HYPOTHESIS: none. Each entry: [Ble.Uuid, ByteArray] (<= 20 bytes).
    function getHandshakeWrites() as Lang.Array {
        return [];
    }

    // ---- Decoder ----------------------------------------------------------
    // HYPOTHESIS packet layout for the burst at FINISH:
    //   byte 0      : 0xA5 sync
    //   byte 1      : n = number of crossings
    //   byte 2..3   : chip id (u16 LE)
    //   then n x 5 bytes: u32 LE timestamp (ticks) , u8 code (1=S,2=L,3=F)
    // Longer than 20 bytes -> arrives as several notifications; reassemble
    // by expected length.
    var _buf = []b;
    var _expected = 0;

    // Feed one notification. Returns an Array<Crossing> when a complete
    // message has been decoded, else null.
    function feed(value as Lang.ByteArray, arrivalTimerMs as Lang.Number) as Lang.Array? {
        if (_expected == 0) {
            if (value.size() < 4 || value[0] != 0xA5) { return null; }
            _expected = 4 + value[1] * 5;
            _buf = []b;
        }
        _buf = _buf.addAll(value);
        if (_buf.size() < _expected) { return null; }

        var n = _buf[1];
        var chipId = (_buf[2] | (_buf[3] << 8)).format("%04X");
        var out = [];
        var off = 4;
        for (var i = 0; i < n; i++) {
            // UINT32 decodes to a Long. Keep chip time as a Long in us so an
            // absolute chip-uptime timestamp cannot overflow a 32-bit Number;
            // the SplitEngine subtracts the rep START before narrowing.
            var ticks = _buf.decodeNumber(Lang.NUMBER_FORMAT_UINT32, { :offset => off, :endianness => Lang.ENDIAN_LITTLE });
            var code = _buf[off + 4];
            if (code > 3) { code = 0; }
            out.add(new Crossing(ticks * TICK_US, code, chipId));
            off += 5;
        }
        _buf = []b;
        _expected = 0;
        return out;
    }

    function reset() as Void { _buf = []b; _expected = 0; }

    // Hex dump for capture mode.
    function hex(value as Lang.ByteArray) as Lang.String {
        var s = "";
        for (var i = 0; i < value.size(); i++) { s += value[i].format("%02X"); }
        return s;
    }
}
