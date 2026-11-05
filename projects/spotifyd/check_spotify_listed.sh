#!/usr/bin/env bash
# Does Spotify itself still list this Connect device? Asks Spotify's Web API
# through HA's spotcast devices sensor, so it runs on xero for any host.
#
# This is the end of the chain the other checks stop short of. spotifyd can be
# running, advertising on the LAN and free of stuck sockets while Spotify's
# backend has forgotten it: on 2026-11-01 xero's websocket died and the device
# vanished from the Spotify app for two days, every other signal green
# (fixed by a restart on 2026-11-03). spotcast's play then fails with "Device
# not found", or the app simply doesn't offer the speaker.
#
# Verified 2026-11-05 that a restart does not drop the device from the list
# (same device id, it stayed listed throughout), so a restart on "missing"
# cannot feed itself.
#
#   projects/spotifyd/check_spotify_listed.sh raspberrypi
# Exit: 0 listed, 1 not listed, 2 can't tell (HA down, no token, sensor
# unknown/unavailable - spotcast loses Spotify's API during internet blips).
set -uo pipefail

NAME="${1:?usage: $0 <connect device name>}"
SENSOR="sensor.spotcast_t2ri8v1ku89v8s2ci4d6vrfv2_spotify_devices"
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
if [ -z "${HA_TOKEN:-}" ] && [ -f "$REPO/.env.healthcheck" ]; then
  HA_TOKEN=$(grep -m1 '^HA_TOKEN=' "$REPO/.env.healthcheck" | cut -d= -f2- | tr -d '"')
fi
[ -n "${HA_TOKEN:-}" ] || { echo "HA_TOKEN not set" >&2; exit 2; }

json=$(curl -s --max-time 10 -H "Authorization: Bearer $HA_TOKEN" "${HA_URL:-http://localhost:8123}/api/states/$SENSOR")
state=$(jq -r '.state // empty' <<<"$json" 2>/dev/null)
case "$state" in
  ""|unknown|unavailable) echo "spotcast devices sensor is '${state:-no answer}' - can't tell" >&2; exit 2 ;;
esac

if jq -e --arg n "$NAME" '[.attributes.devices[]?.name] | index($n)' <<<"$json" >/dev/null; then
  exit 0
fi
echo "Spotify does not list '$NAME' as a Connect device (has: $(jq -r '[.attributes.devices[]?.name]|join(", ")' <<<"$json"))" >&2
exit 1
