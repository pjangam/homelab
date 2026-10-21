#!/usr/bin/env bash
# Load the drivetemp kernel module now and at every boot, so SATA disks get a
# hwmon temperature that xero-stats-mqtt can read without root. Run from a
# real terminal (sudo prompts), then restart the stats:
#
#   projects/xero-stats/enable_drivetemp.sh
#   systemctl --user restart xero-stats-mqtt
set -euo pipefail

echo drivetemp | sudo tee /etc/modules-load.d/drivetemp.conf >/dev/null
sudo modprobe drivetemp
for f in /sys/class/block/sd?/device/hwmon/hwmon*/temp1_input; do
  [ -e "$f" ] || { echo "drivetemp loaded but no disk exposes a temperature" >&2; exit 1; }
  disk=${f#/sys/class/block/}; echo "${disk%%/*}: $(( $(cat "$f") / 1000 ))°C"
done
