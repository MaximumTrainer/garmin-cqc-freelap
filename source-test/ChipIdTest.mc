using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;
using Toybox.Test;

// Issue #64: the athlete types the id printed on their FxChip into Garmin
// Connect, and the watch stores it.
//
// Almost everything here is about input that is *wrong*, because the setting
// is a free-text box on a phone and the value is being copied off a small
// piece of plastic. Two failures matter and they are not symmetrical:
//
//   * refusing something valid is visible immediately - the athlete sees the
//     watch still saying no chip is bound, and tries again;
//   * accepting something invalid as a *different valid-looking id* is
//     invisible until the end of a session that recorded nothing.
//
// So the normaliser is forgiving about separators and case, and refuses
// everything else outright rather than salvaging what it can.

// ---------------------------------------------------------------------------
// What the athlete might type
// ---------------------------------------------------------------------------

(:test)
function testTheIdPrintedOnTheChipIsAccepted(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(Settings.normaliseChipId("BC-9636"), "BC-9636", "as printed");
    return true;
}

(:test)
function testTheSameChipTypedSeveralWaysIsTheSameChip(logger as Test.Logger) as Lang.Boolean {
    // All of these are somebody copying the same six characters off a chip.
    // Rejecting any of them would be a support question, not a safety feature.
    Test.assertEqualMessage(Settings.normaliseChipId("bc-9636"), "BC-9636", "lowercase");
    Test.assertEqualMessage(Settings.normaliseChipId("BC9636"), "BC-9636", "no separator");
    Test.assertEqualMessage(Settings.normaliseChipId("BC 9636"), "BC-9636", "space");
    Test.assertEqualMessage(Settings.normaliseChipId("BC_9636"), "BC-9636", "underscore");
    Test.assertEqualMessage(Settings.normaliseChipId("  bc 9636  "), "BC-9636", "padded");
    return true;
}

(:test)
function testALowNumberedChipIsPaddedToFourDigits(logger as Test.Logger) as Lang.Boolean {
    // Freelap give the format publicly as "2 letters - 4 digits", and the
    // chip's own Bluetooth local name is a fixed-width XX-XXXX, so a chip
    // numbered 42 is printed AA-0042. If hardware ever contradicts that it
    // should fail here rather than confuse an athlete whose watch disagrees
    // with the thing in their hand (#63).
    Test.assertEqualMessage(Settings.normaliseChipId("AA-42"), "AA-0042", "unpadded");
    Test.assertEqualMessage(Settings.normaliseChipId("AA-0042"), "AA-0042", "already padded");
    Test.assertEqualMessage(Settings.normaliseChipId("AA-0"), "AA-0000", "zero");
    return true;
}

(:test)
function testAnIdWiderThanFourDigitsIsAcceptedNotRefused(logger as Test.Logger) as Lang.Boolean {
    // The id is a 16-bit field, which holds far more than four digits can
    // show, so a five-digit id is probably never issued. Accepted anyway:
    // refusing a real chip on the strength of a printing convention would be
    // a much worse failure than accepting one that does not exist (#63).
    Test.assertEqualMessage(Settings.normaliseChipId("BC-65535"), "BC-65535", "the widest id");
    Test.assertEqualMessage(Settings.normaliseChipId("BC-65536"), "", "past 16 bits");
    return true;
}

// ---------------------------------------------------------------------------
// What must not be salvaged
// ---------------------------------------------------------------------------

(:test)
function testAnAbsentSettingReadsAsUnboundNotNull(logger as Test.Logger) as Lang.Boolean {
    // Properties.setValue will not accept null, so "the property is absent"
    // is only reachable through the normaliser - which is why it is pure.
    Test.assertEqualMessage(Settings.normaliseChipId(null), "", "absent");
    Test.assertEqualMessage(Settings.normaliseChipId(""), "", "empty");
    Test.assertEqualMessage(Settings.normaliseChipId("   "), "", "whitespace");
    return true;
}

(:test)
function testTheWrongTypeIsUnbound(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(Settings.normaliseChipId(9636), "", "a number");
    Test.assertEqualMessage(Settings.normaliseChipId(true), "", "a boolean");
    return true;
}

(:test)
function testSomethingThatIsNotAChipIdIsRefusedOutright(logger as Test.Logger) as Lang.Boolean {
    // Every one of these could be salvaged into a plausible id by a normaliser
    // trying to be helpful, and every one of them would then bind the watch to
    // a chip that does not exist.
    Test.assertEqualMessage(Settings.normaliseChipId("9636"), "", "no letters");
    Test.assertEqualMessage(Settings.normaliseChipId("BC"), "", "no digits");
    Test.assertEqualMessage(Settings.normaliseChipId("B-9636"), "", "one letter");
    Test.assertEqualMessage(Settings.normaliseChipId("BCD-9636"), "", "three letters");
    Test.assertEqualMessage(Settings.normaliseChipId("B1-9636"), "", "digit among the letters");
    Test.assertEqualMessage(Settings.normaliseChipId("9636-BC"), "", "the wrong way round");
    Test.assertEqualMessage(Settings.normaliseChipId("BC-96A6"), "", "letter among the digits");
    Test.assertEqualMessage(Settings.normaliseChipId("BC-96.6"), "", "punctuation");
    Test.assertEqualMessage(Settings.normaliseChipId("FxChip BLE BC-9636"), "",
                            "the whole advertised name");
    return true;
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

(:test)
function testABoundChipSurvivesBeingWrittenAndReadBack(logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("chipId");

    Settings.setChipId("bc 9636");

    Test.assertEqualMessage(Settings.chipId(), "BC-9636", "read back canonical");
    Test.assertMessage(Settings.isChipBound(), "and reported as bound");

    // Stored canonical, not as typed, so the on-watch picker (#63) and the
    // settings box cannot write two spellings of the same chip.
    Test.assertEqualMessage(Properties.getValue("chipId"), "BC-9636", "stored canonical");

    Properties.setValue("chipId", previous);
    return true;
}

(:test)
function testAnUnsetChipIdIsReportedAsUnbound(logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("chipId");
    Properties.setValue("chipId", "");

    Test.assertEqualMessage(Settings.chipId(), "", "empty");
    Test.assertMessage(!Settings.isChipBound(), "not bound");

    Properties.setValue("chipId", previous);
    return true;
}

(:test)
function testAMalformedStoredValueLeavesTheWatchUnbound(logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("chipId");
    // Written by hand, or by a version of the app that stored something else.
    Properties.setValue("chipId", "not a chip");

    Test.assertEqualMessage(Settings.chipId(), "", "unbound");
    Test.assertMessage(!Settings.isChipBound(), "and says so");

    Properties.setValue("chipId", previous);
    return true;
}

(:test)
function testWritingRubbishClearsTheBindingRatherThanCorruptingIt(logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("chipId");
    Settings.setChipId("BC-9636");

    Settings.setChipId("nonsense");

    // Better to be visibly unbound than quietly bound to the wrong thing.
    Test.assertEqualMessage(Settings.chipId(), "", "cleared");

    Properties.setValue("chipId", previous);
    return true;
}

// ---------------------------------------------------------------------------
// A sync while the app is running
// ---------------------------------------------------------------------------

(:test)
function testAChipIdChangedInGarminConnectTakesEffectWithoutARestart(
        logger as Test.Logger) as Lang.Boolean {
    var previous = Properties.getValue("chipId");
    Settings.setChipId("BC-9636");

    var app = Application.getApp();
    Properties.setValue("chipId", "ZZ-1234");
    app.onSettingsChanged();

    // Nothing caches the binding, which is the point: an athlete who fixes a
    // typo on their phone mid-warm-up should not have to relaunch the app.
    Test.assertEqualMessage(Settings.chipId(), "ZZ-1234", "the new chip");

    Properties.setValue("chipId", previous);
    return true;
}
