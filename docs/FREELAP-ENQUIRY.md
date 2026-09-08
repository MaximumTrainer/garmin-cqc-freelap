# Asking Freelap for the protocol (issue #8)

> ## Answered. Freelap shared the specification.
>
> They provided the **FxChip BLE broadcast frame specification**, and it
> replaced the entire connection-oriented design this project had guessed at.
> The chip broadcasts and never accepts a connection: no service UUIDs, no
> characteristics, no CCCD, no handshake, no fragmentation.
>
> **The document is confidential and is not in this repository.** `*.pdf` is
> git-ignored with the reason attached, the file is kept outside the working
> tree, and the byte layout is implemented rather than reproduced — not in the
> code comments, not in `docs/`, and not in public issues. See "What was
> restricted" below.
>
> The letter is kept as written because the questions in it turned out to be
> the right ones, and because a follow-up is still owed (see the end).

---

## Where to send it

| | |
| --- | --- |
| Freelap SA (Switzerland) | the manufacturer; general contact via <https://www.freelap.com> → Contact |
| Freelap USA | the US distributor, historically more responsive to developers |
| MyFreelap support | in-app / web support, worth a copy — it reaches the software team rather than sales |

Send to Freelap SA first and copy the others. Check the current addresses on
their site before sending; do not trust an address written down in a repo.

## Draft

> **Subject:** FxChip BLE GATT/packet specification — Garmin Connect IQ integration
>
> Hello,
>
> I am building an open-source Garmin Connect IQ watch app that connects to an
> FxChip BLE over Bluetooth Low Energy and records the crossings it reports into
> the Garmin activity file, so that Freelap split times end up in an athlete's
> normal training log alongside everything else Garmin records.
>
> It is an independent project, not affiliated with Freelap, and it does not
> replace MyFreelap — it reads what the chip broadcasts, the same way any BLE
> client can, and writes it to a FIT file on the watch. Nothing is sent
> anywhere else.
>
> Would you be willing to share the FxChip BLE's GATT specification and packet
> format? Specifically:
>
> 1. the advertised service UUID(s) and device name format;
> 2. which characteristic notifies with crossing data, and whether any
>    command or handshake write is required first;
> 3. the layout of a crossing record: framing, timestamp unit and width,
>    endianness, the transmitter code field, and the chip identifier;
> 4. whether the chip notifies per crossing or sends the whole rep at FINISH;
> 5. the same for the Relay Coach BLE, if it differs.
>
> If any of that is only available under an NDA, I would be glad to discuss
> terms. I would want to be clear up front about one thing: the project is
> open source, so I would need to know which parts, if any, could not be
> published — and if the answer is "the packet format itself", that is useful
> to know before rather than after.
>
> If you would rather not share it, a plain "no" is a perfectly good answer and
> I will not chase it. I would simply rather ask than assume.
>
> The project is at https://github.com/MaximumTrainer/garmin-freelap if it
> is useful context.
>
> Thank you for your time,
>
> *(name)*

## Why it is worth asking even if they say no

- A "no" is recorded, so nobody wonders later whether it was tried.
- A "yes, under NDA" changes the shape of the project — `FreelapProtocol.mc`
  would need a note about which parts cannot be published, and possibly a
  different licence position for that file. Better to know before writing it.
- Silence is also an answer after thirty days, and the project proceeds with
  reverse-engineering (#4, #5) either way. Nothing is blocked on this: it is
  the cheaper path, not the only one.

## What was restricted, and how it is handled

The specification is marked confidential on every page. The line taken, and
applied consistently across the code, the docs and the issue tracker:

**Not published** — the byte-level field layout, the worked example, and the
timing arithmetic constants. These are described where a reader needs to know
they exist, never quoted.

**Published** — the architectural consequences, all of which are observable by
anyone with a phone and nRF Connect: that the chip is broadcast-only, that a
frame is an advertisement plus a scan response, that frames are validated by
Freelap's Bluetooth SIG company identifier `0x0363` (a public registry entry),
and that lap-mode advertising is time-bounded.

**Source code** that implements the protocol necessarily encodes offsets and
constants. That is implementation rather than redistribution, but it is a line
worth naming rather than crossing quietly, and it is named here so the decision
is visible if it ever needs revisiting.

**Test vectors.** The document's worked example is the only external evidence
that the decoder is right rather than merely self-consistent. It lives in a
fixture that is **not committed**, so the tests using it skip in CI and run for
anyone holding the document. A green suite without it proves that
`tools/freelap_frame.py` and `source/ble/BroadcastFrame.mc` agree with each
other, not that either agrees with a chip.

## Still to ask

The specification did not answer everything, and two of the gaps matter enough
to be worth a short follow-up to the same contact:

1. **Which mask** applies to the running totals. The document gives two
   different ones in two different places, and they diverge silently once a
   counter's top bits are set (#6).
2. **How chip ids are printed.** The id is a 16-bit field but the printed form
   is two letters and four digits. Is an id below 1000 shown zero-padded, and
   what happens above 9999? The app renders it back to the athlete, so it has
   to match the chip's face exactly (#63).

Worth adding, since they are cheap: the version and battery bytes, whose
readings in the worked example do not follow a single rule from the bytes
beside them.

## Record

| | |
| --- | --- |
| Sent | *(the enquiry was answered; the sending details were not recorded here)* |
| Outcome | **Specification provided**, confidential, not redistributable |
| Follow-up owed | the two questions above |
