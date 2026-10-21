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

Since 2026-10-21, after datapool's SSD stalled for 44s and logged 5 read and
2 write errors: the temperature of the disk under ZFS_POOL (p95/max, needs
the drivetemp module - enable_drivetemp.sh) and the pool's read, write and
checksum error counts. The counts are levels read once a minute, like disk
usage, not samples; they hold until `zpool clear`, so HA's history shows the
minute they first went up.
"""
import datetime
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import paho.mqtt.client as mqtt

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools" / "host-stats"))
from host_stats import Sampler, drive_temp_file, thermal_zone  # noqa: E402

BROKER = os.environ.get("MQTT_HOST", "localhost")
PORT = 1883
INTERVAL = 60
ZFS_POOL = "datapool"
ZPOOL = "/usr/sbin/zpool"

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
    sensor("drive_temperature_p95", "SSD temperature p95 (1 min)", "mdi:harddisk", **DEG),
    sensor("drive_temperature_max", "SSD temperature max (1 min)", "mdi:harddisk", **DEG),
    sensor("zfs_read_errors", "ZFS read errors", "mdi:alert-circle-outline"),
    sensor("zfs_write_errors", "ZFS write errors", "mdi:alert-circle-outline"),
    sensor("zfs_checksum_errors", "ZFS checksum errors", "mdi:alert-circle-outline"),
    ("ts", {"name": "Stats last report", "icon": "mdi:calendar-check",
            "device_class": "timestamp", "entity_category": "diagnostic",
            "value_template": "{{ value_json.ts }}"}),
]


def pool_device(pool):
    """The first device of a pool, as zpool lists it (/dev/sda1)."""
    out = subprocess.run([ZPOOL, "list", "-vHP", pool], capture_output=True, text=True, check=True).stdout
    return next(line.split()[0] for line in out.splitlines() if line.startswith("\t/dev/"))


def zfs_errors(pool):
    """Read, write and checksum errors summed over every vdev of the pool, as
    `zpool status` counts them; None each if zpool fails."""
    keys = {"read_errors": "zfs_read_errors", "write_errors": "zfs_write_errors",
            "checksum_errors": "zfs_checksum_errors"}
    try:
        out = subprocess.run([ZPOOL, "get", "-H", "-p", ",".join(keys), pool, "all-vdevs"],
                             capture_output=True, text=True, check=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError) as e:
        print(f"zpool get failed: {e!r}", flush=True)
        return dict.fromkeys(keys.values())
    totals = dict.fromkeys(keys.values(), 0)
    for line in out.splitlines():
        _vdev, prop, value, _source = line.split("\t")
        totals[keys[prop]] += int(value)
    return totals


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
    drive_temp = drive_temp_file(pool_device(ZFS_POOL))
    if not drive_temp:
        print(f"no drivetemp reading for {ZFS_POOL}'s disk; run enable_drivetemp.sh", flush=True)
    sampler = Sampler(thermal_zone("x86_pkg_temp"), drive_temp_file=drive_temp)
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
            state = {"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                     "drive_temperature_p95": None, "drive_temperature_max": None,
                     **sampler.report(), **zfs_errors(ZFS_POOL)}
            client.publish(STATE_TOPIC, json.dumps(state), retain=True)
        except Exception as e:  # one bad report must not kill the loop
            print(f"report failed: {e!r}", flush=True)


if __name__ == "__main__":
    main()
