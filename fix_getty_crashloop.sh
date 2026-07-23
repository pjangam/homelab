#!/bin/bash
# Recovery for getty@tty1 crash-looping on a hardcoded console font that no
# longer fits the video mode negotiated at this boot (e.g. monitor unplugged
# at boot time). Rewrites the getty drop-in to try fonts largest-to-smallest
# at every getty start instead of a single hardcoded one, so it can never
# crash-loop on this again. Safe to re-run any time tty1 gets stuck failed.
#
# Must be run from a session with sudo access (not from tty1 itself, since
# probing setfont requires a real console fd - this writes the drop-in
# directly instead of probing).
set -euo pipefail

sudo mkdir -p /etc/systemd/system/getty@.service.d
sudo tee /etc/systemd/system/getty@.service.d/powerline-font.conf > /dev/null <<'EOF'
[Service]
ExecStartPre=/bin/sh -c 'for f in ter-powerline-v24b ter-powerline-v22b ter-powerline-v20b ter-powerline-v18b ter-powerline-v16b; do setfont /usr/share/consolefonts/${f}.psf.gz 2>/dev/null && break; done; true'
EOF

sudo systemctl daemon-reload
sudo systemctl reset-failed getty@tty1.service
sudo systemctl restart getty@tty1.service

sleep 1
systemctl status getty@tty1.service --no-pager
