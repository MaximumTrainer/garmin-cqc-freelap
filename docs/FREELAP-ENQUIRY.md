# Asking Freelap for the protocol (issue #8)

Reverse-engineering the FxChip BLE (#4–#7) is the long way round. Freelap have
partnered with third parties before, so it is worth asking first — and worth
having asked, in writing, whichever way they answer.

**Nobody has sent this yet.** Fill in the record at the bottom when someone
does.

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
> The project is at https://github.com/MaximumTrainer/garmin-cqc-freelap if it
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

## If a spec arrives under NDA

Do not paste it into the repo. `source/ble/FreelapProtocol.mc` is the only file
that knows the packet format, which is deliberate — it is the file that would
have to be handled differently. Record here which parts are restricted, and
keep the capture-derived vectors (`source-test/ProtocolVectorTest.mc`) as the
public evidence that the decoder is correct, since those are observations of
the chip's own output rather than the specification.

## Record

| | |
| --- | --- |
| Sent | *(not yet)* |
| To | |
| By | |
| Reply received | |
| Outcome | |

Update this table and the issue when it is sent, and again when they reply or
thirty days pass.
