#!/usr/bin/env bash
# Watchdog: restarts Node-RED if its MQTT bridge isn't actually connected -
# checked via the container's own TCP state, not by waiting for AC traffic.
# Runs on wol-sender (the Pi) via cron every 10 minutes - moved here from
# cron/watchdog_nodered.sh on xero when Node-RED itself moved (see
# PROJECTS.md "Move some load to the Raspberry Pi").
#
# Originally waited up to 15s for a message on a specific AC state MQTT
# topic. That topic name was wrong from the start (never matched what the
# ha-miraie-ac node actually publishes to), and even the correct topic
# wouldn't have worked: Node-RED only publishes state/availability once per
# reconnect (retain=false in the node's own code), so nothing arrives while
# the AC sits idle - which can be for months in the off-season. Either way
# the watchdog saw an empty read and restarted Node-RED every single run.
# Checking the container's actual TCP connections instead works regardless
# of whether the AC unit itself is powered, since Node-RED's session to
# MirAIe's cloud broker is account-level, not per-device.
set -euo pipefail

CONTAINER="node-red"
MIRAIE_CLOUD_PORT_HEX="22B3"  # 8883, MirAIe cloud MQTT broker (TLS)
LOCAL_BROKER_PORT_HEX="075B"  # 1883, Mosquitto on xero
LOG_TAG="nodered-watchdog"

# The AC is seasonal (unused for months over winter) - set
# WATCHDOG_ENABLED=false in nodered-watchdog.env (next to this script) to
# skip the check entirely rather than restarting Node-RED against a bridge
# nobody needs connected right now. A plain env file next to the script is
# easier to find than a hidden dotfile in $HOME.
ENV_FILE="$(cd "$(dirname "$0")" && pwd)/nodered-watchdog.env"
WATCHDOG_ENABLED=true
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

if [ "$WATCHDOG_ENABLED" != "true" ]; then
  logger -t "$LOG_TAG" "Disabled via WATCHDOG_ENABLED=$WATCHDOG_ENABLED in $ENV_FILE - skipping check"
  exit 0
fi

conns=$(docker exec "$CONTAINER" cat /proc/net/tcp 2>/dev/null || true)

has_established() {
  local port_hex="$1"
  echo "$conns" | awk -v p="$port_hex" \
    'NR>1 { split($3, a, ":"); if (a[2] == p && $4 == "01") { found=1 } } END { exit !found }'
}

cloud_ok=0
local_ok=0
has_established "$MIRAIE_CLOUD_PORT_HEX" && cloud_ok=1
has_established "$LOCAL_BROKER_PORT_HEX" && local_ok=1

if [ "$cloud_ok" -ne 1 ] || [ "$local_ok" -ne 1 ]; then
  logger -t "$LOG_TAG" "MQTT bridge down (cloud_connected=$cloud_ok local_connected=$local_ok) — restarting Node-RED"
  docker restart "$CONTAINER"
  logger -t "$LOG_TAG" "Node-RED restarted"
else
  logger -t "$LOG_TAG" "MQTT bridge healthy (cloud and local broker connections established)"
fi
