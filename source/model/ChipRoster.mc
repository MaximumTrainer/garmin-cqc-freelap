using Toybox.Lang;

// Which chips this session has heard from, and the rep each is on.
//
// A single athlete has one chip and this is a list of one. A Freelap Relay
// Coach BLE aggregates several, and then rep numbering has to be *per chip*:
// two athletes running alternately would otherwise produce reps numbered
// 1, 2, 3, 4 across both of them, and every rep in the FIT file would be
// attributed to whoever happened to cross next.
//
// Slots are assigned in the order chips are first heard and never reused, so
// a chip that goes quiet for a while comes back to its own slot and its own
// rep count.
//
// Nothing here touches Toybox beyond Lang.
class ChipState {
    var id = "";
    var slot = 0;
    var repNumber = 0;
    var current = [] as Lang.Array;   // SplitEvents of the rep in progress
    var repStartChipUs = 0l;          // streaming mode: chip time of this rep's START

    function initialize(chipId as Lang.String, index as Lang.Number) {
        id = chipId;
        slot = index;
    }
}

class ChipRoster {
    // fl_chip_idx is a uint8 and 255 is the "unknown" sentinel, so this is
    // where the slot numbering has to stop. It is far past anything a Relay
    // Coach handles; the cap exists so a garbled chip id cannot grow the
    // roster without bound.
    static const MAX_CHIPS = 16;

    var chips = [] as Lang.Array;   // ChipState, slot order
    var overflow = 0;               // chips seen past the cap

    function initialize() {}

    function size() as Lang.Number { return chips.size(); }

    // The state for `chipId`, creating a slot the first time it is heard.
    // Returns null only when the roster is full.
    function forChip(chipId as Lang.String) as ChipState? {
        for (var i = 0; i < chips.size(); i++) {
            var chip = chips[i] as ChipState;
            if (chip.id.equals(chipId)) { return chip; }
        }
        if (chips.size() >= MAX_CHIPS) {
            overflow++;
            return null;
        }
        var fresh = new ChipState(chipId, chips.size());
        chips.add(fresh);
        return fresh;
    }

    function at(slot as Lang.Number) as ChipState? {
        return slot >= 0 && slot < chips.size() ? chips[slot] as ChipState : null;
    }

    function idOf(slot as Lang.Number) as Lang.String {
        var chip = at(slot);
        return chip == null ? "" : chip.id;
    }

    // The chips seen this session, in slot order, for fl_chip_id. Slot 0 is
    // first, so a single-chip session reads exactly as it did before.
    function idList() as Lang.String {
        var out = "";
        for (var i = 0; i < chips.size(); i++) {
            if (i > 0) { out += ","; }
            out += (chips[i] as ChipState).id;
        }
        return out;
    }

    function clear() as Void {
        chips = [] as Lang.Array;
        overflow = 0;
    }
}
