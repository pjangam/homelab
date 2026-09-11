#!/usr/bin/env bash
# One-shot recovery for a dead MirAIe AC bridge: the AC entity in HA goes
# `unavailable`, often with "This entity is no longer being provided by the
# mqtt integration".
#
# The fix is a single `docker restart node-red` on the Pi - nothing on xero
# needs touching, Mosquitto and HA are fine throughout. This script exists
# because the three things around that restart are what actually matter:
#
#   1. DON'T restart into broken DNS. The 2026-09-07 outage was one failed
#      lookup at startup (`getaddrinfo EAI_AGAIN auth.miraie.in`) which the
#      ha-miraie-ac node never retried, leaving the container `Up (healthy)`
#      with zero broker connections for 29 hours. Restarting while DNS is
#      still down just reproduces that exact state, quietly.
#   2. VERIFY it came back. `docker restart` returning 0 says nothing about
#      whether the MQTT bridge reconnected, and neither does the container's
#      healthcheck (it only proves Node-RED's web UI answers on 1880).
#   3. SAY WHICH FAILURE IT WAS. A reconnected bridge is necessary but not
#      sufficient. On 2026-09-11 both brokers reconnected cleanly on three
#      restarts in a row while HA still showed `unavailable`, because the AC
#      unit itself had been silent to the MirAIe cloud since 79 minutes
#      earlier. No number of restarts fixes that - only switching the unit
#      back on does. So after reconnecting, this script reads the unit's own
#      availability and tells you which of the two problems you have:
#
#        bridge down  -> the restart fixes it, entity returns in seconds
#        AC silent    -> go power-cycle the indoor unit, restarts are wasted
#
#      The signal is the `availability` topic the node publishes for the unit
#      (`online`/`offline` - it is what the discovery payload points HA's own
#      avty_t at, so it is exactly what decides `unavailable` in HA).
#
#      Reading it is the awkward part. Everything under miraie-ac/# is
#      published retain=false and ONLY on reconnect or on a state change - it
#      is not a heartbeat. Measured 2026-09-11: an AC actively cooling
#      published nothing at all on miraie-ac/# across a 5-minute window, and
#      the broker holds no retained message on that prefix either. So there
#      is nothing to read after the fact and nothing to wait for on an idle
#      system; the only way to see the unit's availability is to already be
#      subscribed when the bridge reconnects. Hence: subscriber first, THEN
#      the restart, which is what forces the republish.
#
#      Note what is deliberately NOT used as the verdict: the `ts` inside the
#      state payload. It is the time of the unit's last state CHANGE, not a
#      liveness ping - a healthy AC nobody has touched since morning reports a
#      `ts` hours old. Judging staleness off it would send you to power-cycle
#      a working AC. It is printed as context only.
#
# Safe to run any time: if the bridge is already healthy it changes nothing
# and exits 0. Use --force to restart anyway.
#
#   scripts/fix_miraie_ac.sh
#   scripts/fix_miraie_ac.sh --force
#
# Exit codes:
#   0  healthy - bridge connected and the unit reports online
#   1  bridge did not come back (DNS, credentials, SSH, cloud-side)
#   2  bridge is fine but the AC unit is not there - a human has to go switch
#      it on; re-running this script cannot help
#   3  bridge and unit are both fine but HA still will not show the entity -
#      an HA-side problem; restart the MQTT integration
#
# See scripts/diagnose_miraie_ac.sh for a read-only look at the same path.
set -u

PI_HOST="${PI_HOST:-pramod@192.168.1.124}"
CONTAINER="${CONTAINER:-node-red}"
CLOUD_PORT_HEX="22B3"          # 8883, MirAIe cloud MQTT broker (TLS)
LOCAL_PORT_HEX="075B"          # 1883, Mosquitto on xero
DNS_ATTEMPTS=6                 # ~30s of retries before giving up on DNS
CONNECT_TIMEOUT=90             # how long to wait for the bridge to come back
STATE_WAIT="${STATE_WAIT:-30}" # how long after reconnect to wait for the unit's availability
TOPIC_PREFIX="${TOPIC_PREFIX:-miraie-ac}"
MOSQ_CONTAINER="${MOSQ_CONTAINER:-mosquitto}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HA_DB="${HA_DB:-$REPO_ROOT/HOMEASSISTANT_CONFIG/home-assistant_v2.db}"
HA_ENTITY="${HA_ENTITY:-climate.panasonic_ac_panasonic_ac}"
ENV_MQTT="${ENV_MQTT:-$REPO_ROOT/.env.mqtt}"
force=0
[ "${1:-}" = "--force" ] && force=1

CAPTURE=""
CAPTURE_PID=""
cleanup() {
  [ -n "$CAPTURE_PID" ] && kill "$CAPTURE_PID" 2>/dev/null
  [ -n "$CAPTURE" ] && rm -f "$CAPTURE"
  return 0
}
trap cleanup EXIT

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

# Subscribe to the AC's topics before anything restarts. Must be running
# across the reconnect or there is nothing to see (retain=false, see header).
# Every failure here is non-fatal: the restart is still worth doing, we just
# lose the ability to say which failure mode it was.
start_capture() {
  [ -r "$ENV_MQTT" ] || { echo "  (no readable $ENV_MQTT)"; return 1; }
  # shellcheck disable=SC1090
  set -a; . "$ENV_MQTT"; set +a
  [ -n "${MQTT_PASSWORD:-}" ] || { echo "  (MQTT_PASSWORD not set in $ENV_MQTT)"; return 1; }
  docker ps --filter "name=^${MOSQ_CONTAINER}$" --filter status=running -q 2>/dev/null | grep -q . \
    || { echo "  (mosquitto container not running locally)"; return 1; }
  CAPTURE="$(mktemp)"
  # -W bounds the subscriber inside the container, so it cannot outlive this
  # run even if the kill in cleanup() only reaps the local `docker exec`.
  docker exec "$MOSQ_CONTAINER" mosquitto_sub -h localhost \
      -u "${MQTT_USERNAME:-homelab}" -P "$MQTT_PASSWORD" \
      -v -W "$((CONNECT_TIMEOUT + STATE_WAIT + 15))" -t "${TOPIC_PREFIX}/#" \
      > "$CAPTURE" 2>/dev/null &
  CAPTURE_PID=$!
  sleep 2   # let the subscription land before the restart can publish anything
  return 0
}

# The AC's own last-seen unix time, from the `ts` in its most recent state
# payload. Only matches <prefix>/<device>/state - the power-consumption
# topics sit a level deeper and carry no ts.
ac_last_seen() {
  [ -n "$CAPTURE" ] || return 0
  sed -n "s|^${TOPIC_PREFIX}/[^/]*/state .*\"ts\":\"\([0-9][0-9]*\)\".*|\1|p" "$CAPTURE" | tail -1
}

# The node's own verdict on the unit, published alongside the state. When it
# says `offline` that settles it with no reference to any timing threshold.
ac_availability() {
  [ -n "$CAPTURE" ] || return 0
  sed -n "s|^${TOPIC_PREFIX}/[^/]*/availability \\(.*\\)|\\1|p" "$CAPTURE" | tail -1 | tr -d '\\r'
}

ac_device() {
  [ -n "$CAPTURE" ] || return 0
  sed -n "s|^${TOPIC_PREFIX}/\([^/]*\)/state .*|\1|p" "$CAPTURE" | head -1
}

ha_entity_state() {
  [ -r "$HA_DB" ] || return 0
  python3 - "$HA_DB" "$HA_ENTITY" <<'HAQ' 2>/dev/null
import sqlite3, sys
try:
    c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    r = c.execute("""select s.state from states s
                     join states_meta m on s.metadata_id = m.metadata_id
                     where m.entity_id = ?
                     order by s.last_updated_ts desc limit 1""", (sys.argv[2],)).fetchone()
    print(r[0] if r else "")
except sqlite3.Error:
    print("")
HAQ
}

# Re-deliver an `online` the node already published. NOT a fabricated status:
# only ever called after this run has seen `online` on the wire with its own
# subscriber, so this replays a message HA missed rather than inventing one.
republish_online() {
  [ -n "${MQTT_PASSWORD:-}" ] || return 1
  docker exec "$MOSQ_CONTAINER" mosquitto_pub -h localhost \
      -u "${MQTT_USERNAME:-homelab}" -P "$MQTT_PASSWORD" \
      -t "${TOPIC_PREFIX}/${device}/availability" -m online 2>/dev/null
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
  echo "If HA still shows the AC unavailable, the bridge is not your problem:"
  echo "the AC unit itself is probably not reporting to the MirAIe cloud."
  echo "Re-run with --force and this script will restart the bridge and tell"
  echo "you when the AC last reported, which settles it either way."
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

# Step 2: start watching, THEN restart. Order matters - see the header.
echo "Watching ${TOPIC_PREFIX}/# so we can see what the reconnect publishes..."
capture_ok=0
start_capture && capture_ok=1
[ "$capture_ok" -eq 1 ] && echo "  watching." || echo "  continuing without it - the restart still happens."

# Step 3: the actual fix.
echo "Restarting $CONTAINER..."
ssh_pi "docker restart $CONTAINER" >/dev/null 2>&1 || { echo "FAIL: docker restart failed."; exit 1; }

# Step 4: verify, rather than trusting the restart's exit code.
echo "Waiting for both brokers to reconnect (up to ${CONNECT_TIMEOUT}s)..."
elapsed=0
connected=0
while [ "$elapsed" -lt "$CONNECT_TIMEOUT" ]; do
  sleep 5
  elapsed=$((elapsed + 5))
  if bridge_up; then
    connected=1
    echo "  connected after ${elapsed}s."
    break
  fi
  echo "  ${elapsed}s: not yet..."
done

if [ "$connected" -ne 1 ]; then
  echo
  echo "FAIL: bridge did not come back within ${CONNECT_TIMEOUT}s."
  echo "Check the node's own error, which is usually a credentials or cloud-side problem:"
  echo "  ssh $PI_HOST 'docker logs --tail 30 $CONTAINER'"
  exit 1
fi

echo "OK: MirAIe cloud (8883) and Mosquitto (1883) both connected."

if [ "$capture_ok" -ne 1 ]; then
  echo
  echo "Could not watch MQTT, so this script cannot tell you whether the AC itself"
  echo "is reporting. If HA still shows the entity unavailable in a minute, assume"
  echo "the unit is off the cloud and go switch it on at the wall."
  exit 0
fi

# Step 5: the part a reconnected bridge does not answer - is the AC there?
echo "Waiting up to ${STATE_WAIT}s for the unit's availability..."
waited=0
avail=""
while :; do
  avail="$(ac_availability)"
  [ -n "$avail" ] && break
  [ "$waited" -ge "$STATE_WAIT" ] && break
  sleep 3
  waited=$((waited + 3))
done

device="$(ac_device)"
device="${device:-the AC}"
ts="$(ac_last_seen)"

# `ts` is context for the human, never the verdict - see the header.
last_change=""
if [ -n "$ts" ]; then
  age=$(( $(date +%s) - ts ))
  [ "$age" -lt 0 ] && age=0   # clock skew between the AC and xero
  last_change="last state change $(date -d "@$ts" '+%F %T') ($((age / 60))m ago)"
fi

case "$avail" in
  online)
    echo "$device is online${last_change:+ - $last_change}."
    ;;
  offline)
    echo
    echo "PROBLEM: the bridge is up, but it reports $device as offline."
    [ -n "$last_change" ] && echo "Reported $last_change."
    echo "The bridge is NOT your problem and restarting again will not help."
    echo "Switch the indoor unit on (or power-cycle it at the wall); HA picks the"
    echo "entity back up within seconds of it reporting."
    exit 2
    ;;
  "")
    echo
    echo "PROBLEM: the bridge reconnected but published nothing for the AC in ${STATE_WAIT}s."
    echo "A reconnect always republishes the unit's availability, so silence here"
    echo "means the node never got the device from the MirAIe cloud - the unit is"
    echo "not there. Restarting again will not help; switch it on at the wall."
    echo "If it IS switched on, check the node's own error:"
    echo "  ssh $PI_HOST 'docker logs --tail 30 $CONTAINER'"
    exit 2
    ;;
  *)
    echo
    echo "Unrecognised availability for $device: '$avail'"
    echo "Treating as inconclusive - check HA directly."
    exit 2
    ;;
esac

# Step 6: the bridge and the unit are both fine - but the only thing anyone
# actually cares about is whether HA shows the entity, and those are not the
# same question. On 2026-09-11 they came apart: the unit was provably online
# (it answered a mode/set and published fresh state) while HA held the entity
# `unavailable` for 37 minutes, and an earlier version of this script
# reported success throughout.
#
# Why: the node publishes the unit's `availability` with retain=false, like
# everything else under its prefix. HA gates the entity on that topic (it is
# the avty_t in the discovery payload), so once HA restarts it holds no
# availability value and keeps the entity unavailable no matter how much
# state arrives. It recovers only if HA happens to be subscribed when the
# node republishes `online` - and since the config and the availability go
# out back-to-back on reconnect, that is a race HA can lose. HA had restarted
# at 21:05 that evening, which is what set it up.
#
# So: check the entity, and if it is still unavailable, re-deliver the
# `online` this run already witnessed. That is what fixed it by hand.
if [ -r "$HA_DB" ]; then
  ha_state="$(ha_entity_state)"
  if [ "$ha_state" = "unavailable" ]; then
    echo "HA still shows $HA_ENTITY unavailable - re-delivering the availability HA missed..."
    if republish_online; then
      waited=0
      while [ "$waited" -lt 20 ]; do
        sleep 4
        waited=$((waited + 4))
        ha_state="$(ha_entity_state)"
        [ "$ha_state" != "unavailable" ] && break
      done
    fi
    if [ "$ha_state" = "unavailable" ]; then
      echo
      echo "PROBLEM: bridge connected and $device reports online, but HA still shows"
      echo "$HA_ENTITY unavailable. The AC itself is fine - this one is HA-side."
      echo "Restart the MQTT integration (or HA) and it should pick the entity back up."
      exit 3
    fi
    echo "  HA entity recovered: $ha_state"
  elif [ -n "$ha_state" ]; then
    echo "HA shows $HA_ENTITY = $ha_state."
  fi
fi

if ! ssh_pi "grep -q '^WATCHDOG_ENABLED=true' /home/pramod/nodered-watchdog.env" 2>/dev/null; then
  echo
  echo "NOTE: the Node-RED watchdog is disabled, which is why this needed fixing"
  echo "by hand. In AC season set WATCHDOG_ENABLED=true in"
  echo "/home/pramod/nodered-watchdog.env on the Pi and it self-heals in <10min."
fi
exit 0
