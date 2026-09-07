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
| `fr645m-recording.png` | Forerunner 645 Music | round 240×240, recording |
| `fr265-recording.png` | Forerunner 265 | round 416×416, recording |
| `fr265-idle-menu.png` | Forerunner 265 | the idle menu (BACK before a session) |
| `fr265-course-list.png` | Forerunner 265 | Choose course — only configured slots, with distances |
| `fr265-quick-course.png` | Forerunner 265 | the Quick course distance picker |

`fr55` and `fenix6xpro` are **not** in `manifest.xml`; they were added to a
local copy of it purely to reach 208 px and 280 px, and the product list is
unchanged. `fenix6xpro` is the 280 px sibling of `fenix6pro`, which is in the
list, so it is a reasonable one to add if you want that size supported for real.

`fr645m-recording.png` and `fr265-recording.png` show the **recording** screen
at 240×240 and 416×416: the wireframe in `docs/DESIGN.md` §7, item 3. There is
no way to inject BLE crossings into the simulator, so they were taken with a
temporary rep injected in `FreelapApp.onStart` — the script that does it
(`live_shots.sh` in the issue #20 PR) restores the file on exit, and nothing of
the sort is committed.

The other files show the idle screen. Beyond these, the layouts are checked by
`source-test/MainViewLayoutTest.mc` and `ActivityScreenTest.mc`, which draw the
real view to an off-screen `Dc` and assert that no line is wider than the room
at its height, no line overlaps the one above, no line is drawn in a grey that
disappears on a MIP panel, and no text is drawn in a digits-only font — run
them per device to cover a resolution:

```powershell
monkeydo bin/freelap-test.prg fr55 /t
```

Regenerate the images after a layout change; the recipe is the loop in the
issue #2 PR, or just build, `monkeydo bin/freelap.prg <device>`, and screenshot.

**The simulator does not respond to synthetic `Menu2` navigation.** Arrow keys,
scroll and taps all leave the selection on the first item, so any menu screen
past the first item cannot be photographed by driving the simulator from a
script — the quick-course picker was captured by making it the initial view for
one throwaway build instead. Worth knowing before spending an hour on it; it is
also why issue #18's Discard path has no end-to-end evidence.
