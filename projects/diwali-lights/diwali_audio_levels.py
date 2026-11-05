#!/usr/bin/env python3
"""Per-second sound levels from the Diwali door board's AudioReactive sync.

One line per second: p50 / p95 / max of sampleRaw and the loudest FFT bins,
plus a bar - so a firecracker shows as a spike against the ambient floor, and
a constant electrical hum shows as a flat line that never drops.

Needs sync send on the board (um.AudioReactive.sync.mode = 1, port 11988);
AGC off makes the numbers absolute, which is what thresholds need.

    ./projects/diwali-lights/diwali_audio_levels.py [--seconds 60] [--csv out.csv]
"""
import argparse
import socket
import struct
import time

ap = argparse.ArgumentParser()
ap.add_argument("--seconds", type=float, default=60)
ap.add_argument("--iface", default="192.168.1.123")
ap.add_argument("--csv")
args = ap.parse_args()

FMT = "<6s2Bff2B16BHff"          # WLED 0.14 audioSyncPacket, see aarti-lights/wled-audio-monitor.py
SIZE = struct.calcsize(FMT)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("", 11988))
s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
             struct.pack("4s4s", socket.inet_aton("239.0.0.1"), socket.inet_aton(args.iface)))
s.settimeout(1.0)

def pct(v, q):
    return v[min(len(v) - 1, int(len(v) * q))] if v else 0

out = open(args.csv, "w") if args.csv else None
if out:
    out.write("t,raw,smooth,peak,major_hz," + ",".join(f"b{i}" for i in range(16)) + "\n")
print(f"{'t':>4} {'p50':>5} {'p95':>5} {'max':>5} {'pk':>3}  {'fft p95 low|mid|high':<20} level")
t0 = time.time()
sec, raws, ffts, peaks = 0, [], [], 0
while time.time() - t0 < args.seconds:
    try:
        data, _ = s.recvfrom(2048)
    except socket.timeout:
        continue
    if len(data) < SIZE:
        continue
    f = struct.unpack(FMT, data[:SIZE])
    now = time.time() - t0
    if out:
        out.write(f"{now:.3f},{f[3]:.1f},{f[4]:.1f},{f[5]},{f[25]:.0f}," + ",".join(map(str, f[7:23])) + "\n")
    if int(now) != sec:
        v = sorted(raws)
        lo = sorted(sum(b[0:4]) / 4 for b in ffts)
        mid = sorted(sum(b[4:10]) / 6 for b in ffts)
        hi = sorted(sum(b[10:16]) / 6 for b in ffts)
        bar = "#" * int(pct(v, 0.95) / 255 * 30)
        print(f"{sec:4d} {pct(v, .5):5.0f} {pct(v, .95):5.0f} {v[-1] if v else 0:5.0f} {peaks:3d}  "
              f"{pct(lo, .95):5.0f} {pct(mid, .95):5.0f} {pct(hi, .95):5.0f}      {bar}", flush=True)
        sec, raws, ffts, peaks = int(now), [], [], 0
    raws.append(f[3])
    ffts.append(f[7:23])
    peaks += f[5]
