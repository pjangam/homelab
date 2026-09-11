#!/usr/bin/env bash
# Verifies the clawlight / homelab-health topic split actually enforces, rather
# than just that setup_ntfy_users.sh printed the right ACL lines.
#
# Checks each publisher can post to its own topic, CANNOT post to the other's,
# and that 'pramod' can read both (one phone login, two streams). A wrong
# answer here is silent in normal use - the publish just goes to the wrong
# place, or nowhere.
set -uo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. ./.env.ntfy

BASE="http://127.0.0.1:8127"
fails=0

post() { # token topic -> http code
  curl -sS -m 10 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $1" -H "Title: ntfy topic split verification" \
    -H "Priority: 1" -H "Tags: test_tube" \
    -d "Automated check from scripts/verify_ntfy_topics.sh - safe to ignore." \
    "$BASE/$2"
}

expect() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1 (expected $2, got $3)"; fails=$((fails+1)); fi
}

echo "=== publishers can reach their own topic ==="
expect "healthcheck token -> homelab-health" 200 "$(post "$NTFY_HEALTH_TOKEN" homelab-health)"
expect "clawlight token   -> clawlight"      200 "$(post "$NTFY_CLAWLIGHT_TOKEN" clawlight)"

echo "=== and are denied the other's topic ==="
expect "healthcheck token -> clawlight is refused"      403 "$(post "$NTFY_HEALTH_TOKEN" clawlight)"
expect "clawlight token   -> homelab-health is refused" 403 "$(post "$NTFY_CLAWLIGHT_TOKEN" homelab-health)"

echo "=== anonymous cannot publish to either ==="
anon() { curl -sS -m 10 -o /dev/null -w '%{http_code}' -d "x" "$BASE/$1"; }
expect "anonymous -> homelab-health is refused" 403 "$(anon homelab-health)"
expect "anonymous -> clawlight is refused"      403 "$(anon clawlight)"

echo "=== the phone login can READ both ==="
readable() { # topic
  curl -sS -m 10 -o /dev/null -w '%{http_code}' \
    -u "pramod:$NTFY_ADMIN_PASSWORD" "$BASE/$1/json?poll=1"
}
expect "pramod can read homelab-health" 200 "$(readable homelab-health)"
expect "pramod can read clawlight"      200 "$(readable clawlight)"

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; exit 1
