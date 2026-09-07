using Toybox.Lang;

// One chip seen in a scan: what the watch knows about it, and the scan result
// needed to pair with it.
//
// `name` is the identity. Connect IQ does not expose a BLE device address to
// an app - deliberately, it is a privacy surface - so the advertised name is
// the most stable identifier available, and Freelap chips advertise a name
// that includes their own id (e.g. "FxChip-1234"). If a capture shows the id
// in manufacturer-specific data, prefer that: it survives a firmware rename.
// See docs/DESIGN.md §6.
class ChipCandidate {
    var name = "";
    var rssi = -128;
    var result = null;   // Ble.ScanResult, opaque here so this stays testable

    function initialize(deviceName as Lang.String, signal as Lang.Number, scanResult) {
        name = deviceName;
        rssi = signal;
        result = scanResult;
    }

    // What the chooser menu shows: "FxChip-1234  -54 dBm".
    function label() as Lang.String {
        return name + "  " + rssi.format("%d") + " dBm";
    }
}

// Picks which chip to connect to when more than one is advertising.
//
// This matters at a group session, where every athlete's chip is in range and
// connecting to someone else's means recording their splits into your
// activity - which looks entirely plausible until you compare the numbers.
//
// Nothing here touches Toybox beyond Lang.
module ChipChooser {

    // The remembered chip if it is present, otherwise the strongest signal -
    // which, with chips on waistbands, is the one on *this* athlete.
    //
    // Returns null for an empty list.
    function choose(candidates as Lang.Array, rememberedName as Lang.String?) as ChipCandidate? {
        if (candidates.size() == 0) { return null; }

        if (rememberedName != null && !rememberedName.equals("")) {
            for (var i = 0; i < candidates.size(); i++) {
                var candidate = candidates[i] as ChipCandidate;
                if (candidate.name.equals(rememberedName)) { return candidate; }
            }
        }
        return strongest(candidates);
    }

    function strongest(candidates as Lang.Array) as ChipCandidate? {
        if (candidates.size() == 0) { return null; }
        var best = candidates[0] as ChipCandidate;
        for (var i = 1; i < candidates.size(); i++) {
            var candidate = candidates[i] as ChipCandidate;
            if (candidate.rssi > best.rssi) { best = candidate; }
        }
        return best;
    }

    // Merge a freshly seen chip into the known list, newest RSSI winning. Scan
    // results repeat every advertising interval, so without this the list
    // grows without bound and the menu fills with duplicates.
    function merge(candidates as Lang.Array, seen as ChipCandidate) as Lang.Array {
        for (var i = 0; i < candidates.size(); i++) {
            if ((candidates[i] as ChipCandidate).name.equals(seen.name)) {
                candidates[i] = seen;
                return candidates;
            }
        }
        candidates.add(seen);
        return candidates;
    }

    // Strongest first, so the chooser menu puts the likely one at the top.
    function sortByStrength(candidates as Lang.Array) as Lang.Array {
        var out = [];
        var remaining = candidates.slice(0, null);
        while (remaining.size() > 0) {
            var best = strongest(remaining);
            out.add(best);
            var kept = [];
            for (var i = 0; i < remaining.size(); i++) {
                if (remaining[i] != best) { kept.add(remaining[i]); }
            }
            remaining = kept;
        }
        return out;
    }
}
