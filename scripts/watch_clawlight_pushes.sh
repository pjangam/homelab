#!/usr/bin/env bash
# Streams whatever lands on the clawlight ntfy topic, for verifying a push
# arrived without waiting to see whether the phone buzzed. Reads as user
# `pramod` (the publish token is write-only by design).
#
#   scripts/watch_clawlight_pushes.sh [seconds]   # default 300
set -eu
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. .env.ntfy

NTFY="${NTFY_BASE_URL:-http://127.0.0.1:8127}"
secs="${1:-300}"

echo "watching $NTFY/clawlight for ${secs}s (from $(date +%T))"
curl -sN --max-time "$secs" -u "pramod:$NTFY_ADMIN_PASSWORD" "$NTFY/clawlight/json?since=0s" |
  while IFS= read -r line; do
    case "$line" in
      *'"event":"message"'*)
        printf '%s  PUSH  %s\n' "$(date +%T)" \
          "$(printf '%s' "$line" | sed -n 's/.*"title":"\([^"]*\)".*"message":"\([^"]*\)".*/\1 - \2/p')"
        ;;
    esac
  done
echo "done watching at $(date +%T)"
