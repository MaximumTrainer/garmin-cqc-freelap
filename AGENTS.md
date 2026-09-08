# AGENTS.md — working agreement for agents on this repo

A Connect IQ (Monkey C) watch app that consumes a Freelap FxChip BLE's crossing
data and writes it into the activity FIT file as developer fields. Read in this
order before touching code:

1. `README.md` — layout, build, first run.
2. `docs/DESIGN.md` — architecture, timing model, FIT field table. This is the
   contract; if your change contradicts it, change the doc in the same PR.
3. The [GitHub issues](https://github.com/MaximumTrainer/garmin-freelap/issues)
   — every unit of work already carries a **requirement** and **acceptance
   criteria**. Those criteria are your test list. Do not invent scope outside
   them. The issues are the source of truth; there is no file mirror.
4. `docs/EXPORT.md` — if you are touching the FIT fields or either exporter.
5. `docs/REVERSE-ENGINEERING.md` — only if you are touching the protocol.
6. `CONTRIBUTING.md` — branch/PR/issue mechanics.

## Non-negotiables

- **No production line lands without a test that failed first**, unless the
  change is provably untestable in this ecosystem (BLE stack behaviour, screen
  layout, real-hardware timing). When it is untestable, say so explicitly in the
  PR and replace the test with a written manual verification step.
- **Work outside-in**: start at the acceptance criterion, drive inward. Never
  start by writing a class.
- `source/ble/BroadcastFrame.mc` and `tools/freelap_frame.py` are the only
  places that know Freelap's frame layout, and they are mirrors of each other -
  `tools/tests/test_monkeyc_vectors.py` fails if they drift apart.
- `source/ble/FreelapProtocol.mc` and `PacketAssembler.mc` describe a
  connection-oriented protocol the chip does not speak. They still build and
  still pass their tests; they are retired in #61. Do not add to them.
- The layout comes from a specification Freelap shared in confidence. Implement
  it; do not reproduce it. The document is not in this repo, `*.pdf` is ignored,
  and byte tables do not go in public issues (#8).
- `minApiLevel` stays at `3.1.0`. If an API you want needs more, either avoid it
  or raise it in a dedicated issue.

## The loop

```text
   ring 1  acceptance criterion (issue)         ─ red ─┐
   ring 2  simulator / fake-chip end-to-end            │  each ring's failing
   ring 3  Monkey C unit test (monkeydo -t)            │  test justifies the
   ring 4  pure function / decoder vector        ─ green┘  next ring inward
```

For a task:

1. Copy the issue's acceptance criteria into your scratch notes. Each becomes a
   named test or a named manual step. If a criterion is not testable as written,
   fix the criterion (edit the issue body, and say in the PR what you changed
   and why) before coding.
2. Write the **outermost automatable** test for the first criterion and watch it
   fail for the right reason. "Outermost automatable" is usually ring 3 — see
   the ring guide below for when 2 or 4 is the right entry point.
3. Drive inward only as far as the failing test forces you. Prefer a new pure
   function over a new stateful class; prefer passing a value in over reading a
   property inside.
4. Green, then refactor with the tests still green.
5. Repeat per criterion. Tick the boxes in the PR body as you go.

Do not batch: one criterion, one red test, one green, one commit is the target
rhythm. A PR that adds five classes and one test at the end will be sent back.

## Ring 2 — simulator / end-to-end

The outermost thing a machine can run here.

- `tools/freelap_frame.py` is the reference implementation of the broadcast
  frame: build one, decode one, do the arithmetic. **When you change
  `FreelapProtocol.mc`, change `freelap_frame.py` in the same commit** — the
  two hold the same layout, and drift between them is a silent test hole.
- `tools/fake_chip.py` builds its frames from it, so the fake cannot drift into
  agreeing with a decoder that is wrong. `--print` needs no Bluetooth and is
  how most of the app's development can run; `--vectors` emits Monkey C byte
  arrays for `source-test/`. `--advertise` needs Linux, BlueZ and root, and has
  never been run (#27).
- The only external check that any of this matches a real chip is the worked
  example in Freelap's frame document. It is confidential, so the fixture
  holding it is **not committed**, and the tests using it skip when it is
  absent — see `tools/tests/test_freelap_frame.py`. A green suite without it
  proves self-consistency, not correctness.
- FIT output is verified outside the watch: run a session in the simulator or
  on the watch, pull the `.FIT`, and assert on developer fields with the FIT
  SDK / `fitdecode` rather than by eyeballing Garmin Connect (Connect rounds
  floats in its UI). If an issue needs this repeatedly, add the assertion
  script under `tools/` with its own pytest coverage — do not do it by hand
  twice.
- Ring 2 does not run in CI (the SDK needs a Garmin login, and BlueZ is not
  there). Record what you ran and what it produced in the PR.

## Ring 3 — Monkey C unit tests

This is the default home for new tests: course parsing and matching, split
derivation, rep boundaries and statuses, decoder framing/reassembly, and the
recorder's field bookkeeping against a fake session.

**Layout.** Tests live in `source-test/`, mirroring `source/`:

```text
source-test/CourseTest.mc          tests for source/model/Course.mc
source-test/SplitEngineTest.mc     ...
source-test/fakes/FakeSession.mc   test-only doubles
```

`source-test/` is already on the source path (`base.sourcePath = source;source-test`
in `monkey.jungle`). Every test function **and every test-only helper** carries
`(:test)` so release builds strip it. Verified on SDK 9.1.0 (issue #1): the
`--unit-test` build's `.prg.debug.xml` lists the test symbols and the plain
build's does not. Re-check this if you change the annotation scheme.

**Shape.** Tests are module-scope functions, not methods:

```monkeyc
using Toybox.Test;

(:test)
function testCourseSkipsMalformedSegments(logger as Test.Logger) as Boolean {
    var c = new Course("S:0;garbage;F:100", "t");
    Test.assertEqual(c.size(), 2);
    Test.assertEqualMessage(c.totalDistance(), 100.0, "FINISH distance");
    return true;
}
```

Name them `test<Unit><BehaviourUnderCondition>`. One behaviour per test. Assert
on values the FIT file or the screen actually carries, not on internals.

**Helpers go in a module, not at file scope.** The runner collects *every*
module-scope function annotated `(:test)` as a test case, so a helper written
that way is called with a `Logger` as its first argument and reported as an
ERROR. Put shared helpers inside a `(:test) module` — `source-test/fakes/TestSupport.mc`
is the one that exists — where the annotation still strips them from release
builds but the runner leaves them alone.

**`hidden` is not accessible from a `static` method on the same class.**
`Course.fromSpec()` calling `fallback.addWarning()` fails at runtime with
*Could not find symbol* if `addWarning` is `hidden`. Likewise, assigning to a
class `static` from an instance method needs the class name
(`FreelapBleDelegate.profileRegistered = true`); unqualified, the write does
not reach the static.

**The test build no longer fits on API 3.x devices.** Monkey C caps the
`globals` module at 253 members there, and every `(:test)` function is a
global; the suite passed 253 at 222 tests. `monkeyc --unit-test -d fr645m`
now fails with *Found 261 members in module 'globals'*.

This does **not** affect the app: a release build for the same device is
clean, because `(:test)` is stripped. Run the suite on an API 5.x simulator
(`fr265`, `fr965`) and build — not test — for the older devices, which is what
the per-product `monkeyc -l 1` sweep already does.

If the suite ever needs to run on 3.x again, the way out is annotation groups:
tag test functions `(:test :groupA)` / `(:test :groupB)` and build each with
`base.excludeAnnotations` set to the other. That is friction on every new test,
so it is not worth doing until something actually needs it.

**The simulator's BLE profile registry outlives an `AppBase` instance**, and
the harness restarts the app once per test, so whether a given test's app
instance got a profile depends on how many tests ran before it. Do not assert
on that; assert on the contract instead (see `source-test/AppStartupTest.mc`).

**Run** (needs the Connect IQ SDK on PATH and the simulator running; the SDK is
not installed in CI and may not be installed on the current machine — check
before promising a green run):

```powershell
connectiq                                   # start the simulator once
monkeyc -f monkey.jungle -d fr265 -l 1 --unit-test -y developer_key.der -o bin/freelap-test.prg
monkeydo bin/freelap-test.prg fr265 /t     # /t on Windows; -t on macOS/Linux
```

VS Code: *Monkey C: Run Tests*. An unhandled exception in a test takes the
simulator process down with it, so restart `connectiq` before the next run.

**Boundaries you must cover, because the field will hit them:** empty burst, a
single-crossing burst, more crossings than the course has transmitters, fewer
(partial rep), unknown transmitter code, zero-duration split (divide-by-zero
guard), a fragmented packet split at a record boundary, a truncated packet that
never completes, and a second burst arriving while the first is incomplete.

## Ring 4 — decoder vectors

The decoder is a pure byte-array → crossings function and is tested as one.

- Every capture folder under `captures/` yields at least one **vector**: raw
  hex in, expected crossings out, plus the MyFreelap-displayed values it was
  checked against. Vectors are transcribed into `source-test/` as literal
  `ByteArray`s with the capture path in a comment.
- A decoder change with no new or changed vector is not a decoder change; it is
  a guess. Reject it in review, including your own.
- `TICK_US`, endianness, framing and the transmitter-code mapping are each
  pinned by their own vector, so a wrong unit fails one test rather than all of
  them.

## Ring 4b — Python tools

`tools/*.py` is ordinary Python and has no excuse. Tests live under
`tools/tests/` and `.github/workflows/lint.yml` runs them — this is the only
ring CI can actually execute, so keep it honest. Run it locally with
`python -m pytest tools/tests -q`.

`tools/validate_resources.py` is the other half of that job: it checks the
manifest, XML well-formedness, drawable filenames, and that every
`Rez.Strings.X` and `@Properties.X` the code and settings refer to is actually
declared. Its own tests break each of those on purpose and assert the breakage
is reported — a validator without a red case is a green tick that means
nothing.

## Design rules that keep this testable

- **Inject, don't fetch.** Domain objects take their configuration as
  constructor arguments; only the app layer touches `Application.Storage`,
  `Properties`, `System.getTimer()` or `Time.now()`. The pattern in place:
  `new SplitEngine(course, listener, latencyMs)` and `new Course(spec, name)`
  are the primary constructors, with `SplitEngine.fromSettings()` and
  `Course.loadActive()` as the app-layer conveniences that read settings and
  delegate. Remaining violation to fix when you next touch it:
  `FitRecorder.initialize` reads `clearAfterWrite` and `lapPerCrossing` from
  properties.
- **No module-level mutable state.** `FreelapProtocol._buf` / `_expected` are
  reassembly state on a module, which makes test order matter. Either call
  `reset()` as the first line of every test, or better, move the buffer into an
  instance the BLE delegate owns.
- **Keep `Toybox` out of the domain.** `Course`, `SplitEvent`, `SplitEngine` and
  the decoder should need nothing beyond `Toybox.Lang` (and `Math`). That is
  what makes them runnable under `monkeydo -t` without a session or a radio.
- **Fake at the seam, not below it.** For FIT work the double is a
  `FakeSession` recording `createField` / `setData` / `addLap` calls in order —
  do not try to fake `Toybox.FitContributor` itself.

## Ecosystem gotchas (these cost hours if forgotten)

- Developer fields must be held in class scope for the session's life or they
  vanish from the file.
- Lap/session developer fields are dropped if `setData()` and
  `addLap()`/`save()` run in one path with no yield — the recorder defers by a
  timer tick on purpose. Do not "simplify" that away.
- `addLap()` can only happen *now*; laps cannot be back-dated. Hence one Garmin
  lap per Freelap rep.
- No `String.split` at API 3.1 (`Course.splitString` exists for that reason).
- `decodeNumber(UINT32)` yields a `Long`; subtract the rep start before
  narrowing to `Number`, or chip uptime will overflow.
- BLE: the chip broadcasts and never accepts a connection, so none of the
  connection limits apply. What does apply: Connect IQ has **no scan filter**,
  so every advertisement from every device in range arrives in `onScanResults`
  and is rejected in Monkey C. Keep that path cheap and allocation-free.
- A Monkey C `Number` is signed. The frame's 32-bit counters are `Long`s; a
  chip that has been running a while decodes negative otherwise.
- The chip's tick is 1/1024 s - just under a millisecond. Durations are carried
  in microseconds because that is finer than the chip can measure, **not**
  because the chip measures microseconds. Subtract in ticks and convert once;
  converting each leg and adding the results accumulates error.
- Build with `-l 1` type checking; a new type warning is a failing build.

## Definition of done

- [ ] Every acceptance criterion on the issue is either a passing test or a
      documented manual step with its result in the PR.
- [ ] Tests were written before the code and failed first (say so in the PR).
- [ ] `monkeyc -l 1` clean for one API 3.1 device and one API 5.x device.
- [ ] `monkeydo -t` green.
- [ ] CI (`lint.yml`) green.
- [ ] Protocol changes ship with the capture, the vector, and a `fake_chip.py`
      update.
- [ ] `docs/DESIGN.md` still describes the code.
- [ ] PR references its issue (`Closes #N`) with the criteria ticked.

## Do not

- Do not add products to `manifest.xml` you cannot build for.
- Do not commit `*.der`, developer keys, or captures containing phone-identifying
  data (the chip's own address is fine).
- Do not add `monkeyc` to GitHub-hosted CI; the SDK needs a Garmin login. The
  hook for a self-hosted runner is already noted in `lint.yml`.
- Do not weaken a test to make it pass, and do not delete a failing test without
  saying why in the PR.
- Do not claim hardware verification you did not perform. "Not run — no chip
  available" is an acceptable PR line; a fabricated green is not.
