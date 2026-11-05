#!/usr/bin/env python3
"""Firecracker -> burst animation on the Diwali door lights; steady otherwise.

The board's mic (WLED AudioReactive, AGC off, gain 10) reads a loud, constant
floor in the low and mid FFT bins whatever the street is doing (measured
2026-11-05; dimming the strip does not change it), so WLED's own
sound-reactive effects - which follow the overall level - just stay busy all
the time. A cracker shows up as a burst in the HIGH bins (10-15), which sit at
~30 (p50) between bangs and jump to 200-254 on one. So this listens to the
board's audio sync stream, and:

  - high-band mean >= --threshold for --min-frames packets in a row
      -> preset BURST (Fireworks Starburst), instantly
  - --hold seconds after the last such frame -> back to preset STEADY

It only switches while the board is showing one of those two presets, so
picking anything else in the WLED UI is left alone until it is set back.
If this stops (xero down), the board keeps whatever it shows; it boots into
STEADY on its own.

Needs on the board: um.AudioReactive.sync.mode = 1 (send), port 11988.

    ./projects/diwali-lights/diwali_cracker_fx.py [--threshold 220] [--hold 3] [--dry-run]
Runs as projects/diwali-lights/diwali-cracker-fx.service (systemd --user).
"""
import argparse
import json
import socket
import struct
import time
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="192.168.1.127")
ap.add_argument("--iface", default="192.168.1.123")
ap.add_argument("--threshold", type=float, default=220)
ap.add_argument("--min-frames", type=int, default=4, help="consecutive packets (~42/s) over threshold")
ap.add_argument("--hold", type=float, default=3.0, help="seconds of burst after the last loud frame")
ap.add_argument("--steady", type=int, default=3, help="preset id shown between crackers")
ap.add_argument("--burst", type=int, default=4, help="preset id shown on a cracker")
ap.add_argument("--dry-run", action="store_true")
args = ap.parse_args()

FMT = "<6s2Bff2B16BHff"   # WLED 0.14 audioSyncPacket, see aarti-lights/wled-audio-monitor.py
SIZE = struct.calcsize(FMT)


def wled(path, body=None):
    req = urllib.request.Request(f"http://{args.host}/json/{path}",
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=3) as r:
        return json.load(r)


def current_ps():
    try:
        st = wled("state")
        return st.get("ps") if st.get("on") else None
    except Exception:
        return None


def show(ps):
    if args.dry_run:
        print(f"  (dry run) would show preset {ps}", flush=True)
        return True
    try:
        wled("state", {"ps": ps, "tt": 0 if ps == args.burst else 10})
        return True
    except Exception as e:
        print(f"  WLED unreachable: {e}", flush=True)
        return False


s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", 11988))
s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
             struct.pack("4s4s", socket.inet_aton("239.0.0.1"), socket.inet_aton(args.iface)))
s.settimeout(1.0)
print(f"listening; threshold {args.threshold}, {args.min_frames} frames, hold {args.hold}s, "
      f"steady ps {args.steady}, burst ps {args.burst}", flush=True)

bursting = False
streak = 0
last_loud = 0.0
next_ps_check = 0.0
ps = None
while True:
    try:
        data, _ = s.recvfrom(2048)
    except socket.timeout:
        data = b""
    now = time.time()
    if now >= next_ps_check:
        ps = current_ps()
        next_ps_check = now + 5
    if len(data) >= SIZE:
        fft = struct.unpack(FMT, data[:SIZE])[7:23]
        high = sum(fft[10:16]) / 6
        streak = streak + 1 if high >= args.threshold else 0
        if streak >= args.min_frames:
            last_loud = now
            if not bursting and (ps in (args.steady, args.burst) or args.dry_run):
                print(f"{time.strftime('%H:%M:%S')} cracker (high {high:.0f}) -> burst", flush=True)
                if show(args.burst):
                    bursting, ps = True, args.burst
    if bursting and now - last_loud > args.hold:
        print(f"{time.strftime('%H:%M:%S')} quiet -> steady", flush=True)
        show(args.steady)
        bursting, ps = False, args.steady
