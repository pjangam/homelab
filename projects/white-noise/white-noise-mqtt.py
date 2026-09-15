#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""MQTT bridge for the white-noise systemd unit, with Home Assistant discovery."""
import json
import os
import subprocess
import threading
import time

import paho.mqtt.client as mqtt

BROKER = "localhost"
PORT = 1883

UNIQUE_ID = "white_noise_switch"
NODE = "whitenoise"
COMMAND_TOPIC = f"{NODE}/set"
STATE_TOPIC = f"{NODE}/state"
AVAILABILITY_TOPIC = f"{NODE}/available"
DISCOVERY_TOPIC = f"homeassistant/switch/{UNIQUE_ID}/config"

UID = os.getuid()
USER_ENV = {
    **os.environ,
    "XDG_RUNTIME_DIR": f"/run/user/{UID}",
    "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{UID}/bus",
}

DISCOVERY_PAYLOAD = {
    "name": "White Noise",
    "unique_id": UNIQUE_ID,
    "object_id": "white_noise",
    "icon": "mdi:weather-windy",
    "command_topic": COMMAND_TOPIC,
    "state_topic": STATE_TOPIC,
    "availability_topic": AVAILABILITY_TOPIC,
    "payload_on": "ON",
    "payload_off": "OFF",
    "state_on": "ON",
    "state_off": "OFF",
}


def systemctl(action):
    subprocess.run(["systemctl", "--user", action, "white-noise"], env=USER_ENV, check=False)


def is_active():
    r = subprocess.run(
        ["systemctl", "--user", "is-active", "white-noise"],
        env=USER_ENV,
        capture_output=True,
        text=True,
    )
    return r.stdout.strip() == "active"


def publish_state(client):
    client.publish(STATE_TOPIC, "ON" if is_active() else "OFF", retain=True)


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.publish(AVAILABILITY_TOPIC, "online", retain=True)
    client.publish(DISCOVERY_TOPIC, json.dumps(DISCOVERY_PAYLOAD), retain=True)
    client.subscribe(COMMAND_TOPIC)
    publish_state(client)


def on_message(client, userdata, msg):
    payload = msg.payload.decode().strip().upper()
    if payload == "ON":
        systemctl("start")
    elif payload == "OFF":
        systemctl("stop")
    else:
        return
    publish_state(client)


def periodic_publish(client):
    while True:
        time.sleep(15)
        publish_state(client)


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="white-noise-bridge")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect
    client.on_message = on_message

    client.connect_async(BROKER, PORT, keepalive=30)
    threading.Thread(target=periodic_publish, args=(client,), daemon=True).start()
    client.loop_forever()


if __name__ == "__main__":
    main()
