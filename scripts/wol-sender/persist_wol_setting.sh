#!/bin/bash
# Run on xero directly (needs sudo). Pins the NIC's Wake-on-LAN mode to
# "magic packet only" on every boot, so a future driver/kernel update can't
# silently reset it and defeat the WoL-based power recovery path (see
# PROJECTS.md "Power-outage watchdog"). `Wake-on: g` is currently just the
# driver's out-of-the-box default for this NIC - nothing persists it, so a
# reset would go unnoticed until the next real outage, when the Pi's magic
# packet would silently fail to bring xero back.
set -euo pipefail

IFACE=enp1s0

sudo tee /etc/systemd/system/wol-persist.service > /dev/null <<EOF
[Unit]
Description=Pin Wake-on-LAN mode (magic packet) on ${IFACE}
After=sys-subsystem-net-devices-${IFACE}.device
Requires=sys-subsystem-net-devices-${IFACE}.device

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s ${IFACE} wol g

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wol-persist.service

echo "Installed. Testing it now:"
sudo systemctl start wol-persist.service
sudo systemctl status wol-persist.service --no-pager

echo
echo "Current Wake-on setting (should be 'g'):"
sudo ethtool ${IFACE} | grep -i "Wake-on:"
