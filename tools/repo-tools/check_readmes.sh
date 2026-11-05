#!/usr/bin/env bash
# Every project/service/tool folder must say what it is, in its own README.md,
# and must be listed in the root Readme.md's folder index (added 2026-11-05,
# after projects/smart-switch shipped without an index line).
#
# The rule is in CLAUDE.md, and it is deliberately tied to the folder existing
# rather than to the work finishing: a half-built project is exactly when
# "what is this and what runs it" is hardest to reconstruct, and the folder
# outlives whoever remembered. Same reason as the docs/hardware.md and
# endpoints.toml rules, one level up.
#
#   check_readmes.sh            # every folder; exits 1 if any has no README
#   check_readmes.sh --staged   # only folders this commit adds files to
#
# --staged is what .githooks/pre-commit runs: it cannot fail a commit for the
# repo's existing state, only for a folder the commit itself creates.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# The four homes, plus the deferred groups that still live outside them
# (scripts/, esp32/ - see the layout rules in CLAUDE.md).
HOMES=(projects services tools scripts esp32)
# Folders the root Readme.md indexes. The deferred scripts/ and esp32/ groups
# are not indexed until they move (CLAUDE.md).
INDEXED=(projects services tools)

folders_with_tracked_files() {
    local home
    for home in "${HOMES[@]}"; do
        git ls-files "$home" | awk -F/ 'NF>2 {print $1"/"$2}'
    done | sort -u
}

staged_folders() {
    git diff --cached --name-only --diff-filter=A \
        | awk -F/ 'NF>2 {print $1"/"$2}' | sort -u
}

if [ "${1:-}" = "--staged" ]; then
    mode=staged
    candidates=$(staged_folders)
else
    mode=all
    candidates=$(folders_with_tracked_files)
fi

missing=()
unindexed=()
while read -r dir; do
    [ -n "${dir:-}" ] || continue
    case "$dir" in */) continue ;; esac
    # Only the five homes above; a staged path elsewhere is not in scope.
    printf '%s\n' "${HOMES[@]}" | grep -qx "${dir%%/*}" || continue
    [ -f "$dir/README.md" ] || missing+=("$dir")
    if printf '%s\n' "${INDEXED[@]}" | grep -qx "${dir%%/*}"; then
        grep -qF "$dir/" Readme.md || unindexed+=("$dir")
    fi
done <<< "$candidates"

if [ ${#unindexed[@]} -gt 0 ]; then
    echo "[check-readmes] Not listed in the root Readme.md's folder index:"
    printf '  - %s/\n' "${unindexed[@]}"
    echo "Add a line to its table (### projects/, services/ or tools/)."
    echo
fi

if [ ${#missing[@]} -eq 0 ]; then
    [ ${#unindexed[@]} -gt 0 ] && exit 1
    [ "$mode" = all ] && echo "Every project/service/tool folder has a README.md and is in the root index."
    exit 0
fi

if [ "$mode" = staged ]; then
    echo "[check-readmes] This commit adds files to a folder with no README.md:"
else
    echo "[check-readmes] Folders with tracked files but no README.md:"
fi
printf '  - %s/\n' "${missing[@]}"
echo
echo "Write one saying what it is, what runs it and where its state lives -"
echo "see CLAUDE.md. Bypass a genuine exception with: git commit --no-verify"
exit 1
