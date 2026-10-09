#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""xero's CPU, temperature, memory and CPU pressure over MQTT, as p95 and max.

Runs on xero as the systemd --user unit xero-stats-mqtt.service. Replaces
HA System Monitor's processor use (an average over its poll), processor
temperature (one reading per poll) and CPU pressure (the kernel's own 10s
average) on the dashboards: tools/host-stats/host_stats.py samples every
second and this publishes the p95 and max of each minute, one retained JSON
object on STATE_TOPIC, with HA discovery. Same shape as
projects/pi-health/pi-health-mqtt.py. Started 2026-10-09.
"""
import datetime
import json
import os
import sys
import time
from pathlib import Path

import paho.mqtt.client as mqtt

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools" / "host-stats"))
from host_stats import Sampler, thermal_zone  # noqa: E402

BROKER = os.environ.get("MQTT_HOST", "localhost")
PORT = 1883
INTERVAL = 60

NODE = "homelab/xero"
STATE_TOPIC = f"{NODE}/stats"
AVAILABILITY_TOPIC = f"{NODE}/stats_available"

DEVICE = {
    "identifiers": ["xero"],
    "name": "xero",
    "model": "Beelink mini PC (Celeron N5105)",
}


def sensor(key, name, icon, **extra):
    return (key, {
        "name": name, "icon": icon, "state_class": "measurement",
        "value_template": f"{{{{ value_json.{key} }}}}", **extra,
    })


PCT = {"unit_of_measurement": "%"}
DEG = {"unit_of_measurement": "°C", "device_class": "temperature"}
ENTITIES = [
    sensor("cpu_p95", "CPU p95 (1 min)", "mdi:cpu-64-bit", **PCT),
    sensor("cpu_max", "CPU max (1 min)", "mdi:cpu-64-bit", **PCT),
    sensor("temperature_p95", "CPU temperature p95 (1 min)", "mdi:thermometer", **DEG),
    sensor("temperature_max", "CPU temperature max (1 min)", "mdi:thermometer-alert", **DEG),
    sensor("memory_p95", "Memory used p95 (1 min)", "mdi:memory", **PCT),
    sensor("memory_max", "Memory used max (1 min)", "mdi:memory", **PCT),
    sensor("pressure_p95", "CPU pressure p95 (1 min)", "mdi:gauge", **PCT),
    sensor("pressure_max", "CPU pressure max (1 min)", "mdi:gauge-full", **PCT),
    ("ts", {"name": "Stats last report", "icon": "mdi:calendar-check",
            "device_class": "timestamp", "entity_category": "diagnostic",
            "value_template": "{{ value_json.ts }}"}),
]


def publish_discovery(client):
    for key, cfg in ENTITIES:
        uid = f"xero_{key}"
        payload = {**cfg, "unique_id": uid, "object_id": uid, "state_topic": STATE_TOPIC,
                   "availability_topic": AVAILABILITY_TOPIC, "device": DEVICE}
        client.publish(f"homeassistant/sensor/{uid}/config", json.dumps(payload), retain=True)


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code.is_failure:
        print(f"MQTT connect failed: {reason_code}", flush=True)
        return
    publish_discovery(client)
    client.publish(AVAILABILITY_TOPIC, "online", retain=True)


def main():
    sampler = Sampler(thermal_zone("x86_pkg_temp"))
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="xero-stats")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect
    client.reconnect_delay_set(min_delay=1, max_delay=60)
    client.connect_async(BROKER, PORT, keepalive=INTERVAL)
    client.loop_start()

    while True:
        time.sleep(INTERVAL)
        try:
            state = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(), **sampler.report()}
            client.publish(STATE_TOPIC, json.dumps(state), retain=True)
        except Exception as e:  # one bad report must not kill the loop
            print(f"report failed: {e!r}", flush=True)


if __name__ == "__main__":
    main()
