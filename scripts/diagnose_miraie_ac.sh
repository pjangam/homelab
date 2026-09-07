#!/usr/bin/env bash
# Read-only health check for the MirAIe (Panasonic) AC path:
#
#   AC <-> MirAIe cloud broker <-> Node-RED (ha-miraie-ac, on the Pi)
#        <-> Mosquitto on xero <-> Home Assistant
#
# Written after the AC entity went `unavailable` in HA with "no longer being
# provided by the mqtt integration". The container was `Up (healthy)` the whole
# time - healthy only means Node-RED's web UI answers, it says nothing about
# the MQTT bridge - so `docker ps` is not a useful check here. What actually
# tells you is whether the container holds ESTABLISHED sockets to both brokers,
# the same signal scripts/watchdog_nodered_pi.sh acts on.
#
# Run from xero (needs SSH to the Pi and the mosquitto container locally):
#   scripts/diagnose_miraie_ac.sh            # checks only, changes nothing
#   scripts/diagnose_miraie_ac.sh --capture  # also RESTARTS Node-RED and
#                                            # sniffs what it republishes
#
# --capture exists because ha-miraie-ac publishes state/availability with
# retain=false, once per reconnect (see watchdog_nodered_pi.sh's header). So
# subscribing while the AC sits idle shows nothing whether the bridge is
# healthy or dead, and the only way to see its traffic is to be subscribed
# across a reconnect.
set -u

PI_HOST="${PI_HOST:-pramod@192.168.1.124}"
CONTAINER="${CONTAINER:-node-red}"
CLOUD_PORT_HEX="22B3"  # 8883, MirAIe cloud MQTT broker (TLS)
LOCAL_PORT_HEX="075B"  # 1883, Mosquitto on xero
HA_DB="${HA_DB:-$(cd "$(dirname "$0")/.." && pwd)/HOMEASSISTANT_CONFIG/home-assistant_v2.db}"
capture=0
[ "${1:-}" = "--capture" ] && capture=1

ssh_pi() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" "$@"; }

established_ports() {
  ssh_pi "docker exec $CONTAINER cat /proc/net/tcp 2>/dev/null" \
    | awk 'NR>1 { split($3, a, ":"); if ($4 == "01") print a[2] }' | sort -u | tr '\n' ' '
}

echo "== Pi reachable =="
ping -c1 -W2 "${PI_HOST#*@}" >/dev/null 2>&1 && echo "  ok - ${PI_HOST#*@}" || echo "  FAIL - no ping response"

echo "== Node-RED container =="
ssh_pi "docker ps --filter name=$CONTAINER --format '  {{.Names}} | {{.Status}}'" 2>&1 | head -3

echo "== MQTT bridge (the check that actually matters) =="
ports="$(established_ports)"
case "$ports" in *"$CLOUD_PORT_HEX"*) echo "  ok   - MirAIe cloud broker (8883) connected";;
                 *) echo "  FAIL - no connection to MirAIe cloud (8883)";; esac
case "$ports" in *"$LOCAL_PORT_HEX"*) echo "  ok   - Mosquitto on xero (1883) connected";;
                 *) echo "  FAIL - no connection to Mosquitto (1883)";; esac
echo "  (established remote ports, hex: ${ports:-none})"

echo "== DNS from inside the container =="
# The login failure that started this was `getaddrinfo EAI_AGAIN auth.miraie.in`
# at startup, and the node never retried - so DNS being fine *now* does not
# mean the bridge recovered, it only means a restart should succeed.
for h in auth.miraie.in mqtt.miraie.in; do
  if ssh_pi "docker exec $CONTAINER getent hosts $h" >/dev/null 2>&1; then
    echo "  ok   - $h resolves"
  else
    echo "  FAIL - $h does not resolve"
  fi
done

echo "== Recent Node-RED errors =="
ssh_pi "docker logs --tail 200 $CONTAINER 2>&1 | grep -i 'error' | tail -5" 2>&1 | sed 's/^/  /' | head -6

echo "== Watchdog =="
# Disabled off-season, which is deliberate - but it means this exact failure
# does not self-heal while it is off.
ssh_pi "cat /home/pramod/homelab/scripts/nodered-watchdog.env 2>/dev/null || cat /home/pramod/nodered-watchdog.env 2>/dev/null" 2>&1 \
  | grep -v '^#' | grep . | sed 's/^/  /' || echo "  (env file not found)"

echo "== HA entity state =="
python3 - "$HA_DB" <<'PY'
import sqlite3, sys
try:
    c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    q = """select m.entity_id, s.state, datetime(s.last_updated_ts,'unixepoch','localtime')
           from states s join states_meta m on s.metadata_id = m.metadata_id
           where m.entity_id like 'climate.%'
             and s.state_id in (select max(state_id) from states group by metadata_id)"""
    rows = list(c.execute(q))
    print("\n".join(f"  {e} = {st} (last update {ts})" for e, st, ts in rows) or "  (no climate entities)")
except sqlite3.Error as exc:
    print(f"  (could not read HA db: {exc})")
PY

if [ "$capture" -eq 1 ]; then
  echo "== Capture: restarting Node-RED and sniffing what it republishes =="
  env_file="$(cd "$(dirname "$0")/.." && pwd)/.env.mqtt"
  # shellcheck disable=SC1090
  set -a; . "$env_file"; set +a
  docker exec mosquitto mosquitto_sub -h localhost \
      -u "${MQTT_USERNAME:-homelab}" -P "${MQTT_PASSWORD}" -v -W 60 -t '#' \
      > /tmp/miraie-capture.$$ 2>&1 &
  sub_pid=$!
  sleep 2
  ssh_pi "docker restart $CONTAINER" >/dev/null 2>&1 && echo "  Node-RED restarted, listening 60s..."
  wait "$sub_pid" 2>/dev/null
  echo "  --- topics seen (AC-related) ---"
  grep -iE 'miraie|panasonic|climate|homeassistant' "/tmp/miraie-capture.$$" | cut -c1-200 | head -20 \
    | sed 's/^/  /' || echo "  (nothing AC-related published)"
  echo "  --- all topics seen ---"
  cut -d' ' -f1 "/tmp/miraie-capture.$$" | sort -u | head -20 | sed 's/^/  /'
  rm -f "/tmp/miraie-capture.$$"
fi
