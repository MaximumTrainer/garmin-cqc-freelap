using Toybox.Lang;

// Test doubles for ActivityRecording.Session and FitContributor.Field.
//
// AGENTS.md, "Fake at the seam, not below it": FitRecorder is handed a session
// object, so the double stands in for the session rather than for
// Toybox.FitContributor. Monkey C dispatches by name at runtime, so anything
// answering createField/start/stop/addLap/save/discard will do.
//
// What matters about the recorder is *order* — which value was on a field when
// addLap() ran, whether a split was written before or after the lap closed —
// so both doubles keep every call in sequence rather than only the last one.

(:test)
class FakeField {
    var name;
    var fieldId;
    var dataType;
    var options;
    var values = [];      // every setData() argument, in order

    function initialize(fieldName, id, type, opts) {
        name = fieldName;
        fieldId = id;
        dataType = type;
        options = opts;
    }

    function setData(value) as Void {
        values.add(value);
    }

    // The value the FIT writer would have seen on the next record.
    function last() {
        return values.size() > 0 ? values[values.size() - 1] : null;
    }

    function writes() as Lang.Number { return values.size(); }

    function mesgType() { return options.get(:mesgType); }
    function units() { return options.get(:units); }
}

(:test)
class FakeSession {
    var fields = {};      // name -> FakeField
    var calls = [];       // "start" / "stop" / "addLap" / "save" / "discard"
    var laps = 0;
    var saved = false;
    var discarded = false;

    // Field values captured at the moment each lap closed, so a test can ask
    // what the lap actually carried rather than what the field holds now.
    var lapSnapshots = [];
    // How many writes each field had received when each lap closed. This is
    // how a test asks "were all of the rep's split records on disk before the
    // lap was cut?" without reaching into the recorder.
    var lapWriteCounts = [];

    function initialize() {}

    function createField(name, id, type, opts) {
        var f = new FakeField(name, id, type, opts);
        fields.put(name, f);
        return f;
    }

    function start() as Void { calls.add("start"); }
    function stop() as Void { calls.add("stop"); }

    function addLap() as Void {
        calls.add("addLap");
        laps++;
        lapSnapshots.add(snapshot());
        lapWriteCounts.add(writeCounts());
    }

    function save() as Void { calls.add("save"); saved = true; }
    function discard() as Void { calls.add("discard"); discarded = true; }

    // ---- assertions helpers ------------------------------------------------

    function field(name) as FakeField? {
        return fields.get(name) as FakeField?;
    }

    // Every value written to `name`, in order.
    function valuesOf(name) as Lang.Array {
        var f = field(name);
        return f == null ? [] : f.values;
    }

    function snapshot() as Lang.Dictionary {
        var out = {};
        var names = fields.keys();
        for (var i = 0; i < names.size(); i++) {
            var f = fields.get(names[i]) as FakeField;
            out.put(names[i], f.last());
        }
        return out;
    }

    function writeCounts() as Lang.Dictionary {
        var out = {};
        var names = fields.keys();
        for (var i = 0; i < names.size(); i++) {
            out.put(names[i], (fields.get(names[i]) as FakeField).writes());
        }
        return out;
    }

    // How many writes `name` had received when lap `lapIndex` closed.
    function lapWriteCount(lapIndex as Lang.Number, name) as Lang.Number {
        if (lapIndex >= lapWriteCounts.size()) { return -1; }
        var n = (lapWriteCounts[lapIndex] as Lang.Dictionary).get(name);
        return n == null ? -1 : n;
    }

    // The value `name` held when lap `lapIndex` (0-based) closed.
    function lapValue(lapIndex as Lang.Number, name) {
        if (lapIndex >= lapSnapshots.size()) { return null; }
        return (lapSnapshots[lapIndex] as Lang.Dictionary).get(name);
    }

    // How many of `call` happened, e.g. countOf("addLap").
    function countOf(call as Lang.String) as Lang.Number {
        var n = 0;
        for (var i = 0; i < calls.size(); i++) {
            if (calls[i].equals(call)) { n++; }
        }
        return n;
    }
}
