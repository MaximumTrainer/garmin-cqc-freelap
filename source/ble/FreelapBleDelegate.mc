using Toybox.Application;
using Toybox.BluetoothLowEnergy as Ble;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

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
    var state = BleState.IDLE;
    var device = null;
    var notifyChar = null;
    var engine = null;          // SplitEngine, set by app
    var onStateChanged = null;  // Method(state) for UI
    var lastPacketHex = "";
    var packetCount = 0;
    var captureMode = false;
    var rememberedName = "";
    var _retry = 0;
    var _retryTimer = null;
    var _handshake = [];
    var _capture = [];          // rolling raw log for reverse-engineering

    function initialize() {
        BleDelegate.initialize();
        var app = Application.getApp();
        var cm = app.getProperty("captureMode");
        captureMode = (cm != null && cm);
        var rn = app.getProperty("lastChipName");
        if (rn != null) { rememberedName = rn; }
        Ble.setDelegate(self);
        Ble.registerProfile(FreelapProtocol.profile());
    }

    // ---- public --------------------------------------------------------
    function startScan() as Void {
        setState(BleState.SCANNING);
        Ble.setScanState(Ble.SCAN_STATE_SCANNING);
    }

    function stop() as Void {
        if (captureMode && _capture.size() > 0) {
            Application.Storage.setValue("capture", _capture);
        }
        Ble.setScanState(Ble.SCAN_STATE_OFF);
        if (device != null) { Ble.unpairDevice(device); device = null; }
        notifyChar = null;
        FreelapProtocol.reset();
        setState(BleState.IDLE);
    }

    function isConnected() as Lang.Boolean { return state == BleState.SUBSCRIBED; }

    // ---- BleDelegate callbacks ----------------------------------------
    function onProfileRegister(uuid as Ble.Uuid, status as Ble.Status) as Void {
        // status != STATUS_SUCCESS means the profile dictionary is malformed.
    }

    function onScanResults(results as Ble.Iterator) as Void {
        if (state != BleState.SCANNING) { return; }
        for (var r = results.next(); r != null; r = results.next()) {
            if (FreelapProtocol.matchesScanResult(r, rememberedName)) {
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                setState(BleState.PAIRING);
                var name = r.getDeviceName();
                if (name != null) {
                    rememberedName = name;
                    Application.getApp().setProperty("lastChipName", name);
                }
                device = Ble.pairDevice(r);
                if (device == null) { scheduleRetry(); }
                return;
            }
        }
    }

    function onConnectedStateChanged(dev as Ble.Device, st as Ble.ConnectionState) as Void {
        if (st == Ble.CONNECTION_STATE_CONNECTED) {
            device = dev;
            _retry = 0;
            setState(BleState.DISCOVERING);
            subscribe();
        } else {
            // Dropped or failed. Clean up and try again.
            notifyChar = null;
            FreelapProtocol.reset();
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
            _capture.add([arrival, lastPacketHex]);
            if (_capture.size() > 60) { _capture = _capture.slice(1, null); }
            // Flash write deferred to stop(): Storage.setValue per packet is
            // too slow for fragment bursts and values are capped (~8 KB).
            WatchUi.requestUpdate();
        }
        var crossings = FreelapProtocol.feed(value, arrival);
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
        if (_retry >= 5) { setState(BleState.IDLE); return; }
        var delay = 1000 << _retry;    // 1,2,4,8,16 s
        _retry++;
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
