#!/usr/bin/env bash
# Run this ON XERO. Shows the physical clawlight LED's two states that are hard
# to catch naturally, so they can be checked by eye:
#   1. amber pulse - clawlight-server stopped, its MQTT last-will says offline
#   2. dim amber idle - with the server still stopped, publish availability
#      "online" and state "idle" by hand, as if no session were running
# then starts clawlight-server again, which republishes the real availability
# and state on connect (retained), so nothing hand-published is left behind.
#
#   scripts/clawlight/show_led_states.sh [SECONDS_PER_STATE]   # default 30
set -euo pipefail

HOLD="${1:-30}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
set -a; . "$REPO/.env.mqtt"; set +a

pub() {
  docker exec mosquitto mosquitto_pub -h localhost -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -r -t "$1" -m "$2"
}

trap 'systemctl --user start clawlight-server; echo "$(date +%T) clawlight-server $(systemctl --user is-active clawlight-server) - LED back to the real state"' EXIT

systemctl --user stop clawlight-server
echo "$(date +%T) server stopped - LED should PULSE AMBER for ${HOLD}s"
sleep "$HOLD"

pub clawlight/state idle
pub clawlight/availability online
echo "$(date +%T) published idle - LED should be DIM STEADY AMBER for ${HOLD}s"
sleep "$HOLD"
