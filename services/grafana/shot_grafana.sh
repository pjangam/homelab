#!/usr/bin/env bash
# Screenshot Grafana dashboards (by uid) into <out_dir> and fail if any panel
# shows "No data" or an error - the check to run after build_dashboards.py.
#   services/grafana/shot_grafana.sh <out_dir> hosts containers
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(readlink -f "${1:?usage: shot_grafana.sh <out_dir> <uid>...}"); shift
mkdir -p "$OUT"
docker run --rm --network host -v "$HERE/shot-grafana.js:/work/shot-grafana.js:ro" -v "$OUT:/out" \
  mcr.microsoft.com/playwright:v1.55.0-noble \
  sh -c 'cd /work && npm i --silent --no-save --no-package-lock playwright-core@1.55.0 >/dev/null 2>&1 && node shot-grafana.js "$@"' _ "$@"
