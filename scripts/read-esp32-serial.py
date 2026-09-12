#!/usr/bin/env python3
"""Reset an ESP32 and capture its serial boot log.

Written for the aarti lights build (aarti_lights_setup.md Phase 0): when the
board is flashed but WLED-AP does not appear, the serial log is the only thing
that distinguishes "never booted", "booted and crashed", and "booted fine and
the AP is up but the client cannot see it".

Reset is done the way esptool does it: EN is wired to RTS and IO0 to DTR on
these boards, so pulsing RTS with DTR held inactive reboots into the normal
firmware rather than the bootloader.

    ./scripts/read-esp32-serial.py [--port /dev/ttyUSB0] [--seconds 15]
"""
import argparse
import sys
import time

import serial

ap = argparse.ArgumentParser()
ap.add_argument("--port", default="/dev/ttyUSB0")
ap.add_argument("--baud", type=int, default=115200)
ap.add_argument("--seconds", type=float, default=15.0)
ap.add_argument("--no-reset", action="store_true",
                help="just listen; do not reboot the board")
args = ap.parse_args()

try:
    s = serial.Serial(args.port, args.baud, timeout=0.2)
except Exception as e:
    sys.exit(f"could not open {args.port}: {e}")

with s:
    if not args.no_reset:
        # DTR low keeps IO0 high (normal boot); pulse RTS to yank EN low.
        s.dtr = False
        s.rts = True
        time.sleep(0.1)
        s.rts = False
        print("--- reset pulsed, listening ---", flush=True)
    else:
        print("--- listening (no reset) ---", flush=True)

    deadline = time.time() + args.seconds
    saw_any = False
    while time.time() < deadline:
        data = s.read(4096)
        if data:
            saw_any = True
            sys.stdout.write(data.decode("utf-8", "replace"))
            sys.stdout.flush()

print("\n--- done ---")
if not saw_any:
    print("NO SERIAL OUTPUT AT ALL.")
    print("WLED's release builds ship with serial debug off, so silence here")
    print("is expected and does NOT mean the board is dead. Judge by whether")
    print("the AP appears, not by this.")
