#!/usr/bin/env bash
# Watchdog: restarts spotifyd if its connection to Spotify's backend gets
# stuck. Observed failure mode (2026-08-04): after a "Websocket peer does
# not respond" warning, spotifyd sometimes never reconnects - the process
# stays alive and systemd reports it "active", but the TCP connection to
# Spotify's AP sits in CLOSE-WAIT forever and the daemon silently stops
# showing up as a Connect device. Restart=always doesn't help here because
# the process never exits, so systemd has no failure event to react to.
#
# Every restart is appended to restarts.log so healthcheck.sh can flag
# repeated flapping (a one-off hang is fine to silently self-heal; restarting
# every few minutes means something's actually wrong and needs a look).
#
# Run via cron every 5 minutes.
set -uo pipefail

STATE_DIR="$HOME/.cache/spotifyd-watchdog"
DOWN_SINCE_FILE="$STATE_DIR/down-since"
RESTART_LOG="$STATE_DIR/restarts.log"
DOWN_THRESHOLD_MIN=15
LOG_TAG="spotifyd-watchdog"

# cron runs with no XDG_RUNTIME_DIR, so `systemctl --user` fails with
# "Failed to connect to bus" - same env this repo's other scripts set for
# the same reason (see healthcheck.sh, white-noise-mqtt.py).
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

mkdir -p "$STATE_DIR"

pid=$(systemctl --user show -p MainPID --value spotifyd.service 2>/dev/null)

if [ -z "$pid" ] || [ "$pid" = "0" ]; then
  # Not running at all - systemd's Restart=always owns getting it back up.
  rm -f "$DOWN_SINCE_FILE"
  exit 0
fi

# A CLOSE-WAIT with Recv-Q 0 just means the remote end closed and spotifyd
# hasn't called close() yet - normal, and clears within seconds even during
# healthy reconnect cycling (observed 2026-08-04: a stale post-reconnect fd
# lingered in this state while a separate ESTAB connection worked fine).
# Recv-Q > 0 means data arrived that spotifyd never read - the actual hang
# signature from the 2026-08-04 incident this watchdog was built for.
stuck=$(ss -tnp 2>/dev/null | awk -v needle="pid=$pid," '$1 == "CLOSE-WAIT" && $2+0 > 0 && index($0, needle)')

if [ -z "$stuck" ]; then
  rm -f "$DOWN_SINCE_FILE"
  exit 0
fi

if [ ! -f "$DOWN_SINCE_FILE" ]; then
  date +%s > "$DOWN_SINCE_FILE"
  logger -t "$LOG_TAG" "spotifyd has a stuck CLOSE-WAIT connection - starting watch: $stuck"
  exit 0
fi

down_since=$(cat "$DOWN_SINCE_FILE")
now=$(date +%s)
elapsed_min=$(( (now - down_since) / 60 ))

if [ "$elapsed_min" -ge "$DOWN_THRESHOLD_MIN" ]; then
  logger -t "$LOG_TAG" "spotifyd stuck for ${elapsed_min}m - restarting"
  systemctl --user restart spotifyd
  rm -f "$DOWN_SINCE_FILE"
  date -Iseconds >> "$RESTART_LOG"
  logger -t "$LOG_TAG" "spotifyd restarted"
else
  logger -t "$LOG_TAG" "spotifyd stuck for ${elapsed_min}m (threshold ${DOWN_THRESHOLD_MIN}m) - waiting"
fi
