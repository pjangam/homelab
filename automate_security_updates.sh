#!/bin/bash
# Extends the existing unattended-upgrades setup (already running twice
# daily via apt-daily.timer/apt-daily-upgrade.timer) to also cover the
# Docker and Tailscale apt repos, which aren't in Ubuntu's own archive and
# so aren't touched by unattended-upgrades' default Allowed-Origins.
#
# Adds a new apt.conf.d fragment rather than editing the shipped
# 50unattended-upgrades file, since apt.conf list options append across
# fragments (read in filename order) - no need to touch/merge the
# maintainer-owned conffile.
#
# Tradeoff worth knowing: Docker's apt repo has one rolling "stable" suite
# with no separation between minor and major versions, so this will also
# auto-install a future Docker CE major-version bump with no manual review.
# A docker-ce upgrade restarts the Docker daemon (briefly restarts every
# container) whenever apt-daily-upgrade.timer next fires (currently ~06:50
# and ~19:00 IST) if a new version is available that day.
set -euo pipefail

sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-thirdparty > /dev/null <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "Docker:noble";
    "Tailscale:noble";
};
EOF

echo "=== Dry run (what would be upgraded unattended) ==="
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E "Checking|Allowed origins|Packages that|will be upgraded"
