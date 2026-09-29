#!/usr/bin/env bash
# Review-first: family uploads land in a hidden inbox and reach the album only
# through here.
#
#   services/albums/review.sh list                 what is waiting, and who sent it
#   services/albums/review.sh approve <file>...    move into the album's from-family/
#   services/albums/review.sh approve --all
#   services/albums/review.sh reject <file>...     delete
#
# To look at the files first, open the SMB share "albums" -> _inbox/ on the
# Mac or phone (they are plain photos/videos; the upload hooks already refused
# anything else). Inbox and album are on the same ZFS dataset, so approving is
# a rename: copies=2 carries over, nothing is rewritten.
set -euo pipefail

inbox=/datapool/albums/_inbox/ojaswi-1st-birthday
dest=/datapool/albums/ojaswi-1st-birthday/from-family
log=$inbox/.upload-log.tsv

pending() { find "$inbox" -maxdepth 1 -type f ! -name '.*' ! -name '*.PARTIAL' -printf '%f\n' | sort; }

case "${1:-}" in
list)
    files=$(pending)
    [[ -n $files ]] || { echo "inbox empty"; exit 0; }
    while read -r f; do
        who=$(awk -F'\t' -v f="$f" '$4==f && $6=="ok" {print $2" at "$1}' "$log" 2>/dev/null | tail -1)
        printf '%-45s %8s  %s\n' "$f" "$(du -h --apparent-size "$inbox/$f" | cut -f1)" "${who:-?}"
    done <<<"$files"
    ;;
approve)
    shift
    [[ ${1:-} == --all ]] && mapfile -t files < <(pending) || files=("$@")
    [[ ${#files[@]} -gt 0 ]] || { echo "nothing to approve" >&2; exit 1; }
    mkdir -p "$dest"
    for f in "${files[@]}"; do
        [[ -f $inbox/$f ]] || { echo "not in inbox: $f" >&2; continue; }
        mv -n "$inbox/$f" "$dest/$f" && echo "approved $f"
        [[ -f $inbox/$f ]] && echo "SKIPPED $f: a file with that name is already in the album" >&2
    done
    ;;
reject)
    shift
    [[ $# -gt 0 ]] || { echo "usage: review.sh reject <file>..." >&2; exit 1; }
    for f in "$@"; do rm -v -- "$inbox/$f"; done
    ;;
*)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
