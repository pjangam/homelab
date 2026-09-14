"""Shared audio analysis for the aarti lights Tier 3 work.

One module so the thresholds live in exactly one place: `aarti-classify.py`
(validation) and `aarti-render.py` (the lights) both import from here. If the
mic moves, the bell changes or the room does, re-record with
`aarti-sound-lab.py` and change the numbers here only.

Measured 2026-09-14 from labelled recordings (see data/aarti-sound/README.md):

    class    centroid p10/med/p90   flatness med   energy med
    voice    1.94 /  2.32 /  2.64      0.959           712
    clap     6.55 /  8.72 /  9.27      0.897          2340
    ghanta   3.39 /  8.75 / 11.17      0.820           560

Voice separates on centroid alone. Clap and ghanta do not - their centroids
are identical - so they separate on persistence and tonality instead.
"""
import math
import socket
import struct
import sys
import time

MCAST, PORT = "239.0.0.1", 11988
FMT = "<6s2Bff2B16BHff"
SIZE = struct.calcsize(FMT)

FLOOR_ENERGY = 450          # room floor measured 71-121; 300 let handling noise through
VOICE_CENTROID_MAX = 4.5    # voice p90 2.64, bright p10 6.55 - wide gap, sit in it
BRIGHT_CENTROID_MIN = 5.5
GHANTA_SUSTAIN_S = 1.2      # ghanta rang 13s; every clap ended inside 0.5s
GHANTA_FLATNESS_MAX = 0.78  # live: ghanta 0.694 vs claps 0.839-0.887
GHANTA_FAST_S = 0.30        # tonal for this long => bell, without waiting 1.2s
STRIKE_END_QUIET_S = 0.25


def features(fft):
    """centroid (brightness), flatness (tonal vs broadband), total energy."""
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


def parse(data):
    if len(data) < SIZE:
        return None
    f = struct.unpack(FMT, data[:SIZE])
    return list(f[7:23])


def open_socket(iface, port=PORT):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    mreq = struct.pack("4s4s", socket.inet_aton(MCAST), socket.inet_aton(iface))
    try:
        s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except OSError as e:
        sys.exit(f"could not join {MCAST} on {iface}: {e}\n"
                 "Name the LAN interface with --iface; this host also has "
                 "docker bridges and tailscale.")
    s.settimeout(0.5)
    return s


class Classifier:
    """State machine over frames. Emits ('strike'|'ghanta'|'clap'|'voice', info).

    A strike cannot be named at onset - a bell and a clap are indistinguishable
    for their first moments - so 'strike' fires immediately and is followed by
    'ghanta' or 'clap' once it can be decided. Tonality decides it early where
    it can (a bell is markedly less flat), duration where it cannot.
    """

    def __init__(self):
        self.strike_start = None
        self.last_bright = 0.0
        self.peak = 0.0
        self.flats = []
        self.resolved = None
        self.voice_since = None
        self.level = 0.0        # 0-1, loudness of whatever is happening now

    def update(self, fft, now):
        events = []
        c, fl, tot = features(fft)
        self.level = min(1.0, tot / 3000.0)

        bright = tot > FLOOR_ENERGY and c >= BRIGHT_CENTROID_MIN
        voiced = tot > FLOOR_ENERGY and c < VOICE_CENTROID_MAX

        if bright:
            self.last_bright = now
            if self.strike_start is None:
                self.strike_start, self.peak, self.flats, self.resolved = now, tot, [fl], None
                events.append(("strike", {"energy": tot, "centroid": c}))
            else:
                self.peak = max(self.peak, tot)
                self.flats.append(fl)
                if self.resolved is None:
                    held = now - self.strike_start
                    mean_fl = sum(self.flats) / len(self.flats)
                    # Tonal for long enough is a bell, and says so ~4x sooner
                    # than waiting for it to outlast a clap.
                    if held >= GHANTA_FAST_S and mean_fl <= GHANTA_FLATNESS_MAX:
                        self.resolved = "ghanta"
                        events.append(("ghanta", {"via": "tonality", "flatness": mean_fl,
                                                  "held": held, "peak": self.peak}))
                    elif held >= GHANTA_SUSTAIN_S:
                        self.resolved = "ghanta"
                        events.append(("ghanta", {"via": "duration", "flatness": mean_fl,
                                                  "held": held, "peak": self.peak}))
        elif self.strike_start is not None and now - self.last_bright > STRIKE_END_QUIET_S:
            dur = self.last_bright - self.strike_start
            mean_fl = sum(self.flats) / len(self.flats) if self.flats else 0.0
            if self.resolved is None:
                events.append(("clap", {"duration": dur, "peak": self.peak,
                                        "flatness": mean_fl}))
            else:
                events.append(("ghanta_end", {"duration": dur}))
            self.strike_start, self.resolved = None, None

        if voiced and self.strike_start is None:
            if self.voice_since is None:
                self.voice_since = now
            elif now - self.voice_since > 0.30:
                events.append(("voice", {"centroid": c, "energy": tot}))
                self.voice_since = now
        elif not voiced:
            self.voice_since = None

        return events

    @property
    def ghanta_ringing(self):
        return self.resolved == "ghanta"
