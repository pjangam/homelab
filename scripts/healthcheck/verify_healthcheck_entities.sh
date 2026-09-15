#!/usr/bin/env bash
# Closes the loop on the healthcheck's own dashboard: does Home Assistant
# actually hold the state healthcheck.sh publishes?
#
# Everything else in healthcheck.sh reports what it FINDS. Nothing reported
# whether its findings ever arrived. The MQTT publish is deliberately wrapped
# in `|| true` (a broker hiccup must not break the email path), so a publish
# that fails every time is silent: the tiles freeze on their last retained
# value and the board shows a reassuring green forever. The 2026-09-11
# spotifyd bug was the same shape one layer down - a monitor that could not
# report its own failure.
#
# This is a read-back from the consumer's side, so it catches the publish
# failing, the entities going unavailable in HA, and the board going stale
# because cron stopped - none of which the publisher can see by itself.
#
# Complements the healthchecks.io heartbeat rather than duplicating it: the
# heartbeat fires when this script stops running at all, but pings on every
# run regardless of whether the publish worked, so it cannot see a stale
# board. Conversely this can't detect a dead host - HA is on the same
# machine. Two different blind spots.
#
# Prints one problem line per fault and exits 1; silent + exit 0 when fine.
# Exit 2 means "can't tell" (no token/curl) - callers must not alert on that.
set -uo pipefail

HA_URL="${HA_URL:-http://localhost:8123}"
# Two missed runs of a */15 cron, plus slack for a slow run.
MAX_STALE_MIN="${MAX_STALE_MIN:-40}"
CANARY="binary_sensor.homelab_healthcheck_homelab_overall_status"
STALE_SENSOR="sensor.homelab_healthcheck_homelab_last_healthcheck"

[ -n "${HA_TOKEN:-}" ] || { echo "HA_TOKEN not set - cannot verify dashboard" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl missing" >&2; exit 2; }

problem=0

fetch() { curl -s --max-time 10 -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/states/$1"; }

canary_json=$(fetch "$CANARY")
if [ -z "$canary_json" ]; then
  # HA being down is already caught by the container check; what's new here is
  # "up but not serving state", so say what was actually observed.
  echo "Home Assistant did not answer its API - the health dashboard cannot be trusted right now"
  exit 1
fi

canary_state=$(printf '%s' "$canary_json" | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('state',''))
except Exception: print('')
" 2>/dev/null)

case "$canary_state" in
  "")
    echo "Home Assistant has no state for $CANARY - the healthcheck's MQTT discovery is not registering"
    problem=1
    ;;
  unavailable|unknown)
    echo "Health dashboard entities are '$canary_state' in Home Assistant - tiles are not reflecting reality (check the MQTT bridge)"
    problem=1
    ;;
esac

# Staleness: the publisher stamps this every run, so an old value means the
# board is frozen even if the entity itself looks fine.
stale_state=$(fetch "$STALE_SENSOR" | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('state',''))
except Exception: print('')
" 2>/dev/null)

case "$stale_state" in
  ""|unavailable|unknown) : ;;  # already covered by the canary above
  *)
    age_min=$(python3 - "$stale_state" <<'PY' 2>/dev/null
import sys, datetime
try:
    t = datetime.datetime.fromisoformat(sys.argv[1])
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - t).total_seconds() // 60))
except Exception:
    print("")
PY
)
    if [ -n "$age_min" ] && [ "$age_min" -ge "$MAX_STALE_MIN" ]; then
      echo "Health dashboard is stale - last successful publish was ${age_min}m ago (threshold ${MAX_STALE_MIN}m), so the tiles are showing old data"
      problem=1
    fi
    ;;
esac

exit "$problem"
