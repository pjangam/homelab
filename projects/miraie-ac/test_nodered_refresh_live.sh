#!/usr/bin/env bash
# Live test that Node-RED's 5-minute status refresh (nodered_refresh_flow.json)
# brings the AC entity back in HA on its own, with no restart.
#
# Reproduces the 2026-09-15 end state: HA holding the AC unavailable while the
# unit is online. It does that by publishing `offline` on the availability
# topic, which is what HA gates the entity on, then polls HA until the next
# refresh republishes the cloud's `online`.
#
# Touches the real AC entity: it is unavailable in HA for up to ~5 minutes.
# Refuses to start unless the entity is available first, so it never runs
# against an AC that is really off.
#
#   projects/miraie-ac/test_nodered_refresh_live.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TOPIC="miraie-ac/panasonic-ac/availability"
MAX_WAIT_S=330   # one 300s refresh interval plus slack

set -a; . "$REPO_ROOT/.env.mqtt"; . "$REPO_ROOT/.env.healthcheck"; set +a

"$HERE/check_miraie_ac_available.sh" >/dev/null 2>&1 \
  || { echo "SKIP: the AC is not available in HA right now - nothing to test against."; exit 2; }

echo "Publishing 'offline' to $TOPIC..."
docker exec mosquitto mosquitto_pub -h localhost -u "${MQTT_USERNAME:-homelab}" -P "$MQTT_PASSWORD" -t "$TOPIC" -m offline
sleep 3
if "$HERE/check_miraie_ac_available.sh" >/dev/null 2>&1; then
  echo "FAIL: HA did not go unavailable - the test cannot show anything."; exit 1
fi
echo "HA shows the AC unavailable. Waiting for the refresh (up to ${MAX_WAIT_S}s)..."

waited=0
while [ "$waited" -lt "$MAX_WAIT_S" ]; do
  sleep 10; waited=$((waited + 10))
  if "$HERE/check_miraie_ac_available.sh" >/dev/null 2>&1; then
    echo "PASS: HA took the AC back after ${waited}s, with no restart."
    exit 0
  fi
done

echo "FAIL: still unavailable after ${MAX_WAIT_S}s - the refresh did not fire or did not help."
echo "Restoring: publishing 'online' (the AC was available when this started)."
docker exec mosquitto mosquitto_pub -h localhost -u "${MQTT_USERNAME:-homelab}" -P "$MQTT_PASSWORD" -t "$TOPIC" -m online
exit 1
