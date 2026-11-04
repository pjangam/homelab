#!/bin/bash
# Updates /Applications/Chromium.app to the newest Chromium snapshot build.
#
# The Homebrew `chromium` cask was disabled on 2026-09-01 (fails Gatekeeper),
# so `brew upgrade` no longer moves it, and a snapshot build has no updater of
# its own - hence the "error code 0" on chrome://settings/help. This fetches
# the same snapshot zips the cask used, straight from Google's bucket.
#
# Meant for cron (see README.md). It does nothing while Chromium is running,
# and at most one download per MIN_AGE_HOURS, because snapshots land many
# times a day and each zip is ~200 MB.
#
#   chromium-update.sh            update if due
#   chromium-update.sh --check    print installed vs latest, change nothing
#   chromium-update.sh --force    ignore MIN_AGE_HOURS (still not while running)
set -euo pipefail

APP=${CHROMIUM_APP:-/Applications/Chromium.app}
MIN_AGE_HOURS=${MIN_AGE_HOURS:-24}
STAMP="$HOME/Library/Caches/chromium-update.last"
BUCKET=https://commondatastorage.googleapis.com/chromium-browser-snapshots
case "$(uname -m)" in arm64) PLATFORM=Mac_Arm ;; *) PLATFORM=Mac ;; esac

log() { echo "$(date '+%F %T') $*"; }

installed_rev() {
    # SCMRevision looks like "<sha>-refs/heads/main@{#1629771}"
    /usr/libexec/PlistBuddy -c 'Print :SCMRevision' "$1/Contents/Info.plist" 2>/dev/null \
        | sed -n 's/.*@{#\([0-9]*\)}.*/\1/p'
}

mode=${1:-}
latest=$(curl -fsS --max-time 30 "$BUCKET/$PLATFORM/LAST_CHANGE")
current=$(installed_rev "$APP" || true)

if [ "$mode" = --check ]; then
    echo "installed: r${current:-none}  latest: r$latest"
    exit 0
fi

if [ -n "$current" ] && [ "$current" -ge "$latest" ]; then
    exit 0
fi
if pgrep -qf "$APP/Contents/MacOS/Chromium"; then
    log "r${current:-none} -> r$latest pending: Chromium is running"
    exit 0
fi
if [ "$mode" != --force ] && [ -f "$STAMP" ] \
        && [ -z "$(find "$STAMP" -mmin +$((MIN_AGE_HOURS * 60)))" ]; then
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
log "downloading r$latest"
curl -fsS --max-time 900 -o "$work/chrome-mac.zip" "$BUCKET/$PLATFORM/$latest/chrome-mac.zip"
ditto -x -k "$work/chrome-mac.zip" "$work"
new="$work/chrome-mac/Chromium.app"
[ -x "$new/Contents/MacOS/Chromium" ] || { log "zip has no Chromium.app"; exit 1; }

# Swap, restoring the old bundle if the move-in fails.
[ -d "$APP" ] && mv "$APP" "$work/Chromium.old.app"
if ! mv "$new" "$APP"; then
    [ -d "$work/Chromium.old.app" ] && mv "$work/Chromium.old.app" "$APP"
    log "install failed, kept r${current:-none}"
    exit 1
fi
touch "$STAMP"
log "updated r${current:-none} -> r$(installed_rev "$APP")"
