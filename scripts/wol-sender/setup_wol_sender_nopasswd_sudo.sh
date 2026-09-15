#!/bin/bash
# Run on wol-sender (the Pi) via SSH. Grants pramod passwordless sudo for
# just the commands actually needed to manage this Pi remotely -
# systemctl (service management/reboot), and writing service/sender
# scripts to their standard system locations. Deliberately scoped rather
# than blanket NOPASSWD:ALL.
set -euo pipefail

SUDOERS_FILE=/etc/sudoers.d/pramod-wol-sender

sudo tee "$SUDOERS_FILE" > /dev/null <<'EOF'
pramod ALL=(root) NOPASSWD: /usr/bin/systemctl
pramod ALL=(root) NOPASSWD: /usr/sbin/reboot
pramod ALL=(root) NOPASSWD: /usr/bin/tee /usr/local/bin/*
pramod ALL=(root) NOPASSWD: /usr/bin/tee /etc/systemd/system/*
pramod ALL=(root) NOPASSWD: /usr/bin/chmod +x /usr/local/bin/*
EOF

sudo chmod 440 "$SUDOERS_FILE"
sudo visudo -c -f "$SUDOERS_FILE"

echo "Done. Validated with visudo -c. NOPASSWD sudo scoped to systemctl, reboot, and writes to /usr/local/bin and /etc/systemd/system."
