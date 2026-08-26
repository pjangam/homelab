#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero", "rpi-lgpio"]
# ///
"""MQTT bridge for two momentary push buttons wired to Pi GPIO pins, firing
the "oju sleeping" / "oju awake" scenes directly.

Runs on the wol-sender Pi (not xero) - GPIO needs real pins, which xero
doesn't have. Wiring (no resistor needed, uses the Pi's internal pull-up):
  - Sleep button: GPIO27 (physical pin 13) <-> GND (physical pin 14)
  - Awake button: GPIO22 (physical pin 15) <-> GND (physical pin 14)

Deliberately different shape from toggle-button-mqtt.py: these are momentary
triggers, not a persisted state, so there's no retained binary_sensor and no
availability topic here. toggle-button-mqtt.py originally reconnected every
~5s due to a race in its manual MQTT loop, and each reconnect republished its
retained state through a brief "unavailable" transition - enough to refire
an HA automation watching that state, overriding manual scene/dashboard
control every few seconds. Publishing a plain, non-retained message only on
an actual button press - with nothing retained to replay on reconnect -
sidesteps that whole bug class rather than just fixing this instance of it.

HA side: a plain MQTT trigger automation per topic (payload "PRESS") calling
scene.turn_on - no entity/discovery needed for a momentary trigger.
"""
import os

import paho.mqtt.client as mqtt
from gpiozero import Button

BROKER = "192.168.1.123"  # xero, where Mosquitto runs
PORT = 1883

BUTTONS = {
    "scene_buttons/oju_sleep/pressed": 27,  # BCM27 = physical pin 13
    "scene_buttons/oju_awake/pressed": 22,  # BCM22 = physical pin 15
}


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="scene-buttons-bridge")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])

    buttons = []  # keep references alive - gpiozero closes a pin when its Button is garbage collected
    for topic, pin in BUTTONS.items():
        button = Button(pin, pull_up=True, bounce_time=0.05)
        button.when_pressed = lambda topic=topic: client.publish(topic, "PRESS", retain=False)
        buttons.append(button)

    client.connect_async(BROKER, PORT, keepalive=30)
    client.loop_forever()


if __name__ == "__main__":
    main()
