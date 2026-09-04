#!/usr/bin/env bash
# Renews the Tailscale TLS certs that Caddy serves for xero.<tailnet>, and
# makes failure loud instead of silent.
#
# Background: the previous inline crontab entry failed silently for three
# months (Jul/Aug/Sep 2026). Two reasons, both fixed here:
#   1. It used `sudo tailscale cert`, but sudoers only grants NOPASSWD for
#      `shutdown`. Cron has no TTY, so sudo failed instantly every time.
#      Fixed by `tailscale set --operator=$USER` (run once, manually), which
#      lets this run unprivileged - no sudoers exception needed.
#   2. Its `>> log 2>&1` bound only to the LAST command of an && chain, so the
#      failing first command's output went to unread cron mail. This script
#      logs every run, and pushes an ntfy alert if anything goes wrong.
#
# Renewal is a no-op unless the cert is near expiry - tailscaled returns the
# cached cert - so this is safe to run often. Run WEEKLY, not monthly: a
# monthly job that fails has no second chance before a 90-day cert lapses.
set -uo pipefail
cd "$(dirname "$0")/.."

CERT_DIR="certs"
LOG="cert-renew.log"
WARN_DAYS=21   # alert if the cert would still be this close to expiry after a run
# Without --min-validity, `tailscale cert` only guarantees the cert is not
# ALREADY EXPIRED - it will happily hand back one with days left and report
# success. That is the second reason the old cron entry never renewed anything.
# Asking for 30d forces reissue once the cert drops below that, which with a
# 90-day LE cert and a weekly run leaves ~4 weeks of retries.
MIN_VALIDITY="720h"   # 30 days; Go duration syntax has no "d" unit

# shellcheck disable=SC1091
[ -f .env ] && . ./.env
[ -f .env.ntfy ] && . ./.env.ntfy

HOSTNAME_FQDN="xero.${TAILNET_SUFFIX}"
CRT="$CERT_DIR/$HOSTNAME_FQDN.crt"
KEY="$CERT_DIR/$HOSTNAME_FQDN.key"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

alert() {
  log "ALERT: $*"
  [ -n "${NTFY_CLAWLIGHT_TOKEN:-}" ] || return 0
  curl -sS -m 10 -o /dev/null \
    -H "Authorization: Bearer $NTFY_CLAWLIGHT_TOKEN" \
    -H "Title: TLS cert problem on xero" -H "Priority: 5" -H "Tags: warning" \
    -d "$*" "http://127.0.0.1:8127/clawlight" || true
}

days_left() {  # $1 = cert path; echoes whole days until expiry, or -1 if unreadable
  local end
  end=$(openssl x509 -in "$1" -noout -enddate 2>/dev/null | cut -d= -f2) || { echo -1; return; }
  local end_s now_s
  end_s=$(date -d "$end" +%s 2>/dev/null) || { echo -1; return; }
  now_s=$(date +%s)
  echo $(( (end_s - now_s) / 86400 ))
}

before=$(days_left "$CRT")
log "starting renewal; current cert has ${before}d left"

# Write to temp files first so a partial or failed issuance can never replace a
# working cert with a broken one.
TMP_CRT=$(mktemp); TMP_KEY=$(mktemp)
trap 'rm -f "$TMP_CRT" "$TMP_KEY"' EXIT

if ! out=$(tailscale cert --min-validity "$MIN_VALIDITY" --cert-file "$TMP_CRT" --key-file "$TMP_KEY" "$HOSTNAME_FQDN" 2>&1); then
  alert "tailscale cert failed: $out"
  exit 1
fi
# `tailscale cert` can print an error and still exit 0 (e.g. "Access denied"),
# so validate the output rather than trusting the exit status.
if [ ! -s "$TMP_CRT" ] || ! openssl x509 -in "$TMP_CRT" -noout >/dev/null 2>&1; then
  alert "tailscale cert produced no usable certificate: $out"
  exit 1
fi

subject=$(openssl x509 -in "$TMP_CRT" -noout -subject 2>/dev/null)
case "$subject" in
  *"$HOSTNAME_FQDN"*) ;;
  *) alert "issued cert is for the wrong host: $subject"; exit 1 ;;
esac

after=$(days_left "$TMP_CRT")
install -m 644 "$TMP_CRT" "$CRT"
install -m 600 "$TMP_KEY" "$KEY"
log "installed cert with ${after}d remaining"

# Caddy caches certs read from disk; USR1 makes it reload config and re-read them.
if docker kill --signal=USR1 caddy >/dev/null 2>&1; then
  log "signalled caddy to reload"
else
  alert "cert renewed but caddy reload failed - it may still serve the old cert"
  exit 1
fi

if [ "$after" -lt "$WARN_DAYS" ]; then
  alert "cert still only has ${after}d left after renewal - renewal may not be working"
fi

log "done; ${before}d -> ${after}d"
