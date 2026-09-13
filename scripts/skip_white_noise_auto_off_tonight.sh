#!/usr/bin/env bash
# Skip tonight's white noise auto-off (yaml id white_noise_night_auto_off,
# triggers 23:00/23:30/00:00/00:30) by disabling the automation now and
# scheduling a one-shot systemd --user timer to re-enable it tomorrow at 12:00.
# Relies on Linger=yes for pramod so the transient timer survives logout.
#
# Usage: skip_white_noise_auto_off_tonight.sh          # disable + schedule re-enable
#        skip_white_noise_auto_off_tonight.sh enable   # re-enable now (what the timer runs)
set -euo pipefail

source /home/pramod/code/homelab/.env.healthcheck
ENTITY="automation.white_noise_auto_off_at_night"  # entity_id comes from the alias, not the yaml id

call() {
  curl -sf -m 15 -X POST \
    -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" \
    -d "{\"entity_id\": \"$ENTITY\"}" \
    "http://localhost:8123/api/services/automation/$1" > /dev/null
}

state() {
  curl -sf -m 15 -H "Authorization: Bearer $HA_TOKEN" \
    "http://localhost:8123/api/states/$ENTITY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])'
}

if [[ "${1:-}" == "enable" ]]; then
  call turn_on
  echo "$ENTITY: $(state)"
  exit 0
fi

call turn_off
echo "$ENTITY: $(state)"

systemctl --user stop white-noise-auto-off-reenable.timer 2>/dev/null || true
systemd-run --user --unit=white-noise-auto-off-reenable \
  --on-calendar="$(date -d tomorrow +%F) 12:00:00" \
  "$(realpath "$0")" enable
systemctl --user list-timers white-noise-auto-off-reenable.timer --no-pager
