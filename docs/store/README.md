# Store submission materials

`LISTING.md` is the draft listing copy: name, descriptions, the privacy
statement, the permission justifications and the trademark note. It ends with
six things that have to be true before any of this is submitted — the first
being that the protocol is still a hypothesis and the app has never seen a real
chip.

`screenshots/` holds five captures, cropped from the simulator to roughly the
display area:

| file | screen |
| --- | --- |
| `fr265-recording.png` | recording — velocity, split detail, rep line |
| `fr265.png` | idle — chip status and the course in force |
| `fr265-course-list.png` | choosing one of the configured courses |
| `fr265-quick-course.png` | dialling a quick course |
| `fr645m-recording.png` | the recording screen on a 240×240 face |

**These are not submittable as they are, and it matters why.** The recording
screens were produced by injecting a synthetic rep into `FreelapApp.onStart`,
because there is no chip and no way to feed BLE crossings into the simulator —
so the numbers on them are made up. A store listing must not present invented
results as a recording. Retake them from a real session once #25 has been done.

They are also approximate crops of a simulator window rather than exact
device-resolution images, which is what Garmin's submission form wants.

Nothing here is submitted or scheduled to be. Publishing is a decision for the
repo owner, and `LISTING.md` lists what has to happen first.
