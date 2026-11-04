# tools/chromium-update/

Keeps `/Applications/Chromium.app` on the Mac current. It runs from the Mac's
crontab, not on xero.

Chromium snapshot builds have no updater, so `chrome://settings/help` always
shows "An error occurred while checking for updates: 0". The Homebrew
`chromium` cask used to cover this, but Homebrew disabled it on 2026-09-01
because it fails the Gatekeeper check. Since then `brew upgrade` does nothing.
`chromium-update.sh` downloads the same snapshot zips the cask did, straight
from `commondatastorage.googleapis.com/chromium-browser-snapshots`.

```
tools/chromium-update/chromium-update.sh --check   # installed vs latest revision
tools/chromium-update/chromium-update.sh           # update if due
tools/chromium-update/chromium-update.sh --force   # skip the once-a-day limit
```

It never replaces the app while Chromium is running. It also downloads at most
once every `MIN_AGE_HOURS` (24 by default), because snapshots land many times a
day and each zip is about 200 MB. The time of the last update is stored in
`~/Library/Caches/chromium-update.last`.

## Cron

```
# Chromium snapshot update; acts only when Chromium is closed, at most once a day
15 */2 * * * $HOME/code/personal/homelab/tools/chromium-update/chromium-update.sh >> "$HOME/Library/Logs/chromium-update.log" 2>&1
```

It runs every two hours so that one of the runs finds the browser closed.

## History

An earlier attempt was the launch agent `~/Library/LaunchAgents/com.slaunchaman.chromium.plist`,
copied from someone else's setup. It ran `/Users/slauncha/bin/chromiupdate`, a
path that has never existed on this Mac, so it failed every hour (exit 78)
without anyone noticing. It was removed on 2026-11-04 when this script replaced it.
