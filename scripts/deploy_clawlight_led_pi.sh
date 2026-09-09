#!/usr/bin/env bash
# Run this ON XERO. Installs/updates the physical clawlight LED service on the
# wol-sender Pi: the script, its MQTT credentials, and the systemd unit.
#
# The credentials file is generated here from xero's .env.mqtt rather than
# hand-copied, so the Pi never drifts from the broker's actual password and
# there is no second place to update when it rotates.
#
#   scripts/deploy_clawlight_led_pi.sh            # install/update and restart
#   scripts/deploy_clawlight_led_pi.sh --dry-run  # run with --no-gpio in the
#                                                 # foreground on the Pi, to
#                                                 # test before an LED exists
set -euo pipefail

PI="pramod@192.168.1.124"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

# shellcheck disable=SC1091
set -a; . "$REPO/.env.mqtt"; set +a
: "${MQTT_USERNAME:?missing from .env.mqtt}" "${MQTT_PASSWORD:?missing from .env.mqtt}"

scp -q "$REPO/scripts/clawlight-led.py" "$PI:~/clawlight-led.py"
scp -q "$REPO/systemd/wol-sender/clawlight-led.service" "$PI:~/clawlight-led.service"

# 600 before the secret goes in, not after - otherwise the password is briefly
# world-readable on a box that other household devices can reach.
ssh "$PI" "install -m 600 /dev/null ~/clawlight-led.env && cat > ~/clawlight-led.env" <<ENVFILE
MQTT_USERNAME=$MQTT_USERNAME
MQTT_PASSWORD=$MQTT_PASSWORD
ENVFILE

if [ "$dry_run" -eq 1 ]; then
  echo "== dry run: clawlight-led.py --no-gpio on the Pi (ctrl-c to stop) =="
  ssh -t "$PI" 'set -a; . ~/clawlight-led.env; set +a; /home/pramod/.local/bin/uv run ~/clawlight-led.py --no-gpio'
  exit 0
fi

ssh "$PI" bash -s <<'REMOTE'
set -euo pipefail
chmod +x ~/clawlight-led.py
sudo install -m 644 ~/clawlight-led.service /etc/systemd/system/clawlight-led.service
rm -f ~/clawlight-led.service
sudo systemctl daemon-reload
sudo systemctl enable --now clawlight-led
sleep 8
echo "== clawlight-led: $(systemctl is-active clawlight-led) =="
journalctl -u clawlight-led --no-pager -n 10 -o cat
REMOTE
