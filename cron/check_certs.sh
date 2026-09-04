#!/usr/bin/env bash
# Prints one line per TLS cert problem found; silent when all certs are healthy.
# Exits 1 if any problem was found, 0 otherwise.
#
# This is an INDEPENDENT check on cron/renew_certs.sh. That script alerts when
# it fails, but it cannot alert if it never runs at all - a removed crontab
# line, a deleted script, or a machine that was off every Sunday all look
# identical to silence. That exact failure mode went unnoticed for three months
# (incidents/2026-09-04-tls-cert-renewal-silently-broken.md), so the check that
# catches it deliberately shares no machinery with the thing it checks.
#
# Called by cron/healthcheck.sh (every 15 min). Takes an optional cert
# directory argument so it can be tested against synthetic certs - see
# scripts/test_cert_expiry_check.sh.
#
# Threshold: renewal runs weekly with --min-validity 720h (30d), so a cert can
# legitimately sit just under 30d for up to a week before the next Sunday run.
# Below 21d means renewal has missed at least one scheduled run, plus slack.
set -uo pipefail

CERT_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/certs}"
WARN_DAYS="${CERT_WARN_DAYS:-21}"

found=0
for cert in "$CERT_DIR"/*.crt; do
  [ -e "$cert" ] || continue   # no certs dir on machines that don't serve TLS
  name=$(basename "$cert" .crt)

  if ! end=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2) || [ -z "$end" ]; then
    echo "TLS cert $name: unreadable or malformed ($cert)"; found=1; continue
  fi
  if ! end_epoch=$(date -d "$end" +%s 2>/dev/null); then
    echo "TLS cert $name: couldn't parse expiry '$end'"; found=1; continue
  fi

  days=$(( (end_epoch - $(date +%s)) / 86400 ))
  if [ "$days" -lt 0 ]; then
    echo "TLS cert $name EXPIRED $(( -days ))d ago - run cron/renew_certs.sh"; found=1
  elif [ "$days" -lt "$WARN_DAYS" ]; then
    echo "TLS cert $name expires in ${days}d - weekly renewal has not run; check cert-renew.log and 'crontab -l'"; found=1
  fi
done
exit $found
