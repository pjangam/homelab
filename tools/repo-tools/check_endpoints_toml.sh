#!/usr/bin/env bash
# List every host port docker-compose.yml publishes, and every path the
# Caddyfile handles, that projects/endpoints/endpoints.toml does not mention.
#
# endpoints.toml is the source of the endpoint index served at
# /endpoints (see projects/endpoints/README.md). Nothing makes it match
# reality, so a service that arrives or moves silently leaves the page wrong -
# which is exactly the "where do I open it" problem the page was built to fix.
# This is the check to run before calling a project done - see CLAUDE.md.
#
# Usage: tools/repo-tools/check_endpoints_toml.sh
# Exit:  0 nothing missing, 1 something missing, 2 endpoints.toml not found.
#
# Deliberately reads the TRACKED files (docker-compose.yml, the Caddyfile)
# rather than the live machines, unlike check_hardware_md.sh - so it runs on
# any clone, needs no .env and no ssh, and can run before a change is deployed.
# The cost is that it cannot see anything not in compose: the systemd --user
# services (clawlight on 8126), the Pi, and the ESP32's UDP feeds are all on
# the page but invisible to this check. Adding one of those is on you.
#
# Matching is a plain substring search for the number or path, so a port
# mentioned anywhere in the file - including in a note - counts.

set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
TOML="$REPO/projects/endpoints/endpoints.toml"
COMPOSE="$REPO/docker-compose.yml"
CADDY="$REPO/services/caddy/Caddyfile"

if [ ! -f "$TOML" ]; then
    echo "projects/endpoints/endpoints.toml not found" >&2
    exit 2
fi

missing=0
check() {  # check <where> <needle> [label]
    if ! grep -qF -- "$2" "$TOML"; then
        printf '  %-16s %s\n' "$1" "${3:-$2}"
        missing=1
    fi
}

# Published host ports. Strips comments first so the commented-out Immich
# block does not register as live, then takes the HOST port - the field before
# the container port, which is NF-1 once the optional /tcp|/udp is gone. Doing
# it by field rather than by regex is what makes the loopback-bound
# "127.0.0.1:8127:80" yield 8127 and not some fragment of the IP address.
while read -r port; do
    [ -n "$port" ] && check "compose port" "$port" "$port (published in docker-compose.yml)"
done < <(sed 's/#.*//' "$COMPOSE" \
    | grep -oE '^[[:space:]]*-[[:space:]]*"?[0-9.]+:[0-9]+(:[0-9]+)?(/(tcp|udp))?"?[[:space:]]*$' \
    | tr -d ' "-' | sed 's#/tcp$##; s#/udp$##' \
    | awk -F: 'NF >= 2 { print $(NF-1) }' | sort -un)

# Caddy path matchers - `@name path /foo /foo/*` - so a new handle that is not
# on the page is caught. Trailing slashes are stripped before the sort so the
# `/foo` and `/foo/*` forms of one handle report as a single finding. The catch-all `handle {` block has no matcher and is
# Vaultwarden, which the page lists by URL rather than by path.
while read -r path; do
    [ -n "$path" ] && check "caddy path" "$path" "$path (handled in the Caddyfile)"
done < <(sed 's/#.*//' "$CADDY" \
    | grep -oE '^[[:space:]]*@[a-zA-Z0-9_-]+[[:space:]]+path[[:space:]]+.*' \
    | grep -oE '/[a-zA-Z0-9_/-]+' | sed 's#/*$##' | sort -u)

if [ "$missing" = 0 ]; then
    echo "endpoints.toml mentions every published port and Caddy path."
    exit 0
fi

echo
echo "Add these to projects/endpoints/endpoints.toml, then re-render on xero:"
echo "  projects/endpoints/render_endpoints.py"
exit 1
