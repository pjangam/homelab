#!/usr/bin/env bash
# Run ESPHome (docker, no install on xero) against this folder.
#   esphome.sh compile                  # build only
#   esphome.sh run --device /dev/ttyUSB0  # build + flash over USB, then logs
#   esphome.sh run --device 192.168.1.125 # later flashes, over Wi-Fi (OTA)
#   esphome.sh logs --device 192.168.1.125
# Build cache lives in the esphome-build docker volume, so rebuilds are fast.
set -euo pipefail
cd "$(dirname "$0")"
dev=()
for d in /dev/ttyUSB* /dev/ttyACM*; do [ -e "$d" ] && dev+=(--device "$d"); done
cmd="$1"; shift
tty=(); [ -t 0 ] && tty=(-t)
exec docker run --rm -i "${tty[@]}" "${dev[@]}" --net host \
  -v "$PWD":/config -v esphome-build:/config/.esphome \
  ghcr.io/esphome/esphome:stable "$cmd" voice-satellite.yaml "$@"
