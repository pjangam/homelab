#!/usr/bin/env bash
# Watchdog: restarts Node-RED if the Panasonic AC stops publishing to MQTT.
# Run via cron every 10 minutes.
set -euo pipefail

MQTT_HOST="localhost"
MQTT_PORT="1883"
AC_TOPIC="homeassistant/climate/panasonic-ac/state"
WAIT_SECONDS=15
LOG_TAG="nodered-watchdog"

# Listen for AC status message for up to WAIT_SECONDS
message=$(timeout "$WAIT_SECONDS" mosquitto_sub \
  -h "$MQTT_HOST" -p "$MQTT_PORT" \
  -t "$AC_TOPIC" \
  -C 1 2>/dev/null || true)

if [ -z "$message" ]; then
  logger -t "$LOG_TAG" "No MQTT message on $AC_TOPIC in ${WAIT_SECONDS}s — restarting Node-RED"
  docker restart homelab-node-red-1
  logger -t "$LOG_TAG" "Node-RED restarted"
else
  logger -t "$LOG_TAG" "AC is alive: $message"
fi
