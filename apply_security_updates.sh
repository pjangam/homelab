#!/bin/bash
# One-off: apply pending Docker + Tailscale security updates (2026-07-26).
# docker-ce 29.4.3 -> 29.6.2 fixes several BuildKit CVEs (incl. a command
# injection bug). tailscale 1.98.4 -> 1.98.9 fixes TS-2026-009, an SSH
# privilege-escalation bug (ACL-violating root session via crafted usernames).
set -euo pipefail

sudo apt update
sudo apt install --only-upgrade -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
  docker-compose-plugin docker-ce-rootless-extras docker-model-plugin \
  tailscale

echo "=== Installed versions ==="
dpkg -l | grep -E "^ii  (docker-ce |tailscale )"
