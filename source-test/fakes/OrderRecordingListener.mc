using Toybox.Lang;

// Who was called, in what order. A plain array literal will not do: the type
// checker sees `[]` as empty and rejects `order[0]` at -l 1 as out of bounds.
(:test)
class CallOrder {
    hidden var _names = [] as Lang.Array<Lang.String>;

    function initialize() {}

    function add(name as Lang.String) as Void { _names.add(name); }
    function size() as Lang.Number { return _names.size(); }
    function at(index as Lang.Number) as Lang.String { return _names[index]; }
}

// Records only that it was called, and under what name. Used to assert that
// the recorder is told about a finished rep before the screen is.
(:test)
class OrderRecordingListener {
    hidden var _order;
    hidden var _name;

    function initialize(order as CallOrder, name as Lang.String) {
        _order = order;
        _name = name;
    }

    function onSplit(ev) as Void {}

    function onRepComplete(r) as Void { _order.add(_name); }
}
