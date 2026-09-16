#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero", "rpi-lgpio"]
# ///
"""Physical clawlight: drives a red/green LED on the Pi's GPIO from clawlight state.

The hardware version of clawlight/web/index.html - same source of truth, but
visible without a browser tab open. Runs on the wol-sender Pi (GPIO needs real
pins, xero has none), which works only because that Pi sits next to the desk.

Wiring - 3-leg common-cathode RG (bi-colour) LED, one resistor per colour leg:
  - Red   -> 220R -> GPIO13 (physical pin 33)
  - Green -> 220R -> GPIO19 (physical pin 35)  (100R if a pure-green die looks dim)
  - Common cathode (long leg) -> GND (physical pin 39)
Set COMMON_ANODE = True below if the LED is the other polarity (it will look
inverted - bright when idle, dark when active) and move the long leg to 3.3V.

There is no blue, so amber is red and green mixed. AMBER's green share depends
on the green die and the resistor on its leg - tune it on the bench until the
mix reads amber rather than yellow-green or orange.

Colours:
  active   green        a session is working
  waiting  red          a session needs input
  idle     dim amber    nothing running (dim rather than off, so "no sessions"
                        is distinguishable from "this thing is unplugged");
                        steady, never pulsing, so it can't pass for unknown
  unknown  amber pulse  the server is gone or the broker connection dropped

That last state is the point of the design. The light is only useful if it is
trusted, so it must never keep showing a colour it can no longer verify - see
the 2026-09-07 MirAIe outage, where a bridge that looked healthy while
reporting nothing went unnoticed for 29 hours. Anything other than a steady
colour here means "don't believe me".

Deployed by scripts/clawlight/deploy_clawlight_led_pi.sh; runs as clawlight-led.service.
Test without hardware: ./clawlight-led.py --no-gpio
"""
import argparse
import math
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import paho.mqtt.client as mqtt

BROKER = os.environ.get("MQTT_HOST", "192.168.1.123")  # xero, where Mosquitto runs
PORT = int(os.environ.get("MQTT_PORT", "1883"))
STATE_TOPIC = os.environ.get("MQTT_STATE_TOPIC", "clawlight/state")
AVAILABILITY_TOPIC = os.environ.get("MQTT_AVAILABILITY_TOPIC", "clawlight/availability")

COMMON_ANODE = False
PINS = {"red": 13, "green": 19}

AMBER = (0.5, 1.0)  # (red, green) - picked by eye with --tune-amber, 2026-09-16
IDLE_BRIGHTNESS = 0.3  # picked by eye with --tune-idle, 2026-09-16; 0.06 read as very dim
COLOURS = {
    "active": (0.0, 1.0),
    "waiting": (1.0, 0.0),
    "idle": tuple(c * IDLE_BRIGHTNESS for c in AMBER),
}
PULSE_PERIOD = 2.0  # seconds, off -> full amber -> off
PULSE_STEP = 0.02


def log(msg):
    print(f"{datetime.now().isoformat(timespec='seconds')} {msg}", flush=True)


def amber_pulse():
    """Endless (red, green) values fading amber in and out.

    gpiozero's own pulse() only fades each pin between 0 and full, which would
    turn the red/green mix into yellow. Scaling both channels by one shared
    brightness keeps the hue fixed while it fades.
    """
    t = 0.0
    while True:
        brightness = (1 - math.cos(2 * math.pi * t / PULSE_PERIOD)) / 2
        yield tuple(c * brightness for c in AMBER)
        t += PULSE_STEP


def isolate_lgpio_notify_dir():
    """Give this process its own directory for lgpio's notification FIFO.

    Same guard as the button bridges: lgpio picks the first free `.lgd-nfy<N>`
    slot in the process CWD, so two GPIO services started in the same second
    from the same directory can end up sharing one FIFO and silently eating
    each other's events (docs/incidents/2026-09-04-lgpio-notify-fifo-collision.md).
    This service only writes to pins, but it is a third GPIO process on this
    Pi and there is no reason to be the one that reintroduces the collision.
    """
    run_dir = Path.home() / ".lgpio" / Path(__file__).stem
    run_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(run_dir)


class Light:
    """The LED, or a logging stand-in when run with --no-gpio."""

    def __init__(self, use_gpio: bool):
        self.led = None
        self.shown = None
        if use_gpio:
            from gpiozero import LEDBoard

            # Positional, not red=/green= keywords: LEDBoard orders named pins
            # alphabetically, which would swap every (red, green) value below.
            self.led = LEDBoard(
                PINS["red"], PINS["green"],
                pwm=True, active_high=not COMMON_ANODE,
            )
            self.led.source_delay = PULSE_STEP

    def show(self, state: str):
        if state == self.shown:
            return
        self.shown = state
        colour = COLOURS.get(state)
        if colour is None:
            log(f"state={state!r} -> amber pulse (state unknown)")
            if self.led:
                self.led.source = amber_pulse()
            return
        log(f"state={state!r} -> rg{colour}")
        if self.led:
            self.led.source = None  # stop any pulse before setting a steady colour
            self.led.value = colour


class Clawlight:
    def __init__(self, light: Light):
        self.light = light
        self.state = "unknown"
        self.server_online = False

    def refresh(self):
        # An unreachable or dead server outranks whatever state we last saw:
        # a retained `waiting` from an hour ago is worse than saying nothing.
        self.light.show(self.state if self.server_online else "unknown")

    def on_connect(self, client, userdata, flags, reason_code, properties):
        log(f"mqtt connected: {reason_code}")
        client.subscribe([(STATE_TOPIC, 0), (AVAILABILITY_TOPIC, 0)])
        # Both topics are retained, so the broker replays current state here -
        # the light is correct within a second of boot, not at the next event.

    def on_disconnect(self, client, userdata, flags, reason_code, properties):
        log(f"mqtt disconnected: {reason_code}")
        self.server_online = False
        self.refresh()

    def on_message(self, client, userdata, msg):
        payload = msg.payload.decode(errors="replace").strip()
        if msg.topic == AVAILABILITY_TOPIC:
            self.server_online = payload == "online"
            log(f"server availability: {payload}")
        elif msg.topic == STATE_TOPIC:
            self.state = payload
        self.refresh()


def tune_amber(light: Light):
    """Hold a series of red/green mixes so the amber one can be picked by eye.

    Run by `scripts/clawlight/tune_led.sh amber` with the service stopped. Steady,
    not pulsed: a hue is easier to judge when it is not also changing brightness.

    The walk runs from red-heavy to green-heavy: green rises with red at full,
    then red falls with green at full, since a weak green die can need more
    green than 1.0 can give (2026-09-16: green=1.0 was still the best of the
    first half). Each printed pair is a ready-made AMBER value.
    """
    mixes = [(1.0, g) for g in (0.2, 0.4, 0.6, 0.8, 1.0)]
    mixes += [(r, 1.0) for r in (0.8, 0.6, 0.5, 0.4, 0.3, 0.2)]
    for red, green in mixes:
        print(f"AMBER = ({red}, {green})", flush=True)
        light.led.value = (red, green)
        time.sleep(5)
    light.led.off()


def tune_idle(light: Light):
    """Hold idle's amber at a series of brightnesses so one can be picked by eye.

    6% read as very dim on the real LED (2026-09-16). The upper end stops well
    short of full: idle has to stay clearly quieter than the pulse's peak.
    """
    for brightness in (0.06, 0.1, 0.15, 0.2, 0.3, 0.4):
        print(f"IDLE_BRIGHTNESS = {brightness}", flush=True)
        light.led.value = tuple(c * brightness for c in AMBER)
        time.sleep(6)
    light.led.off()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-gpio", action="store_true",
                        help="log colour changes instead of driving pins (test without hardware)")
    parser.add_argument("--tune-amber", action="store_true",
                        help="step through amber mixes for picking AMBER by eye, then exit")
    parser.add_argument("--tune-idle", action="store_true",
                        help="step through idle brightnesses for picking IDLE_BRIGHTNESS by eye, then exit")
    args = parser.parse_args()
    if (args.tune_amber or args.tune_idle) and args.no_gpio:
        parser.error("tuning needs the real LED")

    if not args.no_gpio:
        isolate_lgpio_notify_dir()

    light = Light(use_gpio=not args.no_gpio)
    if args.tune_amber or args.tune_idle:
        (tune_amber if args.tune_amber else tune_idle)(light)
        return
    app = Clawlight(light)
    app.refresh()  # amber until the broker tells us otherwise

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="clawlight-led")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.on_connect = app.on_connect
    client.on_disconnect = app.on_disconnect
    client.on_message = app.on_message
    client.connect_async(BROKER, PORT, keepalive=30)
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
