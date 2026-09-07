using Toybox.Lang;

// Stands in for Application.Storage wherever the question is *when* a write
// happens, not what was stored. Application.Storage is flash: a write inside
// the BLE notification callback blocks long enough to lose the packets that
// follow, and a fragmented burst arrives milliseconds apart.
(:test)
class FakeStorage {
    var values = {};
    var writes = 0;
    var reads = 0;

    function initialize() {}

    function setValue(key, value) as Void {
        writes++;
        values.put(key, value);
    }

    function getValue(key) {
        reads++;
        return values.get(key);
    }

    // Read without counting, for assertions.
    function get(key) { return values.get(key); }
}
