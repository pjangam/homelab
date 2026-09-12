#!/usr/bin/env python3
"""Listen to WLED's AudioReactive UDP sound-sync broadcast and print levels.

Phase 2 of aarti_lights_setup.md needs a numeric answer to "does the mic
work", and WLED 0.14.4 does not expose the audio level over /json/info - the
web UI reads it over a websocket. But the AudioReactive usermod can transmit
its analysis as a UDP broadcast (Sync -> send, default port 11988), which is
readable from anywhere on the LAN and gives a real number rather than a
judgement about how an effect looks.

Enable transmit first:
  curl -X POST http://<board>/json/cfg -H 'Content-Type: application/json' \
    -d '{"um":{"AudioReactive":{"sync":{"mode":1,"port":11988}}}}'

    ./scripts/wled-audio-monitor.py [--seconds 20] [--port 11988]
"""
import argparse
import socket
import struct
import sys
import time

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=11988)
ap.add_argument("--seconds", type=float, default=20.0)
ap.add_argument("--iface", default="192.168.1.123",
                help="local LAN address to join the multicast group on")
args = ap.parse_args()

# WLED 0.14 audioSyncPacket, 44 bytes little-endian:
#   char header[6]; uint8 pressure[2]; float sampleRaw; float sampleSmth;
#   uint8 samplePeak; uint8 frameCounter; uint8 fftResult[16];
#   uint16 zeroCrossingCount; float FFT_Magnitude; float FFT_MajorPeak;
FMT = "<6s2Bff2B16BHff"
SIZE = struct.calcsize(FMT)

# WLED's AudioReactive does not broadcast - it sends to the multicast group
# 239.0.0.1, so binding the port alone receives nothing. The membership has to
# be joined, and on a host with several interfaces (this one has docker
# bridges and tailscale) the LAN interface must be named explicitly or the
# join lands on the wrong one.
MCAST = "239.0.0.1"

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("", args.port))
except OSError as e:
    sys.exit(f"could not bind UDP {args.port}: {e}")

mreq = struct.pack("4s4s", socket.inet_aton(MCAST), socket.inet_aton(args.iface))
try:
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    print(f"joined multicast {MCAST} on {args.iface}")
except OSError as e:
    print(f"could not join {MCAST} on {args.iface}: {e}")

s.settimeout(1.0)

print(f"listening on UDP {args.port} for {args.seconds:.0f}s "
      f"(expecting {SIZE}-byte packets)")
print("make some noise at the mic - clap, talk, play the aarti\n")
print(f"{'t':>5}  {'raw':>8}  {'smooth':>8}  {'peak':>4}  {'majorHz':>8}  bars")

deadline = time.time() + args.seconds
t0 = time.time()
count = 0
seen_raw = []
while time.time() < deadline:
    try:
        data, addr = s.recvfrom(2048)
    except socket.timeout:
        continue
    count += 1
    if len(data) < SIZE:
        print(f"  short packet ({len(data)} bytes) from {addr[0]}")
        continue
    f = struct.unpack(FMT, data[:SIZE])
    header = f[0].split(b"\0")[0].decode("ascii", "replace")
    raw, smth = f[3], f[4]
    peak, _frame = f[5], f[6]
    fft = f[7:23]
    major = f[25]
    seen_raw.append(raw)
    # 16 FFT bins as a coarse bar, so a frequency response is visible too
    bars = "".join("_.:-=+*#"[min(7, int(v / 32))] for v in fft)
    if count % 3 == 1:   # ~ every third packet, to stay readable
        print(f"{time.time()-t0:5.1f}  {raw:8.1f}  {smth:8.1f}  {peak:4d}  "
              f"{major:8.1f}  {bars}   [{header}]")

print()
if count == 0:
    print("NO PACKETS RECEIVED.")
    print("Either sync transmit is not enabled, the port differs, or the")
    print("multicast join did not take. Check:")
    print("  curl -s http://<board>/json/cfg | python3 -m json.tool | grep -A4 sync")
else:
    lo, hi = min(seen_raw), max(seen_raw)
    print(f"{count} packets. sampleRaw ranged {lo:.1f} .. {hi:.1f}")
    if hi - lo < 1.0:
        print("LEVEL NEVER MOVED - the mic is not producing audio.")
        print("In order of likelihood: WS or SCK on an input-only pin")
        print("(GPIO34-39 cannot drive), mic fed 5V instead of 3.3V, L/R left")
        print("floating, or a cold joint on the header you just soldered.")
    else:
        print("LEVEL MOVES - the mic works.")
