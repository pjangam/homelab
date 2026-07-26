#!/bin/bash
# One-time: lets pramod run ONLY `shutdown` without a password, so
# watchdog_power.sh can act unattended from cron. Scoped to that single
# command - no broader sudo access granted.
set -euo pipefail

RULE='pramod ALL=(root) NOPASSWD: /usr/sbin/shutdown -h now'
FILE=/etc/sudoers.d/power-watchdog

echo "$RULE" | sudo tee "$FILE" > /dev/null
sudo chmod 440 "$FILE"
sudo visudo -cf "$FILE" && echo "OK: sudoers rule installed and syntax-checked"
