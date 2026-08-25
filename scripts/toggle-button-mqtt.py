#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero", "rpi-lgpio"]
# ///
"""MQTT bridge for a physical toggle switch wired to a Pi GPIO pin.

Runs on the wol-sender Pi (not xero) - GPIO needs real pins, which xero
doesn't have. Wiring: switch between GPIO17 (physical pin 11) and GND
(physical pin 9) - no resistor needed, uses the Pi's internal pull-up.

Publishes the switch's own position as a binary_sensor in Home Assistant.
It's a toggle, not a momentary button, so there's no single "pressed"
event - build HA automations off ON/OFF state (or the transition into
each) to decide what each position should trigger.
"""
import json
import os

import paho.mqtt.client as mqtt
from gpiozero import Button

BROKER = "192.168.1.123"  # xero, where Mosquitto runs
PORT = 1883

PIN = 17  # BCM17 = physical pin 11; GND = physical pin 9

UNIQUE_ID = "toggle_switch_1"
NODE = "toggle1"
STATE_TOPIC = f"{NODE}/state"
AVAILABILITY_TOPIC = f"{NODE}/available"
DISCOVERY_TOPIC = f"homeassistant/binary_sensor/{UNIQUE_ID}/config"

DISCOVERY_PAYLOAD = {
    "name": "Toggle Switch 1",
    "unique_id": UNIQUE_ID,
    "object_id": "toggle_switch_1",
    "state_topic": STATE_TOPIC,
    "availability_topic": AVAILABILITY_TOPIC,
    "payload_on": "ON",
    "payload_off": "OFF",
}

button = Button(PIN, pull_up=True, bounce_time=0.05)


def publish_state(client):
    client.publish(STATE_TOPIC, "ON" if button.is_pressed else "OFF", retain=True)


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.publish(AVAILABILITY_TOPIC, "online", retain=True)
    client.publish(DISCOVERY_TOPIC, json.dumps(DISCOVERY_PAYLOAD), retain=True)
    publish_state(client)


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="toggle1-bridge")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect

    button.when_pressed = lambda: publish_state(client)
    button.when_released = lambda: publish_state(client)

    client.connect_async(BROKER, PORT, keepalive=30)
    client.loop_forever()


if __name__ == "__main__":
    main()
