# Screenshots

The main view on each of the round resolutions issue #2 lists, captured from the
Connect IQ simulator with `PrintWindow` (so they are the window's own pixels,
not whatever was on the desktop behind it).

| file | device | display |
| --- | --- | --- |
| `fr55.png` | Forerunner 55 | round 208×208 |
| `fr645m.png` | Forerunner 645 Music | round 240×240 |
| `fenix6.png` | fenix 6 | round 260×260 |
| `fenix6xpro.png` | fenix 6X Pro | round 280×280 |
| `fr265.png` | Forerunner 265 | round 416×416 |

`fr55` and `fenix6xpro` are **not** in `manifest.xml`; they were added to a
local copy of it purely to reach 208 px and 280 px, and the product list is
unchanged. `fenix6xpro` is the 280 px sibling of `fenix6pro`, which is in the
list, so it is a reasonable one to add if you want that size supported for real.

These show the idle screen, because the live screen needs crossings and there is
no way to inject BLE into the simulator. The live and paused layouts are checked
instead by `source-test/MainViewLayoutTest.mc`, which draws the real view to an
off-screen `Dc` and asserts no line is wider than the room at its height and no
line overlaps the one above — run it per device to cover a resolution:

```powershell
monkeydo bin/freelap-test.prg fr55 /t
```

Regenerate the images after a layout change; the recipe is the loop in the
issue #2 PR, or just build, `monkeydo bin/freelap.prg <device>`, and screenshot.
