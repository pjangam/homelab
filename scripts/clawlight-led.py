#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero", "rpi-lgpio"]
# ///
"""Physical clawlight: drives an RGB LED on the Pi's GPIO from clawlight state.

The hardware version of clawlight/web/index.html - same source of truth, but
visible without a browser tab open. Runs on the wol-sender Pi (GPIO needs real
pins, xero has none), which works only because that Pi sits next to the desk.

Wiring - common-cathode RGB LED, one 220R resistor per colour leg:
  - Red   -> GPIO13 (physical pin 33)
  - Green -> GPIO19 (physical pin 35)
  - Blue  -> GPIO26 (physical pin 37)
  - Common cathode -> GND (physical pin 39)
Set COMMON_ANODE = True below if the LED is the other polarity (it will look
inverted - bright when idle, dark when active).

Colours:
  active   green        a session is working
  waiting  red          a session needs input
  idle     dim white    nothing running (dim rather than off, so "no sessions"
                        is distinguishable from "this thing is unplugged")
  unknown  amber pulse  the server is gone or the broker connection dropped

That last state is the point of the design. The light is only useful if it is
trusted, so it must never keep showing a colour it can no longer verify - see
the 2026-09-07 MirAIe outage, where a bridge that looked healthy while
reporting nothing went unnoticed for 29 hours. Anything other than a steady
colour here means "don't believe me".

Deployed by scripts/deploy_clawlight_led_pi.sh; runs as clawlight-led.service.
Test without hardware: ./clawlight-led.py --no-gpio
"""
import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

import paho.mqtt.client as mqtt

BROKER = os.environ.get("MQTT_HOST", "192.168.1.123")  # xero, where Mosquitto runs
PORT = int(os.environ.get("MQTT_PORT", "1883"))
STATE_TOPIC = os.environ.get("MQTT_STATE_TOPIC", "clawlight/state")
AVAILABILITY_TOPIC = os.environ.get("MQTT_AVAILABILITY_TOPIC", "clawlight/availability")

COMMON_ANODE = False
PINS = {"red": 13, "green": 19, "blue": 26}

COLOURS = {
    "active": (0.0, 1.0, 0.0),
    "waiting": (1.0, 0.0, 0.0),
    "idle": (0.06, 0.06, 0.06),
}
UNKNOWN_COLOUR = (1.0, 0.35, 0.0)  # amber, pulsed


def log(msg):
    print(f"{datetime.now().isoformat(timespec='seconds')} {msg}", flush=True)


def isolate_lgpio_notify_dir():
    """Give this process its own directory for lgpio's notification FIFO.

    Same guard as the button bridges: lgpio picks the first free `.lgd-nfy<N>`
    slot in the process CWD, so two GPIO services started in the same second
    from the same directory can end up sharing one FIFO and silently eating
    each other's events (incidents/2026-09-04-lgpio-notify-fifo-collision.md).
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
            from gpiozero import RGBLED

            self.led = RGBLED(
                red=PINS["red"], green=PINS["green"], blue=PINS["blue"],
                active_high=not COMMON_ANODE,
            )

    def show(self, state: str):
        if state == self.shown:
            return
        self.shown = state
        colour = COLOURS.get(state)
        if colour is None:
            log(f"state={state!r} -> amber pulse (state unknown)")
            if self.led:
                self.led.pulse(fade_in_time=1, fade_out_time=1,
                               on_color=UNKNOWN_COLOUR, off_color=(0, 0, 0))
            return
        log(f"state={state!r} -> rgb{colour}")
        if self.led:
            self.led.color = colour


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-gpio", action="store_true",
                        help="log colour changes instead of driving pins (test without hardware)")
    args = parser.parse_args()

    if not args.no_gpio:
        isolate_lgpio_notify_dir()

    light = Light(use_gpio=not args.no_gpio)
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
