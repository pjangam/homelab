#!/usr/bin/env bash
# Restore Immich originals that are missing from disk, from the Google
# Takeout zips on datapool/google-takeout/. Run on xero:
#   restore_from_takeout.sh <asset-id>...
# An asset id is in the server log line that failed ("Input file is missing",
# "Missing video metadata" plus an ffprobe "No such file").
#
# For each asset: look up originalPath and Immich's own SHA-1 (asset.checksum),
# find a zip entry with the same basename (any case), extract it, and copy it
# in only if the SHA-1 matches. The copy goes through the immich_server
# container so it lands root:root 644 like the rest of the library (docker cp
# alone leaves the file owned by the host user). Never overwrites a file that
# exists. The 2026-10-11 restore of 53 photos was the same steps by hand.
set -euo pipefail

cd "$(dirname "$0")/../.."
ZIPS=/datapool/google-takeout
U=$(grep ^DB_USERNAME .env | cut -d= -f2)
D=$(grep ^DB_DATABASE_NAME .env | cut -d= -f2)
q() { docker exec immich_postgres psql -U "$U" -d "$D" -tAc "$1"; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Zip listings once, not once per asset: "zip<TAB>entry".
for z in "$ZIPS"/*.zip; do
  unzip -Z1 "$z" | grep -v '\.json$' | sed "s|^|$z\t|"
done > "$work/index"

rc=0
for id in "$@"; do
  row=$(q "select \"originalPath\", encode(checksum, 'hex') from asset where id = '$id'")
  [[ -n $row ]] || { echo "$id: no such asset"; rc=1; continue; }
  path=${row%|*} sum=${row#*|} name=$(basename "$path")
  if docker exec immich_server test -e "$path"; then
    echo "$name: already on disk, skipped"; continue
  fi
  found=
  while IFS=$'\t' read -r zip entry; do
    dir="$work/x$RANDOM"; mkdir "$dir"
    unzip -q -j "$zip" "$entry" -d "$dir"
    f="$dir/$(basename "$entry")"
    if [[ $(sha1sum < "$f" | cut -d' ' -f1) == "$sum" ]]; then found=$f; break; fi
  done < <(awk -F'\t' -v n="$name" 'BEGIN{n=tolower(n)} {k=$2; sub(/.*\//,"",k); if (tolower(k)==n) print}' "$work/index")
  if [[ -z $found ]]; then echo "$name: no zip entry with SHA-1 $sum"; rc=1; continue; fi
  docker exec immich_server mkdir -p "$(dirname "$path")"
  docker exec -i immich_server sh -c 'cat > "$1" && chown root:root "$1" && chmod 644 "$1"' _ "$path" < "$found"
  if [[ $(docker exec immich_server sha1sum "$path" | cut -d' ' -f1) == "$sum" ]]; then
    echo "$name: restored to $path (SHA-1 verified)"
  else
    echo "$name: copied but SHA-1 differs in place"; rc=1
  fi
done
exit $rc
