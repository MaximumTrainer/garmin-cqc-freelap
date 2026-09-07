# Test fixtures

## `reference-session.fit`

A real activity file written by the Connect IQ simulator, not a hand-built one.
It is what `tools/tests/test_fit_fields.py` asserts the developer field table
against, so issue #16's "field_description messages for all 10 record fields
with the documented names, types and units" is re-checked on every push rather
than claimed once in a PR.

It contains no athlete data: the user profile in it is the SDK simulator's
default (68 kg, 1.78 m), the activity has no GPS positions, and there was no
chip connected, so the record-level split values are unset. What it proves is
that the FIT writer accepts our 20 field declarations and emits them, and that
the session message carries the four session-level values through `save()`.

### Regenerating it

Needs the Connect IQ SDK and the simulator; there is no way to do this in CI
(the SDK requires a Garmin login). The unit-test harness will *not* produce a
file — it tears the app down before the activity is finalised — so this has to
go through the app's own UI:

```powershell
connectiq
monkeyc -f monkey.jungle -d fr265 -l 1 -o bin/freelap.prg -y developer_key.der
monkeydo bin/freelap.prg fr265
# in the simulator: click the watch face to give it focus, then
#   ENTER  start recording
#   (wait a few seconds so some records are written)
#   ENTER  pause
#   ESC    open the Save / Discard menu
#   ENTER  Save
```

The file appears in
`%TEMP%\com.garmin.connectiq\GARMIN\Activities\<timestamp>.fit`. Copy it here,
then check it with:

```powershell
python tools/fit_fields.py tools/tests/data/reference-session.fit --values
```

Once `tools/fake_chip.py` can drive a real rep through the pipeline (issue
#27), regenerate this with actual splits in it and tighten the value
assertions in `test_fit_fields.py` accordingly.
