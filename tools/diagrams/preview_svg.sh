#!/usr/bin/env bash
# Screenshot standalone SVG files the way GitHub shows them: as <img> (no page
# CSS, no webfonts), on a light and a dark page, at desktop and phone width.
#   tools/diagrams/preview_svg.sh OUT_DIR file1.svg [file2.svg ...]
# Writes OUT_DIR/{desktop,phone}-{light,dark}.png via render.sh. Look at them
# with the Read tool before committing a drawing. OUT_DIR: use a *-render/
# path (gitignored) or the scratchpad.
set -euo pipefail
[ $# -ge 2 ] || { sed -n 2,7p "$0"; exit 2; }
out="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$out"
page="$(cd "$out" && pwd)/preview.html"
{
  echo '<!doctype html><html><head><meta charset="utf-8"><title>SVG preview</title>'
  echo '<meta name="viewport" content="width=device-width, initial-scale=1">'
  echo '<style>body{margin:16px;background:#fff}@media (prefers-color-scheme:dark){body{background:#0d1117}}img{max-width:100%;display:block;margin:0 0 16px}</style></head><body>'
  for f in "$@"; do
    echo "<img alt=\"$(basename "$f")\" src=\"data:image/svg+xml;base64,$(base64 -w0 "$f")\">"
  done
  echo '</body></html>'
} > "$page"
"$here/render.sh" "$page" "$out"
