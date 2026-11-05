#!/usr/bin/env bash
# Watchdog for the failure watchdog_spotifyd.sh cannot see: Spotify's backend
# no longer lists the device, while spotifyd runs, advertises and has no stuck
# socket (xero, 2026-11-01 to 11-03: websocket dead, gone from the app for
# two days). The per-host watchdog has no view of Spotify's device list - only
# HA's spotcast sensor does, and HA is on xero - so this runs on xero, from
# cron every 5 minutes, for both hosts: xero's spotifyd restarted locally, the
# wol Pi's over ssh.
#
# A device missing for MISSING_GRACE_MIN is restarted, at most once per
# COOLDOWN_MIN per host: if a restart doesn't bring it back, the cause is
# elsewhere (Spotify, the account, the network) and restarting every 5
# minutes would only add noise. healthcheck.sh alerts on that case.
# "Can't tell" (HA or spotcast down) neither starts nor clears a countdown.
#
# Restarts are appended to listed-restarts-<name>.log under the watchdog's
# state dir, which healthcheck.sh counts into each host's restarts.
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
STATE_DIR="${STATE_DIR:-$HOME/.cache/spotifyd-watchdog}"
MISSING_GRACE_MIN="${MISSING_GRACE_MIN:-15}"
COOLDOWN_MIN="${COOLDOWN_MIN:-60}"
CHECK="${CHECK:-$REPO/projects/spotifyd/check_spotify_listed.sh}"
PI="${PI:-pramod@192.168.1.124}"
LOG_TAG="spotify-listed-watchdog"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
mkdir -p "$STATE_DIR"

restart_host() { # name
  if [ -n "${RESTART_CMD:-}" ]; then "$RESTART_CMD" "$1"; return; fi
  case "$1" in
    xero) systemctl --user restart spotifyd ;;
    raspberrypi) ssh -o BatchMode=yes -o ConnectTimeout=10 "$PI" 'systemctl --user restart spotifyd' ;;
  esac
}

for name in ${HOSTS:-xero raspberrypi}; do
  since_file="$STATE_DIR/listed-missing-since-$name"
  last_file="$STATE_DIR/listed-last-restart-$name"
  "$CHECK" "$name" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && continue
  if [ "$rc" -eq 0 ]; then rm -f "$since_file"; continue; fi

  now=$(date +%s)
  [ -f "$since_file" ] || { echo "$now" > "$since_file"; logger -t "$LOG_TAG" "$name not listed by Spotify - starting watch"; continue; }
  missing_min=$(( (now - $(cat "$since_file")) / 60 ))
  [ "$missing_min" -ge "$MISSING_GRACE_MIN" ] || continue
  if [ -f "$last_file" ] && [ $(( (now - $(cat "$last_file")) / 60 )) -lt "$COOLDOWN_MIN" ]; then
    continue
  fi
  logger -t "$LOG_TAG" "$name not listed by Spotify for ${missing_min}m - restarting its spotifyd"
  if restart_host "$name"; then
    echo "$now" > "$last_file"
    date -Iseconds >> "$STATE_DIR/listed-restarts-$name.log"
  else
    logger -t "$LOG_TAG" "restart of $name's spotifyd failed"
  fi
done
exit 0
