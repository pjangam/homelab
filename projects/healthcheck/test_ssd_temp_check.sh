#!/bin/bash
# Runs healthcheck.sh's SSD temperature block on its own, with the thresholds
# overridden, so the alert text can be seen without heating a disk or
# sending mail. Run on xero:
#   projects/healthcheck/test_ssd_temp_check.sh            # real thresholds
#   projects/healthcheck/test_ssd_temp_check.sh 40 45      # force warn/urgent
#   HA_TOKEN=bad projects/healthcheck/test_ssd_temp_check.sh  # HA down: sysfs only
#   projects/healthcheck/test_ssd_temp_check.sh --spell        # fake hot spell, step by step
set -uo pipefail
cd "$(dirname "$0")/../.."
token=${HA_TOKEN:-}
set -a; source .env.healthcheck; set +a
[ -n "$token" ] && HA_TOKEN=$token

block=$(sed -n '/^# SSD temperatures/,/ssd-boot-hot-spell"$/p' projects/healthcheck/healthcheck.sh)
spell=""; [ "${1:-}" = --spell ] && { spell=1; shift; }
[ -n "${1:-}" ] && block=$(sed "s/^SSD_TEMP_WARN=.*/SSD_TEMP_WARN=$1/" <<< "$block")
[ -n "${2:-}" ] && block=$(sed "s/^SSD_TEMP_URGENT=.*/SSD_TEMP_URGENT=$2/" <<< "$block")

# Scratch hot-spell files, so a test never touches the real ones; and the two
# values the block borrows from the CPU check above it.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
block=${block//'$HOME/.cache/healthcheck'/$tmp}
cpu_temp_window_start=$(date -u -d "-15 min" +%Y-%m-%dT%H:%M:%SZ)
CPU_TEMP_RENOTIFY_RISE=3

if [ -n "$spell" ]; then
  # Replays a run of 15-minute peaks (both SSDs get the same fake one) and
  # prints the Kingston's alert line each run would send. The text changing
  # between two runs is what makes the real script re-send.
  fake=$(sed 's/^  peak=${peak%.\*}$/  peak=$FAKE_PEAK/' <<< "$block")
  prev=""
  for FAKE_PEAK in 66 76 77 79 80 84 86 86 88 70 76; do
    problems=(); eval "$fake"
    line=${problems[0]:-(no alert)}
    [ "$line" != "$prev" ] && sent="SENT " || sent="     "
    printf '%3s°C  %s %s\n' "$FAKE_PEAK" "$sent" "${line:0:70}"
    prev=$line
  done
  exit 0
fi
problems=()
eval "$block"
echo "warn $SSD_TEMP_WARN°C, urgent $SSD_TEMP_URGENT°C"
printf 'alert: %s\n' "${problems[@]:-none}"
