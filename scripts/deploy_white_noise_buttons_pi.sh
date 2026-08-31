#!/usr/bin/env bash
# Run this ON XERO. SSHes into the wol-sender Pi and does the whole
# toggle-switch -> push-buttons swap there in one go: retires the old
# toggle-button-mqtt service, installs white-noise-buttons-mqtt.service, and
# starts it. Needs the Pi's sudo password once (sudo caches it for the rest
# of the SSH session).
#
# Prereqs already done from xero (see white_noise_buttons_setup.md steps 1-3):
#   scp scripts/white-noise-buttons-mqtt.py pramod@192.168.1.124:~/
#   ssh pramod@192.168.1.124 "chmod +x ~/white-noise-buttons-mqtt.py && \
#     cp ~/toggle-button-mqtt.env ~/white-noise-buttons-mqtt.env"
set -euo pipefail

PI="pramod@192.168.1.124"

ssh -t "$PI" bash -s <<'REMOTE'
set -euo pipefail

echo "== disabling old toggle-button-mqtt service =="
sudo systemctl disable --now toggle-button-mqtt 2>/dev/null || true
sudo rm -f /etc/systemd/system/toggle-button-mqtt.service

echo "== installing white-noise-buttons-mqtt.service =="
sudo tee /etc/systemd/system/white-noise-buttons-mqtt.service > /dev/null <<'UNIT'
[Unit]
Description=White noise push buttons MQTT bridge (start/stop)
After=network-online.target
Wants=network-online.target

[Service]
User=pramod
WorkingDirectory=/home/pramod
EnvironmentFile=/home/pramod/white-noise-buttons-mqtt.env
Environment=GPIOZERO_PIN_FACTORY=lgpio
ExecStart=/home/pramod/.local/bin/uv run /home/pramod/white-noise-buttons-mqtt.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

echo "== enabling and starting =="
sudo systemctl daemon-reload
sudo systemctl enable --now white-noise-buttons-mqtt

echo "== status =="
systemctl status white-noise-buttons-mqtt --no-pager -l
REMOTE
