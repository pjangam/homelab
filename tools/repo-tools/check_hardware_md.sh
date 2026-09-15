#!/usr/bin/env bash
# List what is actually running on the homelab, plus every LAN address the
# tracked docs mention, that docs/hardware.md does not mention.
#
# docs/hardware.md is gitignored (it gathers addresses and service locations
# into one lookup), so git status never shows it going stale. This is the
# check to run before calling hardware work done - see CLAUDE.md.
#
# Usage: tools/repo-tools/check_hardware_md.sh [--no-pi]
# Exit:  0 nothing missing, 1 something missing, 2 hardware.md not found.
#
# Matching is a case-insensitive substring search, so a name only has to
# appear somewhere in the file. Write service names as they are spelled on
# the machine (`pihole`, not just "Pi-hole"). An address that is historical
# rather than a live device goes in hardware.md's "Retired addresses" line.

set -uo pipefail

PI_HOST=192.168.1.124
REPO=$(cd "$(dirname "$0")/../.." && pwd)
HW="$REPO/docs/hardware.md"
CHECK_PI=1
[ "${1:-}" = "--no-pi" ] && CHECK_PI=0

if [ ! -f "$HW" ]; then
    echo "docs/hardware.md not found - it is gitignored, so a fresh clone has none" >&2
    exit 2
fi

missing=0
check() {  # check <where> <name>
    if ! grep -qiF -- "$2" "$HW"; then
        printf '  %-14s %s\n' "$1" "$2"
        missing=1
    fi
}

echo "Not mentioned in docs/hardware.md:"

# xero: compose services, user units installed from this repo, cron scripts.
while read -r svc; do
    [ -n "$svc" ] && check "xero docker" "$svc"
done < <(cd "$REPO" && docker compose config --services 2>/dev/null)

while read -r unit; do
    path=$(systemctl --user show -p FragmentPath --value "$unit" 2>/dev/null)
    case "$path" in
        "$HOME"/.config/systemd/user/*) check "xero systemd" "${unit%.service}" ;;
    esac
done < <(systemctl --user list-unit-files --type=service --no-legend 2>/dev/null \
    | awk '$1 !~ /@/ {print $1}')

while read -r script; do
    check "xero cron" "$script"
done < <(crontab -l 2>/dev/null | grep -v '^\s*#' | grep -oE '[^ /]+\.(sh|py)' | sort -u)

# Pi: containers, non-packaged enabled units, cron scripts.
if [ "$CHECK_PI" = 1 ]; then
    pi_out=$(timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" '
        docker ps --format "docker {{.Names}}" 2>/dev/null
        for u in $(systemctl list-unit-files --type=service --state=enabled --no-legend | awk "\$1 !~ /@/ {print \$1}"); do
            p=$(systemctl show -p FragmentPath --value "$u")
            case "$p" in /etc/systemd/system/*) [ -L "$p" ] || echo "systemd ${u%.service}";; esac
        done
        crontab -l 2>/dev/null | grep -v "^\s*#" | grep -oE "[^ /]+\.(sh|py)" | sort -u | sed "s/^/cron /"
    ' 2>/dev/null)
    if [ $? -ne 0 ] && [ -z "$pi_out" ]; then
        echo "  (Pi at $PI_HOST unreachable - its checks were skipped, not passed)"
        missing=1
    fi
    while read -r kind name; do
        [ -n "${name:-}" ] && check "pi $kind" "$name"
    done <<< "$pi_out"
fi

# Every concrete LAN address the tracked docs mention - catches a device added
# by a project (the WLED board was) that nobody wrote up here.
while read -r ip; do
    check "address" "$ip"
done < <(grep -ohE '\b192\.168\.[0-9]+\.[0-9]+\b' "$REPO"/PROJECTS.md "$REPO"/Readme.md "$REPO"/*_setup.md 2>/dev/null \
    | grep -vE '\.(0|255)$' | sort -u)

[ "$missing" = 0 ] && echo "  (nothing)"
exit "$missing"
