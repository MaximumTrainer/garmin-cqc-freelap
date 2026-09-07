using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #11, "Remember the last chip and
// prefer it when several are advertising".
//
// The scenario that makes this matter is a group session: every athlete's chip
// is in range, and connecting to someone else's records *their* splits into
// *your* activity. That is not an obvious failure - the numbers look entirely
// plausible until you compare them with the person who actually ran them.

(:test)
function testNoCandidatesMeansNoChoice(logger as Test.Logger) as Lang.Boolean {
    Test.assertMessage(ChipChooser.choose([], "FxChip-1234") == null, "nothing in range");
    Test.assertMessage(ChipChooser.choose([], null) == null, "and no remembered chip either");
    return true;
}

(:test)
function testTheOnlyChipInRangeIsTheOneChosen(logger as Test.Logger) as Lang.Boolean {
    var only = new ChipCandidate("FxChip-9999", -80, null);

    var chosen = ChipChooser.choose([only], "FxChip-1234");

    // Even though it is not the remembered one: a weak unknown chip beats no
    // chip, and the athlete can pick a different one from the menu.
    Test.assertEqualMessage(chosen.name, "FxChip-9999", "connect to what is there");
    return true;
}

(:test)
function testTheRememberedChipWinsOverAStrongerStranger(logger as Test.Logger) as Lang.Boolean {
    var mine = new ChipCandidate("FxChip-1234", -78, null);
    var theirs = new ChipCandidate("FxChip-5678", -41, null);

    var chosen = ChipChooser.choose([theirs, mine], "FxChip-1234");

    Test.assertEqualMessage(chosen.name, "FxChip-1234",
        "a team-mate standing closer must not hijack the session");
    return true;
}

(:test)
function testTheRememberedChipWinsWhereverItIsInTheList(logger as Test.Logger) as Lang.Boolean {
    var a = new ChipCandidate("FxChip-0001", -50, null);
    var b = new ChipCandidate("FxChip-0002", -50, null);
    var mine = new ChipCandidate("FxChip-1234", -90, null);

    Test.assertEqualMessage(ChipChooser.choose([mine, a, b], "FxChip-1234").name, "FxChip-1234", "first");
    Test.assertEqualMessage(ChipChooser.choose([a, mine, b], "FxChip-1234").name, "FxChip-1234", "middle");
    Test.assertEqualMessage(ChipChooser.choose([a, b, mine], "FxChip-1234").name, "FxChip-1234", "last");
    return true;
}

(:test)
function testWithNoMemoryTheStrongestSignalWins(logger as Test.Logger) as Lang.Boolean {
    var far = new ChipCandidate("FxChip-0001", -91, null);
    var near = new ChipCandidate("FxChip-0002", -44, null);
    var mid = new ChipCandidate("FxChip-0003", -67, null);

    // A chip on this athlete's own waistband is centimetres away; everyone
    // else's is metres away.
    Test.assertEqualMessage(ChipChooser.choose([far, near, mid], "").name, "FxChip-0002", "empty memory");
    Test.assertEqualMessage(ChipChooser.choose([far, near, mid], null).name, "FxChip-0002", "no memory");
    return true;
}

(:test)
function testAForgottenChipIsNoLongerPreferred(logger as Test.Logger) as Lang.Boolean {
    var old = new ChipCandidate("FxChip-1234", -88, null);
    var other = new ChipCandidate("FxChip-5678", -50, null);

    // After "Forget chip" the remembered name is cleared, and the strongest
    // signal wins again.
    Test.assertEqualMessage(ChipChooser.choose([old, other], "").name, "FxChip-5678", "forgotten");
    return true;
}

(:test)
function testARememberedChipThatIsNotHereDoesNotBlockConnecting(logger as Test.Logger) as Lang.Boolean {
    var other = new ChipCandidate("FxChip-5678", -50, null);

    Test.assertEqualMessage(ChipChooser.choose([other], "FxChip-1234").name, "FxChip-5678",
        "left the usual chip at home; connect to the one that is here");
    return true;
}

// ---------------------------------------------------------------------------
// Keeping the list
// ---------------------------------------------------------------------------

(:test)
function testSeeingTheSameChipAgainUpdatesItRatherThanDuplicatingIt(logger as Test.Logger) as Lang.Boolean {
    var candidates = [];

    // Scan results repeat every advertising interval - a few per second.
    candidates = ChipChooser.merge(candidates, new ChipCandidate("FxChip-1234", -70, null));
    candidates = ChipChooser.merge(candidates, new ChipCandidate("FxChip-1234", -55, null));
    candidates = ChipChooser.merge(candidates, new ChipCandidate("FxChip-1234", -60, null));

    Test.assertEqualMessage(candidates.size(), 1, "one chip, not three menu entries");
    Test.assertEqualMessage((candidates[0] as ChipCandidate).rssi, -60, "carrying the latest signal");
    return true;
}

(:test)
function testDifferentChipsAreKeptSeparately(logger as Test.Logger) as Lang.Boolean {
    var candidates = [];
    candidates = ChipChooser.merge(candidates, new ChipCandidate("FxChip-1234", -70, null));
    candidates = ChipChooser.merge(candidates, new ChipCandidate("FxChip-5678", -50, null));

    Test.assertEqualMessage(candidates.size(), 2, "two chips in range");
    return true;
}

(:test)
function testTheChooserMenuListsTheStrongestFirst(logger as Test.Logger) as Lang.Boolean {
    var sorted = ChipChooser.sortByStrength([
        new ChipCandidate("weak", -90, null),
        new ChipCandidate("strong", -40, null),
        new ChipCandidate("middling", -65, null)]);

    Test.assertEqualMessage((sorted[0] as ChipCandidate).name, "strong", "likeliest at the top");
    Test.assertEqualMessage((sorted[1] as ChipCandidate).name, "middling", "then");
    Test.assertEqualMessage((sorted[2] as ChipCandidate).name, "weak", "then");
    return true;
}

(:test)
function testTheMenuLabelCarriesTheNameAndSignal(logger as Test.Logger) as Lang.Boolean {
    // Issue #11 asks the menu to show name and RSSI, because with two
    // identically named chips the signal is the only way to tell them apart.
    Test.assertEqualMessage(new ChipCandidate("FxChip-1234", -54, null).label(),
        "FxChip-1234  -54 dBm", "name and signal");
    return true;
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

(:test)
function testChoosingAChipPersistsItAcrossAppRestarts(logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("lastChipName");
    var ble = new FreelapBleDelegate();

    ble.rememberChip("FxChip-4242");

    Test.assertEqualMessage(ble.rememberedName, "FxChip-4242", "held for this session");
    Test.assertEqualMessage(Properties.getValue("lastChipName"), "FxChip-4242",
        "and written to settings, which is what survives a restart");

    ble.forgetChip();
    Test.assertEqualMessage(ble.rememberedName, "", "forgotten in this session");
    Test.assertEqualMessage(Properties.getValue("lastChipName"), "", "and in settings");

    Properties.setValue("lastChipName", previous);
    ble.stop();
    return true;
}

(:test)
function testANewDelegatePicksUpTheRememberedChip(logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("lastChipName");
    Properties.setValue("lastChipName", "FxChip-7777");

    var ble = new FreelapBleDelegate();

    Test.assertEqualMessage(ble.rememberedName, "FxChip-7777", "read at construction");

    Properties.setValue("lastChipName", previous);
    ble.stop();
    return true;
}
