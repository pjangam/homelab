#!/bin/bash
# Install screen_blank.sh on the wol-sender Pi and (re)start it in the running
# desktop session, so the monitor turns off after 10 idle minutes now and
# after every login. No sudo. Run on xero.
set -e
PI=pramod@192.168.1.124
cd "$(dirname "$0")"
scp -q screen_blank.sh "$PI":~/
ssh "$PI" 'mkdir -p ~/.config/autostart && chmod +x ~/screen_blank.sh'
scp -q screen-blank.desktop "$PI":~/.config/autostart/
ssh "$PI" 'command -v swayidle wlopm >/dev/null || { echo "swayidle or wlopm missing" >&2; exit 1; }
  pkill -x swayidle || true; sleep 1
  export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
  nohup ~/screen_blank.sh >/dev/null 2>&1 &
  sleep 1; pgrep -a swayidle'
echo "Deployed. The monitor turns off after 10 idle minutes; any input wakes it."
