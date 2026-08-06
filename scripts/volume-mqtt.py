#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""MQTT bridge exposing the amixer Master volume as a Home Assistant number entity."""
import json
import re
import subprocess
import time

import paho.mqtt.client as mqtt

BROKER = "localhost"
PORT = 1883

UNIQUE_ID = "server_volume"
NODE = "volume"
COMMAND_TOPIC = f"{NODE}/set"
STATE_TOPIC = f"{NODE}/state"
AVAILABILITY_TOPIC = f"{NODE}/available"
DISCOVERY_TOPIC = f"homeassistant/number/{UNIQUE_ID}/config"

PERCENT_RE = re.compile(r"\[(\d+)%\]")

DISCOVERY_PAYLOAD = {
    "name": "Server Volume",
    "unique_id": UNIQUE_ID,
    "object_id": "server_volume",
    "icon": "mdi:volume-high",
    "command_topic": COMMAND_TOPIC,
    "state_topic": STATE_TOPIC,
    "availability_topic": AVAILABILITY_TOPIC,
    "min": 0,
    "max": 100,
    "step": 1,
    "unit_of_measurement": "%",
    "mode": "slider",
}


def get_volume():
    r = subprocess.run(
        ["amixer", "sget", "Master"], capture_output=True, text=True, check=False
    )
    m = PERCENT_RE.search(r.stdout)
    return int(m.group(1)) if m else None


def set_volume(pct):
    pct = max(0, min(100, pct))
    subprocess.run(["amixer", "sset", "Master", f"{pct}%"], check=False)


def publish_state(client):
    vol = get_volume()
    if vol is not None:
        client.publish(STATE_TOPIC, str(vol), retain=True)


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.publish(AVAILABILITY_TOPIC, "online", retain=True)
    client.publish(DISCOVERY_TOPIC, json.dumps(DISCOVERY_PAYLOAD), retain=True)
    client.subscribe(COMMAND_TOPIC)
    publish_state(client)


def on_message(client, userdata, msg):
    try:
        pct = int(float(msg.payload.decode().strip()))
    except ValueError:
        return
    set_volume(pct)
    publish_state(client)


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="volume-bridge")
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect
    client.on_message = on_message

    while True:
        try:
            client.connect(BROKER, PORT, keepalive=30)
        except OSError:
            time.sleep(5)
            continue
        client.loop_start()
        try:
            while client.is_connected():
                publish_state(client)
                time.sleep(15)
        finally:
            client.loop_stop()
        time.sleep(5)


if __name__ == "__main__":
    main()
