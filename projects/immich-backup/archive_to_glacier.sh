#!/usr/bin/env bash
# Off-site copy of Immich's originals in S3 Glacier Deep Archive: the copy we
# read only if the Kingston SSD and the local backup are both lost. Run on
# xero, monthly from cron:
#   archive_to_glacier.sh [--dry-run]
#
# Every original Immich knows (its asset table, every user and the external
# libraries) that is not yet archived goes into tar bundles of up to
# BUNDLE_MAX bytes, each encrypted with gpg (BACKUP_PASSPHRASE, as the other
# backups) and uploaded as one DEEP_ARCHIVE object. Bundling turns ~18k files
# into a few dozen objects, which is what Deep Archive bills per (requests
# and ~40KB of overhead each); compressing would gain nothing on
# JPEG/HEIC/H.264. Photo dates play no part: a 2012 photo imported today is
# simply not archived yet. The newest of Immich's nightly DB dumps (albums,
# faces, people) and the manifest go up with every run. Objects are only ever
# added: Immich never rewrites an original, which suits Deep Archive's
# 180-day minimum, and the key on xero cannot delete. Transcodes and
# thumbnails are left out: Immich rebuilds them.
#
# A file's bytes are uploaded once, by Immich's SHA-1. Another path with the
# same SHA-1 - the same photo in two users' libraries, or a file Immich moved
# from upload/ to library/ after it was archived - goes in the manifest as an
# alias of the archived copy, so a restore puts it at every path. (For
# external-library assets - the birthday album - Immich's checksum hashes
# the path, not the bytes, so those never alias.)
#
# State: backups/immich-archive/manifest.tsv: sha1, size, object, host path;
# for an alias the object is "alias:<host path of the archived copy>".
# Appended after each bundle's upload is verified, so a run that dies resumes
# where it stopped. Bundles are streamed (tar | gpg | rclone rcat), so the
# SSD is read only as fast as the upload goes (~3MB/s): written to a file
# first, each 4G bundle was read in ~20s, a burst that took the Kingston to
# 66C (it is rated to 70C; long bulk reads on 2026-10-22 had it at 84-87C).
# tee counts the bytes for the size check.
#
# Restore (not with xero's key - it cannot restore or read; use an admin one):
#   rclone backend restore "$REMOTE" -o priority=Bulk -o lifetime=14
#   # ~48h later:
#   rclone copy "$REMOTE" restore/
#   for b in restore/bundles/*.gpg; do gpg -d "$b" | tar -xC /; done
#   gpg -d "$(ls restore/manifest/*.gpg | tail -1)" > manifest.tsv
#   awk -F'\t' '$3 ~ /^alias:/ {print substr($3, 7) "\t" $4}' manifest.tsv |
#     while IFS=$'\t' read -r src dst; do mkdir -p "${dst%/*}"; [[ -e $dst ]] || cp -p "$src" "$dst"; done
#   # then restore/db/ (newest) into a fresh Immich
#
# Requires in .env: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (the upload-only
# user, iam-policy.json) and IMMICH_BACKUP_BUCKET; BACKUP_PASSPHRASE in
# .env.backup.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
dry=${1:-}
env_val() { sed -n "s/^$1=//p" .env | tail -1; }
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-$(env_val AWS_ACCESS_KEY_ID)}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-$(env_val AWS_SECRET_ACCESS_KEY)}
BUCKET=${IMMICH_BACKUP_BUCKET:-$(env_val IMMICH_BACKUP_BUCKET)}
if [[ -z "${BACKUP_PASSPHRASE:-}" && -f .env.backup ]]; then source .env.backup; fi
for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY BUCKET BACKUP_PASSPHRASE; do
  [[ -n ${!v} ]] || { echo "ERROR: $v is not set (.env / .env.backup)"; exit 1; }
done

# IMMICH_ARCHIVE_REMOTE / _STATE point a test run at a local folder instead;
# _MOUNTS / _ASSETS (container dir \t host dir; sha1 \t container path) stand
# in for immich_server's mounts and the asset table (test_archive.sh).
REMOTE=${IMMICH_ARCHIVE_REMOTE:-":s3,provider=AWS,env_auth=true,region=us-east-1:$BUCKET/immich"}
# 128M parts: Deep Archive bills every part as a request (~$0.05/1000), and
# rclone's 5M default would make a 4G bundle 800 of them.
# --s3-no-head: rclone's read-back after an upload is refused by the
# upload-only key (403, then a retry "succeeds" by finding the object); the
# size check in upload() lists the object instead.
RCLONE=(rclone --s3-storage-class DEEP_ARCHIVE --s3-no-check-bucket --s3-no-head
        --s3-chunk-size 128M --s3-upload-concurrency 2)
BUNDLE_MAX=${BUNDLE_MAX:-4000000000}
MAX_BUNDLES=${MAX_BUNDLES:-0}   # stop after this many bundles (0: no limit); the rest go next run
STATE=${IMMICH_ARCHIVE_STATE:-"$REPO/backups/immich-archive"}
MANIFEST="$STATE/manifest.tsv"
U=$(env_val DB_USERNAME); D=$(env_val DB_DATABASE_NAME)
mkdir -p "$STATE"; touch "$MANIFEST"
work=$(mktemp -d "$STATE/.run.XXXXXX")
trap 'rm -rf "$work"' EXIT
log() { echo "[$(date)] $*"; }

# Container path -> host path, from immich_server's own bind mounts.
if [[ -n ${IMMICH_ARCHIVE_MOUNTS:-} ]]; then cp "$IMMICH_ARCHIVE_MOUNTS" "$work/mounts"; else
  docker inspect immich_server --format \
    '{{range .Mounts}}{{if eq .Type "bind"}}{{.Destination}}{{"\t"}}{{.Source}}{{"\n"}}{{end}}{{end}}' \
    | awk -F'\t' 'NF==2' > "$work/mounts"
fi
assets() {
  if [[ -n ${IMMICH_ARCHIVE_ASSETS:-} ]]; then cat "$IMMICH_ARCHIVE_ASSETS"; else
    docker exec immich_postgres psql -U "$U" -d "$D" -AtF $'\t' -c \
      "select encode(checksum, 'hex'), \"originalPath\" from asset order by \"originalPath\""
  fi
}

# Every asset as sha1 \t host path, for files that exist.
assets |
  while IFS=$'\t' read -r sum path; do
    host=
    while IFS=$'\t' read -r dst src; do
      [[ $path == "$dst"/* ]] && { host=$src${path#"$dst"}; break; }
    done < "$work/mounts"
    if [[ -z $host || ! -f $host ]]; then echo "missing on disk: $path" >&2; continue; fi
    printf '%s\t%s\n' "$sum" "$host"
  done > "$work/assets"

# Paths the manifest already has are done. Of the rest, the first path of a
# SHA-1 not yet archived is new (bundled below); any other is an alias, of
# the archived copy or of that first path:
#   new:     sha1 \t host path
#   aliases: sha1 \t source host path \t alias host path
# (FILENAME, not NR==FNR: the first run's manifest is empty.)
awk -F'\t' -v OFS='\t' -v m="$MANIFEST" -v a="$work/aliases" '
  FILENAME == m { have[$4]; if ($3 ~ /^bundles\// && !($1 in src)) src[$1] = $4; next }
  $2 in have   { next }
  $1 in src    { print $1, src[$1], $2 > a; next }
  $1 in first  { print $1, first[$1], $2 > a; next }
               { first[$1] = $2; print }' "$MANIFEST" "$work/assets" > "$work/newpaths"
touch "$work/aliases"
while IFS=$'\t' read -r sum host; do
  printf '%s\t%s\t%s\n' "$sum" "$(stat -c %s "$host")" "$host"
done < "$work/newpaths" > "$work/new"

n=$(wc -l < "$work/new")
bytes=$(awk -F'\t' '{s+=$2} END {print s+0}' "$work/new")
log "$n originals to archive ($((bytes / 1000000)) MB), $(wc -l < "$work/aliases") paths sharing an archived file"
[[ $dry == --dry-run ]] && { log "dry run, nothing uploaded"; exit 0; }

check_size() {  # object name, expected bytes
  local remote; remote=$("${RCLONE[@]}" lsf --format s "$REMOTE/$1")
  [[ $remote == "$2" ]] || { log "ERROR: $1 is $remote bytes remote, $2 sent"; exit 1; }
}
upload() {   # local file, object name under $REMOTE
  "${RCLONE[@]}" copyto "$1" "$REMOTE/$2"
  check_size "$2" "$(stat -c %s "$1")"
}
encrypt() {  # gpg stdin -> $1 (- for stdout)
  gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
      --symmetric --cipher-algo AES256 --compress-algo none --output "$1" 3<<<"$BACKUP_PASSPHRASE"
}

# Split into bundles; one file larger than BUNDLE_MAX gets a bundle to itself.
awk -F'\t' -v max="$BUNDLE_MAX" -v dir="$work" '
  { if (size > 0 && size + $2 > max) { close(f); b++; size = 0 }
    size += $2; f = dir "/bundle." sprintf("%03d", b); print > f }' "$work/new"

stamp=$(date +%Y-%m-%d)
# Numbering carries on from earlier runs, so no object name is ever reused.
seq=$(cut -f3 "$MANIFEST" | { grep '^bundles/' || true; } | sort -u | wc -l)
uploaded=0
for list in "$work"/bundle.*; do
  [[ -e $list ]] || break
  if [[ $MAX_BUNDLES -gt 0 && $uploaded -ge $MAX_BUNDLES ]]; then log "MAX_BUNDLES=$MAX_BUNDLES reached, the rest next run"; break; fi
  name=$(printf "bundles/%s-%05d.tar.gpg" "$stamp" "$seq"); seq=$((seq + 1))
  log "uploading $name ($(awk -F'\t' '{s+=$2} END {printf "%d", s/1e6}' "$list") MB, $(wc -l < "$list") files)"
  rm -f "$work/count"
  cut -f3 "$list" | sed 's#^/##' | tr '\n' '\0' |
    nice -n 10 ionice -c3 tar -C / --null -T - -cf - | encrypt - |
    tee >(wc -c > "$work/count") | "${RCLONE[@]}" rcat "$REMOTE/$name"
  for _ in {1..30}; do [[ -s $work/count ]] && break; sleep 1; done   # wc runs behind tee
  check_size "$name" "$(cat "$work/count")"
  awk -F'\t' -v obj="$name" 'BEGIN {OFS="\t"} {print $1, $2, obj, $3}' "$list" >> "$MANIFEST"
  uploaded=$((uploaded + 1))
done

# Aliases, once their source is in an uploaded bundle (one whose bundle
# MAX_BUNDLES held back waits for the next run).
awk -F'\t' -v OFS='\t' -v m="$MANIFEST" '
  FILENAME == m { if ($3 ~ /^bundles\//) ok[$4]; next }
  $2 in ok      { print $1, "-", "alias:" $2, $3 }' "$MANIFEST" "$work/aliases" > "$work/alias-lines"
aliased=$(wc -l < "$work/alias-lines")
cat "$work/alias-lines" >> "$MANIFEST"

dump=$(ls -1 /datapool/immich-upload/backups/immich-db-backup-*.sql.gz 2>/dev/null | tail -1)
if [[ -n $dump ]] && ! grep -qF "db/$(basename "$dump").gpg" "$MANIFEST"; then
  encrypt "$work/db.gpg" < "$dump"
  upload "$work/db.gpg" "db/$(basename "$dump").gpg"
  printf 'db\t%s\tdb/%s.gpg\t%s\n' "$(stat -c %s "$dump")" "$(basename "$dump")" "$dump" >> "$MANIFEST"
  uploaded=$((uploaded + 1))
fi

if [[ $uploaded -gt 0 || $aliased -gt 0 ]]; then
  encrypt "$work/manifest.gpg" < "$MANIFEST"
  upload "$work/manifest.gpg" "manifest/manifest-$(date +%Y%m%d_%H%M%S).tsv.gpg"
fi
log "Immich archive complete: $uploaded objects uploaded, $aliased aliases recorded"
