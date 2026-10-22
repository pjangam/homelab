#!/usr/bin/env bash
# Exercises archive_to_glacier.sh against a local folder as the remote and a
# made-up asset table, then restores and checks every path. Uploads nothing;
# needs only BACKUP_PASSPHRASE (.env.backup). Run on xero:
#   projects/immich-backup/test_archive.sh [script]   # default: archive_to_glacier.sh
# Covers: the same file at two paths (two users) uploaded once and aliased;
# an alias whose source bundle MAX_BUNDLES held back, recorded next run; a
# file Immich moved after it was archived; a re-run that does nothing.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script=$(realpath "${1:-$here/archive_to_glacier.sh}")
cd "$here/../.."
source .env.backup
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t"/host/u1 "$t"/host/u2 "$t"/remote "$t"/state "$t"/restore
printf '/c\t%s\n' "$t/host" > "$t/mounts"
head -c 300000 /dev/urandom > "$t/host/u1/a.jpg"
head -c 300000 /dev/urandom > "$t/host/u1/b.jpg"
cp "$t/host/u1/a.jpg" "$t/host/u2/a.jpg"; cp "$t/host/u1/b.jpg" "$t/host/u2/b.jpg"
sha() { sha1sum < "$1" | cut -d' ' -f1; }
A=$(sha "$t/host/u1/a.jpg"); B=$(sha "$t/host/u1/b.jpg")
export IMMICH_ARCHIVE_REMOTE=$t/remote IMMICH_ARCHIVE_STATE=$t/state \
       IMMICH_ARCHIVE_MOUNTS=$t/mounts IMMICH_ARCHIVE_ASSETS=$t/assets \
       AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x IMMICH_BACKUP_BUCKET=x BUNDLE_MAX=1
run() { echo "== $1"; shift; env "$@" "$script" | grep -v ' uploading '; }
fail=0; expect() { [[ $2 == "$3" ]] && echo "ok   $1" || { echo "FAIL $1: got '$2', want '$3'"; fail=1; }; }

printf '%s\t/c/u1/a.jpg\n%s\t/c/u1/b.jpg\n%s\t/c/u2/a.jpg\n%s\t/c/u2/b.jpg\n' "$A" "$B" "$A" "$B" > "$t/assets"
run "run 1: two users share a and b; only one bundle allowed" MAX_BUNDLES=1
expect "a uploaded once"             "$(grep -c "^$A.*bundles/" "$t/state/manifest.tsv")" 1
expect "u2/a aliased to u1/a"        "$(grep -c "alias:$t/host/u1/a.jpg	$t/host/u2/a.jpg" "$t/state/manifest.tsv")" 1
expect "u2/b waits (b not uploaded)" "$(grep -c "u2/b.jpg" "$t/state/manifest.tsv" || true)" 0

mkdir -p "$t/host/lib"; mv "$t/host/u1/a.jpg" "$t/host/lib/a.jpg"   # Immich moves it
head -c 300000 /dev/urandom > "$t/host/u1/c.jpg"; C=$(sha "$t/host/u1/c.jpg")
printf '%s\t/c/lib/a.jpg\n%s\t/c/u1/b.jpg\n%s\t/c/u2/a.jpg\n%s\t/c/u2/b.jpg\n%s\t/c/u1/c.jpg\n' "$A" "$B" "$A" "$B" "$C" > "$t/assets"
run "run 2: a moved, c is new, b's bundle goes up"
expect "a not uploaded again"        "$(grep -c "^$A.*bundles/" "$t/state/manifest.tsv")" 1
expect "b and c uploaded"            "$(grep -cE "^($B|$C).*bundles/" "$t/state/manifest.tsv")" 2
expect "lib/a aliased to u1/a"       "$(grep -c "alias:$t/host/u1/a.jpg	$t/host/lib/a.jpg" "$t/state/manifest.tsv")" 1
expect "u2/b aliased to u1/b"        "$(grep -c "alias:$t/host/u1/b.jpg	$t/host/u2/b.jpg" "$t/state/manifest.tsv")" 1
before=$(find "$t/remote" -type f | wc -l)
run "run 3: nothing new"
expect "run 3 uploads nothing"       "$(find "$t/remote" -type f | wc -l)" "$before"

# Restore as the script's header says, under $t/restore instead of /.
for b in "$t"/remote/bundles/*.gpg; do
  gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d "$b" 3<<<"$BACKUP_PASSPHRASE" | tar -xC "$t/restore"
done
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d "$(ls "$t"/remote/manifest/*.gpg | tail -1)" \
  3<<<"$BACKUP_PASSPHRASE" > "$t/m.tsv"
awk -F'\t' '$3 ~ /^alias:/ {print substr($3, 7) "\t" $4}' "$t/m.tsv" |
  while IFS=$'\t' read -r src dst; do d=$t/restore$dst; mkdir -p "${d%/*}"; [[ -e $d ]] || cp -p "$t/restore$src" "$d"; done
while IFS=$'\t' read -r s p; do
  f=$t/restore$t/host${p#/c}
  expect "restored ${p#/c/}" "$([[ -f $f ]] && sha "$f")" "$s"
done < "$t/assets"
exit $fail
