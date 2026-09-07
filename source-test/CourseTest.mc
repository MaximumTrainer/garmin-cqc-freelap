using Toybox.Lang;
using Toybox.Test;

// Tests for source/model/Course.mc.
//
// Driven by the acceptance criteria of issue #13, "Course model: parse,
// validate and match crossings to transmitters".
// Criteria still to cover, in order:
//   - valid 2- and 5-transmitter courses
//   - unknown code letter (rejected)
//   - missing FINISH (accepted, flagged as open-ended)
//   - empty string (falls back to default and warns)
//   - parse errors surfaced on the watch via onSettingsChanged

(:test)
function testCourseParsesValidThreeTransmitterCourse(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;F:100", "3tx");

    Test.assertEqualMessage(c.size(), 3, "three transmitters parsed");
    Test.assertEqualMessage(c.codes[0], TxCode.START, "first is START");
    Test.assertEqualMessage(c.codes[1], TxCode.LAP, "second is LAP");
    Test.assertEqualMessage(c.codes[2], TxCode.FINISH, "third is FINISH");
    Test.assertEqualMessage(c.distances[1], 30.0, "cumulative distance at LAP");
    Test.assertEqualMessage(c.totalDistance(), 100.0, "total distance is the FINISH distance");
    return true;
}

(:test)
function testCourseSkipsMalformedSegments(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;garbage;F:100", "malformed");

    Test.assertEqualMessage(c.size(), 2, "a segment without a colon is dropped");
    Test.assertEqualMessage(c.totalDistance(), 100.0, "FINISH still carries the distance");
    return true;
}

(:test)
function testCourseMatchesCrossingsInCodeOrder(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;F:100", "3tx");

    Test.assertEqualMessage(c.matchCrossing(0, TxCode.START), 0, "START matches index 0");
    Test.assertEqualMessage(c.matchCrossing(1, TxCode.LAP), 1, "LAP matches index 1");
    Test.assertEqualMessage(c.matchCrossing(2, TxCode.FINISH), 2, "FINISH matches index 2");
    return true;
}

(:test)
function testCourseReturnsUnmatchedForCrossingBeyondTheCourse(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;F:100", "3tx");

    // Acceptance criterion: "a rep with an extra crossing (more than the course
    // has) yields txIndex = -1 for the extra".
    Test.assertEqualMessage(c.matchCrossing(3, TxCode.FINISH), -1, "a fourth crossing has no course index");
    return true;
}

// ---------------------------------------------------------------------------
// RED. This is the next criterion to implement, not a bug in the test.
//
// Acceptance criterion: "non-monotonic distances (rejected)".
// Course.parse() currently has no validation, so it happily builds a course
// whose distances go backwards; every split derived from it would then have a
// negative distance and a nonsense velocity.
//
// Expected to fail with size() == 3 until validation lands. When it does, this
// test should grow an assertion on whatever the error is reported through
// (the criterion also requires the message to reach the watch), and the
// remaining validation criteria listed at the top of this file follow.
// ---------------------------------------------------------------------------
(:test)
function testCourseRejectsNonMonotonicDistances(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:60;F:30", "backwards");

    Test.assertEqualMessage(c.size(), 0, "a course whose distances go backwards must not parse");
    return true;
}
