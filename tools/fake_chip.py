#!/usr/bin/env python3
"""Fake FxChip BLE peripheral for end-to-end testing of the watch app before
the real protocol is known. Advertises the HYPOTHESIS service from
FreelapProtocol.mc and, on each Enter keypress, notifies one rep burst in the
hypothesised layout.

Requires Linux + BlueZ and `pip install bless`. Adjust UUIDs and packet
layout in lock-step with FreelapProtocol.mc.
"""
import asyncio
import struct
import sys

# bless is only needed to actually advertise; the packet builders below are
# imported by tools/tests/ on machines (and in CI) that have no BlueZ.
try:
    from bless import BlessServer, GATTCharacteristicProperties, GATTAttributePermissions
except ImportError:
    BlessServer = None

SERVICE = "6E400001-B5A3-F393-E0A9-E50E24DCC9E6"
NOTIFY = "6E400003-B5A3-F393-E0A9-E50E24DCC9E6"
COMMAND = "6E400002-B5A3-F393-E0A9-E50E24DCC9E6"
NAME = "FxChip-TEST"

# One rep on a S:0;L:30;L:60;F:100 course, chip ticks in ms.
REP = [(0, 1), (4120, 2), (7480, 2), (11930, 3)]


def build_packet(rep, chip_id=0x1234):
    body = bytes([0xA5, len(rep)]) + struct.pack("<H", chip_id)
    for ticks, code in rep:
        body += struct.pack("<IB", ticks, code)
    return body


def fragments(data, mtu=20):
    return [data[i : i + mtu] for i in range(0, len(data), mtu)]


async def main():
    if BlessServer is None:
        sys.exit("pip install bless (and run on Linux with BlueZ)")
    server = BlessServer(name=NAME)
    await server.add_new_service(SERVICE)
    await server.add_new_characteristic(
        SERVICE, NOTIFY,
        GATTCharacteristicProperties.notify | GATTCharacteristicProperties.read,
        None, GATTAttributePermissions.readable)
    await server.add_new_characteristic(
        SERVICE, COMMAND,
        GATTCharacteristicProperties.write, None, GATTAttributePermissions.writeable)
    await server.start()
    print(f"Advertising as {NAME}. Press Enter to send a rep, Ctrl-C to quit.")
    loop = asyncio.get_event_loop()
    while True:
        await loop.run_in_executor(None, sys.stdin.readline)
        pkt = build_packet(REP)
        for frag in fragments(pkt):
            server.get_characteristic(NOTIFY).value = bytearray(frag)
            server.update_value(SERVICE, NOTIFY)
            await asyncio.sleep(0.03)
        print("sent", pkt.hex(" "))


if __name__ == "__main__":
    asyncio.run(main())
