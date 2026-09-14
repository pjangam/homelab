#!/usr/bin/env python3
"""Drive the aarti strip from sound classification - one zone per class.

Tier 3 (see PROJECTS.md). Two ways to draw the same classification:

  --mode zones   one third of the strip per class. Legible and literal:
                   0- 59 VOICE amber | 60-119 CLAP white | 120-179 GHANTA green
                 Two thirds sit at idle most of the time.

  --mode layers  all three share the whole strip, composited additively:
                   VOICE  a warm base glow along the full length
                   CLAP   a white burst sweeping outward from the centre
                   GHANTA a green shimmer laid over the top, decaying with the ring
                 Nothing is wasted on dark thirds, and two sounds at once read
                 as two things happening rather than one winning.

This is different from Tier 2, which splits by pitch. A clap and a ghanta have
the same spectral centroid (8.72 vs 8.75 measured), so a frequency split lights
the same LEDs for both. Telling them apart needs time as well as spectrum,
which is what the classifier does - hence a zone per meaning, not per pitch.

HOW IT DRAWS: WLED's realtime UDP (DRGB on port 21324). This program renders
every pixel; WLED's own effects are bypassed while it runs. The protocol
carries a timeout, so if this process stops, WLED reverts to its own effects
on its own after a couple of seconds - the decoration keeps working if this
does not.

Because a strike cannot be identified at onset, both the CLAP and GHANTA zones
light dimly together the moment a bright sound starts, and the one that wins
goes to full while the other falls away. That ambiguity is honest and reads as
a flicker rather than a mistake.

    ./scripts/aarti-render.py                 # run until Ctrl-C
    ./scripts/aarti-render.py --seconds 60    # timed
    ./scripts/aarti-render.py --quiet         # no per-event logging
"""
import argparse
import math
import socket
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aarti_audio import Classifier, open_socket, parse  # noqa: E402

WLED_IP = "192.168.1.125"
WLED_UDP_PORT = 21324
N_LEDS = 180

# Zone colours at full. Amber for voice because it sits behind a makhar and
# warm light suits it; white for a clap because a transient should read as a
# flash; green for the ghanta - chosen on 2026-09-14; it keeps all three hues
# far apart, which matters more than any individual choice.
ZONES = [
    ("VOICE",  0,   60,  (255, 120, 20)),
    ("CLAP",   60,  120, (255, 255, 255)),
    ("GHANTA", 120, 180, (0, 255, 90)),
]

IDLE = 0.06         # never fully dark: an unlit third reads as broken, not idle
DECAY_PER_S = 2.2   # how fast a zone falls back once its sound stops
FPS = 40


BURST_LIFE = 0.9      # seconds for a clap burst to cross and fade
BURST_SPEED = 0.85    # fraction of half-strip per second
VOICE_DECAY = 1.6
GHANTA_DECAY = 1.1


class Layers:
    """Additive composite of three independent visual layers.

    Kept separate rather than blended by priority so that a clap during a
    ringing ghanta shows as both - which is what actually happens during an
    aarti, and what the zone mode cannot express.
    """

    def __init__(self, n):
        self.n = n
        self.voice = 0.0
        self.ghanta = 0.0
        self.bursts = []

    def on_clap(self, strength=1.0):
        self.bursts.append({"t0": time.time(), "s": min(1.0, strength)})

    def frame(self, now, dt):
        self.voice = max(0.0, self.voice - VOICE_DECAY * dt)
        self.ghanta = max(0.0, self.ghanta - GHANTA_DECAY * dt)
        n = self.n
        buf = [[0.0, 0.0, 0.0] for _ in range(n)]

        # Base glow. Never zero - a dark strip reads as broken, not resting.
        lvl = max(IDLE, self.voice)
        for i in range(n):
            k = lvl * (0.72 + 0.28 * math.sin(i / n * math.pi))
            buf[i][0] += 255 * k
            buf[i][1] += 110 * k
            buf[i][2] += 20 * k

        # Ghanta shimmer: a standing ripple so the ring reads as alive rather
        # than as a flat wash of blue.
        if self.ghanta > 0.01:
            for i in range(n):
                sh = 0.62 + 0.38 * math.sin(i * 0.55 + now * 7.5)
                k = self.ghanta * sh
                buf[i][0] += 0 * k
                buf[i][1] += 255 * k
                buf[i][2] += 90 * k

        # Clap bursts travelling out from the centre, both directions.
        alive = []
        half = n / 2.0
        for b in self.bursts:
            age = now - b["t0"]
            if age > BURST_LIFE:
                continue
            alive.append(b)
            pos = age * BURST_SPEED * half * (1.0 / BURST_LIFE) * BURST_LIFE
            fade = (1.0 - age / BURST_LIFE) ** 1.5 * b["s"]
            for sgn in (-1, 1):
                centre = half + sgn * pos
                lo = max(0, int(centre - 7))
                hi = min(n, int(centre + 8))
                for i in range(lo, hi):
                    d = i - centre
                    k = fade * math.exp(-(d * d) / 9.0)
                    buf[i][0] += 255 * k
                    buf[i][1] += 255 * k
                    buf[i][2] += 255 * k
        self.bursts = alive
        return buf


def pack(buf):
    out = bytearray([2, 2])
    for r, g, b in buf:
        out += bytes((min(255, int(r)), min(255, int(g)), min(255, int(b))))
    return bytes(out)


def render(levels, phase):
    """levels: 0-1 per zone. Returns a DRGB payload for WLED.

    Byte 0 is the protocol (2 = DRGB), byte 1 a timeout in seconds after which
    WLED drops back to its own effects. Then three bytes per LED.
    """
    buf = bytearray([2, 2])
    for zi, (_, start, stop, (r, g, b)) in enumerate(ZONES):
        lvl = max(IDLE, min(1.0, levels[zi]))
        n = stop - start
        for i in range(n):
            # A gentle centre-weighted falloff so a zone reads as a body of
            # light rather than a hard-edged block butting against its
            # neighbour.
            d = abs((i + 0.5) / n - 0.5) * 2.0
            k = lvl * (1.0 - 0.35 * d * d)
            buf += bytes((int(r * k), int(g * k), int(b * k)))
    return bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default="192.168.1.123")
    ap.add_argument("--wled", default=WLED_IP)
    ap.add_argument("--seconds", type=float, default=0.0)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--mode", choices=("zones", "layers"), default="layers")
    a = ap.parse_args()

    rx = open_socket(a.iface)
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    clf = Classifier()
    levels = [0.0, 0.0, 0.0]        # voice, clap, ghanta  (zones mode)
    layers = Layers(N_LEDS)         # (layers mode)
    t0 = time.time()
    next_frame = t0

    print(f"rendering to {a.wled}:{WLED_UDP_PORT}, {N_LEDS} LEDs, {FPS}fps, mode={a.mode}")
    if a.mode == "zones":
        print("zones:  0-59 VOICE amber | 60-119 CLAP white | 120-179 GHANTA green")
    else:
        print("layers: amber glow = voice | white burst = clap | green shimmer = ghanta")
    print("Ctrl-C to stop - WLED returns to its own effects a moment later.\n", flush=True)

    try:
        while a.seconds == 0 or time.time() - t0 < a.seconds:
            now = time.time()
            try:
                data, _ = rx.recvfrom(2048)
                fft = parse(data)
            except socket.timeout:
                fft = None
            if fft:
                for kind, info in clf.update(fft, now):
                    if kind == "strike":
                        # Cannot yet tell bell from clap: light both, dimly.
                        levels[1] = max(levels[1], 0.45)
                        levels[2] = max(levels[2], 0.45)
                    elif kind == "clap":
                        levels[1] = 1.0
                        levels[2] *= 0.3
                        layers.on_clap(min(1.0, info["peak"] / 3000.0))
                        if not a.quiet:
                            print(f"[{now-t0:6.2f}] CLAP   {info['duration']*1000:.0f}ms "
                                  f"peak {info['peak']:.0f}", flush=True)
                    elif kind == "ghanta":
                        levels[2] = 1.0
                        levels[1] *= 0.3
                        layers.ghanta = 1.0
                        if not a.quiet:
                            print(f"[{now-t0:6.2f}] GHANTA via {info['via']} "
                                  f"flatness {info['flatness']:.3f}", flush=True)
                    elif kind == "voice":
                        v = min(1.0, info["energy"] / 1500.0)
                        levels[0] = max(levels[0], v)
                        layers.voice = max(layers.voice, v)
                    elif kind == "ghanta_end" and not a.quiet:
                        print(f"[{now-t0:6.2f}] ghanta ended "
                              f"({info['duration']:.1f}s)", flush=True)
                if clf.ghanta_ringing:
                    levels[2] = max(levels[2], 0.55 + 0.45 * clf.level)
                    layers.ghanta = max(layers.ghanta, 0.55 + 0.45 * clf.level)

            if now >= next_frame:
                dt = 1.0 / FPS
                if a.mode == "zones":
                    for i in range(3):
                        levels[i] = max(0.0, levels[i] - DECAY_PER_S * dt)
                    payload = render(levels, now - t0)
                else:
                    payload = pack(layers.frame(now, dt))
                tx.sendto(payload, (a.wled, WLED_UDP_PORT))
                next_frame = now + dt
            else:
                time.sleep(0.002)
    except KeyboardInterrupt:
        pass
    print("\nstopped - WLED will resume its own effects shortly.", flush=True)


main()
