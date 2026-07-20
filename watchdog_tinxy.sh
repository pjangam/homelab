#!/usr/bin/env bash
# Watchdog: restarts Home Assistant if the Tinxy integration has been
# disconnected from mqtt.tinxy.in continuously for DOWN_THRESHOLD_MIN.
#
# Context: intermittent ISP outages (flood damage to local ISP infra) cause
# Tinxy devices to flap "unavailable". Tinxy is cloud_push (MQTT to
# mqtt.tinxy.in), so short blips reconnect on their own — only a *sustained*
# outage triggers a restart. Restarting doesn't fix the ISP, it just makes
# sure HA/Tinxy resync promptly once the ISP does recover.
#
# Run via cron every 5 minutes.
#
# Disable anytime with: touch ~/.tinxy-watchdog-disabled
# Re-enable with:       rm ~/.tinxy-watchdog-disabled
set -euo pipefail

DISABLE_FLAG="$HOME/.tinxy-watchdog-disabled"
LOG_FILE="/home/pramod/code/homelab/HOMEASSISTANT_CONFIG/home-assistant.log"
STATE_DIR="$HOME/.cache/tinxy-watchdog"
DOWN_SINCE_FILE="$STATE_DIR/down-since"
DOWN_THRESHOLD_MIN=20
LOG_TAG="tinxy-watchdog"

if [ -f "$DISABLE_FLAG" ]; then
  exit 0
fi

if [ ! -f "$LOG_FILE" ]; then
  logger -t "$LOG_TAG" "HA log file not found at $LOG_FILE - skipping check"
  exit 0
fi

mkdir -p "$STATE_DIR"

last_down=$(grep "custom_components.tinxy.coordinator\] Tinxy: MQTT disconnected" "$LOG_FILE" | tail -1 | cut -d' ' -f1,2) || true
last_up=$(grep "custom_components.tinxy.mqtt_client\] Tinxy MQTT: connected to" "$LOG_FILE" | tail -1 | cut -d' ' -f1,2) || true

is_down=false
if [ -n "$last_down" ]; then
  if [ -z "$last_up" ]; then
    is_down=true
  else
    down_epoch=$(date -d "$last_down" +%s)
    up_epoch=$(date -d "$last_up" +%s)
    [ "$down_epoch" -gt "$up_epoch" ] && is_down=true
  fi
fi

if [ "$is_down" = false ]; then
  rm -f "$DOWN_SINCE_FILE"
  exit 0
fi

# Currently down. Start (or continue) the clock.
if [ ! -f "$DOWN_SINCE_FILE" ]; then
  date +%s > "$DOWN_SINCE_FILE"
  logger -t "$LOG_TAG" "Tinxy MQTT disconnected - starting watch (last event: $last_down)"
  exit 0
fi

down_since=$(cat "$DOWN_SINCE_FILE")
now=$(date +%s)
elapsed_min=$(( (now - down_since) / 60 ))

if [ "$elapsed_min" -ge "$DOWN_THRESHOLD_MIN" ]; then
  logger -t "$LOG_TAG" "Tinxy MQTT down for ${elapsed_min}m (>=${DOWN_THRESHOLD_MIN}m threshold) - restarting Home Assistant"
  docker restart homeassistant
  date +%s > "$DOWN_SINCE_FILE"   # reset clock: if ISP is still down, wait a full threshold before restarting again
  logger -t "$LOG_TAG" "Home Assistant restarted"
else
  logger -t "$LOG_TAG" "Tinxy MQTT down for ${elapsed_min}m (threshold ${DOWN_THRESHOLD_MIN}m) - waiting"
fi
