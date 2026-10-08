#!/bin/bash
# Runs healthcheck.sh's xero CPU temperature block on its own, with the
# thresholds overridden, so the alert text can be seen without heating the
# CPU or sending mail. Run on xero:
#   projects/healthcheck/test_cpu_temp_check.sh            # real thresholds
#   projects/healthcheck/test_cpu_temp_check.sh 40 50      # force warn/urgent
#   HA_TOKEN=bad projects/healthcheck/test_cpu_temp_check.sh  # HA down: sysfs only
set -uo pipefail
cd "$(dirname "$0")/../.."
token=${HA_TOKEN:-}
set -a; source .env.healthcheck; set +a
[ -n "$token" ] && HA_TOKEN=$token

block=$(sed -n '/^# xero CPU temperature/,/^fi$/p' projects/healthcheck/healthcheck.sh)
[ -n "${1:-}" ] && block=$(sed "s/^CPU_TEMP_WARN=.*/CPU_TEMP_WARN=$1/" <<< "$block")
[ -n "${2:-}" ] && block=$(sed "s/^CPU_TEMP_URGENT=.*/CPU_TEMP_URGENT=$2/" <<< "$block")

problems=()
eval "$block"
echo "peak over the window: ${cpu_temp_peak:-none}°C (warn $CPU_TEMP_WARN, urgent $CPU_TEMP_URGENT)"
printf 'alert: %s\n' "${problems[@]:-none}"
