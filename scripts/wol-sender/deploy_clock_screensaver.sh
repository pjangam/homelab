#!/bin/bash
# Deploy the clock screensaver to the wol-sender Pi and (re)start it in the
# running desktop session, so it works now and at every login.
# Needs python3-gi-cairo on the Pi (sudo apt install python3-gi-cairo).
set -e
PI=pramod@192.168.1.124
cd "$(dirname "$0")"

scp -q analog_clock.py clock_screensaver.sh "$PI":~/
ssh "$PI" 'mkdir -p ~/.config/autostart && chmod +x ~/clock_screensaver.sh'
scp -q clock-screensaver.desktop "$PI":~/.config/autostart/

ssh "$PI" 'python3 -c "import gi; gi.require_foreign(\"cairo\")" 2>/dev/null \
    || { echo "python3-gi-cairo missing: sudo apt install python3-gi-cairo" >&2; exit 1; }
  pkill -f clock_screensaver.sh; pkill -x swayidle; sleep 1
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  nohup ~/clock_screensaver.sh >/dev/null 2>&1 &
  sleep 1; pgrep -a swayidle'
echo "Deployed. Clock appears after 5 idle minutes."
