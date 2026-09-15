#!/usr/bin/env python3
"""Classify ghanta / clap / voice from WLED's audio stream, live.

Tier 3 of the aarti lights (see PROJECTS.md). Thresholds below are measured,
not guessed - from labelled recordings made on 2026-09-14 with this bell,
this mic and this room, via aarti-sound-lab.py. Re-measure if any of those
change; the numbers are in the table in CLASSES.

What the recordings showed:

  class    centroid (p10/med/p90)   flatness med   energy med
  voice    1.94 /  2.32 /  2.64        0.959           712
  clap     6.55 /  8.72 /  9.27        0.897          2340
  ghanta   3.39 /  8.75 / 11.17        0.820           560

Voice separates on centroid alone. Clap and ghanta do NOT - their centroids
are identical to two decimal places - so they are separated by how long the
bright state persists: the ghanta rang continuously for 13 seconds, while
claps were discrete bursts under a second. That makes this a state machine
rather than a per-frame rule.

A consequence worth understanding: a strike cannot be identified at its
onset, because a bell and a clap look the same for the first second. So the
onset is reported as STRIKE, and resolves to GHANTA or CLAP once its duration
is known. Visually that is what you want anyway - a flash that settles into
the bell's colour.

    ./scripts/aarti-lights/aarti-classify.py            # live, prints classifications
    ./scripts/aarti-lights/aarti-classify.py --verbose  # also prints every frame
"""
import argparse
import functools
import math
import socket
import struct
import sys
import time

print = functools.partial(__builtins__.print if hasattr(__builtins__, "print")
                          else __import__("builtins").print, flush=True)

MCAST, PORT = "239.0.0.1", 11988
FMT = "<6s2Bff2B16BHff"
SIZE = struct.calcsize(FMT)

# --- measured thresholds -----------------------------------------------------
FLOOR_ENERGY = 300      # room floor sat at 71-121; loud frames all exceeded 300
VOICE_CENTROID_MAX = 4.5   # voice p90 was 2.64, bright sounds p10 was 6.55
BRIGHT_CENTROID_MIN = 5.5  # gap between the two, biased toward "bright"
GHANTA_SUSTAIN_S = 1.2     # ghanta rang 13s; claps ended inside 0.9s
STRIKE_END_QUIET_S = 0.25  # bright must stay gone this long to end a strike


def features(fft):
    total = sum(fft)
    if total <= 0:
        return 0.0, 0.0, 0.0
    centroid = sum(i * v for i, v in enumerate(fft)) / total
    nz = [v for v in fft if v > 0]
    if len(nz) < 2:
        return centroid, 0.0, total
    gm = math.exp(sum(math.log(v) for v in nz) / len(nz))
    am = sum(nz) / len(nz)
    return centroid, (gm / am if am else 0.0), total


def open_socket(iface):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", PORT))
    mreq = struct.pack("4s4s", socket.inet_aton(MCAST), socket.inet_aton(iface))
    try:
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except OSError as e:
        sys.exit(f"could not join {MCAST} on {iface}: {e}")
    s.settimeout(1.0)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default="192.168.1.123")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--seconds", type=float, default=0.0, help="0 = run until Ctrl-C")
    a = ap.parse_args()

    s = open_socket(a.iface)
    print("listening. Make sounds: ring the ghanta, clap, talk.\n")

    strike_start = None      # when the current bright run began
    strike_peak = 0.0
    strike_flat = []
    reported = None          # what this strike has already been called
    last_bright = 0.0
    voice_since = None
    t0 = time.time()

    with s:
        while a.seconds == 0 or time.time() - t0 < a.seconds:
            try:
                data, _ = s.recvfrom(2048)
            except socket.timeout:
                continue
            except KeyboardInterrupt:
                break
            if len(data) < SIZE:
                continue
            f = struct.unpack(FMT, data[:SIZE])
            c, fl, tot = features(list(f[7:23]))
            now = time.time()

            if a.verbose and tot > FLOOR_ENERGY:
                print(f"    e{tot:6.0f} c{c:5.2f} f{fl:5.3f}")

            bright = tot > FLOOR_ENERGY and c >= BRIGHT_CENTROID_MIN
            voiced = tot > FLOOR_ENERGY and c < VOICE_CENTROID_MAX

            if bright:
                last_bright = now
                if strike_start is None:
                    strike_start, strike_peak, strike_flat, reported = now, tot, [fl], None
                    print(f"[{now-t0:6.2f}] STRIKE   (bell or clap - too early to tell)")
                else:
                    strike_peak = max(strike_peak, tot)
                    strike_flat.append(fl)
                    if reported is None and now - strike_start >= GHANTA_SUSTAIN_S:
                        reported = "ghanta"
                        mf = sum(strike_flat) / len(strike_flat)
                        print(f"[{now-t0:6.2f}] -> GHANTA  sustained {now-strike_start:.1f}s, "
                              f"peak {strike_peak:.0f}, flatness {mf:.3f}")
            elif strike_start is not None and now - last_bright > STRIKE_END_QUIET_S:
                dur = last_bright - strike_start
                if reported is None:
                    mf = sum(strike_flat) / len(strike_flat) if strike_flat else 0
                    print(f"[{now-t0:6.2f}] -> CLAP    {dur*1000:.0f}ms, "
                          f"peak {strike_peak:.0f}, flatness {mf:.3f}")
                else:
                    print(f"[{now-t0:6.2f}] .. ghanta ended after {dur:.1f}s")
                strike_start, reported = None, None

            if voiced and strike_start is None:
                if voice_since is None:
                    voice_since = now
                elif now - voice_since > 0.5:
                    print(f"[{now-t0:6.2f}] VOICE    centroid {c:.2f}")
                    voice_since = now + 1.5   # rate-limit the reporting
            elif not voiced:
                voice_since = None


main()
