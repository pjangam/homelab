#!/usr/bin/env bash
# Watch the live pihole log for DNS queries from a specific client.
#
# Why not just `tail -f | grep IP`: that prints nothing until a match lands, so
# you cannot tell "waiting" from "hung". This prints a heartbeat every 10s with
# a running match count, so silence is visibly *meaningful* rather than ambiguous.
#
# Per the usual gotcha: the FTL database and the admin UI lag, so only a marker
# in the live pihole.log proves a query path actually works.
#
# Usage: scripts/watch-peer-dns.sh 100.74.192.33 [192.168.1.102 ...]

set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <client-ip> [more-ips...]" >&2; exit 1; }

PATTERN="from ($(IFS='|'; echo "$*" | sed 's/ /|/g'))\b"
echo "Watching pihole.log for: $*"
echo "Heartbeat every 10s. Ctrl-C to stop."
echo

COUNT=0
STATE=$(mktemp)
# Heartbeat on a separate track so an idle client still shows liveness.
( while true; do sleep 10; printf '[%s] waiting... matches=%s\n' "$(date '+%H:%M:%S')" "$(cat "$STATE" 2>/dev/null || echo 0)"; done ) &
HB=$!
trap 'kill $HB 2>/dev/null; rm -f "$STATE"' EXIT

echo 0 > "$STATE"
docker exec pihole tail -f /var/log/pihole/pihole.log \
  | grep --line-buffered -E "$PATTERN" \
  | while IFS= read -r line; do
      COUNT=$((COUNT+1)); echo "$COUNT" > "$STATE"
      echo "MATCH #$COUNT: $line"
    done
