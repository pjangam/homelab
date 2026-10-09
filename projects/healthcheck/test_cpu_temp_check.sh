#!/bin/bash
# Runs healthcheck.sh's xero CPU temperature block on its own, with the
# thresholds overridden, so the alert text can be seen without heating the
# CPU or sending mail. Run on xero:
#   projects/healthcheck/test_cpu_temp_check.sh            # real thresholds
#   projects/healthcheck/test_cpu_temp_check.sh 40 50      # force warn/urgent
#   HA_TOKEN=bad projects/healthcheck/test_cpu_temp_check.sh  # HA down: sysfs only
#   projects/healthcheck/test_cpu_temp_check.sh --spell        # fake hot spell, step by step
set -uo pipefail
cd "$(dirname "$0")/../.."
token=${HA_TOKEN:-}
set -a; source .env.healthcheck; set +a
[ -n "$token" ] && HA_TOKEN=$token

block=$(sed -n '/^# xero CPU temperature/,/^fi$/p' projects/healthcheck/healthcheck.sh)
[ -n "${1:-}" ] && block=$(sed "s/^CPU_TEMP_WARN=.*/CPU_TEMP_WARN=$1/" <<< "$block")
[ -n "${2:-}" ] && block=$(sed "s/^CPU_TEMP_URGENT=.*/CPU_TEMP_URGENT=$2/" <<< "$block")

# A scratch hot-spell file, so a test never touches the real one.
export CPU_TEMP_SPELL_FILE=$(mktemp -u)
trap 'rm -f "$CPU_TEMP_SPELL_FILE"' EXIT

if [ "${1:-}" = --spell ]; then
  # Replays a run of 15-minute peaks through the block (the measured peak is
  # replaced by each fake one) and prints the alert line each run would send.
  # The text changing between two runs is what makes the real script re-send.
  fake=$(sed 's/^cpu_temp_peak=${cpu_temp_peak%.\*}$/cpu_temp_peak=$FAKE_PEAK/' <<< "$block")
  prev=""
  for FAKE_PEAK in 85 91 92 93 94 97 99 99 100 88 92; do
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
echo "peak over the window: ${cpu_temp_peak:-none}°C (warn $CPU_TEMP_WARN, urgent $CPU_TEMP_URGENT)"
printf 'alert: %s\n' "${problems[@]:-none}"
