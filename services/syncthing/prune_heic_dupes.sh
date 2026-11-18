#!/usr/bin/env bash
# Remove HEIC files from the Documents share when a JPG/JPEG of the same name
# sits next to them (iPhone uploads often land as both).
# Dry run by default; pass --apply to act.
# Files are moved into .stversions/ (Syncthing's own versions folder, never
# synced) with Syncthing's ~YYYYMMDD-HHMMSS suffix, so they stay restorable
# on xero and age out with the folder's versioning. The removal itself syncs
# to every paired device.
set -euo pipefail

ROOT=/datapool/documents
APPLY=0
[[ ${1:-} == --apply ]] && APPLY=1
stamp=$(date +%Y%m%d-%H%M%S)
n=0

while IFS= read -r -d '' heic; do
  base=${heic%.*}
  jpg=
  for ext in jpg JPG jpeg JPEG; do
    [[ -s $base.$ext ]] && { jpg=$base.$ext; break; }
  done
  [[ -z $jpg ]] && continue
  file -b "$jpg" | grep -q '^JPEG image' || { echo "skip (bad jpg): $jpg"; continue; }

  rel=${heic#"$ROOT"/}
  name=$(basename "$rel"); dir=$(dirname "$rel")
  dest="$ROOT/.stversions/$dir/${name%.*}~$stamp.${name##*.}"
  if (( APPLY )); then echo "moved: $rel"; else echo "would move: $rel"; fi
  if (( APPLY )); then
    mkdir -p "$(dirname "$dest")"
    mv -n "$heic" "$dest"
  fi
  n=$((n+1))
done < <(find "$ROOT" -path "$ROOT/.stversions" -prune -o -type f -iname '*.heic' -print0)

echo "$n HEIC file(s) with a JPG twin$( (( APPLY )) || echo ' (dry run; --apply to move)')"
