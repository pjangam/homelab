#!/usr/bin/env bash
# End-to-end check of clawlight's notification rules against the LIVE server
# and the LIVE ntfy topic: `waiting` (end of a normal turn) must stay silent,
# `input_needed` must produce exactly one push once the delay is up.
#
# Reads the topic back as user `pramod` rather than trusting the publish call's
# exit code - the only thing that proves a notification exists is finding it on
# the topic. Expect one real buzz on the phone while this runs.
#
# Run: scripts/verify_clawlight_notify.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. .env.ntfy

SERVER="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
NTFY="${NTFY_BASE_URL:-http://127.0.0.1:8127}"
SID="notifycheck$$"
SETTLE=25  # NOTIFY_DELAY_SECONDS (20) plus room for the timer thread

report() {
  curl -fsS -m 3 -X POST "$SERVER/clawlight/api/report" \
    -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"$SID\",\"host\":\"xero\",\"state\":\"$1\",\"cwd\":\"/tmp/notify-check\"}" \
    >/dev/null
}

# Messages published to the topic since $1 (epoch seconds).
since_count() {
  curl -fsS -u "pramod:$NTFY_ADMIN_PASSWORD" "$NTFY/clawlight/json?poll=1&since=$1" |
    grep -c '"event":"message"' || true
}

cleanup() { report end || true; }
trap cleanup EXIT

fail=0
check() { # desc got want
  if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected $3, got $2)"; fail=1; fi
}

t0="$(date +%s)"
echo "1/2  reporting 'waiting' (end of a normal turn) - expecting silence..."
report active
report waiting
sleep "$SETTLE"
check "end of a normal turn sends nothing" "$(since_count "$t0")" 0

t1="$(date +%s)"
echo "2/2  reporting 'input_needed' - expecting one push after ${SETTLE}s..."
report input_needed
sleep "$SETTLE"
check "a session waiting on input sends one push" "$(since_count "$t1")" 1
curl -fsS -u "pramod:$NTFY_ADMIN_PASSWORD" "$NTFY/clawlight/json?poll=1&since=$t1" |
  sed -n 's/.*"title":"\([^"]*\)".*"message":"\([^"]*\)".*/      sent: \1 - \2/p' || true

exit "$fail"
