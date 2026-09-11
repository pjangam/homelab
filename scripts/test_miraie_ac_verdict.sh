#!/usr/bin/env bash
# Tests the decision fix_miraie_ac.sh makes AFTER the bridge reconnects:
# does it correctly separate "the AC is live" from "the bridge is fine but the
# unit is silent"? That distinction is the whole point of the script (see its
# header, and the 2026-09-11 incident where three restarts in a row reported
# success while HA stayed unavailable), and it is exactly the part that is
# impossible to exercise on demand against the real AC - you would have to
# wait for the unit to drop off the MirAIe cloud.
#
# So everything external is faked: `ssh` to the Pi, the local `docker`, and
# the MQTT capture. Nothing here touches the Pi, Mosquitto, HA, or the AC.
#
#   scripts/test_miraie_ac_verdict.sh
set -u

FIX="$(cd "$(dirname "$0")" && pwd)/fix_miraie_ac.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0
fail=0

# /proc/net/tcp rows shaped the way bridge_up parses them: $3 is rem_address,
# $4 == 01 is ESTABLISHED. Both brokers present = a healthy bridge.
mk_fakes() {
  mkdir -p "$WORK/bin"
  cat > "$WORK/bin/ssh" <<'EOF'
#!/usr/bin/env bash
cmd="$*"
case "$cmd" in
  *"/proc/net/tcp"*)
    echo "  sl  local_address rem_address   st"
    echo "   0: 0100007F:0016 0A000001:22B3 01"
    echo "   1: 0100007F:0016 0A000002:075B 01" ;;
  *"getent hosts"*)      exit 0 ;;
  *"docker ps"*)         echo "fakenodered" ;;
  *"docker restart"*)    exit 0 ;;
  *"WATCHDOG_ENABLED"*)  exit 0 ;;   # pretend enabled, keeps output short
  *)                     exit 0 ;;
esac
EOF
  # $1 of the fake docker run is the seeded capture file (may be empty).
  cat > "$WORK/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *mosquitto_sub*) cat "$WORK/seed" ;;
  "ps "*|ps)       echo "fakemosquitto" ;;
  *)               exit 0 ;;
esac
EOF
  chmod +x "$WORK/bin/ssh" "$WORK/bin/docker"
  printf 'MQTT_USERNAME=test\nMQTT_PASSWORD=test\n' > "$WORK/env.mqtt"
}

run_case() {
  local name="$1" want_code="$2" want_text="$3"
  local out code
  out="$(PATH="$WORK/bin:$PATH" ENV_MQTT="$WORK/env.mqtt" STATE_WAIT=6 \
         "$FIX" --force 2>&1)"
  code=$?
  if [ "$code" -eq "$want_code" ] && printf '%s' "$out" | grep -qi -- "$want_text"; then
    echo "  PASS  $name (exit $code)"
    pass=$((pass + 1))
  else
    echo "  FAIL  $name - wanted exit $want_code matching '$want_text', got exit $code:"
    printf '%s\n' "$out" | sed 's/^/          /'
    fail=$((fail + 1))
  fi
}

mk_fakes
now="$(date +%s)"

echo "== unit online =="
{
  echo "miraie-ac/panasonic-ac/availability online"
  echo "miraie-ac/panasonic-ac/state {\"ts\":\"$now\",\"ps\":\"on\",\"actmp\":\"24.0\"}"
} > "$WORK/seed"
run_case "online availability is a pass" 0 "is online"

echo "== unit offline: the 2026-09-11 failure =="
{
  echo "miraie-ac/panasonic-ac/availability offline"
  echo "miraie-ac/panasonic-ac/state {\"ts\":\"$((now - 4700))\",\"ps\":\"off\"}"
} > "$WORK/seed"
run_case "offline is blamed on the unit, not the bridge" 2 "reports panasonic-ac as offline"

echo "== nothing published at all =="
: > "$WORK/seed"
run_case "silence after a reconnect is blamed on the unit" 2 "published nothing for the AC"

echo "== an hours-old ts does NOT make a live unit look dead =="
# The regression this guards: `ts` is the unit's last state CHANGE, not a
# heartbeat. Measured 2026-09-11 - an AC that was actively cooling published
# nothing for 5 minutes straight, and reported a ts 8.6min old immediately
# after a reconnect. An earlier draft of this script treated a stale ts as
# failure, which would have sent someone to power-cycle a working AC.
{
  echo "miraie-ac/panasonic-ac/availability online"
  echo "miraie-ac/panasonic-ac/state {\"ts\":\"$((now - 18000))\",\"ps\":\"on\"}"
} > "$WORK/seed"
run_case "5h-old ts with online availability still passes" 0 "is online"

echo "== ts is still surfaced as context =="
{
  echo "miraie-ac/panasonic-ac/availability online"
  echo "miraie-ac/panasonic-ac/state {\"ts\":\"$((now - 3600))\",\"ps\":\"on\"}"
} > "$WORK/seed"
run_case "the last state change is reported to the human" 0 "last state change"

echo "== power-consumption topics never mistaken for a state reading =="
# These sit a level deeper and carry no ts; parsing them as the unit's state
# would invent a reading out of a power figure.
{
  echo "miraie-ac/panasonic-ac/availability online"
  echo "miraie-ac/panasonic-ac/daily-power-consumption/state 0"
  echo "miraie-ac/panasonic-ac/monthly-power-consumption/state 0.79695"
} > "$WORK/seed"
run_case "deeper topics yield no ts" 0 "is online"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
