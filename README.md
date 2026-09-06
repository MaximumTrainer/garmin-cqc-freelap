# Freelap for Garmin (Connect IQ)

A native Garmin watch app that connects to a Freelap FxChip BLE over Bluetooth Low Energy, receives every transmitter crossing the chip recorded, and writes split time (µs), cumulative time, distance, velocity, speed and pace into the activity as FIT developer fields — one Garmin lap per Freelap rep, plus rep and session summaries.

Read `docs/DESIGN.md` first. The short version: the watch cannot sense Freelap's magnetic transmitters itself; the chip does, and the watch consumes the chip's BLE output exactly as the MyFreelap phone app does.

## Status

Skeleton. Everything compiles against the CIQ 3.1 API surface in intent, but **the packet format in `source/ble/FreelapProtocol.mc` is a placeholder** until you have sniffed the real chip (`docs/REVERSE-ENGINEERING.md`). The rest of the pipeline (BLE state machine, split engine, FIT fields, UI) is complete enough to test with `tools/fake_chip.py`.

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
tools/decode_capture.py             find timestamp fields in a BLE capture
tools/fake_chip.py                  BLE peripheral that replays a rep
docs/DESIGN.md                      architecture, timing model, FIT layout
docs/BACKLOG.md                     issue backlog (requirements + acceptance criteria)
captures/                           BLE captures the protocol was derived from
docs/REVERSE-ENGINEERING.md         sniffing plan
```

## Work tracking

The plan is broken into GitHub issues grouped by milestone (M0 Foundations → M5 Beyond v0.1), each with a requirement and acceptance criteria. `docs/BACKLOG.md` mirrors them; `.github/issues.json` is the source and `tools/issues.py create` (re)creates them on GitHub.

## Build

1. Install the Connect IQ SDK (7.x or newer) and the VS Code Monkey C extension.
2. Add a `resources/drawables/launcher_icon.png` (40×40 is fine) and generate a developer key.
3. Trim `manifest.xml` products to devices you own.
4. `monkeyc -f monkey.jungle -d fr255 -o bin/freelap.prg -y developer_key.der` (or *Run* from VS Code). CI does not run `monkeyc` because the SDK needs a Garmin login; `.github/workflows/lint.yml` validates resources and tooling only.
5. Sideload `bin/freelap.prg` to `GARMIN/APPS/` on the watch.

## First run

1. Settings (Garmin Connect app → the watch → Connect IQ apps → Freelap): enter your course, e.g. `S:0;L:30;L:60;F:100`, enable *Capture mode*.
2. Open the app; it scans for the chip. With the placeholder UUIDs it will only find `tools/fake_chip.py` or a chip whose name starts with `FxChip`/`Freelap`.
3. Press START, run a rep. In capture mode the last raw packet is shown on screen and the last 60 packets are kept in app storage (written at exit).
4. BACK while recording = manual rep end; START = pause; BACK while paused = save/discard.

## Where the data ends up

In the `.FIT` file, as developer fields with a `field_description` each (field ids 0–9 on `record`, 20–25 on `lap`, 40–43 on `session`). Garmin Connect charts the record fields and lists lap fields per lap. For lossless µs values use the FIT file directly (FIT SDK `FitCSVTool`, `fitparse`, `fitdecode`); Connect's UI rounds floats but shows uint32 as-is.
