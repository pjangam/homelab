#!/usr/bin/env python3
"""Record and inspect WLED's audio analysis, for the aarti lights Tier 3 work.

Tier 3 is telling a ghanta from a clap from a voice and colouring each
differently (see PROJECTS.md). That needs thresholds derived from this bell,
this room and this mic - not from assumptions - so the first job is capturing
labelled samples of each sound and looking at what actually distinguishes
them.

Source is WLED's AudioReactive sound-sync broadcast: 16 FFT bins plus a raw
and smoothed level, about 20-40 times a second, multicast to 239.0.0.1. That
is the microphone already mounted behind the makhar, which is why we use it
rather than a second mic on this machine - xero is in the wrong room.

Set WLED's squelch to 0 while collecting: at a higher threshold the board
zeroes quiet frames and throws away the decay tail, which is the single most
useful feature for separating a ringing bell from a clap.

    ./scripts/aarti-sound-lab.py live
    ./scripts/aarti-sound-lab.py record --label ghanta --seconds 20
    ./scripts/aarti-sound-lab.py events  --label ghanta
"""
import argparse
import json
import math
import os
import socket
import struct
import sys
import time

MCAST = "239.0.0.1"
PORT = 11988
# WLED 0.14/16.x audioSyncPacket, 44 bytes little-endian.
FMT = "<6s2Bff2B16BHff"
SIZE = struct.calcsize(FMT)
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "aarti-sound")

# Approximate centre of each of WLED's 16 bins, Hz. Used only for describing
# features in human terms; the classifier works on bin indices.
BIN_HZ = [64, 107, 172, 323, 495, 710, 990, 1270, 1570, 1936, 2584,
          3375, 4428, 5621, 6644, 11383]


def open_socket(iface, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    mreq = struct.pack("4s4s", socket.inet_aton(MCAST), socket.inet_aton(iface))
    try:
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except OSError as e:
        sys.exit(f"could not join {MCAST} on {iface}: {e}\n"
                 "Name the LAN interface address with --iface; this host also "
                 "has docker bridges and tailscale to choose from.")
    s.settimeout(1.0)
    return s


def parse(data):
    if len(data) < SIZE:
        return None
    f = struct.unpack(FMT, data[:SIZE])
    return {
        "raw": f[3],
        "smth": f[4],
        "peak": f[5],
        "fft": list(f[7:23]),
        "mag": f[24],
        "major": f[25],
    }


def features(fft):
    """Shape of one frame's spectrum, independent of loudness.

    centroid  - energy-weighted mean bin. Low for a voice, high for a bell or
                cymbal. This is the "brightness" axis.
    flatness  - geometric over arithmetic mean. Near 1 means broadband noise
                (a clap); near 0 means energy concentrated in a few bins (a
                tonal bell).
    """
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


def cmd_live(args):
    s = open_socket(args.iface, args.port)
    print(f"listening on {MCAST}:{args.port}. Ctrl-C to stop.\n")
    print(f"{'raw':>6} {'energy':>7} {'centroid':>9} {'flatness':>9}  spectrum")
    with s:
        while True:
            try:
                data, _ = s.recvfrom(2048)
            except socket.timeout:
                continue
            except KeyboardInterrupt:
                break
            p = parse(data)
            if not p:
                continue
            c, fl, tot = features(p["fft"])
            if p["raw"] < args.floor and tot < args.floor:
                continue
            bars = "".join("_.:-=+*#"[min(7, int(v / 32))] for v in p["fft"])
            print(f"{p['raw']:6.0f} {tot:7.0f} {c:9.2f} {fl:9.3f}  {bars}")


def cmd_record(args):
    os.makedirs(DATA_DIR, exist_ok=True)
    path = os.path.join(DATA_DIR, f"{args.label}.jsonl")
    s = open_socket(args.iface, args.port)
    print(f"recording '{args.label}' for {args.seconds:.0f}s -> {path}")
    print("make the sound several times, with a gap between each\n")
    n = 0
    t0 = time.time()
    with s, open(path, "a") as fh:
        while time.time() - t0 < args.seconds:
            try:
                data, _ = s.recvfrom(2048)
            except socket.timeout:
                continue
            p = parse(data)
            if not p:
                continue
            p["t"] = round(time.time() - t0, 4)
            p["label"] = args.label
            fh.write(json.dumps(p) + "\n")
            n += 1
            if n % 20 == 0:
                print(f"\r  {time.time()-t0:5.1f}s  {n} frames", end="", flush=True)
    print(f"\n{n} frames written to {path}")


def cmd_events(args):
    """Segment a recording into onsets and describe each one.

    An event starts when energy crosses the threshold and ends when it falls
    back for a sustained stretch. Duration is the feature that separates a
    ringing ghanta from a clap; centroid and flatness separate a bell from a
    voice.
    """
    path = os.path.join(DATA_DIR, f"{args.label}.jsonl")
    if not os.path.exists(path):
        sys.exit(f"no recording at {path} - run 'record --label {args.label}' first")
    frames = [json.loads(l) for l in open(path)]
    if not frames:
        sys.exit("recording is empty")

    rows = []
    for f in frames:
        c, fl, tot = features(f["fft"])
        rows.append((f["t"], f["raw"], tot, c, fl))

    # Two thresholds, not one. A single level measures only the attack: the
    # moment a bell's ring decays past it the event is declared over, and a
    # 1.5s ghanta gets reported as 90ms. Onset needs a high bar so the room
    # does not trigger it; sustain needs a low one so the decay is followed
    # all the way down. That decay is the whole point - it is what separates
    # a ringing bell from a clap.
    #
    # The floor comes from a low percentile rather than the median, because
    # in a recording of repeated bell strikes the median is itself partly
    # ring tail and drags the threshold far too high.
    energies = sorted(r[2] for r in rows)
    floor = energies[int(len(energies) * 0.20)]
    onset = max(args.threshold, floor * 4 + 30)
    sustain = max(args.threshold * 0.4, floor * 1.5 + 10)
    print(f"{len(frames)} frames, p20 energy {floor:.0f}")
    print(f"onset threshold {onset:.0f}, sustain threshold {sustain:.0f}\n")

    events, cur = [], None
    quiet = 0
    for t, raw, tot, c, fl in rows:
        if cur is None:
            if tot >= onset:
                cur = {"t0": t, "t1": t, "peak": tot, "cs": [c], "fls": [fl],
                       "attack_c": c, "attack_fl": fl}
                quiet = 0
        else:
            if tot >= sustain:
                quiet = 0
                cur["peak"] = max(cur["peak"], tot)
                cur["cs"].append(c)
                cur["fls"].append(fl)
                cur["t1"] = t
            else:
                quiet += 1
                if quiet >= args.gap:
                    events.append(cur)
                    cur = None
    if cur:
        events.append(cur)

    if not events:
        print("no events found above threshold - make the sound louder, or lower --threshold")
        return
    # Attack features are reported separately from the whole-event average:
    # the first frame is what a live classifier has to decide on, since it
    # cannot wait for a bell to stop ringing before choosing a colour.
    print(f"{'#':>3} {'start':>7} {'dur ms':>7} {'peak':>7} {'cent':>6} {'flat':>6}   "
          f"{'attack cent':>11} {'attack flat':>11}")
    for i, e in enumerate(events, 1):
        dur = (e["t1"] - e["t0"]) * 1000
        c = sum(e["cs"]) / len(e["cs"])
        fl = sum(e["fls"]) / len(e["fls"])
        print(f"{i:>3} {e['t0']:7.2f} {dur:7.0f} {e['peak']:7.0f} {c:6.2f} {fl:6.3f}   "
              f"{e['attack_c']:11.2f} {e['attack_fl']:11.3f}")
    durs = sorted((e["t1"] - e["t0"]) * 1000 for e in events)
    cs = sorted(sum(e["cs"]) / len(e["cs"]) for e in events)
    fls = sorted(sum(e["fls"]) / len(e["fls"]) for e in events)
    mid = lambda v: v[len(v) // 2]
    print(f"\nmedian for '{args.label}':  duration {mid(durs):.0f} ms   "
          f"centroid {mid(cs):.2f} (~{BIN_HZ[min(15, int(mid(cs)))]} Hz)   flatness {mid(fls):.3f}")


ap = argparse.ArgumentParser(description=__doc__,
                             formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--iface", default="192.168.1.123")
ap.add_argument("--port", type=int, default=PORT)
sub = ap.add_subparsers(dest="cmd", required=True)

p_live = sub.add_parser("live", help="print features as they arrive")
p_live.add_argument("--floor", type=float, default=1.0)
p_live.set_defaults(func=cmd_live)

p_rec = sub.add_parser("record", help="capture a labelled sample to data/aarti-sound/")
p_rec.add_argument("--label", required=True)
p_rec.add_argument("--seconds", type=float, default=20.0)
p_rec.set_defaults(func=cmd_record)

p_ev = sub.add_parser("events", help="segment a recording into onsets and describe them")
p_ev.add_argument("--label", required=True)
p_ev.add_argument("--threshold", type=float, default=0.0)
p_ev.add_argument("--gap", type=int, default=4, help="quiet frames that end an event")
p_ev.set_defaults(func=cmd_events)

args = ap.parse_args()
args.func(args)
