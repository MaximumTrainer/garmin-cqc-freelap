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
tools/decode_capture.py             find timestamp fields in a BLE capture
tools/fake_chip.py                  BLE peripheral that replays a rep
tools/validate_resources.py         what CI can check without the Garmin SDK
tools/tests/                        pytest suite for the above
docs/DESIGN.md                      architecture, timing model, FIT layout
captures/                           BLE captures the protocol was derived from
docs/REVERSE-ENGINEERING.md         sniffing plan
```

## Work tracking

The plan is broken into [GitHub issues](https://github.com/MaximumTrainer/garmin-cqc-freelap/issues) grouped by milestone (M0 Foundations → M5 Beyond v0.1), each carrying a requirement and acceptance criteria. The issues are the single source of truth: the criteria on an issue are the test list for the PR that closes it (see `AGENTS.md`).

## Build

1. Install the Connect IQ SDK (7.x or newer) and the VS Code Monkey C extension.
2. Generate a developer key (VS Code: *Monkey C: Generate a Developer Key*). `resources/drawables/launcher_icon.png` is a placeholder disc — replace it before release.
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
4. BACK while recording = manual rep end; START = pause; BACK while paused = save/discard.

## Where the data ends up

In the `.FIT` file, as developer fields with a `field_description` each (field ids 0–9 on `record`, 20–25 on `lap`, 40–43 on `session`). Garmin Connect charts the record fields and lists lap fields per lap. For lossless µs values use the FIT file directly (FIT SDK `FitCSVTool`, `fitparse`, `fitdecode`); Connect's UI rounds floats but shows uint32 as-is.
