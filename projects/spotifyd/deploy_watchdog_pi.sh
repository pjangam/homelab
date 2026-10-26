#!/usr/bin/env bash
# Run this ON XERO. Installs watchdog_spotifyd.sh on the wol Pi, where spotifyd
# has run since the 2026-09-24 cutover, and gives it the */5 cron line xero's
# crontab used to carry. The cutover moved spotifyd but not its watchdog, so
# until 2026-10-26 nothing on the Pi restarted a stuck spotifyd.
#
# Same layout as deploy_audio_pi.sh: no repo clone on the Pi, files go under
# ~/homelab at their repo paths. Re-run after changing the watchdog; the cron
# line is only added once. No sudo: the watchdog restarts a user unit.
set -euo pipefail

PI="pramod@192.168.1.124"
PI_ROOT="/home/pramod/homelab"
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"

"$REPO/projects/spotifyd/test_watchdog_spotifyd.sh" >/dev/null \
  || { echo "watchdog tests fail - not deploying" >&2; exit 1; }

ssh "$PI" "mkdir -p $PI_ROOT/projects/spotifyd"
scp -q "$REPO/projects/spotifyd/watchdog_spotifyd.sh" "$PI:$PI_ROOT/projects/spotifyd/"

# Only $PI_ROOT crosses as an argument: ssh joins its args into one remote
# shell string, so a cron line passed that way gets its * globbed and its >>
# run as a redirect on the Pi. The line is built over there instead.
ssh "$PI" bash -s -- "$PI_ROOT" <<'REMOTE'
set -euo pipefail
root=$1
line="*/5 * * * * $root/projects/spotifyd/watchdog_spotifyd.sh >> $root/spotifyd-watchdog.log 2>&1"
chmod +x "$root/projects/spotifyd/watchdog_spotifyd.sh"
current=$(crontab -l 2>/dev/null || true)
if grep -qF "projects/spotifyd/watchdog_spotifyd.sh" <<<"$current"; then
  echo "cron line already present"
else
  printf '%s\n%s\n' "$current" "$line" | sed '/^$/d' | crontab -
  echo "cron line added"
fi
# One run now, so a broken install shows here rather than in five minutes.
"$root/projects/spotifyd/watchdog_spotifyd.sh" && echo "watchdog ran clean"
tail -3 "$HOME/.cache/spotifyd-watchdog/restarts.log" 2>/dev/null || echo "no restarts logged"
REMOTE
