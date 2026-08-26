#!/usr/bin/env bash
# Watchdog: shuts this server down cleanly if it's been running on UPS
# battery for too long, to avoid the kind of ZFS corruption a hard,
# uncontrolled power loss can cause (found in datapool on 2026-07-12,
# most likely from the 2026-06-29 kernel-lockup hard power cycle).
#
# Context: enp1s0 connects through a WiFi extender with no battery backup
# of its own (see the WiFi failover step in new_machine_setup.sh). When it loses carrier, mains
# power is very likely out, and this server is separately running on its
# own RouterUPS battery - measured at ~288min (4h49m) real runtime under
# this load via a live outage test on 2026-07-31 (rated 8h, but that's for
# the lighter router/modem load it's normally sold for). If that battery
# runs out before mains returns, the server crashes uncontrolled - which is
# exactly what happened during that same test, since the watchdog was still
# unarmed (dry-run only) the whole time. ZFS came back healthy afterward,
# but that's not something to rely on happening again. Threshold set to
# 200min, leaving ~88min of real margin before the confirmed failure point.
# A clean shutdown well before that happens avoids it entirely - everything
# unmounts properly, no torn writes.
#
# Safety: defaults to DRY RUN (logs what it would do, never actually shuts
# down) until armed. Arm with: touch ~/.power-watchdog-armed
# Disarm/disable anytime with: rm ~/.power-watchdog-armed
#                          or: touch ~/.power-watchdog-disabled
#
# Requires passwordless sudo for /usr/sbin/shutdown only (installed by
# new_machine_setup.sh) since this runs unattended from cron.
#
# Run via cron every 5 minutes.
set -euo pipefail

DISABLE_FLAG="$HOME/.power-watchdog-disabled"
ARM_FLAG="$HOME/.power-watchdog-armed"
IFACE="enp1s0"
STATE_DIR="$HOME/.cache/power-watchdog"
DOWN_SINCE_FILE="$STATE_DIR/down-since"
LAST_MILESTONE_FILE="$STATE_DIR/last-logged-milestone-min"
THRESHOLD_CROSSED_FILE="$STATE_DIR/threshold-crossed"
DOWN_THRESHOLD_MIN=200
# How often to re-log while still down and below threshold, so a long
# outage doesn't spam a near-duplicate line every 5-minute cron tick (a
# real 288min test outage produced 48+ near-identical "waiting" lines,
# burying the two moments that actually matter: carrier lost/restored and
# the threshold being crossed). Those two moments are still logged
# immediately, every time, regardless of this interval.
MILESTONE_INTERVAL_MIN=30
LOG_TAG="power-watchdog"

if [ -f "$DISABLE_FLAG" ]; then
  exit 0
fi

mkdir -p "$STATE_DIR"

carrier=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo "1")

if [ "$carrier" = "1" ]; then
  if [ -f "$DOWN_SINCE_FILE" ]; then
    logger -t "$LOG_TAG" "$IFACE carrier restored - clearing watch"
  fi
  rm -f "$DOWN_SINCE_FILE" "$LAST_MILESTONE_FILE" "$THRESHOLD_CROSSED_FILE"
  exit 0
fi

# Currently no carrier. Start (or continue) the clock.
if [ ! -f "$DOWN_SINCE_FILE" ]; then
  date +%s > "$DOWN_SINCE_FILE"
  rm -f "$LAST_MILESTONE_FILE" "$THRESHOLD_CROSSED_FILE"
  logger -t "$LOG_TAG" "$IFACE lost carrier - likely on UPS battery, starting watch"
  exit 0
fi

down_since=$(cat "$DOWN_SINCE_FILE")
now=$(date +%s)
elapsed_min=$(( (now - down_since) / 60 ))

last_milestone=0
if [ -f "$LAST_MILESTONE_FILE" ]; then
  last_milestone=$(cat "$LAST_MILESTONE_FILE")
fi
at_milestone=0
if [ "$elapsed_min" -ge $(( last_milestone + MILESTONE_INTERVAL_MIN )) ]; then
  at_milestone=1
fi

if [ "$elapsed_min" -ge "$DOWN_THRESHOLD_MIN" ]; then
  if [ -f "$ARM_FLAG" ]; then
    logger -t "$LOG_TAG" "$IFACE down for ${elapsed_min}m (>=${DOWN_THRESHOLD_MIN}m) - shutting down cleanly to avoid a hard power-loss crash"
    sudo /usr/sbin/shutdown -h now
  else
    # First crossing logs immediately regardless of the milestone interval -
    # this is the critical "would shut down now" moment. Repeats after that
    # are throttled to the same milestone cadence as the waiting branch.
    if [ ! -f "$THRESHOLD_CROSSED_FILE" ] || [ "$at_milestone" = 1 ]; then
      logger -t "$LOG_TAG" "[DRY RUN] $IFACE down for ${elapsed_min}m (>=${DOWN_THRESHOLD_MIN}m) - would shut down now (touch ~/.power-watchdog-armed to arm)"
      touch "$THRESHOLD_CROSSED_FILE"
      echo "$elapsed_min" > "$LAST_MILESTONE_FILE"
    fi
  fi
else
  if [ "$at_milestone" = 1 ]; then
    logger -t "$LOG_TAG" "$IFACE down for ${elapsed_min}m (threshold ${DOWN_THRESHOLD_MIN}m) - waiting"
    echo "$elapsed_min" > "$LAST_MILESTONE_FILE"
  fi
fi
