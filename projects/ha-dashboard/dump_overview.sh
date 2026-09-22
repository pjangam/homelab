#!/usr/bin/env bash
# Dump the config HA's auto-generated Overview currently expands to, as YAML.
# Overview is built by a frontend strategy in the browser and never stored, so
# the only way to read it is to render it: this runs dump-overview.js in the
# already-pulled Playwright container (xero has no browser or Node).
#
#   projects/ha-dashboard/dump_overview.sh > projects/ha-dashboard/overview.yaml
#   DASH=dashboard-stats projects/ha-dashboard/dump_overview.sh   (any other dashboard)
#
# Needs HA_TOKEN (read from .env.healthcheck if not set).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
: "${HA_TOKEN:=$(grep '^HA_TOKEN=' "$REPO/.env.healthcheck" | cut -d= -f2-)}"
export HA_TOKEN

docker run --rm --network host -e HA_TOKEN -e HA_URL -e DASH \
  -v "$HERE/dump-overview.js:/work/dump-overview.js:ro" -v "${OUT_DIR:-/tmp}:/out" \
  mcr.microsoft.com/playwright:v1.55.0-noble \
  sh -c 'cd /work && npm i --silent --no-save --no-package-lock playwright-core@1.55.0 >/dev/null 2>&1 && node dump-overview.js' \
  | python3 -c 'import json,sys,yaml; yaml.safe_dump(json.load(sys.stdin), sys.stdout, sort_keys=False, allow_unicode=True, width=1000)'
