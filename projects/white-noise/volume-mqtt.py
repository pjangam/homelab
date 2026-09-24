#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""MQTT bridge exposing the amixer Master volume as a Home Assistant number entity."""
import json
import os
import re
import subprocess
import threading
import time

import paho.mqtt.client as mqtt

# MQTT_HOST is set where the bridge runs off the broker's own host (the wol Pi).
BROKER = os.environ.get("MQTT_HOST", "localhost")
PORT = 1883

UNIQUE_ID = "server_volume"
NODE = "volume"
COMMAND_TOPIC = f"{NODE}/set"
STATE_TOPIC = f"{NODE}/state"
AVAILABILITY_TOPIC = f"{NODE}/available"
DISCOVERY_TOPIC = f"homeassistant/number/{UNIQUE_ID}/config"

PERCENT_RE = re.compile(r"\[(\d+)%\]")

# Which mixer the slider drives. Defaults are xero's (default card, Master);
# the wol Pi sets VOLUME_CARD/VOLUME_CONTROL in a systemd drop-in, because its
# default ALSA device is PipeWire and the speaker's own control is not Master.
AMIXER = ["amixer"] + (["-c", os.environ["VOLUME_CARD"]] if os.environ.get("VOLUME_CARD") else [])
CONTROL = os.environ.get("VOLUME_CONTROL", "Master")
# The slider's top. The Pi's 3.5mm jack goes above 0 dB and clips past ~97%,
# so deploy_audio_pi.sh caps it at 93 there.
MAX = int(os.environ.get("VOLUME_MAX", "100"))

DISCOVERY_PAYLOAD = {
    "name": "Server Volume",
    "unique_id": UNIQUE_ID,
    "object_id": "server_volume",
    "icon": "mdi:volume-high",
    "command_topic": COMMAND_TOPIC,
    "state_topic": STATE_TOPIC,
    "availability_topic": AVAILABILITY_TOPIC,
    "min": 0,
    "max": MAX,
    "step": 1,
    "unit_of_measurement": "%",
    "mode": "slider",
}


def get_volume():
    r = subprocess.run(
        [*AMIXER, "sget", CONTROL], capture_output=True, text=True, check=False
    )
    m = PERCENT_RE.search(r.stdout)
    return int(m.group(1)) if m else None


def set_volume(pct):
    pct = max(0, min(MAX, pct))
    subprocess.run([*AMIXER, "sset", CONTROL, f"{pct}%"], check=False)


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


def periodic_publish(client):
    while True:
        time.sleep(15)
        publish_state(client)


# Reconnection is left to paho. The old manual loop checked is_connected()
# straight after loop_start(), which can read False before the CONNACK lands -
# so after a broker restart it tore down and redialled every 5s forever. Same
# race, and same fix, as docs/incidents/2026-08-31-white-noise-mqtt-reconnect-loop.md.
def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="volume-bridge")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect
    client.on_message = on_message

    client.connect_async(BROKER, PORT, keepalive=30)
    threading.Thread(target=periodic_publish, args=(client,), daemon=True).start()
    client.loop_forever()


if __name__ == "__main__":
    main()
