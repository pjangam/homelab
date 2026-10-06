#!/usr/bin/env bash
# Run ESPHome (docker, no install on xero) against this folder.
#   esphome.sh compile                  # build only
#   esphome.sh run --device /dev/ttyUSB0  # build + flash over USB, then logs
#   esphome.sh run --device 192.168.1.125 # later flashes, over Wi-Fi (OTA)
#   esphome.sh logs --device 192.168.1.125
#   esphome.sh flash-bin build-out/firmware.factory.bin [/dev/ttyUSB0]
#                                       # flash a .bin built elsewhere
#                                       # (build_on_mac.sh), no compile here
# CONFIG=voice-bedroom.yaml picks another board (default voice-satellite.yaml).
# Build cache lives in the esphome-build docker volume, so rebuilds are fast.
set -euo pipefail
cd "$(dirname "$0")"
dev=()
for d in /dev/ttyUSB* /dev/ttyACM*; do [ -e "$d" ] && dev+=(--device "$d"); done
cmd="$1"; shift
tty=(); [ -t 0 ] && tty=(-t)
if [ "$cmd" = flash-bin ]; then
  bin="$1"; port="${2:-/dev/ttyUSB0}"
  exec docker run --rm -i "${tty[@]}" --device "$port" -v "$PWD":/config \
    --entrypoint esptool ghcr.io/esphome/esphome:stable \
    --port "$port" --baud 460800 write-flash 0x0 "/config/$bin"
fi
exec docker run --rm -i "${tty[@]}" "${dev[@]}" --net host \
  -v "$PWD":/config -v esphome-build:/config/.esphome \
  ghcr.io/esphome/esphome:stable "$cmd" "${CONFIG:-voice-satellite.yaml}" "$@"
