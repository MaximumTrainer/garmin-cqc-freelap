using Toybox.Lang;
using Toybox.Test;

// Limits the chip itself imposes, from Freelap's published documentation
// rather than from anything we worked out.
//
//   * "Your FxChip BLE has a memory of maximum 10 intermediate times. This
//     means that your track must contain a maximum of 11 transmitters."
//     (FxChip BLE manual; the FAQ says the same.)
//   * "Respect a minimum of 10 meters or 0.7 seconds between 2 transmitters."
//     (FAQ.)
//
// Both are warnings rather than rejections, and the distinction is the point.
// A course that breaks them is not unusable - the app can still record what
// the chip reports - it is *quietly incomplete*, which is worse. An athlete
// who sets out twelve transmitters gets splits for eleven of them and no
// indication that anything is missing, and the numbers all look right.
//
// Only the distance rule can be checked from a course definition. The 0.7 s
// rule depends on how fast the athlete runs, which the course does not know.

(:test)
function testACourseWithinTheChipsLimitsHasNothingToSay(logger as Test.Logger) as Lang.Boolean {
    var course = Course.fromSpec("S:0;L:30;L:60;F:100", "Course 1");

    Test.assertEqualMessage(course.problem(), "", "no complaint");
    return true;
}

(:test)
function testACourseWithElevenTransmittersIsAccepted(logger as Test.Logger) as Lang.Boolean {
    // Eleven is the documented maximum, not the first value over it.
    var spec = "S:0";
    for (var i = 1; i <= 9; i++) { spec += ";L:" + (i * 20).format("%d"); }
    spec += ";F:200";

    var course = Course.fromSpec(spec, "Course 1");

    Test.assertEqualMessage(course.size(), 11, "eleven transmitters");
    Test.assertEqualMessage(course.problem(), "", "and no complaint");
    return true;
}

(:test)
function testACourseWithTwelveTransmittersWarns(logger as Test.Logger) as Lang.Boolean {
    var spec = "S:0";
    for (var i = 1; i <= 10; i++) { spec += ";L:" + (i * 20).format("%d"); }
    spec += ";F:220";

    var course = Course.fromSpec(spec, "Course 1");

    // The chip stores ten intermediate times. A twelfth transmitter means
    // splits the chip never reports, and nothing downstream could tell.
    Test.assertMessage(!course.problem().equals(""), "says something");
    Test.assertMessage(course.problem().find("11") != null,
                       "names the limit: " + course.problem());
    return true;
}

(:test)
function testTooManyTransmittersIsAWarningNotARejection(logger as Test.Logger) as Lang.Boolean {
    var spec = "S:0";
    for (var i = 1; i <= 10; i++) { spec += ";L:" + (i * 20).format("%d"); }
    spec += ";F:220";

    var course = Course.fromSpec(spec, "Course 1");

    // Falling back to the default course would throw away the athlete's own
    // distances and record a session against the wrong ones - worse than
    // recording eleven of their twelve transmitters and saying so.
    Test.assertMessage(!course.usingFallback, "the athlete's course is still in force");
    Test.assertEqualMessage(course.size(), 12, "all of it kept");
    return true;
}

(:test)
function testTransmittersCloserThanTenMetresWarn(logger as Test.Logger) as Lang.Boolean {
    var course = Course.fromSpec("S:0;L:5;F:30", "Course 1");

    // Below this the chip may simply not detect the second transmitter, and a
    // crossing that never happened is indistinguishable from one the watch
    // missed.
    Test.assertMessage(!course.problem().equals(""), "says something");
    Test.assertMessage(course.problem().find("10") != null,
                       "names the distance: " + course.problem());
    return true;
}

(:test)
function testExactlyTenMetresApartIsFine(logger as Test.Logger) as Lang.Boolean {
    var course = Course.fromSpec("S:0;L:10;F:20", "Course 1");

    Test.assertEqualMessage(course.problem(), "", "ten metres is the minimum, not below it");
    return true;
}

(:test)
function testAQuickCourseIsNeverBelowTheMinimumGap(logger as Test.Logger) as Lang.Boolean {
    // The on-watch dial starts at 10 m (issue #22), which is exactly the
    // documented minimum. This pins the two together so that lowering one
    // without the other fails here.
    var course = Course.fromSpec(Settings.quickCourseSpec(Settings.QUICK_MIN_M), "Quick");

    Test.assertEqualMessage(course.problem(), "", "the shortest quick course is legal");
    return true;
}
