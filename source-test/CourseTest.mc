using Toybox.Lang;
using Toybox.Test;

// Tests for source/model/Course.mc.
//
// Driven by the acceptance criteria of issue #13, "Course model: parse,
// validate and match crossings to transmitters".
//
// The vocabulary these tests assume:
//   valid == false   the spec is rejected outright; codes/distances are empty
//                    and error says why. Nothing downstream can use it.
//   warning != ""    the spec parsed, but something is worth telling the
//                    athlete: a skipped segment, a course with no FINISH, or
//                    a fall back to the default.
//   openEnded        parsed, but the last transmitter is not a FINISH.

// ---------------------------------------------------------------------------
// Valid courses
// ---------------------------------------------------------------------------

(:test)
function testCourseParsesValidTwoTransmitterCourse(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;F:30", "2tx");

    Test.assertMessage(c.valid, "a start and a finish is a course");
    Test.assertEqualMessage(c.size(), 2, "two transmitters parsed");
    Test.assertEqualMessage(c.codes[0], TxCode.START, "first is START");
    Test.assertEqualMessage(c.codes[1], TxCode.FINISH, "second is FINISH");
    Test.assertEqualMessage(c.totalDistance(), 30.0, "total distance");
    Test.assertMessage(!c.openEnded, "a course ending in FINISH is not open-ended");
    return true;
}

(:test)
function testCourseParsesValidThreeTransmitterCourse(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;F:100", "3tx");

    Test.assertMessage(c.valid, "three-transmitter course is valid");
    Test.assertEqualMessage(c.size(), 3, "three transmitters parsed");
    Test.assertEqualMessage(c.codes[0], TxCode.START, "first is START");
    Test.assertEqualMessage(c.codes[1], TxCode.LAP, "second is LAP");
    Test.assertEqualMessage(c.codes[2], TxCode.FINISH, "third is FINISH");
    Test.assertEqualMessage(c.distances[1], 30.0, "cumulative distance at LAP");
    Test.assertEqualMessage(c.totalDistance(), 100.0, "total distance is the FINISH distance");
    return true;
}

(:test)
function testCourseParsesValidFiveTransmitterCourse(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:100;L:200;L:300;F:400", "5tx");

    Test.assertMessage(c.valid, "five-transmitter course is valid");
    Test.assertEqualMessage(c.size(), 5, "five transmitters parsed");
    Test.assertEqualMessage(c.codes[3], TxCode.LAP, "fourth is the last LAP");
    Test.assertEqualMessage(c.distances[3], 300.0, "cumulative distance at the last LAP");
    Test.assertEqualMessage(c.totalDistance(), 400.0, "total distance");
    return true;
}

(:test)
function testCourseAcceptsACourseWithNoFinishAndFlagsItOpenEnded(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;L:60", "open");

    Test.assertMessage(c.valid, "a course with no FINISH still parses");
    Test.assertEqualMessage(c.size(), 3, "all three transmitters kept");
    Test.assertMessage(c.openEnded, "flagged as open-ended");
    Test.assertMessage(!c.warning.equals(""), "and says so, so the watch can show it");
    return true;
}

(:test)
function testCourseAcceptsLowerCaseCodeLetters(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("s:0;l:30;f:100", "lower case");

    Test.assertMessage(c.valid, "the settings field has no caps lock");
    Test.assertEqualMessage(c.codes[2], TxCode.FINISH, "f is a FINISH");
    return true;
}

// ---------------------------------------------------------------------------
// Rejected courses. A rejected course carries no transmitters at all: half a
// course would silently derive splits over the wrong distances.
// ---------------------------------------------------------------------------

(:test)
function testCourseRejectsNonMonotonicDistances(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:60;F:30", "backwards");

    Test.assertEqualMessage(c.size(), 0, "a course whose distances go backwards must not parse");
    Test.assertMessage(!c.valid, "and is marked invalid");
    Test.assertMessage(!c.error.equals(""), "with a message for the watch");
    return true;
}

(:test)
function testCourseRejectsRepeatedDistances(logger as Test.Logger) as Lang.Boolean {
    // Two transmitters at the same metre mark give a zero-distance split.
    var c = new Course("S:0;L:30;F:30", "repeated");

    Test.assertMessage(!c.valid, "distances must strictly increase");
    Test.assertEqualMessage(c.size(), 0, "nothing is kept");
    return true;
}

(:test)
function testCourseRejectsAnUnknownCodeLetter(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;X:30;F:100", "unknown letter");

    Test.assertMessage(!c.valid, "X is not a transmitter code");
    Test.assertEqualMessage(c.size(), 0, "nothing is kept");
    Test.assertMessage(c.error.find("X") != null, "the message names the offending code");
    return true;
}

(:test)
function testCourseRejectsANonNumericDistance(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:thirty;F:100", "bad distance");

    Test.assertMessage(!c.valid, "thirty is not a distance");
    Test.assertEqualMessage(c.size(), 0, "nothing is kept");
    return true;
}

(:test)
function testCourseRejectsANegativeDistance(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:-10;F:30", "negative");

    Test.assertMessage(!c.valid, "a course cannot start behind the start line");
    return true;
}

(:test)
function testCourseRejectsASingleTransmitter(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0", "lonely");

    Test.assertMessage(!c.valid, "one transmitter cannot produce a split");
    return true;
}

(:test)
function testCourseRejectsAnEmptySpec(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("", "empty");

    Test.assertMessage(!c.valid, "an empty course string is not a course");
    Test.assertEqualMessage(c.size(), 0, "nothing is kept");
    return true;
}

(:test)
function testCourseSkipsMalformedSegments(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;garbage;F:100", "malformed");

    Test.assertMessage(c.valid, "a segment with no colon is dropped, not fatal");
    Test.assertEqualMessage(c.size(), 2, "a segment without a colon is dropped");
    Test.assertEqualMessage(c.totalDistance(), 100.0, "FINISH still carries the distance");
    Test.assertMessage(!c.warning.equals(""), "but the drop is reported, not silent");
    return true;
}

// ---------------------------------------------------------------------------
// Falling back to the default. fromSpec() is the seam the app uses, kept free
// of Toybox so it can be tested without touching settings.
// ---------------------------------------------------------------------------

(:test)
function testCourseFallsBackToTheDefaultOnAnEmptySpec(logger as Test.Logger) as Lang.Boolean {
    var c = Course.fromSpec("", "Course 1");

    Test.assertMessage(c.valid, "the fallback is usable");
    Test.assertEqualMessage(c.size(), 2, "the default course is S:0;F:30");
    Test.assertEqualMessage(c.totalDistance(), 30.0, "default total distance");
    Test.assertMessage(c.usingFallback, "flagged as the fallback, not the athlete's course");
    Test.assertMessage(!c.warning.equals(""), "and warns that it is a fallback");
    return true;
}

(:test)
function testCourseFallsBackToTheDefaultOnANullSpec(logger as Test.Logger) as Lang.Boolean {
    var c = Course.fromSpec(null, "Course 1");

    Test.assertMessage(c.valid, "a missing setting is not a crash");
    Test.assertEqualMessage(c.totalDistance(), 30.0, "the default course is in force");
    return true;
}

(:test)
function testCourseFallsBackToTheDefaultOnAnInvalidSpecAndKeepsTheReason(logger as Test.Logger) as Lang.Boolean {
    var c = Course.fromSpec("S:0;L:60;F:30", "Course 2");

    Test.assertMessage(c.valid, "the fallback is usable");
    Test.assertEqualMessage(c.totalDistance(), 30.0, "the default course is in force");
    Test.assertMessage(c.warning.find("increase") != null,
        "the warning still explains what was wrong with the setting");
    return true;
}

(:test)
function testCourseFromSpecKeepsAValidSpecUntouched(logger as Test.Logger) as Lang.Boolean {
    var c = Course.fromSpec("S:0;L:30;F:100", "Course 3");

    Test.assertEqualMessage(c.totalDistance(), 100.0, "a valid spec is used as given");
    Test.assertMessage(!c.usingFallback, "it is the athlete's own course");
    Test.assertEqualMessage(c.warning, "", "and needs no warning");
    return true;
}

(:test)
function testCourseProblemIsEmptyOnlyForACleanCourse(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqualMessage(new Course("S:0;F:30", "clean").problem(), "",
        "clean course, nothing to say");
    Test.assertMessage(!new Course("S:0;L:60;F:30", "bad").problem().equals(""),
        "rejected course reports its error");
    Test.assertMessage(!new Course("S:0;L:30", "open").problem().equals(""),
        "open-ended course reports its warning");
    return true;
}

// ---------------------------------------------------------------------------
// Matching crossings to transmitters
// ---------------------------------------------------------------------------

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

    Test.assertEqualMessage(c.matchCrossing(3, TxCode.FINISH), -1, "a fourth crossing has no course index");
    return true;
}

(:test)
function testCourseMatchesAnEarlyFinishToTheFinishTransmitter(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;L:60;F:100", "4tx");

    // The athlete crossed START and then went straight past the finish line.
    Test.assertEqualMessage(c.matchCrossing(1, TxCode.FINISH), 3,
        "an early FINISH is still the FINISH transmitter");
    return true;
}

(:test)
function testCourseFallsBackToIndexOrderWhenTheChipGivesNoCode(logger as Test.Logger) as Lang.Boolean {
    var c = new Course("S:0;L:30;F:100", "3tx");

    Test.assertEqualMessage(c.matchCrossing(1, TxCode.UNKNOWN), 1, "no code: trust the arrival order");
    return true;
}
