#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""One-shot MQTT publisher for healthcheck.sh results, with Home Assistant
discovery. Reads a JSON blob on stdin (built by healthcheck.sh) and publishes
retained discovery configs plus state/attribute topics, then exits - this
runs once per healthcheck.sh invocation (cron, every 15min), not as a
long-lived daemon like white-noise-mqtt.py.
"""
import datetime
import json
import sys
import time

import paho.mqtt.client as mqtt

BROKER = "localhost"
PORT = 1883
NODE = "homelab/healthcheck"

DEVICE = {
    "identifiers": ["homelab_healthcheck"],
    "name": "Homelab Healthcheck",
    "manufacturer": "homelab",
}


def binary_sensor(key, name, icon):
    return {
        "name": name,
        "unique_id": f"homelab_{key}",
        "object_id": f"homelab_{key}",
        "state_topic": f"{NODE}/{key}",
        "json_attributes_topic": f"{NODE}/{key}/attributes",
        "payload_on": "ON",
        "payload_off": "OFF",
        "device_class": "problem",
        "icon": icon,
        "device": DEVICE,
    }


def sensor(key, name, icon, unit=None, device_class=None):
    cfg = {
        "name": name,
        "unique_id": f"homelab_{key}",
        "object_id": f"homelab_{key}",
        "state_topic": f"{NODE}/{key}",
        "icon": icon,
        "device": DEVICE,
    }
    if unit:
        cfg["unit_of_measurement"] = unit
    if device_class:
        cfg["device_class"] = device_class
    return cfg


BINARY_SENSORS = {
    "docker": binary_sensor("docker", "Homelab Docker Containers", "mdi:docker"),
    "systemd": binary_sensor("systemd", "Homelab Systemd Units", "mdi:cog-outline"),
    "zfs": binary_sensor("zfs", "Homelab ZFS Pool", "mdi:harddisk"),
    "overall": binary_sensor("overall", "Homelab Overall Status", "mdi:server"),
}

SENSORS = {
    "disk_root": sensor("disk_root", "Homelab Disk Usage (root)", "mdi:harddisk", unit="%"),
    "disk_datapool": sensor("disk_datapool", "Homelab Disk Usage (datapool)", "mdi:harddisk", unit="%"),
    "backup_vaultwarden_age": sensor(
        "backup_vaultwarden_age", "Vaultwarden Backup Age", "mdi:clock-alert-outline", unit="h"
    ),
    "backup_homeassistant_age": sensor(
        "backup_homeassistant_age", "Home Assistant Backup Age", "mdi:clock-alert-outline", unit="h"
    ),
    "last_check": sensor(
        "last_check", "Homelab Last Healthcheck", "mdi:calendar-check", device_class="timestamp"
    ),
}


def main():
    data = json.load(sys.stdin)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="homelab-healthcheck-publisher")
    client.connect(BROKER, PORT, keepalive=10)
    client.loop_start()

    for key, cfg in BINARY_SENSORS.items():
        client.publish(f"homeassistant/binary_sensor/homelab_{key}/config", json.dumps(cfg), retain=True)
    for key, cfg in SENSORS.items():
        client.publish(f"homeassistant/sensor/homelab_{key}/config", json.dumps(cfg), retain=True)

    def pub_binary(key, is_problem, attrs):
        client.publish(f"{NODE}/{key}", "ON" if is_problem else "OFF", retain=True)
        client.publish(f"{NODE}/{key}/attributes", json.dumps(attrs), retain=True)

    def pub_sensor(key, value):
        if value is None:
            return
        client.publish(f"{NODE}/{key}", str(value), retain=True)

    pub_binary("docker", data["docker_problem"], {"bad_containers": data["docker_bad"]})
    pub_binary("systemd", data["systemd_problem"], {"failed_units": data["systemd_failed_text"]})
    pub_binary("zfs", not data["zfs_ok"], {"status": data["zfs_status"]})
    pub_binary("overall", data["overall_problem"], {"problems": data["problems"]})

    pub_sensor("disk_root", data["disk_root"])
    pub_sensor("disk_datapool", data["disk_datapool"])
    pub_sensor("backup_vaultwarden_age", data["backup_vw_age_hours"])
    pub_sensor("backup_homeassistant_age", data["backup_ha_age_hours"])
    pub_sensor("last_check", datetime.datetime.now(datetime.timezone.utc).isoformat())

    time.sleep(0.5)  # let publishes flush before disconnecting
    client.loop_stop()
    client.disconnect()


if __name__ == "__main__":
    main()
