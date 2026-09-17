#!/usr/bin/env python3
"""Measure the ambient FFT energy the classifier sees, with the room resting.

`wled-audio-monitor.py` reports WLED's own sampleRaw, which is what the squelch
acts on. The Tier 3 classifier instead thresholds the *sum of the 16 FFT bins*
against FLOOR_ENERGY in aarti_audio.py, and those are different numbers. To
decide whether a resting room (ceiling fan, traffic) crosses that floor - and
where an "is anything actually happening" cutoff belongs - the distribution of
that sum is the thing to measure.

    ./projects/aarti-lights/ambient-energy.py [--seconds 30]
"""
import argparse
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aarti_audio import (FLOOR_ENERGY, VOICE_CENTROID_MAX, BRIGHT_CENTROID_MIN,
                         features, open_socket, parse)

ap = argparse.ArgumentParser()
ap.add_argument("--seconds", type=float, default=30.0)
ap.add_argument("--iface", default="192.168.1.123")
a = ap.parse_args()

rx = open_socket(a.iface)
energies, over, voiced, bright = [], 0, 0, 0
t0 = time.time()
while time.time() - t0 < a.seconds:
    try:
        data, _ = rx.recvfrom(2048)
    except OSError:
        continue
    fft = parse(data)
    if not fft:
        continue
    c, fl, tot = features(fft)
    energies.append((tot, c))
    if tot > FLOOR_ENERGY:
        over += 1
        if c < VOICE_CENTROID_MAX:
            voiced += 1
        elif c >= BRIGHT_CENTROID_MIN:
            bright += 1

if not energies:
    sys.exit("no packets - is UDP sound sync still on? see wled-audio-monitor.py")

tots = sorted(e for e, _ in energies)
n = len(tots)
def pct(p):
    return tots[min(n - 1, int(n * p / 100))]

print(f"{n} frames over {a.seconds:.0f}s   FLOOR_ENERGY = {FLOOR_ENERGY}")
print(f"  total FFT energy: min {tots[0]:.0f}  median {pct(50):.0f}  "
      f"p90 {pct(90):.0f}  p95 {pct(95):.0f}  p99 {pct(99):.0f}  max {tots[-1]:.0f}")
print(f"  frames over the floor: {over}/{n} ({100*over/n:.1f}%)   "
      f"of those: {voiced} would read as voice, {bright} as a strike")
loud = [c for e, c in energies if e > FLOOR_ENERGY]
if loud:
    print(f"  centroid of those frames: min {min(loud):.2f}  max {max(loud):.2f}")
