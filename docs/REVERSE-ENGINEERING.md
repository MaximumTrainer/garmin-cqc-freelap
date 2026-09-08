# Confirming the FxChip BLE protocol against a real chip

**This document used to be a plan for working out an unknown protocol by
sniffing a Bluetooth connection. That is no longer the job.**

Freelap were asked for the specification and provided it (issue #8). What it
establishes, and what changes everything below, is architectural:

**The chip broadcasts. It never accepts a connection.** There is no service
UUID, no characteristic, no CCCD subscription, no handshake write, no
notification and no fragmentation. A rep arrives as two fixed-layout payloads
carried as Bluetooth manufacturer-specific data under Freelap's registered
company identifier `0x0363`:

* the **advertisement** — the chip's printed id, and the rep's running totals.
  Broadcast for a bounded window after a Finish crossing, then it stops;
* the **scan response** — the intermediate crossing times, if the course had
  any.

So the remaining work is confirmation, not discovery, and most of it is about
the *watch* rather than the chip.

## What is already settled, and how

The decoder exists twice and the two are checked against each other:

* `tools/freelap_frame.py` — the reference implementation. It reproduces every
  value in the vendor document's worked example, and the legs of the rep sum to
  the rep total, which the document never states and which would not hold if
  any offset were wrong.
* `source/ble/BroadcastFrame.mc` — the watch's decoder, checked against vectors
  generated from the Python one. `tools/tests/test_monkeyc_vectors.py`
  re-derives those vectors and fails if the two drift apart.

Because the worked example is confidential it lives in a fixture that is not
committed, so those particular tests skip in CI. **A green suite without it
proves the two implementations agree with each other, not that either agrees
with a chip.** Closing that gap is what the rest of this document is for.

## What may and may not be published

The specification was shared in confidence, so this is worth stating once and
plainly rather than leaving each contributor to guess.

**Not published** — the byte-level field layout, the worked example, and the
timing arithmetic constants. Describe them where a reader needs to know they
exist; do not quote them. That applies to code comments, to `docs/`, and to
public issues.

**Published** — the architectural consequences, every one of which is
observable by anyone in range with a phone and nRF Connect: that the chip is
broadcast-only, that a frame is an advertisement plus a scan response, that
frames are validated by Freelap's Bluetooth SIG company identifier `0x0363`
(a public registry entry), and that lap-mode advertising is time-bounded.

**Source code** that implements the protocol necessarily encodes offsets and
constants. That is implementation rather than redistribution — but it is a line
worth naming rather than crossing quietly, which is why it is named here.

**The document itself** is kept outside the working tree and `*.pdf` is
git-ignored, with the reason attached so the rule survives someone tidying
`.gitignore`.

Two questions the specification did not settle are worth a short follow-up to
the same contact, alongside the technical ones below: how a chip id below 1000
is printed on the case (#63 renders it back to the athlete, so it has to match
exactly), and how to read the version and battery bytes, whose values in the
worked example do not follow a single rule from the bytes beside them.

## Kit

* An FxChip BLE, and at least one transmitter that can be set to **Finish** —
  without one the chip never enters lap mode and never advertises.
* A phone running nRF Connect, or `btmon` on Linux, or an nRF52840 dongle with
  the Wireshark sniffer plugin. Any of the three will do: the chip broadcasts,
  so there is no connection to get inside and no pairing to defeat.
* MyFreelap, as the independent source of truth for the times.
* A tape measure.

Note what is *not* needed any more: Android HCI snoop logs, a rooted phone, or
any attempt to observe the MyFreelap↔chip conversation. There is no
conversation. The phone is just another passive listener, and so is the watch.

## The runs that still matter (issue #5)

For each run record the values MyFreelap displays, the transmitters crossed and
their modes, and anything surprising.

| Run | Setup | What it settles |
|---|---|---|
| A | Start + Finish, one rep | The minimum frame; what the lap array holds with no intermediates |
| B | Start + 2 intermediates + Finish | Intermediate laps in the scan response, and their order |
| C | As B, three reps back to back | Whether the counters reset per rep or accumulate — this is what settles `OFFSET` vs `FROMLAP` |
| D | Chip held in a transmitter's field for 5 s | Discoverable mode, and the chip's local name |
| E | A rep, then wait out the window without listening | That the advertising really does stop, and how long the watch has |
| F | Two chips crossing the same transmitters | That frames separate by chip id — the basis of #63 and #28 |
| G | Chip taken out of range mid-rep and returned | Whether a missed crossing is recoverable from a later frame, or lost |

## The three questions the document could not answer

These are the reason a capture is still needed, and each has a home:

1. **Which mask** (issue #6). The specification applies two different masks to
   the running totals in two different places. They agree until a counter's top
   bits are set and then diverge silently, so a chip that has been running long
   enough is the only way to tell. Both are implemented as a parameter, and
   there is a test asserting the worked example *cannot* separate them, so that
   nobody later cites it as evidence.
2. **`OFFSET` versus `FROMLAP`** (issue #6). The two origins are *equal* in the
   worked example, because it is a first lap. A decoder that treated them as
   interchangeable would pass every test derivable from the document and then
   be wrong from the second lap of every session onwards. Run C settles it.
3. **Truncate or round** (settled, recorded here for completeness). The
   document's worked example truncates; the MyFreelap screenshot beside it
   rounds, which is how one leg reads `00:02.00` in the text and `00:02.01` in
   the picture. The app rounds, because #25 measures it against MyFreelap.

## The question about the watch, not the chip (issue #60)

**This is the one that decides what the app can be**, and it needs no
understanding of the protocol at all.

The intermediate splits are in the *scan response*. Nothing in the Connect IQ
SDK says whether Connect IQ performs an active scan — which is what elicits a
scan response — or whether scan-response payload reaches `onScanResults` at
all. `grep -ri "scan response"` across the BLE documentation returns nothing.

If it does, the app works as designed. If it does not, the app can report a rep
total and a final split and nothing else, which is a different product. Run a
minimal scanning app on a **real watch** and record:

* how many entries `getManufacturerSpecificDataIterator()` yields for company
  `0x0363` — one, or two;
* the length of `getRawData()`;
* whether `getDeviceName()` returns anything. The local name is only ever sent
  in a scan response, so a non-null name is itself evidence of an active scan.

Record simulator behaviour **separately and label it as such**. The simulator's
BLE stack has already proved not to match a watch once.

## Capturing without a sniffer

`tools/decode_capture.py` reads a capture export and decodes every Freelap
frame in it at the documented offsets. Given times it also brute-forces every
offset where each could be encoded — the search this tool was originally built
for. That is kept deliberately: it is the honest way to investigate a frame
that does *not* decode. Rather than assuming our offsets are right and the chip
is odd, it asks where the number actually is. If it ever finds a time at an
offset the decoder does not use, the decoder is wrong.

`tools/fake_chip.py --print` generates frames with no radio at all, and prints
the times a correct decoder should get back from them, which is usually a
faster way to test a change than finding a chip.

## Watch-side capture mode

Capture mode logs what the watch itself saw, which is the only way to tell
"the chip never advertised" from "the watch was not listening" — a distinction
that matters a great deal once #9 starts counting missed reps. Log every frame
including repeats, since the repeat rate is itself evidence, and log frames
that fail validation as well as those that pass: a frame we rejected and should
not have is exactly the bug this would catch.
