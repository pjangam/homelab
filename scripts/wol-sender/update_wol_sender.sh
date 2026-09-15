#!/bin/bash
# Run on wol-sender (the Pi) via SSH. Replaces the naive `sleep 3` with a
# real wait-for-connectivity loop (up to 2 minutes) plus sending the packet
# 3 times for reliability - the fixed 3s sleep wasn't safe for a real
# outage-recovery scenario, since the home router/AP itself also lost
# power and can take 60-120s to fully boot, often longer than the Pi.
set -euo pipefail

sudo tee /usr/local/bin/wol-xero-sender.sh > /dev/null <<'EOF'
#!/bin/bash
# Waits for real network connectivity, then sends a WoL magic packet to
# xero 3 times. See wol-xero.service and PROJECTS.md "Power-outage
# watchdog" for context.
set -uo pipefail

MAX_WAIT=120
elapsed=0
while ! ip route get 1.1.1.1 &>/dev/null; do
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    logger -t wol-xero "gave up waiting for network after ${MAX_WAIT}s"
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

logger -t wol-xero "network up after ${elapsed}s - sending magic packet (x3)"
for i in 1 2 3; do
  wakeonlan -i 192.168.1.255 68:1D:EF:38:8C:72
  sleep 2
done
logger -t wol-xero "done"
EOF

sudo chmod +x /usr/local/bin/wol-xero-sender.sh

sudo tee /etc/systemd/system/wol-xero.service > /dev/null <<'EOF'
[Unit]
Description=Send Wake-on-LAN magic packet to xero on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wol-xero-sender.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wol-xero.service

echo "Updated. Testing it now:"
sudo systemctl start wol-xero.service
journalctl -t wol-xero --no-pager -n 10
