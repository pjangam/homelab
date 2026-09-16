#!/usr/bin/env bash
# Screenshot a local wiring-diagram HTML page at desktop and phone widths, in
# light and dark mode, so whoever drew it (usually the circuit-diagram agent,
# .claude/agents/circuit-diagram.md) can look at the result for overlapping
# labels, wires running through text and unreadable dark-mode colours before
# publishing. xero has no browser of its own, so this runs in the same
# Playwright image as projects/projects-ui/scripts/screenshot.sh.
#
# Usage: render.sh PAGE.html [OUT_DIR]     (OUT_DIR defaults to PAGE's name + -render/)
set -euo pipefail

PAGE=$(realpath "${1:?usage: render.sh PAGE.html [OUT_DIR]}")
OUT_DIR=$(realpath -m "${2:-${PAGE%.html}-render}")
PLAYWRIGHT=1.55.0
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$OUT_DIR"
# --network host only so Google Fonts load; the page itself is mounted read-only.
docker run --rm --network host --ipc host \
  -v "$HERE/render.mjs:/work/render.mjs:ro" \
  -v "$PAGE:/work/page.html:ro" \
  -v "$OUT_DIR:/out" \
  --user "$(id -u):$(id -g)" -e HOME=/tmp \
  "mcr.microsoft.com/playwright:v${PLAYWRIGHT}-noble" \
  sh -c "cd /tmp && npm init -y >/dev/null && npm i --silent playwright@${PLAYWRIGHT} >/dev/null \
         && cp /work/render.mjs . && node render.mjs"

ls -1 "$OUT_DIR"
