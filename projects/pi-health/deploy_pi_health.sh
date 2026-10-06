#!/usr/bin/env bash
# Run this ON XERO. Installs pi-health-mqtt (PROJECTS.md "wol Pi health
# monitoring") on the wol Pi as an enabled systemd --user unit and restarts
# it. Re-run after changing pi-health-mqtt.py or the unit.
#
# The Pi has no repo clone: the script lands under ~/homelab with its repo
# path, and the unit's /home/pramod/code/homelab is rewritten to match - the
# same layout projects/white-noise/deploy_audio_pi.sh uses. MQTT credentials
# and MQTT_HOST come from the ~/homelab/.env.mqtt that deploy already wrote.
# No sudo: a user unit, and linger is on.
set -euo pipefail

PI="pramod@192.168.1.124"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PI_ROOT="/home/pramod/homelab"

ssh "$PI" "mkdir -p $PI_ROOT/projects/pi-health ~/.config/systemd/user"
scp -q "$REPO/projects/pi-health/pi-health-mqtt.py" "$PI:$PI_ROOT/projects/pi-health/"
sed "s|/home/pramod/code/homelab|$PI_ROOT|g" "$REPO/projects/pi-health/pi-health-mqtt.service" \
  | ssh "$PI" 'cat > ~/.config/systemd/user/pi-health-mqtt.service'

ssh "$PI" bash -s <<'REMOTE'
set -euo pipefail
test -f ~/homelab/.env.mqtt || { echo "~/homelab/.env.mqtt missing - run deploy_audio_pi.sh first" >&2; exit 1; }
systemctl --user daemon-reload
systemctl --user enable pi-health-mqtt.service
systemctl --user restart pi-health-mqtt.service
sleep 15
systemctl --user --no-pager status pi-health-mqtt.service | head -5
journalctl --user -u pi-health-mqtt.service --no-pager -n 5
REMOTE
