# Captures

Captures of the chip's **advertisements**, used to confirm
`source/ble/BroadcastFrame.mc` against real hardware. The chip broadcasts and
never accepts a connection, so these are recorded off the air with nRF Connect,
`btmon` or a sniffer — there is no connection to get inside, and no phone
needed.

One folder per session, `YYYY-MM-DD-<chip-or-firmware>/`, containing the export
(`<epoch>	<anything>	<hex>`, which `tools/decode_capture.py` reads), the run
script that was followed (see `docs/REVERSE-ENGINEERING.md`), and the MyFreelap
values noted for each run.

Include the chip's **firmware version** — the specification applies from a
stated minimum and a capture from an older chip proves nothing.

Never commit anything containing a phone's identifying data. The chip's own
address is fine.
