#!/bin/bash
# Install wireplumber-bluez-no-logind.lua on xero and restart WirePlumber
# (drops Bluetooth audio for a few seconds; the cron reconnect brings the
# speaker back within a minute).
set -eu
d="$HOME/.config/wireplumber/bluetooth.lua.d"
mkdir -p "$d"
cp "$(dirname "$0")/wireplumber-bluez-no-logind.lua" "$d/80-bluez-no-logind.lua"
systemctl --user restart wireplumber
echo "installed; WirePlumber restarted"
