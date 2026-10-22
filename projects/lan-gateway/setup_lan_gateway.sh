#!/bin/bash
# Turn xero into an opt-in internet gateway for the LAN. Run on xero, from a
# real terminal (sudo prompts):  projects/lan-gateway/setup_lan_gateway.sh
#
# Changes nothing for any device on its own: the router stays everyone's
# gateway, and only a device pointed at 192.168.1.123 uses this.
# Undo everything with:          projects/lan-gateway/setup_lan_gateway.sh --remove
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = "--remove" ]; then
  sudo systemctl disable --now lan-gateway-usage.timer lan-gateway.service || true
  sudo nft delete table ip lan_gateway 2>/dev/null || true
  sudo rm -f /etc/systemd/system/lan-gateway.service /etc/systemd/system/lan-gateway-usage.{service,timer} \
    /etc/sysctl.d/90-lan-gateway.conf
  sudo systemctl daemon-reload
  sudo ufw route delete allow in on enp1s0 out on enp1s0 from 192.168.1.0/24 || true
  rm -f "$here/../../services/node-exporter/textfile/lan_gateway.prom"
  echo "Removed. (send_redirects stays 0 until reboot; harmless.)"
  exit 0
fi

# 1. Forwarding. Docker already sets ip_forward=1; persist it anyway. Stop xero
#    sending ICMP redirects, which would tell each device "use 192.168.1.1
#    directly" and quietly route it around xero.
sudo tee /etc/sysctl.d/90-lan-gateway.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.enp1s0.send_redirects = 0
EOF
sudo sysctl -q -p /etc/sysctl.d/90-lan-gateway.conf

# 2. ufw's forward policy is DROP: allow LAN -> internet through enp1s0.
#    Replies are let back in by ufw's own established/related rule.
sudo ufw route allow in on enp1s0 out on enp1s0 from 192.168.1.0/24

# 3. NAT + counters, loaded now and at every boot.
sudo nft -c -f "$here/lan-gateway.nft"
sudo tee /etc/systemd/system/lan-gateway.service >/dev/null <<EOF
[Unit]
Description=xero LAN gateway: NAT and per-device counters (projects/lan-gateway)
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f $here/lan-gateway.nft
ExecStop=/usr/sbin/nft delete table ip lan_gateway

[Install]
WantedBy=multi-user.target
EOF

# 4. Counters -> node-exporter textfile, every minute.
sudo tee /etc/systemd/system/lan-gateway-usage.service >/dev/null <<EOF
[Unit]
Description=Export lan_gateway byte counters for node-exporter (projects/lan-gateway)

[Service]
Type=oneshot
ExecStart=$here/usage_textfile.sh
EOF
sudo tee /etc/systemd/system/lan-gateway-usage.timer >/dev/null <<'EOF'
[Unit]
Description=Export lan_gateway byte counters every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now lan-gateway.service lan-gateway-usage.timer
sudo systemctl start lan-gateway-usage.service
echo
sudo nft list table ip lan_gateway
echo
echo "Ready. Nothing uses it yet: point one device's gateway at 192.168.1.123 to test (README.md)."
