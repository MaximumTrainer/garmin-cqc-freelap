# Freelap → Garmin: native Connect IQ app design

Target: Connect IQ 3.1+ devices with the BluetoothLowEnergy API (Forerunner 245/645M/945 and later, Fenix 5 Plus/6/7/8, Venu, Edge 530+, etc.). Language: Monkey C. App type: watch-app (a full activity app, so it owns the FIT session).

## 1. The one thing to get right up front: what the watch can and cannot detect

A Freelap course is made of transmitters (Tx Junior Pro, Tx Pad Pro, Tx Touch Pro, Tx Track Pro, e-Starter). Each transmitter emits a coded, low-frequency magnetic field with a detection zone of about 1.5 m. The athlete wears an FxChip (or FxChip BLE) on the waistband; the chip is the only thing that detects the field and it timestamps every crossing with its own internal clock. Freelap quotes 2/100 s precision and requires at least 0.7 s (≈10 m) between two transmitters. The FxChip BLE does not stream each crossing in real time: it buffers the run and pushes the whole set of splits over Bluetooth Low Energy when it crosses a FINISH-coded transmitter, and the MyFreelap phone app receives it.

A Garmin watch has no receiver for that magnetic field. Its magnetometer is a slow (tens of Hz) DC/compass sensor exposed through the Sensor API; it cannot demodulate a coded kHz field, and the Connect IQ sandbox wouldn't give you raw samples fast enough even if the hardware could. So "detect Freelap transmitters" from the watch means one thing in practice:

**The watch talks to the FxChip BLE (or a Freelap Relay Coach BLE) over Bluetooth Low Energy, receives the crossing data the chip already captured, and writes it into the activity.** The transmitters are detected by the chip; the watch consumes the chip's output. This is the same relationship the MyFreelap phone app has with the chip, so nothing is lost versus the phone.

Consequence for timing: the numbers of record are the chip's. The watch's job is to keep them intact (microsecond field, no rounding), anchor them to wall-clock time as well as it can, and derive pace/speed/velocity from the distances you configure for the course.

## 2. System overview

```
 Tx START ──┐                         ┌──────────────────────────┐
 Tx LAP  ───┼─ magnetic field ─▶ FxChip BLE ── BLE GATT notify ─▶│  Garmin watch (CIQ app)  │
 Tx FINISH ─┘   (chip timestamps)     └──────────────────────────┘
                                              │
                        ┌─────────────────────┼──────────────────────┐
                        ▼                     ▼                      ▼
                 BLE layer            Split engine              FIT recorder
            (scan/pair/notify)   (course model, derive        (developer fields on
                                  pace/speed/velocity)         record/lap/session,
                                                               addLap per rep)
                                              │
                                              ▼
                                 .FIT file → Garmin Connect / Strava / your tools
```

Four modules, one direction of data flow:

1. **BLE layer** (`source/ble/`). Scans for the chip, pairs, subscribes to notifications, hands raw ByteArrays to the protocol adapter. Owns reconnect logic.
2. **Protocol adapter** (`source/ble/FreelapProtocol.mc`). The only file that knows Freelap's packet format. Today it is a stub that decodes a *hypothesised* layout and, in capture mode, logs every raw packet with a watch timestamp so you can reverse-engineer it. Swapping in the real decoder does not touch anything else.
3. **Split engine** (`source/model/`). Holds the course definition (ordered transmitters with cumulative distance), turns crossings into `SplitEvent`s, computes split time, cumulative time, distance, speed (km/h), velocity (m/s), pace (s/km and min/km), and tracks reps.
4. **FIT recorder** (`source/fit/`). Owns the `ActivityRecording.Session`, creates the developer fields, writes each split, calls `addLap()` at each FINISH so every Freelap rep is a Garmin lap, and writes rep/session summaries.

## 3. Timing model (why "microseconds" needs care)

There are three clocks:

| Clock | Resolution | Who owns it | Notes |
|---|---|---|---|
| FxChip internal | Freelap quotes 0.02 s precision; internal tick likely 1 ms or finer (verify by sniffing) | chip | Authoritative for split *durations*. Relative, not wall-clock. |
| Watch `System.getTimer()` | 1 ms, monotonic | watch | Used to timestamp BLE packet arrival. |
| Watch `Time.now()` / FIT timestamp | 1 s (FIT `timestamp` is uint32 seconds; records also carry `timestamp_ms` internally, but CIQ doesn't expose sub-second control) | watch | What Garmin Connect shows on the timeline. |

Design decisions:

- **Durations are stored as uint32 microseconds exactly as received, never rounded.** `split_time_us` and `rep_time_us` are the primary fields. A uint32 in µs wraps at 71.6 minutes; a single split or a single rep will never approach that. Cumulative session time is stored in ms as a separate field to avoid the wrap.
- **Absolute timestamps are estimated, not measured.** When the FINISH packet arrives at `t_arrive` (watch monotonic ms), the FINISH crossing is assumed to have happened at `t_arrive − L`, where `L` is the configurable `bleLatencyMs` setting (default 150 ms). Every earlier crossing in the same rep is placed at `t_finish − (rep_time − cumulative_time_at_crossing)`, so the gaps between estimates are the chip's own splits rather than an even spread. These go in `fl_est_ms` (ms since session start), named `_est_` so nobody mistakes them for measurements. Anyone analysing the file uses the chip's µs durations for performance and the estimate only for placing splits on the timeline.

  Worked, with the numbers `source-test/LatencyModelTest.mc` pins — session start at t=10 000 ms, burst at t=30 000, L=150, rep 0 / 4.120 / 7.480 / 11.930 s:

  | crossing | `fl_est_ms` | derivation |
  | --- | --- | --- |
  | FINISH | 19 850 | (30 000 − 150) − 10 000 |
  | LAP 2 | 15 400 | 19 850 − (11.930 − 7.480)×1000 |
  | LAP 1 | 12 040 | 19 850 − (11.930 − 4.120)×1000 |
  | START | 7 920 | 19 850 − 11.930×1000 |

  Changing `bleLatencyMs` shifts every estimate in a rep by exactly the delta; it never changes a duration.

- **An estimate that lands before the session started is clamped to 0 and flagged.** This is not defensive coding for an impossible case: the chip *buffers*, so starting the watch part-way through a rep gives crossings that genuinely predate the session. A negative offset is not a time, and `fl_est_ms` is a uint32. The clamp keeps the field valid; `SplitEvent.estClamped` (and `SplitEngine.clampedEstimates`) is what stops the resulting `0` being read as "this crossing happened exactly at session start". The flag travels in the stored split log because no FIT field carries it — adding a 21st developer field for a diagnostic was not worth it.

  **`L` has not been measured.** 150 ms is a placeholder until someone runs the ten timed trials against a phone stopwatch with a real chip (issue #15's third criterion). When that happens the measured value belongs here, replacing this paragraph.
- **Garmin laps are aligned to reps, not to individual splits.** `addLap()` can only be called "now"; CIQ cannot back-date a lap. Since the chip delivers a rep's splits in one burst at FINISH, the app calls `addLap()` once on FINISH, so each Garmin lap = one Freelap rep, with the rep's totals in lap-level developer fields. Individual splits are written as a burst of record-level developer fields (one split per 1 Hz record, see §5) plus kept in app storage for export.

If Freelap's chip turns out to also notify on START and each LAP crossing in real time (possible on newer firmware; the sniffing plan will tell you), the engine already supports "streaming" mode: each crossing is written the moment it arrives and `addLap()` can optionally fire on every crossing.

## 4. Distance and derived metrics

Transmitters don't know where they are. Distance comes from a **course profile** you set up once (in app settings via Garmin Connect / Express, or on-watch for quick sessions):

```
Course "100m fly-in"
  #  code     cumulative_m
  0  START    0
  1  LAP      30      (30 m)
  2  LAP      60      (30 m)
  3  FINISH   100     (40 m)
```

For a crossing *i* with chip cumulative time `T_i` (µs) and previous crossing time `T_{i-1}`:

- `split_time_us = T_i − T_{i−1}`
- `split_distance_m = D_i − D_{i−1}`
- `velocity_mps = split_distance_m / (split_time_us / 1e6)` (m/s, the sprint-coaching number)
- `speed_kmh = velocity_mps × 3.6`
- `pace_s_per_km = 1000 / velocity_mps` (also shown as m:ss/km on the watch)
- rep totals: `rep_time_us = T_finish − T_start`, `rep_distance_m` = the last transmitter the course could place, `rep_avg_velocity`, `rep_peak_velocity` (fastest split)

Worked example, and the numbers the unit tests pin (`source-test/SplitEngineTest.mc`):

| | split time | distance | velocity | speed | pace |
| --- | --- | --- | --- | --- | --- |
| START → LAP 1 | 4 120 000 µs | 30 m | 7.282 m/s | 26.21 km/h | 137.3 s/km |
| LAP 1 → LAP 2 | 3 360 000 µs | 30 m | 8.929 m/s | 32.14 km/h | 112.0 s/km |
| LAP 2 → FINISH | 4 450 000 µs | 40 m | 8.989 m/s | 32.36 km/h | 111.2 s/km |
| **rep** | 11 930 000 µs | 100 m | 8.382 m/s avg, 8.989 peak | | |

Three rules the arithmetic follows:

- **Chip time stays a `Long` until the rep origin has been subtracted.** The FxChip timestamps with its own clock, which may be an absolute uptime well past 2³¹ µs; `decodeNumber(UINT32)` returns a `Long` for exactly this reason. Narrowing before the subtraction wraps the value and every derived metric with it.
- **Durations stay integer microseconds end to end.** Nothing rounds before the FIT file.
- **A zero-length or zero-duration split gives velocity, speed and pace of 0**, never an exception and never a fabricated number. A transmitter that double-fires, and a crossing the course cannot place, both land here.

`best_rep_us` only ever considers `RepStatus.OK` reps — a "best" of 8 s from a rep where the athlete missed a transmitter would be worse than useless — while `total_distance_m` sums every rep, because the athlete ran the metres either way.

If the chip reports more crossings than the course has transmitters (athlete ran through an extra Tx, or a course with mixed codes), the engine matches by code sequence first (START → LAP… → FINISH) and falls back to index order, flagging the rep as `unmatched` in a status field rather than guessing distances. The rep's distance is the last transmitter the course could actually place, so a trailing unmatched crossing cannot invent one.

### 4.1 Course validation

The course string is typed by hand into a settings field, so it is the most likely thing in the system to be wrong, and a wrong course is silent: every split it produces is over the wrong distance and still looks plausible in the FIT file. `Course` therefore validates **all-or-nothing** — a rejected spec yields *no* transmitters, never the prefix that happened to parse.

Rejected, with the reason in `error`:

| Spec | Reason |
| --- | --- |
| `""` | course is empty |
| `S:0` | needs 2+ transmitters |
| `S:0;X:30;F:100` | unknown code 'X' |
| `S:0;L:thirty;F:100` | `'thirty'` is not a number |
| `S:-10;F:30` | negative distance |
| `S:0;L:60;F:30` | distances must increase |
| `S:0;L:30;F:30` | distances must increase (equal is a zero-length split, and a divide by zero) |

Accepted, with a note in `warning`:

| Spec | Note |
| --- | --- |
| `S:0;garbage;F:100` | the unreadable segment is dropped, and counted in the warning |
| `S:0;L:30;L:60` | `openEnded` — no FINISH, so reps end on the lap button |

`Course.fromSpec()` is the seam the app uses. It always hands back a course that can record: the athlete's if it parsed, otherwise `DEFAULT_SPEC` (`S:0;F:30`) with `usingFallback` set and the rejection reason in `warning`. `loadActive()` is the same thing plus the settings read, so everything above is testable without Toybox.

`problem()` is the one line the watch shows — `error` if there is one, else `warning`. `MainView` draws it under the course summary before recording starts (red when the athlete's own course was thrown away, amber for a caveat about the one in force), because the settings screen accepted the string and by the time a rep is running it is too late to find out.

Optional: the watch's own GPS-derived distance is left untouched in the native fields, so Garmin Connect's total distance stays sane on a track. The Freelap distance is a developer field, not a replacement for Garmin's distance.

## 5. FIT layout

All custom data goes through `Toybox.FitContributor` developer fields, which is the only supported way for a CIQ app to add data to the FIT file. Native record fields (speed, distance, cadence) cannot be overwritten. Developer fields are created once on the session at start (they must be held in class scope for the life of the session — a known gotcha) and appear in Garmin Connect charts and in the FIT file with a `field_description` message each.

Field numbers are the app's own namespace (0–255). Keep the total small: older devices cap developer fields per app and each costs memory.

**Record-level (MESG_TYPE_RECORD), written once per 1 Hz record.** Values are non-null only on the record(s) that carry a split; on every other record they are left at the last value or cleared, selectable by setting (`clearAfterWrite`, default true, so charts show spikes at split events rather than step plateaus).

| id | name | type | units | meaning |
|---|---|---|---|---|
| 0 | `fl_split_us` | uint32 | us | split duration from previous transmitter |
| 1 | `fl_cum_us` | uint32 | us | cumulative time since START within the rep |
| 2 | `fl_dist_m` | float | m | cumulative distance within rep (from course) |
| 3 | `fl_velocity` | float | m/s | split velocity |
| 4 | `fl_speed` | float | km/h | split speed |
| 5 | `fl_pace` | float | s/km | split pace |
| 6 | `fl_tx_idx` | uint8 | – | transmitter index in course (0 = START) |
| 7 | `fl_tx_code` | uint8 | – | 1 START, 2 LAP, 3 FINISH, 0 unknown |
| 8 | `fl_rep` | uint16 | – | rep number (1-based) |
| 9 | `fl_est_ms` | uint32 | ms | estimated crossing time, ms since session start (see §3) |

Because a rep's splits arrive together, the recorder queues them and drains one split per record tick, so N splits occupy N consecutive records (N seconds). Order is preserved and `fl_est_ms` carries the true estimated time, so the one-per-second placement is cosmetic only.

**Lap-level (MESG_TYPE_LAP), one Garmin lap per Freelap rep** (written just before `addLap()`):

| id | name | type | units |
|---|---|---|---|
| 20 | `fl_rep_time_us` | uint32 | us |
| 21 | `fl_rep_dist_m` | float | m |
| 22 | `fl_rep_avg_vel` | float | m/s |
| 23 | `fl_rep_peak_vel` | float | m/s |
| 24 | `fl_rep_splits` | uint8 | – (number of crossings) |
| 25 | `fl_rep_status` | uint8 | – (0 ok, 1 unmatched course, 2 partial) |

**Session-level (MESG_TYPE_SESSION)**, written before `save()`:

| id | name | type | units |
|---|---|---|---|
| 40 | `fl_reps` | uint16 | – |
| 41 | `fl_best_rep_us` | uint32 | us |
| 42 | `fl_total_fl_dist_m` | float | m |
| 43 | `fl_chip_id` | string(16) | – (chip name/serial from advertising) |

Known SDK caveat (Garmin forum bug report): lap/session developer fields are sometimes dropped if `setData()` and `addLap()`/`save()` happen in the same code path with no yield. The recorder therefore sets lap fields, waits one timer tick (≥250 ms) and only then calls `addLap()`; same for session fields before `save()`.

**Export alongside the FIT.** Every split is also appended to `Application.Storage` as a compact array. On save, the app writes a summary the user can view on-watch, and the raw event list is retrievable through the CIQ simulator / a companion phone app later if you want a CSV with full µs precision independent of Garmin Connect's rendering (Connect displays developer fields but rounds in the UI; the FIT file itself keeps the uint32).

### 5.1 How a lap actually gets cut

Two Connect IQ constraints decide the shape of `FitRecorder.onTick()`:

- **`addLap()` can only happen now.** Laps cannot be back-dated, which is why one Garmin lap per Freelap rep is the design at all.
- **`setData()` and `addLap()` in the same pass drops the lap's developer fields.** The close is therefore deferred by a tick. That deferral is load bearing; do not "simplify" it away.

Splits and rep summaries share **one queue**, in arrival order:

```
_queue = [ split, split, split, split, RepSummary,  split, split, ... ]
                                       ^ closes the rep those four belong to
```

One queue rather than a split queue plus a pending-lap slot, because reps can arrive faster than records drain — a chip that buffered several reps pushes them together, or an athlete runs a 30 m course as a set with no rest — and a single slot silently drops every lap but the last. That was a real defect, found by issue #17's "5 reps produce 5 lap messages" criterion.

Each tick does exactly one of, in this order:

1. **A lap is owed** → `addLap()`. Its fields were set on an earlier tick.
2. **The queue has work** → write the next record. If the *next* item is the `RepSummary` for the rep this split just finished, set the lap's six fields in the same pass — only `addLap()` needs the yield, and doing it here means a rep does not cost an extra, duplicate record.
3. **Nothing queued** → blank the record fields, if `clearAfterWrite`.

With `lapPerCrossing` on, every split arms a lap of its own carrying that split's numbers (`fl_rep_time_us` = the split time, `fl_rep_splits` = 1, status from whether the crossing matched), and the `RepSummary` markers are discarded so the rep does not also cut a lap.

`save()` runs the same drain with no ticks left, so lap fields and `addLap()` go in one pass there — the documented risk above, taken deliberately because the alternative is losing the rep altogether.

## 6. BLE layer

Constraints from the CIQ API: max 3 registered profiles, one delegate, pairing does not persist across app launches, writes limited to 20 bytes, notifications enabled by writing `0x0001` to the CCCD descriptor. Scan results expose device name, RSSI, service UUIDs, manufacturer-specific data and (4.x) raw advertising bytes.

State machine:

```
IDLE ─start─▶ SCANNING ─match─▶ PAIRING ─connected─▶ DISCOVERING ─cccd written─▶ SUBSCRIBED
   ▲                                  │                    │                          │
   └────────── user cancel ◀──────────┴── fail/timeout ◀───┴──── disconnect ──────────┘
                                                                 (auto-retry: rescan with backoff 1,2,4,8,16 s, then stop)
```

**Backoff, and when to stop.** Five attempts at 1, 2, 4, 8 and 16 s — 31 s in all. Long enough to ride out a lap of the track with the chip out of range; short enough that a chip which is simply switched off is not hammered for the rest of the session, which costs battery in the middle of a workout. After the fifth failure `gaveUp` is set, the screen shows *No chip*, and nothing further happens until the athlete asks: BACK on the idle screen then opens a menu offering **Rescan for chip** (and Exit, so BACK never traps you). The menu only appears when there is something in it — a rescan to offer or a capture to dump — because two presses to leave an app that is doing nothing would be worse than the problem it solves.

Device match (in order): a remembered device name from the last session; a service UUID from `FreelapProtocol.SERVICE_UUID`; a name prefix (`"FxChip"`, `"Freelap"`, `"Relay"`) as a fallback. The matcher lives in `FreelapProtocol` so it can be corrected once the real advertising is known.

**Which chip, when several match.** Matching is not choosing. At a group session every athlete's chip is in range, and connecting to the first one to appear records *their* splits into *your* activity — a failure that looks entirely plausible until someone compares the numbers with the person who actually ran them. So a scan pass collects every match into a `ChipCandidate` list (merged by name, newest RSSI winning, because advertisements repeat several times a second) and `ChipChooser.choose` decides:

1. the remembered chip, if it is in range;
2. otherwise the strongest signal — with chips worn on waistbands, that is the one on *this* athlete.

If the automatic choice is wrong, **Choose chip** in the idle menu lists every match with its name and RSSI, strongest first, and **Forget chip** clears the memory so the strongest wins again.

**The identity is the advertised name.** Connect IQ does not expose a BLE device address to an app — deliberately, it is a privacy surface — so the name is the most stable identifier available, and Freelap chips advertise one containing their own id (`FxChip-1234`). It is stored in the `lastChipName` setting, which is what survives an app restart; BLE pairing itself does not. If a capture shows the chip id in manufacturer-specific data, prefer that: it survives a firmware rename, and two chips can advertise the same name.

Subscribing: after `onConnectedStateChanged` reports connected, get service → get notify characteristic → get CCCD descriptor → `requestWrite([0x01,0x00]b)`. `onDescriptorWrite` with status OK moves to SUBSCRIBED. Some chips need a "start session" write to a command characteristic first; the adapter has a hook (`getHandshakeWrites()`) that returns a list of `[charUuid, bytes]` to send in sequence, empty by default.

Reception: `onCharacteristicChanged(char, value)` stamps `System.getTimer()` and passes `value` to a `PacketAssembler` the delegate owns. A notification carries at most 20 bytes, so a rep of more than three crossings arrives fragmented; the assembler holds the partial message between them. `FreelapProtocol` supplies the framing — `expectedLength(bytes)` and `decodeMessage(bytes)` — and stays the only file that knows the packet format.

The buffer is an object rather than module state on `FreelapProtocol` for two reasons, and the second is the one that bites:

- Module-level mutable state makes test order matter: a test that leaves half a message in the buffer breaks the *next* test, not itself.
- **On a link drop the buffer has to be thrown away.** The tail of a message from before the drop, concatenated onto the head of one after it, decodes to plausible and completely wrong crossings — the length was fixed by the first fragment, so nothing downstream can tell. `source-test/ReconnectTest.mc` demonstrates that failure explicitly and then asserts the reset prevents it. Owning the buffer is what makes "reset it on disconnect" a thing that can be tested at all.

The assembler also refuses a claimed length over 256 bytes. `0xA5` appears inside payloads, so a false sync byte would otherwise leave it waiting for bytes that never arrive.

Multiple athletes: a Freelap Relay Coach BLE aggregates several chips. The same design works; the adapter would then carry a chip-id per packet and the engine keeps one `RepState` per chip. The skeleton is single-chip with the chip-id plumbed through so the extension is mechanical.

## 7. App UX

Watch-app, not a data field, because a data field cannot use BLE on most devices nor own the session.

Screens:

1. **Connect** — scan progress, list of matching devices with RSSI, tap to pair. Remembers last chip.
2. **Course** — pick a saved course (from settings) or "Quick": START + FINISH at a distance you dial in.
3. **Activity** — the only screen that exists while a session runs. Wireframe, and what each line is:

   ```
        Chip OK            status, coloured: green subscribed,
                           amber scanning/pairing, red none

        8.99 m/s           last split velocity, 2 dp. The number is in a
                           FONT_NUMBER_* face; the unit beside it is not.

     4.45s  40m  1:51/km   that split's time (1/100 s), distance, and pace

       Rep 1   11.93s      reps completed, and the last rep's time.
                           Amber if that rep was not RepStatus.OK.

         PAUSED            only while paused
         No splits         a notice, for two seconds
     #12 A50412340000...   only in capture mode
   ```

   Every line is white or a status colour — no mid greys, which vanish on a MIP panel with the backlight off. START/STOP toggles the session; BACK ends a rep manually (see §7.1); BACK while paused opens save/discard.
4. **Rep summary** (auto after each FINISH, 5 s, dismissable) — split table for the rep.
5. **Capture mode** (settings toggle) — shows raw hex of the last packet and a running count, for reverse-engineering in the field without a laptop.

   `CaptureLog` keeps a rolling window of the last 60 notifications with their `System.getTimer()` arrival stamps. Two bounds, not one: a packet count *and* a total character budget, because a chip that fragments hard sends many more and shorter packets than the count cap assumes, and the storage value would blow past an API 3.1 device's ~8 KB allowance while still under 60.

   **Nothing writes to flash while packets arrive.** `Application.Storage` is flash; a write inside the BLE notification callback blocks long enough to lose the packets that follow, and a fragmented burst arrives milliseconds apart. `CaptureLog` never writes; `flush()` does, once, and the delegate calls it from `stop()`. `CaptureLog` takes the storage as an argument, so a test asserts the write count rather than a reviewer promising it.

   With capture mode on, BACK from the idle screen opens a menu with **Dump capture** (and Exit, so BACK never traps you). Dump prints the log to the CIQ console in the tab-separated shape `tools/decode_capture.py` reads — arrival seconds, handle, hex — so a field capture pastes straight into the decoder. The handle column is a placeholder: the watch does not expose the ATT handle a notification arrived on. The console only exists in the simulator, which is why the log is also written to storage on `stop()`.

Settings (Garmin Connect app → CIQ settings): courses (up to 8; each a list of `code,cumulative_m`), BLE latency estimate, clear-after-write, capture mode, sport/subsport (default Running / Track).

### 7.0 Drawing on a round watch

Two rules, because between them they are every layout bug this screen has had.

**The room a centred line has is the chord at its height, not the display width.** On a 416×416 round face, a line at `y = 0.08 h` has about 250 px, not 416. Getting this wrong is what made *Scanning for chip…* clip at both edges. `MainView.usableWidth(dc, y)` computes it; on a non-round face it returns 96% of the width.

**Nothing hard-codes a font for a screen size.** Each line gives a preference list, largest first, and `pickFont` takes the first that fits the room at that height — so the velocity readout is `FONT_NUMBER_MEDIUM` on a 454 px face and steps down on a 208 px one without a per-device table to maintain. Lines are then stacked by *measured* font height rather than by fractions of the display, so two lines cannot overlap however small the display is, and `fitText` truncates with an ellipsis as a last resort.

**Letters never go in a `FONT_NUMBER_*` face.** Those fonts contain digits and punctuation only. Drawing `"8.99 m/s"` in one renders the letters as tofu — and worse, `getTextWidthInPixels` measures the missing glyphs as *zero*, so the string looks narrow enough to fit and the fitting logic picks the font that cannot render it. It showed up as `8.99 □/□` on a 240×240 face while looking correct at 416×416. `stackValueWithUnit` draws the number and its unit in separate fonts, centred as a group, and a test asserts no traced line with letters in it ended up in a numeric font.

This is deliberately runtime measurement rather than per-resolution resource overrides. The overrides would need a table per device family, would still be wrong for any device released after them, and cannot know how long a course error message is — the athlete types the course string.

`source-test/MainViewLayoutTest.mc` asserts both rules against a real `Dc` at whatever resolution the simulator is running, so the check is repeatable rather than a screenshot someone once looked at. Screenshots of the result live in `docs/screenshots/`.

### 7.05 Launcher icons

Devices do not agree on launcher icon size and it does not follow screen size: `fr265`, `venu2` and `epix2` are all 416×416 and want 60, 70 and 60 px. One file makes the compiler scale it and warn. So `tools/make_icons.py` renders the mark at each size into `resources-icon-<n>/`, and `monkey.jungle` points each device at the right one; `resources/` holds the 40 px default that most products want. `tools/tests/test_make_icons.py` fails if a committed icon drifts from what the script produces, or if a product needs a size no jungle line supplies.

### 7.1 Buttons, and what happens to the session

Three pure functions of the recorder's state — `selectAction`, `backAction` and `tapAction` — decide what every control means, and one `perform(action)` turns an action into a side effect. That split is on purpose: the mapping can be tested without a view stack, and the button, the tap and anything added later cannot drift apart, because they all end up in the same `perform`.

| state | START / SELECT | BACK | tap upper half | tap lower half |
| --- | --- | --- | --- | --- |
| no session | start recording | leave the app | start recording | start recording |
| recording | pause | end the rep | pause | end the rep |
| paused | resume | Save / Discard | resume | Save / Discard |

BACK is the lap button while the timer runs, as on any Garmin watch. There is deliberately no way to leave the app straight from a running session: pause first. That is the Garmin convention and it means an active session is never abandoned by a single press.

The tap column exists so a touch-only device can reach all five actions without a physical button (issue #24). The screen splits in half: upper is the START button, lower is BACK. There are no permanent on-screen hints — a watch face this small cannot spare the room, and the split mirrors the physical buttons' own positions.

**Ending a rep that has no crossings does nothing, and says so.** `manualLap()` returns whether it actually closed a rep; when it did not, `perform` raises the notice *No splits*. An empty lap in the FIT file would be worse than none — it appears in Connect's lap table as a rep the athlete never ran — and a button that silently does nothing gets pressed again, and again.

Notices are drawn by `MainView` rather than through `WatchUi.showToast`, which needs API 4.0; `minApiLevel` here is 3.1. They clear themselves after two seconds.

**`onStop` saves; it does not discard.** By the time `onStop` runs the view stack is gone, so nothing can be asked. A session still open at that point was never explicitly discarded by the athlete — the watch closed the app, or the battery did — so it is saved. Losing a training session is much the worse of the two mistakes, and a stray activity can be deleted in Garmin Connect in two taps. A session already saved through the menu has `recorder.session == null` and is left alone, so nothing is saved twice.

### 7.2 What the simulator can and cannot show you

Recorded here because it cost time. The simulator writes the activity file to `%TEMP%\com.garmin.connectiq\GARMIN\Activities` **from the moment the session starts** — it appears at 0 bytes and grows — so "no new file appeared" is not a test of discard. What distinguishes a saved session is that its `session` message carries `fl_reps`, `fl_best_rep_us`, `fl_total_dist_m` and `fl_chip_id`; only `save()` writes those.

The unit-test harness cannot produce an activity file at all: it tears the app down before the file is finalised, so `session.save()` returns and nothing lands. Any FIT-level check has to go through the app's own UI.


## 8. Reverse-engineering plan (see `docs/REVERSE-ENGINEERING.md`)

Short version: capture the phone ↔ chip traffic with Android's HCI snoop log or an nRF52840 dongle + Wireshark while doing a scripted set of runs (known distances, count splits, note times shown in MyFreelap), then diff packets against the app's displayed values to identify the timestamp unit, packet framing, transmitter code field and any handshake. The watch's capture mode doubles as a field logger once the service UUID is known. `tools/decode_capture.py` is a scaffold for the diffing.

## 9. Risks and open questions

- **Protocol is proprietary and undocumented.** Everything in `FreelapProtocol.mc` is a hypothesis until sniffed. The layered design confines the blast radius to that file. Also worth an email to Freelap: they have partnered with third parties (e.g. for team apps) and may share the GATT spec under NDA.
- **The chip may refuse a second central.** If MyFreelap must stay connected, the watch can't also connect (BLE peripherals usually allow one central). Test with the phone app closed.
- **Chip may only push data on FINISH.** Designed for; streaming is a bonus.
- **Absolute-time accuracy is ~100–300 ms** because of BLE latency; durations are exact. Documented in the field names (`_est_`).
- **Developer-field limits and memory on older 3.1 devices.** 22 fields is deliberate; drop `fl_speed`/`fl_pace` (derivable) first if a device balks.
- **Garmin Connect charting rounds floats** and shows uint32 fine; if you want µs visible in Connect's UI, the uint32 fields are the ones to chart.
- **Lap/session developer fields dropped without a yield** — handled with a deferred `addLap()`.

### 9.1 SDK and API-level workarounds in the code

Each of these is a compile error or a crash without the workaround, and each is
commented at the site. `minApiLevel` stays at `3.1.0`.

| Where | Why | Workaround |
| --- | --- | --- |
| `manifest.xml` permissions | `ActivityRecording.createSession()` is gated by the **`Fit`** permission; `Session.createField()` by **`FitContributor`**. Declaring only `FitContributor` fails the build with *Permission 'Fit' required*. | Both permissions are declared. |
| `FreelapBleDelegate.onScanResults` | `Ble.Iterator.next()` is typed `Object?`, so `-l 1` cannot find `getDeviceName()` on it. | `results.next() as Ble.ScanResult?` in the loop. |
| `SplitEngine.onRepBurst` | `var prev = null` gives `prev` the type `Null`, so `prev.cumDistM` does not resolve at `-l 1`. | `var prev = null as SplitEvent?`. |
| `FreelapBleDelegate.registerProfileOnce` | BLE allows **three registered profiles per app** and the registry outlives an `AppBase` instance inside one VM. Re-registering on every app start threw an unhandled `ProfileRegistrationException` — reproduced by `monkeydo /t`, which restarts the app between tests and died on the third one. | Register once behind a `static` flag, inside `try`/`catch`; a refusal sets `profileError`, which `MainView` renders, instead of killing the app. |
| `FitRecorder.start` | `Activity.SPORT_RUNNING` / `SUB_SPORT_TRACK` need API 3.2. | The deprecated `ActivityRecording.SPORT_*` constants are used deliberately; they still work at 3.1 and the deprecation warning is expected. Swap them when `minApiLevel` rises. |
| `Course.splitString` | No `String.split` at API 3.1. | Hand-rolled splitter. |
| `FreelapProtocol.feed` | `decodeNumber(UINT32)` yields a `Long`. | Chip time stays `Long` until the rep START has been subtracted, then narrows to `Number`. |

## 10. Build & run

Prereqs: Connect IQ SDK 7.x+, and the **device definitions downloaded through the SDK Manager** for whichever `manifest.xml` products you intend to build — `monkeyc -d <id>` refuses an id whose definition is not installed, and the manifest only warns. `monkeyc -f monkey.jungle -d fr265 -l 1 -o bin/freelap.prg -y developer_key`, then sideload or run in the simulator. On Windows the SDK's `monkeydo.bat` takes `/t`, not `-t`. The simulator can't emulate the chip; use capture mode on a real watch, or the `tools/fake_chip.py` BLE peripheral (Linux/BlueZ + bleak) that advertises the hypothesised service and replays a captured rep so you can test the pipeline end-to-end before the real decoder exists.
