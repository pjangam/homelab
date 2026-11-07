#!/usr/bin/env bash
# Watch one voice satellite for drop-outs, e.g. after changing its USB power
# supply (2026-11-07: the living room board fell off HA on a GaN adapter).
# Every INTERVAL seconds: HA's state for its assist_satellite entity and
# whether its ESPHome API port answers. Prints a line only when either changes.
#
# Run on xero, from the repo root:
#   set -a; . ./.env.healthcheck; set +a
#   projects/voice-assistant/watch_satellite_power.sh [minutes] [ip] [entity]
set -u
MINUTES=${1:-15}
IP=${2:-192.168.1.126}
ENTITY=${3:-assist_satellite.voice_living_room_assist_satellite}
INTERVAL=${INTERVAL:-10}
: "${HA_TOKEN:?source .env.healthcheck first}"

end=$(( $(date +%s) + MINUTES * 60 ))
last=""; changes=0
while [ "$(date +%s)" -lt "$end" ]; do
  st=$(curl -s -m5 -H "Authorization: Bearer $HA_TOKEN" \
        "http://localhost:8123/api/states/$ENTITY" | python3 -c \
        'import json,sys; print(json.load(sys.stdin).get("state","?"))' 2>/dev/null || echo "ha-error")
  api=$(nc -z -w3 "$IP" 6053 2>/dev/null && echo api-up || echo api-down)
  now="$st $api"
  if [ "$now" != "$last" ]; then
    echo "$(date +%T) $now"; [ -n "$last" ] && changes=$((changes + 1)); last=$now
  fi
  sleep "$INTERVAL"
done
echo "$(date +%T) done after ${MINUTES}min: $changes change(s)"
