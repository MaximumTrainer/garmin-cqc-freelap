using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Test;

// Driven by the acceptance criteria of issue #20, "Activity screen: live split
// readout, rep counter, chip status".
//
// The screen is read at a glance, mid-session, often in sunlight. What matters
// is that the numbers are in the units a sprint coach expects, that the chip
// status colour means what it looks like it means, and that nothing on it is
// drawn in a grey too thin to read on a MIP display with the backlight off.

// ---------------------------------------------------------------------------
// Number formatting
// ---------------------------------------------------------------------------

(:test)
function testSplitTimeIsShownToAHundredthOfASecond(logger as Test.Logger) as Lang.Boolean {
    var ev = new SplitEvent();

    ev.splitTimeUs = 4120000;
    Test.assertEqualMessage(ev.formatSplit(), "4.12", "4.120 s");

    ev.splitTimeUs = 4129999;
    Test.assertEqualMessage(ev.formatSplit(), "4.12", "truncated, not rounded up past the measurement");

    ev.splitTimeUs = 4050000;
    Test.assertEqualMessage(ev.formatSplit(), "4.05", "leading zero in the hundredths is kept");

    ev.splitTimeUs = 0;
    Test.assertEqualMessage(ev.formatSplit(), "0.00", "a zero split still reads as a time");
    return true;
}

(:test)
function testSplitTimeOverTenSecondsIsNotTruncated(logger as Test.Logger) as Lang.Boolean {
    var ev = new SplitEvent();
    ev.splitTimeUs = 11930000;

    Test.assertEqualMessage(ev.formatSplit(), "11.93", "a whole rep time");
    return true;
}

(:test)
function testPaceIsShownAsMinutesAndSecondsPerKilometre(logger as Test.Logger) as Lang.Boolean {
    var view = new MainView();

    Test.assertEqualMessage(view.formatPace(137.3), "2:17/km", "137.3 s/km");
    Test.assertEqualMessage(view.formatPace(112.0), "1:52/km", "112 s/km");
    Test.assertEqualMessage(view.formatPace(305.0), "5:05/km", "seconds are zero padded");
    return true;
}

(:test)
function testPaceIsBlankedRatherThanInfiniteWhenThereIsNoVelocity(logger as Test.Logger) as Lang.Boolean {
    var view = new MainView();

    Test.assertEqualMessage(view.formatPace(0.0), "--:--/km", "a stopped athlete has no pace");
    return true;
}

(:test)
function testVelocityIsShownToTwoDecimalsInMetresPerSecond(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    // The worked rep's last split is 40 m in 4.450 s = 8.98876 m/s.
    var big = trace[1] as Lang.Dictionary;
    Test.assertEqualMessage(big.get(:text), "8.99 m/s", "two decimals, in m/s");
    return true;
}

(:test)
function testTheUnitIsNeverDrawnInANumericFont(logger as Test.Logger) as Lang.Boolean {
    // Graphics.FONT_NUMBER_* have digits and punctuation only. Letters drawn
    // in one come out as tofu, and getTextWidthInPixels measures the missing
    // glyphs as zero width - so the fitting logic thinks the string is narrow
    // and picks the font that cannot render it. Seen on a 240x240 face as
    // "8.99 [] / []".
    var numeric = [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
                   Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_THAI_HOT];
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    for (var i = 0; i < trace.size(); i++) {
        var line = trace[i] as Lang.Dictionary;
        if (line.get(:numericFont) as Lang.Boolean) { continue; }   // value drawn alone
        var font = line.get(:font);
        for (var n = 0; n < numeric.size(); n++) {
            Test.assertMessage(font != numeric[n],
                "\"" + line.get(:text) + "\" would be drawn in a digits-only font");
        }
    }
    return true;
}

(:test)
function testTheDetailLineCarriesSplitTimeDistanceAndPace(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    var detail = (trace[2] as Lang.Dictionary).get(:text) as Lang.String;
    Test.assertMessage(detail.find("4.45") != null, "the split time: " + detail);
    Test.assertMessage(detail.find("40m") != null, "the split distance: " + detail);
    Test.assertMessage(detail.find("/km") != null, "the pace: " + detail);
    return true;
}

(:test)
function testTheRepLineCountsRepsAndShowsTheLastRepTime(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainView(TestSupport.engineWithARep(), false);

    var repLine = (trace[3] as Lang.Dictionary).get(:text) as Lang.String;
    Test.assertMessage(repLine.find("1") != null, "one rep done: " + repLine);
    Test.assertMessage(repLine.find("11.93") != null, "and how long it took: " + repLine);
    return true;
}

// ---------------------------------------------------------------------------
// Chip status
// ---------------------------------------------------------------------------

(:test)
function testChipStatusIsGreenWhenSubscribed(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainViewWithBleState(BleState.SUBSCRIBED);

    Test.assertEqualMessage((trace[0] as Lang.Dictionary).get(:color), Graphics.COLOR_GREEN,
        "green means the chip is delivering crossings");
    return true;
}

(:test)
function testChipStatusIsYellowWhileScanningOrPairing(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(
        (TestSupport.traceMainViewWithBleState(BleState.SCANNING)[0] as Lang.Dictionary).get(:color),
        Graphics.COLOR_YELLOW, "scanning");
    Test.assertEqualMessage(
        (TestSupport.traceMainViewWithBleState(BleState.PAIRING)[0] as Lang.Dictionary).get(:color),
        Graphics.COLOR_YELLOW, "pairing");
    Test.assertEqualMessage(
        (TestSupport.traceMainViewWithBleState(BleState.DISCOVERING)[0] as Lang.Dictionary).get(:color),
        Graphics.COLOR_YELLOW, "discovering");
    return true;
}

(:test)
function testChipStatusIsRedWhenThereIsNoChip(logger as Test.Logger) as Lang.Boolean {
    var trace = TestSupport.traceMainViewWithBleState(BleState.IDLE);

    Test.assertEqualMessage((trace[0] as Lang.Dictionary).get(:color), Graphics.COLOR_RED,
        "red means no crossings are coming");
    return true;
}

// ---------------------------------------------------------------------------
// MIP readability
// ---------------------------------------------------------------------------

(:test)
function testNothingIsDrawnInAGreyTooThinForAMipDisplay(logger as Test.Logger) as Lang.Boolean {
    // Issue #20: "screen remains readable with the backlight off on MIP
    // displays (no thin grey text)". On a transflective MIP panel with no
    // backlight, mid greys on black are close to invisible; every line here is
    // either white or a status colour.
    var screens = [
        TestSupport.traceMainView(null, false),
        TestSupport.traceMainView(TestSupport.engineWithARep(), false),
        TestSupport.traceMainView(TestSupport.engineWithARep(), true)
    ];

    for (var s = 0; s < screens.size(); s++) {
        var trace = screens[s] as Lang.Array;
        for (var i = 0; i < trace.size(); i++) {
            var line = trace[i] as Lang.Dictionary;
            var color = line.get(:color);
            Test.assertMessage(color != Graphics.COLOR_LT_GRAY && color != Graphics.COLOR_DK_GRAY,
                "\"" + line.get(:text) + "\" is drawn in grey");
        }
    }
    return true;
}
