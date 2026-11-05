#!/usr/bin/env bash
# Tests watchdog_spotify_listed.sh with a stubbed Spotify check and a stubbed
# restart, so nothing real is queried or restarted:
# first miss only starts a watch, a miss past the grace restarts once, the
# cooldown stops a second restart, "can't tell" changes nothing, and
# recovery clears the watch.
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
export STATE_DIR="$T/state" HOSTS="raspberrypi" CHECK="$T/check" RESTART_CMD="$T/restart"
printf '#!/bin/sh\nexit $(cat %s/rc)\n' "$T" > "$T/check"
printf '#!/bin/sh\necho "$1" >> %s/restarted\n' "$T" > "$T/restart"
chmod +x "$T/check" "$T/restart"
run() { "$HERE/watchdog_spotify_listed.sh"; }
restarts() { [ -f "$T/restarted" ] && wc -l < "$T/restarted" || echo 0; }
expect() { [ "$2" = "$3" ] && echo "ok   $1" || { echo "FAIL $1: got '$2', want '$3'"; fails=$((fails+1)); }; }
age() { echo $(( $(date +%s) - $2 * 60 )) > "$STATE_DIR/$1"; } # file minutes-ago

echo 1 > "$T/rc"; run
expect "first miss starts a watch, no restart" "$(restarts)" 0
[ -f "$STATE_DIR/listed-missing-since-raspberrypi" ] && expect "watch file written" yes yes || expect "watch file written" no yes

age listed-missing-since-raspberrypi 16; run
expect "miss past grace restarts" "$(restarts)" 1
expect "restart logged" "$(wc -l < "$STATE_DIR/listed-restarts-raspberrypi.log")" 1

run
expect "cooldown blocks a second restart" "$(restarts)" 1

age listed-last-restart-raspberrypi 61; run
expect "after cooldown it restarts again" "$(restarts)" 2

echo 2 > "$T/rc"; run
[ -f "$STATE_DIR/listed-missing-since-raspberrypi" ] && expect "can't-tell keeps the watch" yes yes || expect "can't-tell keeps the watch" no yes

echo 0 > "$T/rc"; run
[ -f "$STATE_DIR/listed-missing-since-raspberrypi" ] && expect "recovery clears the watch" no yes || expect "recovery clears the watch" yes yes

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
