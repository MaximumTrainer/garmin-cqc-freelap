using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

// Where the rolling capture log is stored, and the adapter that lets
// CaptureLog write to it without knowing about Toybox.
const CAPTURE_KEY = "capture";
const CHIP_NAME_KEY = "lastChipName";

class StorageSink {
    function initialize() {}
    function setValue(key, value) as Void { Application.Storage.setValue(key, value); }
}

module BleState {
    const IDLE        = 0;
    const SCANNING    = 1;
    const PAIRING     = 2;
    const DISCOVERING = 3;
    const SUBSCRIBED  = 4;
}

// Owns the BLE lifecycle: scan -> pair -> subscribe -> deliver packets to
// FreelapProtocol -> hand crossings to the SplitEngine. Reconnects with
// backoff on drop.
class FreelapBleDelegate extends Ble.BleDelegate {
    // Five attempts spans about 31 seconds. Past that the chip is off, not out
    // of range, and retrying forever costs battery in the middle of a session.
    static const MAX_RETRIES = 5;

    // BLE allows at most three registered profiles per app, and the registry
    // outlives a single AppBase instance in the VM (the unit-test harness
    // restarts the app between tests, which used to hit the limit and take
    // the app down with an unhandled ProfileRegistrationException on the
    // third start). Register once, and treat a refusal as a state the UI can
    // show rather than a crash.
    static var profileRegistered = false;
    // How many times we actually called Ble.registerProfile in this VM. The
    // guard above is only worth having if this stays at one.
    static var profileRegistrations = 0;

    var state = BleState.IDLE;
    var profileError = false;
    var device = null;
    var notifyChar = null;
    var engine = null;          // SplitEngine, set by app
    var onStateChanged = null;  // Method(state) for UI
    var lastPacketHex = "";
    var packetCount = 0;
    var captureMode = false;
    var rememberedName = "";
    var _retryTimer = null;
    var _handshake = [];
    var capture = new CaptureLog();   // rolling raw log for reverse-engineering
    var assembler = new PacketAssembler();
    var gaveUp = false;               // retries exhausted; only a rescan helps
    var retries = 0;                  // consecutive failed attempts
    var candidates = [];              // ChipCandidate, every chip seen this scan

    function initialize() {
        BleDelegate.initialize();
        var cm = Properties.getValue("captureMode");
        captureMode = (cm != null && cm);
        var rn = Properties.getValue(CHIP_NAME_KEY);
        if (rn != null) { rememberedName = rn; }
        Ble.setDelegate(self);
        registerProfileOnce();
    }

    function registerProfileOnce() as Void {
        // Qualified on purpose: an unqualified write inside an instance method
        // does not reach the class static, which would silently re-register on
        // every app start.
        if (FreelapBleDelegate.profileRegistered) { return; }
        try {
            Ble.registerProfile(FreelapProtocol.profile());
            FreelapBleDelegate.profileRegistrations += 1;
            FreelapBleDelegate.profileRegistered = true;
        } catch (e) {
            // Too Many Profiles, or a malformed profile dictionary. Either
            // way there is nothing to scan for; say so instead of dying.
            profileError = true;
        }
    }

    // ---- public --------------------------------------------------------
    function startScan() as Void {
        if (profileError) { setState(BleState.IDLE); return; }
        setState(BleState.SCANNING);
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    // The manual way back after the app has given up. Retrying forever would
    // flatten the battery mid-session for a chip that is switched off.
    function rescan() as Void {
        retries = 0;
        gaveUp = false;
        candidates = [];
        assembler.reset();
        startScan();
    }

    // How long to wait before attempt `attempt` (0-based). Exponential, so a
    // chip that is briefly out of range is picked up in about a second while
    // one that is genuinely gone is not hammered.
    static function retryDelayMs(attempt as Lang.Number) as Lang.Number {
        return 1000 << attempt;   // 1, 2, 4, 8, 16 s
    }

    function stop() as Void {
        // The one flash write. Nothing is written while packets arrive: see
        // CaptureLog.
        if (captureMode) { capture.flush(new StorageSink(), CAPTURE_KEY); }
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        if (device != null) { Ble.unpairDevice(device); device = null; }
        notifyChar = null;
        assembler.reset();
        setState(BleState.IDLE);
    }

    function isConnected() as Lang.Boolean { return state == BleState.SUBSCRIBED; }

    // ---- BleDelegate callbacks ----------------------------------------
    function onProfileRegister(uuid as Ble.Uuid, status as Ble.Status) as Void {
        // status != STATUS_SUCCESS means the profile dictionary is malformed.
    }

    function onScanResults(results as Ble.Iterator) as Void {
        if (state != BleState.SCANNING) { return; }

        // Collect every match before deciding. Connecting to the first one to
        // appear is how, at a group session, you end up recording a
        // team-mate's splits into your own activity.
        // Ble.Iterator.next() is declared as Object?; the cast is what lets
        // -l 1 see a ScanResult here.
        for (var r = results.next() as Ble.ScanResult?; r != null; r = results.next() as Ble.ScanResult?) {
            if (!FreelapProtocol.matchesScanResult(r, rememberedName)) { continue; }
            var name = r.getDeviceName();
            if (name == null) { name = "chip"; }
            candidates = ChipChooser.merge(candidates, new ChipCandidate(name, r.getRssi(), r));
        }

        var chosen = ChipChooser.choose(candidates, rememberedName);
        if (chosen != null) { connectTo(chosen); }
    }

    function connectTo(candidate as ChipCandidate) as Void {
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        setState(BleState.PAIRING);
        rememberChip(candidate.name);
        device = Ble.pairDevice(candidate.result);
        if (device == null) { scheduleRetry(); }
    }

    // The chip identity. Connect IQ does not expose a BLE address to an app,
    // so the advertised name is the most stable identifier available - see
    // docs/DESIGN.md §6.
    function rememberChip(name as Lang.String) as Void {
        rememberedName = name;
        Properties.setValue(CHIP_NAME_KEY, name);
    }

    function forgetChip() as Void {
        rememberedName = "";
        Properties.setValue(CHIP_NAME_KEY, "");
    }

    function onConnectedStateChanged(dev as Ble.Device, st as Ble.ConnectionState) as Void {
        if (st == Ble.CONNECTION_STATE_CONNECTED) {
            device = dev;
            retries = 0;
            gaveUp = false;
            setState(BleState.DISCOVERING);
            subscribe();
        } else {
            // Dropped or failed. Throw away any half-received message: the
            // tail of one from before the drop concatenated onto the head of
            // one after it decodes to plausible, wrong crossings.
            notifyChar = null;
            assembler.reset();
            if (state != BleState.IDLE) { scheduleRetry(); }
        }
    }

    function onDescriptorWrite(desc as Ble.Descriptor, status as Ble.Status) as Void {
        if (status == Ble.STATUS_SUCCESS && state == BleState.DISCOVERING) {
            _handshake = FreelapProtocol.getHandshakeWrites();
            if (_handshake.size() == 0) {
                setState(BleState.SUBSCRIBED);
            } else {
                sendNextHandshake();
            }
        } else if (status != Ble.STATUS_SUCCESS) {
            scheduleRetry();
        }
    }

    function onCharacteristicWrite(ch as Ble.Characteristic, status as Ble.Status) as Void {
        if (_handshake.size() > 0) {
            sendNextHandshake();
        } else if (state == BleState.DISCOVERING) {
            setState(BleState.SUBSCRIBED);
        }
    }

    function onCharacteristicChanged(ch as Ble.Characteristic, value as Lang.ByteArray) as Void {
        var arrival = System.getTimer();   // stamp first, before any work
        packetCount++;
        if (captureMode) {
            lastPacketHex = FreelapProtocol.hex(value);
            capture.add(arrival, lastPacketHex);
            WatchUi.requestUpdate();
        }
        var crossings = assembler.feed(value, arrival);
        if (crossings == null || engine == null) { return; }
        if (FreelapProtocol.STREAMING) {
            for (var i = 0; i < crossings.size(); i++) { engine.onCrossing(crossings[i], arrival); }
        } else {
            engine.onRepBurst(crossings, arrival);
        }
        WatchUi.requestUpdate();
    }

    // ---- internals -------------------------------------------------------
    function subscribe() as Void {
        var svc = device.getService(FreelapProtocol.serviceUuid());
        if (svc == null) { scheduleRetry(); return; }
        notifyChar = svc.getCharacteristic(FreelapProtocol.notifyUuid());
        if (notifyChar == null) { scheduleRetry(); return; }
        var cccd = notifyChar.getDescriptor(Ble.cccdUuid());
        if (cccd == null) { scheduleRetry(); return; }
        try {
            cccd.requestWrite([0x01, 0x00]b);   // enable notifications
        } catch (e) {
            scheduleRetry();
        }
    }

    function sendNextHandshake() as Void {
        if (_handshake.size() == 0) { setState(BleState.SUBSCRIBED); return; }
        var w = _handshake[0];
        _handshake = _handshake.slice(1, null);
        var svc = device.getService(FreelapProtocol.serviceUuid());
        var ch = svc != null ? svc.getCharacteristic(w[0]) : null;
        if (ch == null) { setState(BleState.SUBSCRIBED); return; }
        try {
            ch.requestWrite(w[1], { :writeType => Ble.WRITE_TYPE_WITH_RESPONSE });
        } catch (e) {
            setState(BleState.SUBSCRIBED);
        }
    }

    function scheduleRetry() as Void {
        if (retries >= MAX_RETRIES) {
            // Stop, and say so. The idle menu offers a rescan.
            gaveUp = true;
            setState(BleState.IDLE);
            return;
        }
        var delay = retryDelayMs(retries);
        retries++;
        if (_retryTimer == null) { _retryTimer = new Timer.Timer(); }
        _retryTimer.start(method(:onRetry), delay, false);
    }

    function onRetry() as Void {
        if (device != null) { Ble.unpairDevice(device); device = null; }
        startScan();
    }

    function setState(s as Lang.Number) as Void {
        state = s;
        if (onStateChanged != null) { onStateChanged.invoke(s); }
        WatchUi.requestUpdate();
    }
}
