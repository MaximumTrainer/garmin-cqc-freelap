using Toybox.Application;
using Toybox.Application.Properties;
using Toybox.Lang;

// Test-only helpers.
//
// These live inside a module rather than at file scope on purpose: the test
// runner collects *every* module-scope function annotated `(:test)` as a test
// case, so a helper written that way is run with a Logger as its first
// argument and reported as an ERROR. Inside a module it is still stripped from
// release builds by the annotation, but it is not a test.
(:test)
module TestSupport {

    // A rep's worth of Crossings from parallel time/code arrays.
    function burst(timesUs as Lang.Array, codes as Lang.Array) as Lang.Array {
        var out = [];
        for (var i = 0; i < timesUs.size(); i++) {
            out.add(new Crossing(timesUs[i], codes[i], "TEST"));
        }
        return out;
    }

    // Put `spec` in the course 1 setting, push it through the app the way
    // Garmin Connect would, and hand back the course the app ended up with.
    // The previous values are restored so tests do not leak into each other.
    function courseAfterSettingsChange(spec as Lang.String) as Course {
        var previousSpec = Properties.getValue("course1");
        var previousActive = Properties.getValue("activeCourse");

        Properties.setValue("course1", spec);
        Properties.setValue("activeCourse", 1);

        var app = Application.getApp() as FreelapApp;
        app.onSettingsChanged();
        var reloaded = app.course;

        Properties.setValue("course1", previousSpec);
        Properties.setValue("activeCourse", previousActive);
        return reloaded;
    }
}
