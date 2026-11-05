#!/bin/bash
# Retire the clock screensaver from the wol-sender Pi (closed 2026-11-05):
# stop the running clock and its swayidle, remove the login autostart, and
# delete the Pi's copy of the HA token the weather panel used. Run on xero.
#
# The code stays in this folder on purpose - analog_clock.py (weather and
# clawlight sessions beside a clock) is the starting point for a small,
# low-power clawlight display. deploy_clock_screensaver.sh puts it all back.
# kanshi-config is left on the Pi: it only sets the display layout.
set -e
PI=pramod@192.168.1.124
ssh "$PI" 'pkill -x swayidle || true
  pkill -f "^python3 .*analog_clock" || true
  rm -f ~/.config/autostart/clock-screensaver.desktop ~/clock_screensaver.sh ~/analog_clock.py ~/.config/analog-clock.env
  sleep 1
  if pgrep -x swayidle || pgrep -f "^python3 .*analog_clock"; then echo "still running" >&2; exit 1; fi
  ls ~/.config/autostart/'
echo "Clock screensaver removed from the Pi."
