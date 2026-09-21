#!/usr/bin/env bash
# Rewrite every file in a ZFS dataset so it picks up the dataset's current
# `copies` setting. `copies` only applies to blocks written after it is set,
# so data that was already there keeps its old number of copies until it is
# rewritten.
#
# Each file is copied with dd into a temp file next to it, checked with
# sha256, then renamed over the original (keeping mode, owner and mtime).
# It has to be dd: this pool has block cloning enabled, and cp - and even
# cat, since coreutils 9 - use copy_file_range, which ZFS answers by
# pointing at the same single-copy blocks instead of writing new ones.
# The first run of this script used cat and changed nothing (2026-09-21).
# Check with `zpool get bcloneused datapool`: it must stay 0 while this runs.
#
# Usage: rewrite_for_copies.sh [dir]   (default /datapool/phone-uploads)
# Needs free space for the largest file times the copies count. Safe to
# re-run: a rerun rewrites everything again, it just costs time.
set -euo pipefail

dir=${1:-/datapool/phone-uploads}
ds=$(zfs list -H -o name "$dir")

report() { zfs get -H -o property,value used,logicalused,copies "$ds" | tr '\n' ' '; echo; }
echo "before: $(report)"

n=0
while IFS= read -r -d '' f; do
    tmp="$(dirname "$f")/.rewrite.$$.$(basename "$f")"
    dd if="$f" of="$tmp" bs=4M status=none
    if [ "$(sha256sum < "$f")" != "$(sha256sum < "$tmp")" ]; then
        rm -f -- "$tmp"
        echo "MISMATCH, left untouched: $f" >&2
        exit 1
    fi
    chmod --reference="$f" -- "$tmp"
    touch --reference="$f" -- "$tmp"
    mv -f -- "$tmp" "$f"
    n=$((n + 1))
    echo "[$n] $f"
done < <(find "$dir" -type f ! -name '.rewrite.*' -print0)

# Freed blocks are released asynchronously; give the numbers a moment.
zpool sync "${ds%%/*}" 2>/dev/null || sync
echo "rewrote $n files"
echo "after:  $(report)"
