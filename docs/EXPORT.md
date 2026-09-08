# Getting the splits out

There are two copies of every split, and they are independent on purpose.

| | where | precision | needs |
| --- | --- | --- | --- |
| **The FIT file** | the activity, synced to Garmin Connect | full, in the file | a desktop and `fitdecode` |
| **The on-watch log** | `Application.Storage`, last session only | full | the simulator console |

Garmin Connect **rounds floats in its UI**. It shows `uint32` fields as-is, which is why the durations are `uint32` and not `float` — but `fl_velocity`, `fl_speed` and `fl_pace` will look rounded there. Read the file if the exact numbers matter.

### What "precision" means here

The durations are carried in **microseconds, which is finer than the chip can measure**. The FxChip counts in ticks of 1/1024 s — just under a millisecond — so a microsecond field is a container, not a claim. What the chip actually resolves is about 0.98 ms, which is still around ten times finer than the hundredths MyFreelap displays.

Two consequences worth knowing before you compare numbers with anything:

* the app subtracts in the chip's own ticks and converts once, because the tick is not a decimal fraction of a second and converting each leg before adding them up accumulates error;
* converting a tick count to microseconds is exact only when that count is a multiple of 16. The residue is under a microsecond and far below what the chip can measure, but it is not nothing, and "nothing is rounded on the way" — which this document used to say — was not true.

## From the FIT file

```bash
pip install fitdecode

python tools/fit_splits.py activity.fit                 # one row per split
python tools/fit_splits.py activity.fit --laps          # one row per rep
python tools/fit_splits.py activity.fit --summary       # session totals
python tools/fit_splits.py activity.fit --out splits.csv
```

`python tools/fit_fields.py activity.fit --values` prints the raw developer field table instead, which is the thing to look at when a column comes out empty.

## From the watch

Idle menu → **Dump splits**, paste the console output into a file, then:

```bash
python tools/splits_to_csv.py dump.txt > splits.csv
```

Only the last session is kept, and only up to 300 splits (`SplitLog.MAX_ROWS`) — a two-hour session of 60 reps is 240, so a normal session is complete. The dump says how many were dropped if any were.

## What the columns mean

| CSV column | FIT field | |
| --- | --- | --- |
| `rep` | `fl_rep` | 1-based Freelap rep; one Garmin lap each |
| `tx_index` | `fl_tx_idx` | position on the course, 0 = START. **Blank** when the course could not place the crossing (`255` in the file, `-1` on the watch) |
| `tx_code` | `fl_tx_code` | 1 START, 2 LAP, 3 FINISH, 0 unknown |
| `cum_us` | `fl_cum_us` | µs since this rep's START, converted from the chip's ticks (see above) |
| `split_us` | `fl_split_us` | µs since the previous crossing, likewise |
| `cum_dist_m` | `fl_dist_m` | metres from the course definition, not measured |
| `velocity_mps` | `fl_velocity` | the sprint-coaching number |
| `speed_kmh` | `fl_speed` | `velocity × 3.6` |
| `pace_s_per_km` | `fl_pace` | `1000 / velocity` |
| `est_ms` | `fl_est_ms` | **estimated** ms into the session — see below |
| — | `fl_chip_idx` | which chip, as a slot into the session's `fl_chip_id` list. `255` on a record with no split |
| `est_clamped` | *(watch log only)* | the estimate could not be placed |

Lap rows carry `rep_time_us`, `rep_dist_m`, `rep_avg_vel_mps`, `rep_peak_vel_mps`, `rep_splits` and `rep_status` (`ok` / `unmatched` / `partial`). The session row carries `reps`, `best_rep_us`, `total_dist_m` and `chip_id` — the last being every chip heard from, comma separated in slot order, so `fl_chip_idx` on a record resolves to one of them. A single-athlete session has one id and no separator.

**`est_ms` is a guess, and the only one here.** Everything else is measured by the chip or defined by your course. It places a crossing on the session's timeline by working back from when the BLE packet arrived, minus the assumed `bleLatencyMs`; the durations are exact but *where they sit* is ±100–300 ms. Use `split_us` for performance and `est_ms` only for lining splits up against other timeline data. On the watch log, `est_clamped = true` means even that failed — the crossing happened before the session started, so the `0` is not a time.

## Intervals.icu

Intervals.icu reads the FIT file directly, so a synced activity arrives with the developer fields on it; nothing needs converting for that. Two things are worth doing by hand:

- **Intervals.** Each Freelap rep is already a Garmin lap, so intervals.icu shows one interval per rep with the correct start and duration. `fl_rep_time_us / 1e6` is the authoritative duration — its own lap duration is whole seconds.
- **Custom fields.** Intervals.icu supports per-activity custom fields; the useful ones are `best_rep_us`, `reps` and `total_dist_m` from `--summary`, and per-interval `rep_time_us` and `rep_peak_vel_mps` from `--laps`.

| intervals.icu | from |
| --- | --- |
| interval start / duration | the Garmin lap, one per rep |
| interval `Distance` | `rep_dist_m` |
| interval `Avg Speed` | `rep_avg_vel_mps` |
| interval `Max Speed` | `rep_peak_vel_mps` |
| activity custom `Best rep (s)` | `best_rep_us / 1e6` |
| activity custom `Reps` | `reps` |

**Not verified.** Nobody has pushed one of these files to intervals.icu yet — there has never been a session with real crossings in it (no chip). The mapping above is from the field semantics, not from a round trip. Treat it as a starting point and correct it here once someone has actually done it.
