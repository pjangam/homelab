#!/usr/bin/env bash
# One-shot recovery for a dead MirAIe AC bridge: the AC entity in HA goes
# `unavailable`, often with "This entity is no longer being provided by the
# mqtt integration".
#
# The fix is a single `docker restart node-red` on the Pi - nothing on xero
# needs touching, Mosquitto and HA are fine throughout. This script exists
# because the two things around that restart are what actually matter:
#
#   1. DON'T restart into broken DNS. The 2026-09-07 outage was one failed
#      lookup at startup (`getaddrinfo EAI_AGAIN auth.miraie.in`) which the
#      ha-miraie-ac node never retried, leaving the container `Up (healthy)`
#      with zero broker connections for 29 hours. Restarting while DNS is
#      still down just reproduces that exact state, quietly.
#   2. VERIFY it came back. `docker restart` returning 0 says nothing about
#      whether the MQTT bridge reconnected, and neither does the container's
#      healthcheck (it only proves Node-RED's web UI answers on 1880).
#
# Safe to run any time: if the bridge is already healthy it changes nothing
# and exits 0. Use --force to restart anyway.
#
#   scripts/fix_miraie_ac.sh
#   scripts/fix_miraie_ac.sh --force
#
# See scripts/diagnose_miraie_ac.sh for a read-only look at the same path.
set -u

PI_HOST="${PI_HOST:-pramod@192.168.1.124}"
CONTAINER="${CONTAINER:-node-red}"
CLOUD_PORT_HEX="22B3"          # 8883, MirAIe cloud MQTT broker (TLS)
LOCAL_PORT_HEX="075B"          # 1883, Mosquitto on xero
DNS_ATTEMPTS=6                 # ~30s of retries before giving up on DNS
CONNECT_TIMEOUT=90             # how long to wait for the bridge to come back
force=0
[ "${1:-}" = "--force" ] && force=1

ssh_pi() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" "$@"; }

# Both brokers connected? Mirrors watchdog_nodered_pi.sh's check - container
# TCP state, not AC traffic, since the node publishes nothing while idle.
bridge_up() {
  local ports
  ports="$(ssh_pi "docker exec $CONTAINER cat /proc/net/tcp 2>/dev/null" \
    | awk 'NR>1 { split($3, a, ":"); if ($4 == "01") print a[2] }' | sort -u | tr '\n' ' ')"
  case "$ports" in
    *"$CLOUD_PORT_HEX"*) case "$ports" in *"$LOCAL_PORT_HEX"*) return 0;; esac;;
  esac
  return 1
}

if ! ssh_pi true 2>/dev/null; then
  echo "FAIL: cannot SSH to $PI_HOST - fix that first, nothing else here will work."
  exit 1
fi

if ! ssh_pi "docker ps --filter name=^${CONTAINER}$ --filter status=running -q" 2>/dev/null | grep -q .; then
  echo "Container $CONTAINER is not running - starting it."
  ssh_pi "docker start $CONTAINER" >/dev/null 2>&1
  sleep 10
fi

if [ "$force" -eq 0 ] && bridge_up; then
  echo "Bridge is already healthy (both brokers connected) - nothing to do."
  echo "If HA still shows the AC unavailable, the AC unit itself may be powered"
  echo "off, or run with --force to republish MQTT discovery."
  exit 0
fi

# Step 1: DNS must work before a restart is worth spending.
echo "Checking DNS inside the container before restarting..."
dns_ok=0
for i in $(seq 1 "$DNS_ATTEMPTS"); do
  if ssh_pi "docker exec $CONTAINER getent hosts auth.miraie.in >/dev/null 2>&1 && \
             docker exec $CONTAINER getent hosts mqtt.miraie.in >/dev/null 2>&1"; then
    dns_ok=1
    break
  fi
  echo "  attempt $i/$DNS_ATTEMPTS: miraie.in not resolving yet, waiting 5s..."
  sleep 5
done

if [ "$dns_ok" -ne 1 ]; then
  echo
  echo "FAIL: DNS for miraie.in is still broken after $((DNS_ATTEMPTS * 5))s - NOT restarting."
  echo "Restarting now would just recreate the original failure (the node does not"
  echo "retry a failed login). Fix DNS on the Pi first, then re-run this script."
  echo "Start with: scripts/diagnose_dns_paths.sh, and check Pi-hole is up on xero."
  exit 1
fi
echo "  DNS ok."

# Step 2: the actual fix.
echo "Restarting $CONTAINER..."
ssh_pi "docker restart $CONTAINER" >/dev/null 2>&1 || { echo "FAIL: docker restart failed."; exit 1; }

# Step 3: verify, rather than trusting the restart's exit code.
echo "Waiting for both brokers to reconnect (up to ${CONNECT_TIMEOUT}s)..."
elapsed=0
while [ "$elapsed" -lt "$CONNECT_TIMEOUT" ]; do
  sleep 5
  elapsed=$((elapsed + 5))
  if bridge_up; then
    echo "  connected after ${elapsed}s."
    echo
    echo "OK: MirAIe cloud (8883) and Mosquitto (1883) both connected."
    echo "Node-RED republishes homeassistant/climate/panasonic-ac/config on connect,"
    echo "so the HA entity should return within a few seconds."
    if ! ssh_pi "grep -q '^WATCHDOG_ENABLED=true' /home/pramod/nodered-watchdog.env" 2>/dev/null; then
      echo
      echo "NOTE: the Node-RED watchdog is disabled, which is why this needed fixing"
      echo "by hand. In AC season set WATCHDOG_ENABLED=true in"
      echo "/home/pramod/nodered-watchdog.env on the Pi and it self-heals in <10min."
    fi
    exit 0
  fi
  echo "  ${elapsed}s: not yet..."
done

echo
echo "FAIL: bridge did not come back within ${CONNECT_TIMEOUT}s."
echo "Check the node's own error, which is usually a credentials or cloud-side problem:"
echo "  ssh $PI_HOST 'docker logs --tail 30 $CONTAINER'"
exit 1
