#!/usr/bin/env bash
# Watchdog: recovers Home Assistant's Tinxy integration if it's been
# disconnected from mqtt.tinxy.in continuously for DOWN_THRESHOLD_MIN.
#
# Context: intermittent ISP outages (flood damage to local ISP infra) cause
# Tinxy devices to flap "unavailable". Tinxy is cloud_push (MQTT to
# mqtt.tinxy.in), so short blips reconnect on their own — only a *sustained*
# outage triggers action. Two-tier escalation, learned from the 2026-07-27
# outage: a full container restart doesn't always fix it right away (the
# Tinxy integration's setup can stall mid-restart if the network is still
# recovering, invisible to this script's log-grep) - but a lighter
# config-entry reload (same as the "Reload" button in Settings > Devices &
# Services > Tinxy) fixed it with far less disruption. So: reload first,
# and only escalate to a full restart if that doesn't clear it either.
#
# Down-detection uses two signals, OR'd together: the MQTT connect/disconnect
# log lines (fast, but blind to a stalled integration setup that logs
# nothing distinctive - exactly what happened on 2026-07-27), and actual
# entity availability via the API (slower to notice, but reflects ground
# truth regardless of which internal failure caused it). A handful of
# decommissioned devices always show unavailable, so this only trips on
# >=90% of registered Tinxy entities being unavailable, not any single one.
#
# Run via cron every 5 minutes.
#
# Disable anytime with: touch ~/.tinxy-watchdog-disabled
# Re-enable with:       rm ~/.tinxy-watchdog-disabled
set -euo pipefail

DISABLE_FLAG="$HOME/.tinxy-watchdog-disabled"
LOG_FILE="/home/pramod/code/homelab/HOMEASSISTANT_CONFIG/home-assistant.log"
ENTITY_REGISTRY="/home/pramod/code/homelab/HOMEASSISTANT_CONFIG/.storage/core.entity_registry"
ENV_FILE="/home/pramod/code/homelab/.env.healthcheck"
STATE_DIR="$HOME/.cache/tinxy-watchdog"
DOWN_SINCE_FILE="$STATE_DIR/down-since"
RELOAD_DONE_FILE="$STATE_DIR/reload-attempted"
DOWN_THRESHOLD_MIN=20
RESTART_THRESHOLD_MIN=35
UNAVAILABLE_FRACTION_THRESHOLD=0.9
TINXY_ENTRY_ID="01KTVVTH8EYA06Y1ZE413AE64F"
LOG_TAG="tinxy-watchdog"

if [ -f "$DISABLE_FLAG" ]; then
  exit 0
fi

if [ ! -f "$LOG_FILE" ]; then
  logger -t "$LOG_TAG" "HA log file not found at $LOG_FILE - skipping check"
  exit 0
fi

mkdir -p "$STATE_DIR"

set -a
source "$ENV_FILE"
set +a

last_down=$(grep "custom_components.tinxy.coordinator\] Tinxy: MQTT disconnected" "$LOG_FILE" | tail -1 | cut -d' ' -f1,2) || true
last_up=$(grep "custom_components.tinxy.mqtt_client\] Tinxy MQTT: connected to" "$LOG_FILE" | tail -1 | cut -d' ' -f1,2) || true

is_down_mqtt=false
if [ -n "$last_down" ]; then
  if [ -z "$last_up" ]; then
    is_down_mqtt=true
  else
    down_epoch=$(date -d "$last_down" +%s)
    up_epoch=$(date -d "$last_up" +%s)
    [ "$down_epoch" -gt "$up_epoch" ] && is_down_mqtt=true
  fi
fi

# Second signal: actual entity availability, straight from ground truth.
# On any failure (API unreachable, bad token, etc.) this prints "unknown"
# and is ignored, falling back to the MQTT log signal alone.
is_down_entities=$(python3 - "$ENTITY_REGISTRY" "$HA_TOKEN" "$UNAVAILABLE_FRACTION_THRESHOLD" <<'PYEOF'
import json, sys, urllib.request

registry_path, token, threshold = sys.argv[1], sys.argv[2], float(sys.argv[3])
try:
    with open(registry_path) as f:
        reg = json.load(f)
    tinxy_ids = {e["entity_id"] for e in reg["data"]["entities"] if e.get("platform") == "tinxy"}
    if not tinxy_ids:
        print("unknown")
        sys.exit(0)

    req = urllib.request.Request(
        "http://localhost:8123/api/states",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        states = json.load(resp)

    unavailable = sum(1 for s in states if s["entity_id"] in tinxy_ids and s["state"] == "unavailable")
    fraction = unavailable / len(tinxy_ids)
    print("true" if fraction >= threshold else "false")
except Exception:
    print("unknown")
PYEOF
) || is_down_entities="unknown"

is_down=false
[ "$is_down_mqtt" = true ] && is_down=true
[ "$is_down_entities" = "true" ] && is_down=true

if [ "$is_down" = false ]; then
  rm -f "$DOWN_SINCE_FILE" "$RELOAD_DONE_FILE"
  exit 0
fi

# Currently down. Start (or continue) the clock.
if [ ! -f "$DOWN_SINCE_FILE" ]; then
  date +%s > "$DOWN_SINCE_FILE"
  logger -t "$LOG_TAG" "Tinxy down - starting watch (mqtt_log=$is_down_mqtt, entities=$is_down_entities, last mqtt event: ${last_down:-none})"
  exit 0
fi

down_since=$(cat "$DOWN_SINCE_FILE")
now=$(date +%s)
elapsed_min=$(( (now - down_since) / 60 ))

if [ "$elapsed_min" -ge "$RESTART_THRESHOLD_MIN" ]; then
  logger -t "$LOG_TAG" "Tinxy MQTT still down after ${elapsed_min}m (config-entry reload didn't clear it) - restarting Home Assistant"
  docker restart homeassistant
  date +%s > "$DOWN_SINCE_FILE"   # reset clock: if ISP is still down, wait a full cycle before acting again
  rm -f "$RELOAD_DONE_FILE"
  logger -t "$LOG_TAG" "Home Assistant restarted"
elif [ "$elapsed_min" -ge "$DOWN_THRESHOLD_MIN" ]; then
  if [ -f "$RELOAD_DONE_FILE" ]; then
    logger -t "$LOG_TAG" "Tinxy MQTT down for ${elapsed_min}m - already reloaded, waiting until ${RESTART_THRESHOLD_MIN}m for full restart"
  else
    logger -t "$LOG_TAG" "Tinxy MQTT down for ${elapsed_min}m (>=${DOWN_THRESHOLD_MIN}m threshold) - reloading Tinxy config entry"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 15 -X POST \
      -H "Authorization: Bearer $HA_TOKEN" \
      "http://localhost:8123/api/config/config_entries/entry/${TINXY_ENTRY_ID}/reload") || http_code="curl-failed"
    logger -t "$LOG_TAG" "Tinxy config entry reload requested (HTTP $http_code)"
    touch "$RELOAD_DONE_FILE"
  fi
else
  logger -t "$LOG_TAG" "Tinxy MQTT down for ${elapsed_min}m (threshold ${DOWN_THRESHOLD_MIN}m) - waiting"
fi
