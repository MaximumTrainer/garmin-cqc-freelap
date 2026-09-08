# Connect IQ store listing

Draft copy for the store submission. **Not ready to submit** — see *Before you
submit* at the bottom.

---

## App name

Freelap Splits

## Short description (one line)

Records Freelap FxChip BLE crossings into your activity as exact split times.

## Long description

Freelap Splits listens for a Freelap FxChip BLE and writes every transmitter
crossing into your Garmin activity: split time, cumulative time, distance,
velocity, speed and pace, with one Garmin lap per Freelap rep. There is no
pairing to do — the chip broadcasts, and the watch simply listens for the one
you tell it is yours.

Times are the chip's own, carried into the FIT file without being re-measured
or re-derived on the way. Set up your course once
(`S:0;L:30;L:60;F:100`, or dial a distance on the watch) and the app matches
each crossing to a transmitter and derives the distances for you.

**On the watch, while you run**

- the last split's velocity, large, with its time, distance and pace
- rep count and last rep time
- which chip you are bound to, and whether it has been heard
- a summary of every split in the rep, for five seconds after each finish

**In the activity file**

- one Garmin lap per Freelap rep, with rep time, distance, average and peak
  velocity, split count and status
- per-split developer fields on every record
- session totals: reps, best rep, total distance, chip id

**Also**

- up to eight courses, editable in Garmin Connect or picked on the watch
- a Quick course: start line to finish line, 10–400 m, dialled on the wrist
- listens for your chip by the id printed on it, so a training partner's chip
  in range never lands in your activity
- tells you when a rep was missed, rather than quietly leaving a hole
- a capture mode that logs raw frames, for anyone working on the protocol

## What you need

A Freelap FxChip BLE and Freelap transmitters. The watch cannot detect Freelap's
magnetic transmitters itself — the chip does that, and this app reads what the
chip recorded.

## Privacy

**Nothing leaves your watch.** The app has no network permission and makes no
network requests. It talks to your Freelap chip over Bluetooth Low Energy and
writes to your own activity file, which syncs to Garmin Connect exactly as any
other activity does. The app stores your course settings and the last session's
splits on the watch, and the id of the chip you told it to listen for.
No analytics, no accounts, no third-party services.

## Permissions, and why each is needed

| Permission | Why |
| --- | --- |
| Bluetooth Low Energy | to listen for the FxChip's broadcasts — the entire point of the app. The app never connects to the chip or to anything else |
| Fit | to create the activity recording session |
| FitContributor | to add the split fields to that activity |

The app requests **nothing else**. In particular it does not request Positioning
(it does not use or record GPS), Sensor, or Communications/network access.

## Support

<https://github.com/MaximumTrainer/garmin-freelap/issues>

## Trademark and affiliation

**Freelap** is a trademark of Freelap SA. This app is **not** made by, endorsed
by, or affiliated with Freelap SA. It is an independent, open-source project
that reads the chip's Bluetooth output the same way any BLE client can.

Garmin, Connect IQ and Garmin Connect are trademarks of Garmin Ltd.

---

## Before you submit

Six things, and the first is the one that matters:

1. **The protocol is still a hypothesis.** `FreelapProtocol.mc` has never seen a
   real FxChip — issues #4, #5, #6 and #7. Publishing an app that cannot
   actually read the chip would be worse than not publishing at all. Do #25
   (twenty reps on a real track, checked against MyFreelap) first.
2. **Retake the screenshots from a real session.** The ones here were captured
   in the simulator, and the recording screen was produced by injecting a
   synthetic rep, because there is no chip to produce a real one. A store
   listing must not show numbers that were made up. They are also approximate
   crops of the simulator window rather than exact device-resolution images.
3. **Review the product list.** `manifest.xml` lists 24 devices. Five of them
   (`fr245`, `fr245m`, `fr255`, `fr165`, `enduro`) have never been built, let
   alone run — their device definitions are not installed locally (#1). Ship
   only what you have tested, or at minimum what builds.
4. **Check the app id.** It was regenerated for this issue. If a build has
   already been sideloaded anywhere, changing it makes that a different app.
5. **Confirm the trademark wording** with someone who has read Freelap's terms.
   The statement above is the honest position — independent, unaffiliated — but
   it is not legal advice, and #8 (asking Freelap directly) is unanswered.
6. **Decide about GPS.** The app records no GPS track, so the activity has no
   map and Garmin's own distance stays at zero. On a track that is arguably
   correct — the chip measures the distance that matters — but it will surprise
   people. If you want a track, the app needs `Positioning` back *and* code to
   enable location events; declaring the permission alone does nothing.
