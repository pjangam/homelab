#!/usr/bin/env bash
# Screenshot the live projects dashboard at desktop and phone widths, clicking
# through a project and the shopping list on the way, so a layout change can
# be checked in a real browser rather than only in jsdom. xero has no Node or
# browser of its own, so it all runs in the Playwright image.
#
# Usage: screenshot.sh [OUT_DIR] [URL]
set -euo pipefail

OUT_DIR=$(realpath -m "${1:-./projects-ui-screens}")
URL=${2:-http://localhost:8125/projects/}
PLAYWRIGHT=1.55.0
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$OUT_DIR"
docker run --rm --network host --ipc host \
  -v "$HERE/screenshot.mjs:/work/screenshot.mjs:ro" \
  -v "$OUT_DIR:/out" \
  -e URL="$URL" \
  "mcr.microsoft.com/playwright:v${PLAYWRIGHT}-noble" \
  sh -c "cd /tmp && npm init -y >/dev/null && npm i --silent playwright@${PLAYWRIGHT} >/dev/null \
         && cp /work/screenshot.mjs . && node screenshot.mjs"

ls -1 "$OUT_DIR"
