#!/usr/bin/env bash
# Screenshot HA dashboard paths and fail if any card rendered as an error -
# the check to run after editing a YAML dashboard in dashboards/.
#
#   projects/ha-dashboard/shot_dashboard.sh <out_dir> dashboard-home/overview home/overview ...
#
# Needs HA_TOKEN (read from .env.healthcheck if not set).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=$(readlink -f "${1:?usage: shot_dashboard.sh <out_dir> <path>...}"); shift
mkdir -p "$OUT"
: "${HA_TOKEN:=$(grep '^HA_TOKEN=' "$REPO/.env.healthcheck" | cut -d= -f2-)}"
export HA_TOKEN

rc=0
docker run --rm --network host -e HA_TOKEN -e HA_URL \
  -v "$HERE/shot-dashboard.js:/work/shot-dashboard.js:ro" -v "$OUT:/out" \
  mcr.microsoft.com/playwright:v1.55.0-noble \
  sh -c 'cd /work && npm i --silent --no-save --no-package-lock playwright-core@1.55.0 >/dev/null 2>&1 && node shot-dashboard.js "$@"' _ "$@" || rc=$?
# the container writes as root; hand the screenshots back
sudo -n chown -R "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true
exit $rc
