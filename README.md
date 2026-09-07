# Freelap for Garmin (Connect IQ)

A native Garmin watch app that connects to a Freelap FxChip BLE over Bluetooth Low Energy, receives every transmitter crossing the chip recorded, and writes split time (µs), cumulative time, distance, velocity, speed and pace into the activity as FIT developer fields — one Garmin lap per Freelap rep, plus rep and session summaries.

Read `docs/DESIGN.md` first. The short version: the watch cannot sense Freelap's magnetic transmitters itself; the chip does, and the watch consumes the chip's BLE output exactly as the MyFreelap phone app does.

## Status

Skeleton, and it builds: `monkeyc -l 1` is clean for every `manifest.xml` product whose device definition is installed (19 of 24, API 3.2 through 6.0), the app launches in the simulator, and `monkeydo /t` runs the unit tests. **The packet format in `source/ble/FreelapProtocol.mc` is still a placeholder** until you have sniffed the real chip (`docs/REVERSE-ENGINEERING.md`). The rest of the pipeline (BLE state machine, split engine, FIT fields, UI) is complete enough to test with `tools/fake_chip.py`.

## Layout

```
manifest.xml / monkey.jungle        CIQ project
resources/settings/                 course strings, BLE latency, capture mode
source/FreelapApp.mc                app entry, wiring
source/ble/FreelapProtocol.mc       ← the only file that knows the packet format
source/ble/FreelapBleDelegate.mc    scan / pair / subscribe / reconnect
source/model/Course.mc              "S:0;L:30;F:100" course parser & matcher
source/model/SplitEvent.mc          one crossing with derived metrics
source/model/SplitEngine.mc         crossings → splits → reps
source/fit/FitRecorder.mc           session + developer fields + laps
source/ui/                          activity screen, buttons, save menu
source-test/                        Monkey C unit tests (see AGENTS.md)
site/                               the project website (see below)
tools/decode_capture.py             find timestamp fields in a BLE capture
tools/fake_chip.py                  BLE peripheral: one rep, N synthetic reps, or a capture replay
tools/check_links.py                internal links in the site and the docs
tools/validate_resources.py         what CI can check without the Garmin SDK
tools/fit_fields.py                 read the fl_* developer fields out of a .FIT
tools/splits_to_csv.py              a dumped on-watch split log -> CSV
tools/fit_splits.py                 a .FIT file -> CSV (splits, laps or session)
tools/make_icons.py                 render the launcher icon at every size devices ask for
tools/tests/                        pytest suite for the above
docs/DESIGN.md                      architecture, timing model, FIT layout
docs/EXPORT.md                      getting the splits out, and what each column means
docs/FREELAP-ENQUIRY.md             drafted letter asking Freelap for the spec
docs/screenshots/                   the main view at each target resolution
captures/                           BLE captures the protocol was derived from
docs/REVERSE-ENGINEERING.md         sniffing plan
```

## Website

<https://maximumtrainer.github.io/garmin-cqc-freelap/>

Published by `.github/workflows/pages.yml` from **`site/`** — a plain static
page, no Jekyll. `docs/` is deliberately *not* the publishing source: Pages
serving `/docs` would also publish the unsent letter to Freelap and the
unsubmitted store listing, and an exclude list only works until the next
working document is added. The screenshots the page uses are listed in
`site/assets.txt` and copied in at deploy time, so there is one copy of each
image in the repository.

## Work tracking

The plan is broken into [GitHub issues](https://github.com/MaximumTrainer/garmin-cqc-freelap/issues) grouped by milestone (M0 Foundations → M5 Beyond v0.1), each carrying a requirement and acceptance criteria. The issues are the single source of truth: the criteria on an issue are the test list for the PR that closes it (see `AGENTS.md`).

## Build

1. Install the Connect IQ SDK (7.x or newer) and the VS Code Monkey C extension.
2. Generate a developer key (VS Code: *Monkey C: Generate a Developer Key*).
3. Download the device definitions you need in the SDK Manager, and trim `manifest.xml` products to devices you own. `monkeyc -d <id>` refuses an id whose definition is not installed; the manifest itself only warns.
4. `monkeyc -f monkey.jungle -d fr265 -l 1 -o bin/freelap.prg -y developer_key.der` (or *Run* from VS Code).
5. Sideload `bin/freelap.prg` to `GARMIN/APPS/` on the watch.

CI does not run `monkeyc`: the SDK needs a Garmin login, so it cannot be
installed on a GitHub-hosted runner. [`.github/workflows/lint.yml`](.github/workflows/lint.yml)
validates the manifest, the resources and their cross-references, and runs the
Python tooling tests; its header comment carries the exact `monkeyc`/`monkeydo`
step to add once a self-hosted runner has the SDK. Run those two rings locally
before you push — see **Test** below.

```powershell
python tools/validate_resources.py   # the same check CI runs
python -m pytest tools/tests -q
```

## Test

Unit tests live in `source-test/` and run in the simulator:

```powershell
connectiq                                   # start the simulator once
monkeyc -f monkey.jungle -d fr265 -l 1 --unit-test -y developer_key.der -o bin/freelap-test.prg
monkeydo bin/freelap-test.prg fr265 -t
```

On Windows the SDK's `monkeydo.bat` takes `/t`, not `-t`. Or use *Monkey C: Run
Tests* in VS Code. `source-test/CourseTest.mc` still has one deliberately
failing test (`testCourseRejectsNonMonotonicDistances`) marking the next piece
of work — course validation, issue #13. `AGENTS.md` describes the outside-in
TDD loop this project follows.

## First run

1. Settings (Garmin Connect app → the watch → Connect IQ apps → Freelap): enter your course, e.g. `S:0;L:30;L:60;F:100`, enable *Capture mode*.
2. Open the app; it scans for the chip. With the placeholder UUIDs it will only find `tools/fake_chip.py` or a chip whose name starts with `FxChip`/`Freelap`.
3. Press START, run a rep. In capture mode the last raw packet is shown on screen and the last 60 packets are kept in app storage (written at exit).
4. Controls: START = start / pause / resume. BACK = end the current rep while recording,
   or open Save/Discard while paused. On a touch screen, tapping the upper half is START and
   the lower half is BACK. Ending a rep with no crossings shows *No splits* and writes nothing.
   There is no way out of a running session without pausing first, which is deliberate. If the
   watch closes the app with a session still open, the session is **saved**, not discarded.

## Where the data ends up

In the `.FIT` file, as developer fields with a `field_description` each (field ids 0–10 on `record`, 20–25 on `lap`, 40–43 on `session`), and independently in `Application.Storage` as the last session's split log.

```bash
python tools/fit_splits.py activity.fit > splits.csv    # from the FIT file
python tools/splits_to_csv.py dump.txt > splits.csv     # from the watch's own log
```

**`docs/EXPORT.md`** explains both routes, what every column means, and which single number in there is an estimate rather than a measurement. `python tools/fit_fields.py <file.fit> --values` prints the raw developer field table, which is what to look at when a column comes out empty; `tools/tests/data/reference-session.fit` is a real file from the simulator that CI asserts the table against. Garmin Connect charts the record fields and lists lap fields per lap. For lossless µs values use the FIT file directly (FIT SDK `FitCSVTool`, `fitparse`, `fitdecode`); Connect's UI rounds floats but shows uint32 as-is.
