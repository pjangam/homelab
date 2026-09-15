#!/usr/bin/env bash
# Print when cron/healthcheck.sh last completed, from the retained MQTT state
# that scripts/healthcheck/publish_healthcheck_mqtt.py publishes at the end of every run.
#
# healthcheck.log has no timestamps and a healthy run writes nothing to it, so
# the log cannot tell a run that succeeded from one that never happened. The
# retained last_check can - it only advances if the run reached the publisher.
# Written to verify cron still works after the scripts/ reorganisation.
set -eu
cd "$(dirname "$0")/../.."
set -a; . ./.env.mqtt; set +a
docker exec mosquitto mosquitto_sub -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" \
  -t 'homelab/healthcheck/#' -v -W 3 2>/dev/null | grep -E 'last_check|overall' || true
