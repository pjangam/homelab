#!/usr/bin/env bash
# Brings the MirAIe AC back in HA after every HA restart, within ~2 minutes
# instead of the healthcheck auto-fix's 15-30.
#
# Why an HA restart kills the AC: Node-RED's MirAIe node publishes its
# discovery config and availability with retain=false, and only when its own
# MQTT connection (re)connects. An HA restart does not drop Node-RED's
# connection to Mosquitto, so nothing is republished and the fresh HA holds
# the entity `unavailable` until something restarts node-red. On 2026-10-09
# that cost the AC three times in one day (10:15, 17:50, 23:10 - the last two
# from the Tinxy watchdog's escalation restart), each cured only by
# healthcheck.sh's auto-fix on its next-but-one run.
#
# The signal: HA publishes its MQTT birth message (`online` on
# homeassistant/status, not retained) every time its MQTT integration
# connects - so on every HA start, and also when Mosquitto restarts. On each
# one this waits for HA to settle, asks check_miraie_ac_available.sh whether
# the entity is actually down, and only then runs fix_miraie_ac.sh --force
# (restart node-red, verify, re-deliver availability). The check matters: a
# Mosquitto restart also makes Node-RED reconnect and republish, so the entity
# is usually fine and restarting node-red would be pointless churn.
#
# Alerting stays with healthcheck.sh: if this fix fails, the entity is still
# unavailable on the next two healthcheck runs, which run the fix again and
# alert with its verdict.
#
# It also owns the "Fix AC" button on the Home dashboard's Bedroom view
# (button.miraie_ac_fixer_fix_ac). HA runs in docker and cannot reach the Pi's ssh key or
# xero's docker, so the button cannot run the fix itself: it is an MQTT button,
# registered here by a retained discovery config, that publishes `force` on
# BUTTON_TOPIC, and a press runs fix_miraie_ac.sh --force straight away with no
# check first (pressing it is the human's check). The output goes to this
# unit's journal: `journalctl --user -u miraie-ha-birth`.
#
# Runs as projects/miraie-ac/miraie-ha-birth.service (systemd --user on xero).
#
# Overridable for tests (projects/miraie-ac/test_ha_birth_listener.sh):
#   SUB_CMD        command printing one `topic payload` per line (default:
#                  mosquitto_sub -v inside the mosquitto container)
#   PUB_CMD        command run with the discovery topic and payload as $1 $2
#   CHECK, FIX     the check and fix scripts
#   SETTLE_S       wait after a birth before checking (default 60)
#   CHECK_TRIES, CHECK_RETRY_S   retries while the check says "can't tell"
#   LISTENER_ONCE  1 = exit when the subscriber exits instead of resubscribing
set -uo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CHECK="${CHECK:-$DIR/check_miraie_ac_available.sh}"
FIX="${FIX:-$DIR/fix_miraie_ac.sh}"
SETTLE_S="${SETTLE_S:-60}"
CHECK_TRIES="${CHECK_TRIES:-4}"
CHECK_RETRY_S="${CHECK_RETRY_S:-30}"
FIX_TIMEOUT_S="${FIX_TIMEOUT_S:-240}"
LISTENER_ONCE="${LISTENER_ONCE:-0}"
BIRTH_TOPIC="${BIRTH_TOPIC:-homeassistant/status}"
BUTTON_TOPIC="${BUTTON_TOPIC:-homelab/miraie-ac/fix}"
DISCOVERY_TOPIC="homeassistant/button/miraie_ac_fix/config"
# A press arriving within this long of a fix finishing was queued behind it
# (double tap, impatient re-press) - the fix it asked for just ran.
BUTTON_DEBOUNCE_S="${BUTTON_DEBOUNCE_S:-30}"
last_fix_end=0

log() { echo "[$(date '+%F %T')] $*"; }

subscribe() {
  if [ -n "${SUB_CMD:-}" ]; then
    bash -c "$SUB_CMD"
    return
  fi
  # -R drops stale retained messages, so (re)subscribing never looks like a
  # birth. HA's birth is not retained today; this keeps it that way if it is.
  docker exec mosquitto mosquitto_sub -h localhost \
      -u "${MQTT_USERNAME:-homelab}" -P "${MQTT_PASSWORD:?MQTT_PASSWORD not set}" \
      -R -v -t "$BIRTH_TOPIC" -t "$BUTTON_TOPIC"
}

publish_retained() {
  if [ -n "${PUB_CMD:-}" ]; then
    bash -c "$PUB_CMD" _ "$1" "$2"
    return
  fi
  docker exec mosquitto mosquitto_pub -h localhost \
      -u "${MQTT_USERNAME:-homelab}" -P "${MQTT_PASSWORD:?MQTT_PASSWORD not set}" \
      -r -t "$1" -m "$2"
}

# Retained, so HA rediscovers the button on every restart without us. Sent on
# each (re)subscribe anyway, so a wiped broker or a changed payload heals itself.
announce_button() {
  publish_retained "$DISCOVERY_TOPIC" "$(cat <<JSON
{"name":"Fix AC","unique_id":"miraie_ac_fix",
 "command_topic":"$BUTTON_TOPIC","payload_press":"force","icon":"mdi:air-conditioner",
 "device":{"identifiers":["homelab_miraie_ac_fix"],"name":"MirAIe AC fixer"}}
JSON
)" || log "could not publish the button's discovery config"
}

run_fix() {
  timeout "$FIX_TIMEOUT_S" "$FIX" --force 2>&1 </dev/null | sed 's/^/  /'
  local rc=${PIPESTATUS[0]}
  last_fix_end=$(date +%s)
  return "$rc"
}

on_button() {
  if [ $(( $(date +%s) - last_fix_end )) -lt "$BUTTON_DEBOUNCE_S" ]; then
    log "Fix AC pressed again right after a fix - ignoring"
    return
  fi
  log "Fix AC pressed - running fix_miraie_ac.sh --force"
  run_fix
  local rc=$?
  case "$rc" in
    0) log "fixed - AC entity is back" ;;
    1) log "fix_miraie_ac.sh exited 1 - bridge did not come back" ;;
    2) log "fix_miraie_ac.sh exited 2 - the AC unit is off the cloud; switch it on at the wall" ;;
    3) log "fix_miraie_ac.sh exited 3 - HA-side; restart the MQTT integration" ;;
    *) log "fix_miraie_ac.sh exited $rc" ;;
  esac
}

on_birth() {
  log "HA birth on $BIRTH_TOPIC - checking the AC entity in ${SETTLE_S}s"
  sleep "$SETTLE_S"

  local rc out try=1
  while :; do
    out="$("$CHECK" 2>&1 </dev/null)"; rc=$?
    [ "$rc" -ne 2 ] && break
    if [ "$try" -ge "$CHECK_TRIES" ]; then
      log "check could not tell after $try tries (${out:-no output}) - leaving it to healthcheck.sh"
      return
    fi
    try=$((try + 1))
    sleep "$CHECK_RETRY_S"
  done

  if [ "$rc" -eq 0 ]; then
    log "AC entity is fine - nothing to do"
    return
  fi

  log "AC entity down after HA birth (${out}) - running fix_miraie_ac.sh --force"
  run_fix
  rc=$?
  case "$rc" in
    0) log "fixed - AC entity is back" ;;
    *) log "fix_miraie_ac.sh exited $rc - healthcheck.sh will retry and alert" ;;
  esac
}

log "listening for HA births on $BIRTH_TOPIC and Fix AC presses on $BUTTON_TOPIC"
while :; do
  announce_button
  # Births arriving while a fix runs queue up in the pipe; each one re-checks,
  # finds the entity healthy, and does nothing.
  subscribe | while IFS=' ' read -r topic payload; do
    case "$topic" in
      "$BIRTH_TOPIC")  [ "$payload" = online ] && on_birth ;;
      "$BUTTON_TOPIC") [ "$payload" = force ] && on_button ;;
    esac
  done
  rc=${PIPESTATUS[0]}
  [ "$LISTENER_ONCE" = 1 ] && exit 0
  # Mosquitto restarting (or not up yet at boot) ends the subscriber.
  log "subscriber exited ($rc) - resubscribing in 10s"
  sleep 10
done
