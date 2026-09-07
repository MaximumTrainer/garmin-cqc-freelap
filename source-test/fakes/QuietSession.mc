using Toybox.Lang;

// A session double that remembers counts but not values.
//
// FakeSession keeps every setData argument in order, which is exactly what the
// FIT tests need and exactly wrong for a memory soak: after 60 reps it is
// holding thousands of values of its own, and a test asking "how much memory
// does the app use" measures the double instead. This one is O(1) per write.
(:test)
class QuietField {
    var writes = 0;
    var last = null;
    function initialize() {}
    function setData(value) as Void { writes++; last = value; }
}

(:test)
class QuietSession {
    var laps = 0;
    var starts = 0;
    var stops = 0;
    var saved = false;
    var discarded = false;
    hidden var _fields = {};

    function initialize() {}

    function createField(name, id, type, opts) {
        var f = new QuietField();
        _fields.put(name, f);
        return f;
    }

    function start() as Void { starts++; }
    function stop() as Void { stops++; }
    function addLap() as Void { laps++; }
    function save() as Void { saved = true; }
    function discard() as Void { discarded = true; }

    function field(name) as QuietField? { return _fields.get(name) as QuietField?; }
}
