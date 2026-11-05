#!/usr/bin/env bash
# The wol Pi's spotifyd (`raspberrypi`) as seen from xero, for healthcheck.sh.
# Prints one line: "<advert_rc> <listed_rc> <restarts_24h>"
#   advert_rc    check_spotifyd_advertising.sh --remote: 0 ok, 1 not on the LAN, 2 can't tell
#   listed_rc    check_spotify_listed.sh: 0 ok, 1 Spotify doesn't list it, 2 can't tell
#   restarts_24h the Pi's own watchdog restarts (its restarts.log, over ssh)
#                plus xero's listed-watchdog restarts of the Pi; -1 if the Pi
#                can't be reached (healthcheck's "wol Pi not reporting" covers that)
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
PI="${PI:-pramod@192.168.1.124}"
STATE_DIR="$HOME/.cache/spotifyd-watchdog"

"$REPO/projects/spotifyd/check_spotifyd_advertising.sh" 8 raspberrypi --remote >/dev/null 2>&1
advert_rc=$?
"$REPO/projects/spotifyd/check_spotify_listed.sh" raspberrypi >/dev/null 2>&1
listed_rc=$?

cutoff=$(date -d "-24 hours" +%s)
count_recent() { # reads ISO timestamps on stdin
  local n=0 ts e
  while read -r ts; do
    [ -n "$ts" ] || continue
    e=$(date -d "$ts" +%s 2>/dev/null) || continue
    [ "$e" -ge "$cutoff" ] && n=$((n + 1))
  done
  echo "$n"
}

if pi_log=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$PI" 'cat ~/.cache/spotifyd-watchdog/restarts.log 2>/dev/null; true' 2>/dev/null); then
  restarts=$(( $(count_recent <<<"$pi_log") + $(count_recent < <(cat "$STATE_DIR/listed-restarts-raspberrypi.log" 2>/dev/null)) ))
else
  restarts=-1
fi

echo "$advert_rc $listed_rc $restarts"
