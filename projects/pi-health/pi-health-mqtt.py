#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""wol Pi health over MQTT, with Home Assistant discovery.

Runs ON THE PI as pi-health-mqtt.service. Every INTERVAL seconds it reads the
Pi's own health and publishes it as one retained JSON object on STATE_TOPIC;
each HA entity picks its field out with a value_template. Availability is a
last-will, so the entities go unavailable within a keepalive if the Pi drops
off the network or this daemon dies - which is how xero's healthcheck.sh
tells "Pi healthy" from "Pi silent".

Started 2026-10-06 for the Pi's under-voltage (PROJECTS.md "wol Pi health
monitoring"). To add a metric (CPU, memory, temperature, ...): set its field
in collect() and add one line to ENTITIES. Nothing else changes.

vcgencmd get_throttled bits:
  0 under-voltage now     16 under-voltage since boot
  1 freq capped now       17 freq capped since boot
  2 throttled now         18 throttled since boot
  3 soft temp limit now   19 soft temp limit since boot
"""
import datetime
import json
import os
import subprocess
import time

import paho.mqtt.client as mqtt

BROKER = os.environ.get("MQTT_HOST", "localhost")
PORT = 1883
INTERVAL = 60

NODE = "homelab/wol_pi"
STATE_TOPIC = f"{NODE}/state"
AVAILABILITY_TOPIC = f"{NODE}/available"

DEVICE = {
    "identifiers": ["wol_pi"],
    "name": "wol Pi",
    "model": "Raspberry Pi 3B",
    "manufacturer": "Raspberry Pi",
}

# The kernel has said both "Under-voltage detected!" and (6.x hwmon)
# "Undervoltage detected!"; "Voltage normalised" ends an episode.
UV_WORDS = ("under-voltage", "undervoltage")


def throttled_flags():
    out = subprocess.run(["vcgencmd", "get_throttled"], capture_output=True, text=True, check=True)
    return int(out.stdout.strip().split("=")[1], 16)


def kernel_undervoltage():
    """(count, last ISO timestamp) of under-voltage lines in this boot's kernel log."""
    out = subprocess.run(
        ["journalctl", "-k", "-b", "--no-pager", "-o", "short-iso"],
        capture_output=True, text=True,
    ).stdout
    hits = [line for line in out.splitlines() if any(w in line.lower() for w in UV_WORDS)]
    last = hits[-1].split()[0] if hits else None
    return len(hits), last


def boot_time():
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("btime "):
                ts = int(line.split()[1])
                return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).isoformat()
    return None


def collect():
    flags = throttled_flags()
    uv_count, uv_last = kernel_undervoltage()
    return {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "boot": boot_time(),
        "throttled_raw": f"0x{flags:x}",
        "undervoltage_now": bool(flags & 0x1),
        "undervoltage_since_boot": bool(flags & 0x10000),
        "throttled_now": bool(flags & 0xE),
        "throttled_since_boot": bool(flags & 0xE0000),
        "undervoltage_events": uv_count,
        "undervoltage_last": uv_last,
    }


def binary(key, name, icon):
    return ("binary_sensor", key, {
        "name": name, "icon": icon, "device_class": "problem",
        "value_template": f"{{{{ 'ON' if value_json.{key} else 'OFF' }}}}",
    })


def sensor(key, name, icon, **extra):
    return ("sensor", key, {
        "name": name, "icon": icon,
        "value_template": f"{{{{ value_json.{key} }}}}", **extra,
    })


ENTITIES = [
    binary("undervoltage_now", "Under-voltage", "mdi:flash-alert"),
    binary("undervoltage_since_boot", "Under-voltage since boot", "mdi:flash-alert-outline"),
    binary("throttled_now", "Throttled", "mdi:speedometer-slow"),
    binary("throttled_since_boot", "Throttled since boot", "mdi:speedometer-slow"),
    sensor("undervoltage_events", "Under-voltage events since boot", "mdi:counter",
           state_class="measurement"),
    # None until the first event of a boot; HA wants "None" for an empty timestamp.
    ("sensor", "undervoltage_last", {
        "name": "Last under-voltage", "icon": "mdi:clock-alert-outline",
        "device_class": "timestamp",
        "value_template": "{{ value_json.undervoltage_last or None }}",
    }),
    sensor("throttled_raw", "get_throttled", "mdi:chip", entity_category="diagnostic"),
    sensor("boot", "Booted", "mdi:restart", device_class="timestamp", entity_category="diagnostic"),
    sensor("ts", "Last report", "mdi:calendar-check", device_class="timestamp",
           entity_category="diagnostic"),
]


def publish_discovery(client):
    for component, key, cfg in ENTITIES:
        uid = f"wol_pi_{key}"
        payload = {
            **cfg,
            "unique_id": uid,
            "object_id": uid,
            "state_topic": STATE_TOPIC,
            "availability_topic": AVAILABILITY_TOPIC,
            "device": DEVICE,
        }
        client.publish(f"homeassistant/{component}/{uid}/config", json.dumps(payload), retain=True)


def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code.is_failure:
        print(f"MQTT connect failed: {reason_code}", flush=True)
        return
    # Re-announce on every (re)connect: a broker restart loses nothing retained,
    # but an HA that lost its discovery state gets it back without a Pi restart.
    publish_discovery(client)
    client.publish(AVAILABILITY_TOPIC, "online", retain=True)


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="wol-pi-health")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.will_set(AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect
    client.reconnect_delay_set(min_delay=1, max_delay=60)
    client.connect_async(BROKER, PORT, keepalive=INTERVAL)
    client.loop_start()

    while True:
        try:
            state = collect()
            client.publish(STATE_TOPIC, json.dumps(state), retain=True)
            if state["undervoltage_now"] or state["undervoltage_since_boot"]:
                print(f"under-voltage: {state}", flush=True)
        except Exception as e:  # one bad read must not kill the loop
            print(f"collect failed: {e!r}", flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
