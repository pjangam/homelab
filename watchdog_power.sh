#!/usr/bin/env bash
# Watchdog: shuts this server down cleanly if it's been running on UPS
# battery for too long, to avoid the kind of ZFS corruption a hard,
# uncontrolled power loss can cause (found in datapool on 2026-07-12,
# most likely from the 2026-06-29 kernel-lockup hard power cycle).
#
# Context: enp1s0 connects through a WiFi extender with no battery backup
# of its own (see setup_wifi_failover.sh). When it loses carrier, mains
# power is very likely out, and this server is separately running on its
# own RouterUPS battery (~3-4hr real runtime under this load - it's rated
# 8h, but that's for the lighter router/modem load it's normally sold for).
# If that battery runs out before mains returns, the server crashes
# uncontrolled. A clean shutdown well before that happens avoids it
# entirely - everything unmounts properly, no torn writes.
#
# Safety: defaults to DRY RUN (logs what it would do, never actually shuts
# down) until armed. Arm with: touch ~/.power-watchdog-armed
# Disarm/disable anytime with: rm ~/.power-watchdog-armed
#                          or: touch ~/.power-watchdog-disabled
#
# Requires passwordless sudo for /usr/sbin/shutdown only (see
# setup_power_watchdog_sudoers.sh) since this runs unattended from cron.
#
# Run via cron every 5 minutes.
set -euo pipefail

DISABLE_FLAG="$HOME/.power-watchdog-disabled"
ARM_FLAG="$HOME/.power-watchdog-armed"
IFACE="enp1s0"
STATE_DIR="$HOME/.cache/power-watchdog"
DOWN_SINCE_FILE="$STATE_DIR/down-since"
DOWN_THRESHOLD_MIN=90
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
  rm -f "$DOWN_SINCE_FILE"
  exit 0
fi

# Currently no carrier. Start (or continue) the clock.
if [ ! -f "$DOWN_SINCE_FILE" ]; then
  date +%s > "$DOWN_SINCE_FILE"
  logger -t "$LOG_TAG" "$IFACE lost carrier - likely on UPS battery, starting watch"
  exit 0
fi

down_since=$(cat "$DOWN_SINCE_FILE")
now=$(date +%s)
elapsed_min=$(( (now - down_since) / 60 ))

if [ "$elapsed_min" -ge "$DOWN_THRESHOLD_MIN" ]; then
  if [ -f "$ARM_FLAG" ]; then
    logger -t "$LOG_TAG" "$IFACE down for ${elapsed_min}m (>=${DOWN_THRESHOLD_MIN}m) - shutting down cleanly to avoid a hard power-loss crash"
    sudo /usr/sbin/shutdown -h now
  else
    logger -t "$LOG_TAG" "[DRY RUN] $IFACE down for ${elapsed_min}m (>=${DOWN_THRESHOLD_MIN}m) - would shut down now (touch ~/.power-watchdog-armed to arm)"
  fi
else
  logger -t "$LOG_TAG" "$IFACE down for ${elapsed_min}m (threshold ${DOWN_THRESHOLD_MIN}m) - waiting"
fi
