#!/usr/bin/env python3
"""Drive the aarti strip from sound classification - one zone per class.

Tier 3 (see PROJECTS.md). Two ways to draw the same classification:

  --mode zones   one third of the strip per class. Legible and literal:
                   0- 59 VOICE amber | 60-119 CLAP white | 120-179 GHANTA blue
                 Two thirds sit at idle most of the time.

  --mode layers  all three share the whole strip, composited additively:
                   VOICE  a warm base glow along the full length
                   CLAP   a white burst sweeping outward from the centre
                   GHANTA a blue shimmer laid over the top, decaying with the ring
                 Nothing is wasted on dark thirds, and two sounds at once read
                 as two things happening rather than one winning.

In both modes the toddler gets the whole strip: a red flash on each detection
that falls away in about a third of a second, so babbling reads as a pulse.
Red because it is the one hue none of amber/white/blue is near, and she is
the point of it (PROJECTS.md, "A flashy colour for the toddler").

This is different from Tier 2, which splits by pitch. A clap and a ghanta have
the same spectral centroid (8.72 vs 8.75 measured), so a frequency split lights
the same LEDs for both. Telling them apart needs time as well as spectrum,
which is what the classifier does - hence a zone per meaning, not per pitch.

HOW IT DRAWS: WLED's realtime UDP (DRGB on port 21324). This program renders
every pixel; WLED's own effects are bypassed while it runs. The protocol
carries a timeout, so if this process stops, WLED reverts to its own effects
on its own after a couple of seconds - the decoration keeps working if this
does not.

IDLE: with nothing classified for IDLE_TIMEOUT_S the strip fades to black and
stays there, so a silent room means a dark decoration rather than a dim glow.
It keeps sending black frames so WLED's own effects do not take back over, and
the next sound lights it immediately. --idle-timeout 0 restores the old
always-lit resting glow.

Because a strike cannot be identified at onset, both the CLAP and GHANTA zones
light dimly together the moment a bright sound starts, and the one that wins
goes to full while the other falls away. That ambiguity is honest and reads as
a flicker rather than a mistake.

    ./projects/aarti-lights/aarti-render.py                 # run until Ctrl-C
    ./projects/aarti-lights/aarti-render.py --seconds 60    # timed
    ./projects/aarti-lights/aarti-render.py --quiet         # no per-event logging
"""
import argparse
import json
import math
import socket
import threading
import urllib.request
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from aarti_audio import Classifier, open_socket, parse  # noqa: E402

WLED_IP = "192.168.1.125"
WLED_UDP_PORT = 21324
N_LEDS = 180

# Zone colours at full. Amber for voice because it sits behind a makhar and
# warm light suits it; white for a clap because a transient should read as a
# flash; blue for the ghanta. Tried green on 2026-09-14 and went back: green sits
# too near the amber voice glow, so a bell during singing blended into it
# instead of standing out. Blue is the furthest hue from amber, and hue
# separation is what makes the three layers readable from across a room.
ZONES = [
    ("VOICE",  0,   60,  (255, 120, 20)),
    ("CLAP",   60,  120, (255, 255, 255)),
    ("GHANTA", 120, 180, (30, 90, 255)),
]

IDLE = 0.05         # resting glow while the room is awake - see IDLE_TIMEOUT_S
MASTER = 0.55       # composite headroom - see soft_clip

# The resting glow exists so an idle strip reads as idle rather than broken.
# But left on a timer of its own it also means the decoration is never off: at
# 01:20 on 2026-09-18 the strip sat at a dim amber low with the room silent,
# which looked like the mic picking up the ceiling fan. It was not - measured
# with ambient-energy.py, a resting room runs 215-371 total FFT energy against
# a FLOOR_ENERGY of 450, so nothing was classified at all. The glow was this
# floor, painted unconditionally.
#
# So the floor now expires. After IDLE_TIMEOUT_S with nothing classified it
# fades out over IDLE_FADE_S and the renderer sends black frames. Black frames
# rather than no frames on purpose: silence would let WLED's realtime timeout
# lapse and hand the strip back to its own Gravimeter preset, which is lit and
# sound-reactive - the opposite of off. Holding the realtime lock with black
# keeps the strip dark and still lights it on the next sound with no ramp-up.
IDLE_TIMEOUT_S = 20.0   # silence before the resting glow starts to go
IDLE_FADE_S = 3.0       # and how long it takes to reach black

DECAY_PER_S = 2.2   # how fast a zone falls back once its sound stops
FPS = 40


BURST_LIFE = 0.9      # seconds for a clap burst to cross and fade
BURST_SPEED = 0.85    # fraction of half-strip per second
VOICE_DECAY = 1.6
GHANTA_DECAY = 1.1
KID_COLOUR = (255, 0, 0)
KID_DECAY = 3.0     # a flash, gone in ~0.33s; detections repeat every 0.3s
KID_DUCK = 0.8      # how far the other layers dim under her flash


def idle_floor(quiet_for, timeout=IDLE_TIMEOUT_S, fade=IDLE_FADE_S):
    """The resting glow level, given how long the room has been silent.

    Full IDLE up to the timeout, then a linear fade to zero. Zero means the
    strip is genuinely dark - see the note beside IDLE_TIMEOUT_S for why it
    keeps sending black rather than stopping.
    """
    if timeout <= 0:                    # --idle-timeout 0: never go dark
        return IDLE
    if quiet_for <= timeout:
        return IDLE
    if fade <= 0:
        return 0.0
    return IDLE * max(0.0, 1.0 - (quiet_for - timeout) / fade)


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
        self.kid = 0.0
        self.bursts = []

    def on_clap(self, strength=1.0):
        self.bursts.append({"t0": time.time(), "s": min(1.0, strength)})

    def frame(self, now, dt, floor=IDLE):
        self.voice = max(0.0, self.voice - VOICE_DECAY * dt)
        self.ghanta = max(0.0, self.ghanta - GHANTA_DECAY * dt)
        n = self.n
        buf = [[0.0, 0.0, 0.0] for _ in range(n)]

        # Base glow. Floored while the room is awake, and faded to nothing
        # once it has been silent for IDLE_TIMEOUT_S.
        lvl = max(floor, self.voice)
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
                buf[i][0] += 25 * k
                buf[i][1] += 90 * k
                buf[i][2] += 255 * k

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

        # Toddler flash, over everything. The rest is ducked under it rather
        # than added to, or red on top of the amber glow reads as orange.
        self.kid = max(0.0, self.kid - KID_DECAY * dt)
        if self.kid > 0.01:
            duck = 1.0 - KID_DUCK * self.kid
            kr, kg, kb = KID_COLOUR
            for px in buf:
                px[0] = px[0] * duck + kr * self.kid
                px[1] = px[1] * duck + kg * self.kid
                px[2] = px[2] * duck + kb * self.kid
        return buf


def soft_clip(v):
    """Compress toward 255 instead of clamping at it.

    Three additive layers reach 255 on every channel easily, and a hard clamp
    turns that into flat white: the hues stop being distinguishable exactly
    when the most is happening, and the strip sits pinned at the current cap.
    A knee above 180 keeps bright moments bright while leaving colour in them.
    """
    if v <= 180.0:
        return v
    return 180.0 + (v - 180.0) / (1.0 + (v - 180.0) / 90.0)


def pack(buf):
    out = bytearray([2, 2])
    for r, g, b in buf:
        out += bytes((int(min(255, soft_clip(r * MASTER))),
                      int(min(255, soft_clip(g * MASTER))),
                      int(min(255, soft_clip(b * MASTER)))))
    return bytes(out)


def render(levels, phase, floor=IDLE, kid=0.0):
    """levels: 0-1 per zone. Returns a DRGB payload for WLED.

    Byte 0 is the protocol (2 = DRGB), byte 1 a timeout in seconds after which
    WLED drops back to its own effects. Then three bytes per LED.
    """
    buf = bytearray([2, 2])
    for zi, (_, start, stop, (r, g, b)) in enumerate(ZONES):
        lvl = max(floor, min(1.0, levels[zi]))
        n = stop - start
        for i in range(n):
            # A gentle centre-weighted falloff so a zone reads as a body of
            # light rather than a hard-edged block butting against its
            # neighbour.
            d = abs((i + 0.5) / n - 0.5) * 2.0
            k = lvl * (1.0 - 0.35 * d * d)
            duck = 1.0 - KID_DUCK * kid
            px = [c * k * duck + kc * kid for c, kc in zip((r, g, b), KID_COLOUR)]
            buf += bytes(int(min(255, c)) for c in px)
    return bytes(buf)


class PowerWatch:
    """Track WLED's own on/off so this renderer does not override it.

    Realtime UDP data wins over everything in WLED, so a renderer that always
    sends makes the light impossible to switch off - the Home Assistant
    schedule would fire at 09:30 and nothing would happen. Polling the state
    and simply not sending while it is off hands control back: WLED stops
    receiving, drops out of realtime mode after its timeout, and honours its
    own off state.

    Polled on a thread because an HTTP round-trip inside the 40fps render loop
    would stutter it.
    """

    def __init__(self, host, period=2.0):
        self.url = f"http://{host}/json/state"
        self.period = period
        self.on = True          # assume on until told otherwise
        self.reachable = True
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            try:
                with urllib.request.urlopen(self.url, timeout=1.5) as r:
                    self.on = bool(json.load(r).get("on", True))
                self.reachable = True
            except Exception:
                # Unreachable is not the same as off. Keep rendering: a brief
                # network blip should not blank the decoration mid-aarti.
                self.reachable = False
            time.sleep(self.period)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iface", default="192.168.1.123")
    ap.add_argument("--wled", default=WLED_IP)
    ap.add_argument("--seconds", type=float, default=0.0)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--mode", choices=("zones", "layers"), default="layers")
    ap.add_argument("--idle-timeout", type=float, default=IDLE_TIMEOUT_S,
                    help="seconds of silence after which the strip goes dark "
                         "(0 keeps the old always-lit resting glow)")
    ap.add_argument("--ignore-power", action="store_true",
                    help="render even when WLED is switched off")
    a = ap.parse_args()

    rx = open_socket(a.iface)
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    power = None if a.ignore_power else PowerWatch(a.wled)
    clf = Classifier()
    levels = [0.0, 0.0, 0.0]        # voice, clap, ghanta  (zones mode)
    kid = 0.0                       # toddler flash        (zones mode)
    layers = Layers(N_LEDS)         # (layers mode)
    t0 = time.time()
    next_frame = t0
    last_sound = t0     # nothing classified since: drives the idle blackout
    dark = False

    print(f"rendering to {a.wled}:{WLED_UDP_PORT}, {N_LEDS} LEDs, {FPS}fps, mode={a.mode}")
    if a.mode == "zones":
        print("zones:  0-59 VOICE amber | 60-119 CLAP white | 120-179 GHANTA blue "
              "| whole strip red = toddler")
    else:
        print("layers: amber glow = voice | white burst = clap | blue shimmer = ghanta "
              "| red flash = toddler")
    if a.idle_timeout > 0:
        print(f"idle:   dark after {a.idle_timeout:.0f}s with nothing classified")
    else:
        print("idle:   resting glow stays lit (--idle-timeout 0)")
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
                    if kind in ("strike", "clap", "ghanta", "voice", "kid"):
                        last_sound = now
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
                    elif kind == "kid":
                        kid = 1.0
                        layers.kid = 1.0
                        if not a.quiet:
                            print(f"[{now-t0:6.2f}] KID", flush=True)
                    elif kind == "ghanta_end" and not a.quiet:
                        print(f"[{now-t0:6.2f}] ghanta ended "
                              f"({info['duration']:.1f}s)", flush=True)
                if clf.ghanta_ringing:
                    last_sound = now
                    levels[2] = max(levels[2], 0.55 + 0.45 * clf.level)
                    layers.ghanta = max(layers.ghanta, 0.55 + 0.45 * clf.level)

            if now >= next_frame:
                dt = 1.0 / FPS
                quiet_for = now - last_sound
                floor = idle_floor(quiet_for, a.idle_timeout)
                if floor <= 0.0 and not dark:
                    dark = True
                    if not a.quiet:
                        print(f"[{now-t0:6.2f}] dark - {quiet_for:.0f}s silent",
                              flush=True)
                elif floor > 0.0 and dark:
                    dark = False
                    if not a.quiet:
                        print(f"[{now-t0:6.2f}] awake", flush=True)
                if a.mode == "zones":
                    for i in range(3):
                        levels[i] = max(0.0, levels[i] - DECAY_PER_S * dt)
                    kid = max(0.0, kid - KID_DECAY * dt)
                    payload = render(levels, now - t0, floor, kid)
                else:
                    payload = pack(layers.frame(now, dt, floor))
                if power is None or power.on:
                    tx.sendto(payload, (a.wled, WLED_UDP_PORT))
                next_frame = now + dt
            else:
                time.sleep(0.002)
    except KeyboardInterrupt:
        pass
    print("\nstopped - WLED will resume its own effects shortly.", flush=True)


if __name__ == "__main__":
    main()
