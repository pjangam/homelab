#!/usr/bin/env bash
# Deploys nodered_refresh_flow.json into Node-RED on the Pi, then watches
# MQTT to prove the refresh publishes the same availability as a reconnect
# does. Rolls the flow back on its own if it does not.
#
# The flow is one inject node wired into the ha-miraie-ac node: every 5
# minutes (and 90s after start) it makes the node fetch each AC's status from
# the MirAIe cloud API and republish state + availability. That closes the
# window that kept the entity unavailable for 75m on 2026-09-15 - HA missing
# the one retain=false `online` a reconnect sends - to at most 5 minutes,
# without inventing a status: the value is the cloud's own onlineStatus.
#
# Why the live check is not optional: the refresh reads availability from the
# HTTP status API, while a reconnect reads it off the MirAIe MQTT feed. If the
# HTTP response ever lacks `onlineStatus`, the node publishes `offline` and
# the refresh would knock out a working AC every 5 minutes. So this compares
# the refresh's availability against the reconnect's in the same run.
#
# Deploys by editing flows.json and restarting the container, because the
# admin API needs the editor password. A timestamped flows.json backup is left
# on the Pi. Idempotent: nodes are matched by id and replaced.
#
#   projects/miraie-ac/deploy_nodered_refresh_flow.sh
#   projects/miraie-ac/deploy_nodered_refresh_flow.sh --rollback   # restore newest backup
#
# Exit codes: 0 deployed and verified, 1 deploy failed or rolled back.
set -uo pipefail

PI_HOST="${PI_HOST:-pramod@192.168.1.124}"
CONTAINER="node-red"
FLOWS="/home/pramod/node-red-data/flows.json"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FRAGMENT="$HERE/nodered_refresh_flow.json"
WATCH_S=200   # restart + npm install + 90s onceDelay + slack

ssh_pi() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" "$@"; }

rollback() {
  echo "Rolling back to the newest flows.json backup..."
  ssh_pi "b=\$(ls -t $FLOWS.bak-* 2>/dev/null | head -1); [ -n \"\$b\" ] && cp \"\$b\" $FLOWS && echo \"  restored \$b\" && docker restart $CONTAINER >/dev/null"
}

if [ "${1:-}" = "--rollback" ]; then
  rollback; exit $?
fi

ssh_pi true || { echo "FAIL: cannot SSH to $PI_HOST"; exit 1; }

echo "Backing up flows.json and merging the refresh flow..."
ssh_pi "cp $FLOWS $FLOWS.bak-\$(date +%Y%m%d-%H%M%S)" || { echo "FAIL: backup"; exit 1; }
# Replace nodes with the fragment's ids, append the rest. The MirAIe node the
# inject wires into must exist, or the flow would deploy wired to nothing.
# The fragment travels base64-encoded inside the script: its "info" text has
# \n escapes that a Python string literal would turn into raw newlines.
ssh_pi "python3 - $FLOWS" < <(cat <<PY
import base64, json, sys
path = sys.argv[1]
flows = json.load(open(path))
fragment = json.loads(base64.b64decode("$(base64 -w0 "$FRAGMENT")"))
targets = {w for n in fragment for out in n.get("wires", []) for w in out}
missing = targets - {n["id"] for n in flows}
if missing:
    sys.exit(f"MirAIe node(s) {missing} not in flows.json - refusing to deploy")
ids = {n["id"] for n in fragment}
flows = [n for n in flows if n["id"] not in ids] + fragment
json.dump(flows, open(path, "w"), indent=4)
print(f"  flows.json now has {len(flows)} nodes")
PY
) || { echo "FAIL: merge"; exit 1; }

# shellcheck disable=SC1091
set -a; . "$REPO_ROOT/.env.mqtt"; set +a
CAPTURE="$(mktemp)"; trap 'rm -f "$CAPTURE"' EXIT
docker exec mosquitto mosquitto_sub -h localhost -u "${MQTT_USERNAME:-homelab}" -P "$MQTT_PASSWORD" \
  -W "$WATCH_S" -F '%U %t %p' -t 'miraie-ac/+/availability' -t 'miraie-ac/+/state' > "$CAPTURE" 2>/dev/null &
sleep 2

echo "Restarting $CONTAINER and watching MQTT for ${WATCH_S}s..."
ssh_pi "docker restart $CONTAINER" >/dev/null || { echo "FAIL: restart"; rollback; exit 1; }
wait

avail_lines="$(grep ' miraie-ac/[^/]*/availability ' "$CAPTURE")"
echo "Availability seen:"
printf '%s\n' "$avail_lines" | while read -r ts topic payload; do
  [ -n "$ts" ] && echo "  $(date -d "@${ts%.*}" +%T) $topic $payload"
done

first_ts="$(printf '%s\n' "$avail_lines" | awk 'NF{print int($1); exit}')"
if [ -z "$first_ts" ]; then
  echo "FAIL: no availability at all after the restart - the node did not come up."
  rollback; exit 1
fi
# The reconnect burst lands within seconds; the refresh comes 90s after flows
# start. Anything 45s+ after the first availability is the refresh.
reconnect="$(printf '%s\n' "$avail_lines" | awk -v t="$first_ts" 'NF && int($1) < t+45 {p=$3} END{print p}')"
refresh="$(printf '%s\n' "$avail_lines" | awk -v t="$first_ts" 'NF && int($1) >= t+45 {p=$3} END{print p}')"

if [ -z "$refresh" ]; then
  echo "FAIL: the refresh published no availability within ${WATCH_S}s."
  echo "  Check: ssh $PI_HOST 'docker logs --tail 30 $CONTAINER'"
  rollback; exit 1
fi
if [ "$refresh" != "$reconnect" ]; then
  echo "FAIL: reconnect said '$reconnect' but the refresh said '$refresh' - the HTTP"
  echo "status API disagrees with the MQTT feed, so the refresh would lie to HA."
  rollback; exit 1
fi
echo "OK: the refresh republished '$refresh', matching the reconnect."

# Same keys in the state payload both ways, or HA's climate templates
# (value_json.acmd, actmp, rmtmp, acfs, ps) would read nothing after a refresh.
state_keys() {
  grep ' miraie-ac/[^/]*/state ' "$CAPTURE" \
    | awk -v t="$first_ts" -v want="$1" 'NF && ((want=="reconnect" && int($1) < t+45) || (want=="refresh" && int($1) >= t+45))' \
    | tail -1 | cut -d' ' -f3- | python3 -c 'import sys,json; s = json.load(sys.stdin); print(" ".join(k for k in ("acmd","actmp","rmtmp","acfs","ps") if k in s))' 2>/dev/null
}
rk="$(state_keys reconnect)"; fk="$(state_keys refresh)"
echo "  state keys HA reads - reconnect: [${rk}] refresh: [${fk}]"
if [ -z "$fk" ] || { [ -n "$rk" ] && [ "$rk" != "$fk" ]; }; then
  echo "FAIL: the refresh's state payload lacks keys HA's climate entity reads."
  rollback; exit 1
fi

set -a; . "$REPO_ROOT/.env.healthcheck"; set +a
if "$HERE/check_miraie_ac_available.sh"; then
  echo "OK: HA shows the AC available. Refresh flow deployed."
  exit 0
fi
rc=$?
if [ "$rc" -eq 1 ] && [ "$refresh" = offline ]; then
  echo "The AC is reporting offline both ways, so HA is right to show it unavailable."
  echo "The flow is deployed; re-run once the AC is on to verify it against 'online'."
  exit 0
fi
echo "WARN: the refresh looked right but HA does not show the AC available (check rc=$rc)."
echo "Flow left deployed. If HA stays unavailable, run projects/miraie-ac/fix_miraie_ac.sh --force"
exit 1
