#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero", "rpi-lgpio"]
# ///
"""MQTT bridge for two momentary push buttons wired to Pi GPIO pins,
starting/stopping white noise directly via HA.

Runs on the wol-sender Pi (not xero) - GPIO needs real pins, which xero
doesn't have. Wiring (no resistor needed, uses the Pi's internal pull-up):
  - Start button: GPIO17 (physical pin 11) <-> GND (physical pin 9)
  - Stop button:  GPIO18 (physical pin 12) <-> GND (physical pin 14)

Replaces toggle-button-mqtt.py: GPIO17 was originally wired to a latching
toggle switch (persisted ON/OFF position), but the physical hardware was
swapped for two momentary push buttons, so this follows the
scene-buttons-mqtt.py shape instead - plain non-retained "PRESS" messages,
no entity/discovery, no retained state for a reconnect to replay. Already
uses the fixed connect_async() + loop_forever() pattern from the start.

HA side: a plain MQTT trigger automation per topic (payload "PRESS") calling
switch.turn_on/turn_off on switch.white_noise directly - no entity/discovery
needed for a momentary trigger.
"""
import os

import paho.mqtt.client as mqtt
from gpiozero import Button

BROKER = "192.168.1.123"  # xero, where Mosquitto runs
PORT = 1883

BUTTONS = {
    "white_noise_buttons/start/pressed": 17,  # BCM17 = physical pin 11
    "white_noise_buttons/stop/pressed": 18,  # BCM18 = physical pin 12
}


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="white-noise-buttons-bridge")
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
