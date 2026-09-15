#!/usr/bin/env bash
# Renews the ha-miraie-ac node's MirAIe login before it expires. Run daily
# from xero's crontab; it only acts when renewal is due.
#
# The node logs in once, when node-red starts, and never again. Its 5-minute
# status refresh (nodered_refresh_flow.json) and every MirAIe broker
# reconnect use that one token. A login lasts 84 days (`expiresIn` 7257599s,
# measured 2026-09-15 with check_miraie_token_lifetime.sh). The node has no
# way to log in again while running, so renewing means restarting node-red.
# That is done through fix_miraie_ac.sh --force, which checks DNS first,
# verifies both broker connections come back, and makes sure HA takes the
# entity back.
#
# Expiry is worked out from the container's StartedAt rather than a fixed
# date, because every node-red restart (the Pi watchdog, the fix script, the
# healthcheck auto-fix, a Pi reboot) logs in again and moves it. StartedAt is
# a few seconds before the actual login (DNS wait + npm install), so the
# estimate errs early. Renewal happens RENEW_BEFORE_DAYS before expiry, which
# leaves two weeks of daily retries if a renewal ever fails.
#
#   projects/miraie-ac/renew_miraie_login.sh           # renew only if due
#   projects/miraie-ac/renew_miraie_login.sh --force   # renew now
#
# Exit codes: 0 not due or renewed, 1 renewal failed (alerted), 2 could not
# read node-red's start time (Pi unreachable) - not alerted, the healthcheck
# already notices a dead AC.
set -uo pipefail

PI_HOST="${PI_HOST:-pramod@192.168.1.124}"
CONTAINER="node-red"
TOKEN_LIFETIME_DAYS="${TOKEN_LIFETIME_DAYS:-84}"
RENEW_BEFORE_DAYS="${RENEW_BEFORE_DAYS:-14}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
FIX_SCRIPT="${FIX_SCRIPT:-$HERE/fix_miraie_ac.sh}"
NOTIFY_DIR="${NOTIFY_DIR:-$REPO_ROOT/tools/notify}"

set -a
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env.healthcheck" ] && . "$REPO_ROOT/.env.healthcheck"
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env.ntfy" ] && . "$REPO_ROOT/.env.ntfy"
set +a
# shellcheck disable=SC1091
. "$NOTIFY_DIR/send_email.sh"
# shellcheck disable=SC1091
. "$NOTIFY_DIR/push_ntfy.sh"

force=0
[ "${1:-}" = "--force" ] && force=1

log() { echo "[$(date '+%F %T')] $*"; }

started_epoch() {
  local s
  s="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$PI_HOST" "docker inspect -f '{{.State.StartedAt}}' $CONTAINER" 2>/dev/null)" || return 1
  date -d "$s" +%s 2>/dev/null
}

fmt() { date -d "@$1" '+%F %H:%M'; }

if ! started="$(started_epoch)" || [ -z "$started" ]; then
  log "Cannot read $CONTAINER's start time from $PI_HOST - skipping."
  exit 2
fi

expires=$(( started + TOKEN_LIFETIME_DAYS * 86400 ))
renew_at=$(( expires - RENEW_BEFORE_DAYS * 86400 ))
now=$(date +%s)

if [ "$force" -eq 0 ] && [ "$now" -lt "$renew_at" ]; then
  log "Login from $(fmt "$started") expires ~$(fmt "$expires"); renewal due $(fmt "$renew_at"). Nothing to do."
  exit 0
fi

log "Renewing: login from $(fmt "$started") expires ~$(fmt "$expires")$([ "$force" -eq 1 ] && echo ' (--force)'). Restarting $CONTAINER via fix_miraie_ac.sh --force"
output="$("$FIX_SCRIPT" --force 2>&1)"
fix_rc=$?
printf '%s\n' "$output" | sed 's/^/  /'

# Exit 2 (the AC is off the cloud) and 3 (HA-side) both come after the
# bridge reconnected to the MirAIe cloud, which needs the new login - so the
# renewal itself worked. Whatever is wrong with the AC or HA is the
# healthcheck's to report, not this script's.
new_started="$(started_epoch)"
if { [ "$fix_rc" -eq 0 ] || [ "$fix_rc" -eq 2 ] || [ "$fix_rc" -eq 3 ]; } \
   && [ -n "$new_started" ] && [ "$new_started" -gt "$started" ]; then
  log "Renewed (fix exit $fix_rc). New login expires ~$(fmt $(( new_started + TOKEN_LIFETIME_DAYS * 86400 )))."
  exit 0
fi

days_left=$(( (expires - now) / 86400 ))
log "FAILED: fix exit $fix_rc, start time $( [ -n "$new_started" ] && fmt "$new_started" || echo unknown)."
body="The MirAIe login used by Node-RED on the Pi expires around $(fmt "$expires") (${days_left} days left), and renewing it by restarting node-red failed (fix_miraie_ac.sh exit $fix_rc). This retries daily. After expiry the 5-minute AC status refresh stops working and a broker reconnect cannot log in.

Run projects/miraie-ac/renew_miraie_login.sh --force by hand once the cause is fixed. Output:

$output"
send_email "[homelab] MirAIe login renewal failed" "$body" || true
push_ntfy "homelab: MirAIe login renewal failed" "Node-RED's MirAIe login expires ~$(fmt "$expires") (${days_left}d left) and the restart to renew it failed (exit $fix_rc). Details in email / miraie-login-renew.log."
exit 1
