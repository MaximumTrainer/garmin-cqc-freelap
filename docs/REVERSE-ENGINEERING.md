# Reverse-engineering the FxChip BLE protocol

Goal: fill in the constants and `decode()` in `source/ble/FreelapProtocol.mc`. You need to learn:

1. Advertising: device name, service UUID(s), manufacturer data (company ID + bytes). → device matching.
2. GATT: which characteristic notifies with run data, whether a command/handshake write is needed, MTU / fragmentation.
3. Packet format: framing, per-crossing record layout, timestamp unit and width, transmitter code field, chip id, checksum.

## Kit

- Android phone with MyFreelap installed + Developer options → *Enable Bluetooth HCI snoop log*. Free, no extra hardware, captures everything the app does including any handshake writes. Pull `btsnoop_hci.log` via `adb bugreport` and open in Wireshark.
- Or: nRF52840 dongle + nRF Sniffer for BLE (Wireshark plugin) to sniff over-the-air, useful when you also want to see the watch↔chip traffic later.
- nRF Connect (phone app) to browse the chip's GATT table directly: service/characteristic UUIDs and properties (notify/write) in 30 seconds.
- A tape measure and 3 transmitters.

## Scripted session (do this exactly, note everything)

For each run write down: MyFreelap's displayed splits (to the 1/100 or 1/1000 it shows), the number of transmitters crossed, and the wall time you crossed FINISH (phone stopwatch started as you cross START is enough).

| Run | Course | Purpose |
|---|---|---|
| A | START → FINISH, 20 m, walk | one record; find the timestamp field by matching the displayed time |
| B | same, jog | same layout, different value; confirms unit (ms vs 1/100 vs µs) and endianness |
| C | START → LAP → FINISH, 10 m + 10 m | two records; find the record stride and the transmitter code byte |
| D | START → LAP → LAP → FINISH | three; confirms stride, look for a count/length byte in the header |
| E | Cross START only, wait 30 s, cross FINISH | is there a START notification in real time or only a burst at FINISH? |
| F | Run C twice without reconnecting | rep counter / sequence number? |
| G | Power-cycle the chip, run A | what resets: sequence, timestamp base? |

## Diffing

`tools/decode_capture.py` takes a Wireshark export (`File → Export Packet Dissections → CSV` with `btatt.value` visible, or `tshark -T fields -e frame.time_epoch -e btatt.value`) and prints each notification as hex with the arrival time and the delta to the previous packet. Add your noted MyFreelap values as arguments and it will search each packet for those values encoded as u16/u32 LE/BE in ms, 1/100 s and µs, which usually pinpoints the timestamp field in one pass.

Things to check once you've found the timestamp:

- Is it absolute (chip uptime) or relative to START? Run E vs G answers this.
- Width: if it is u32 in ms it wraps at 49.7 days — irrelevant. If u24 or u16 note the wrap and handle it in `decode()`.
- Does the FINISH packet include all crossings, or does the chip notify per crossing (Run E)? Set `STREAMING` accordingly.
- Does the app write anything before data flows (look for ATT Write Request in the snoop log right after connect)? Copy it into `getHandshakeWrites()`.
- Fragmentation: any notification of exactly 20 bytes followed immediately by a shorter one is a fragment pair; find the length field.

## Estimating BLE latency (for `fl_est_ms`)

With the decoder working: start a phone stopwatch and cross START at the same instant, cross FINISH at a known reading, compare to the watch's `t_arrive` for the FINISH packet minus `rep_time`. Ten trials, take the median, set `bleLatencyMs` in settings. Expect 50–300 ms.

## Watch-side capture mode

Once the service UUID is known, enable *Capture mode* in the app settings. The watch subscribes and logs every notification (hex + `System.getTimer()`) to `Application.Storage` (last 200 packets, rolling) and shows the latest on screen. Useful for confirming the watch sees the same bytes as the phone, and for catching packets the phone app never triggers (e.g. real-time START).
