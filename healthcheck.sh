#!/bin/bash
# Synthetic healthcheck for the homelab. Checks containers, systemd units,
# ZFS pool health, disk space, and linger (the systemd --user gotcha that
# broke white-noise). Emails pjangam2015@gmail.com only when something's
# actually wrong - silent on success to avoid alert fatigue.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
set -a
source "$SCRIPT_DIR/.env.healthcheck"
set +a

# cron runs with no XDG_RUNTIME_DIR, so `systemctl --user` fails with
# "Failed to connect to bus" and (since we redirect stderr) would silently
# report zero failed units regardless of actual state. Same env this repo's
# other scripts (white-noise-mqtt.py) already set for the same reason.
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

problems=()

# Docker containers: anything not running, or running but unhealthy
while IFS=$'\t' read -r name state status; do
  [ -z "$name" ] && continue
  if [ "$state" != "running" ]; then
    problems+=("Container $name is $state ($status)")
  fi
done < <(docker ps -a --format '{{.Names}}	{{.State}}	{{.Status}}')

while read -r name; do
  [ -z "$name" ] && continue
  problems+=("Container $name is unhealthy")
done < <(docker ps --filter health=unhealthy --format '{{.Names}}')

# systemd --user failed units (this is what caught the white-noise/linger bug)
user_failed=$(systemctl --user --failed --no-legend 2>/dev/null)
[ -n "$user_failed" ] && problems+=("systemd --user has failed units:"$'\n'"$user_failed")

# systemd system failed units (would have caught the getty@tty1 crash-loop)
sys_failed=$(systemctl --failed --no-legend 2>/dev/null)
[ -n "$sys_failed" ] && problems+=("systemd has failed units:"$'\n'"$sys_failed")

# ZFS pool health
zfs_status=$(zpool status -x 2>&1)
[ "$zfs_status" != "all pools are healthy" ] && problems+=("ZFS pool issue: $zfs_status")

# Disk space
while read -r mount pct; do
  pct_num="${pct%\%}"
  if [ "$pct_num" -ge 90 ]; then
    problems+=("Disk $mount is ${pct} full")
  fi
done < <(df -h --output=target,pcent / /datapool 2>/dev/null | tail -n +2)

# Linger (systemd --user services die on logout without this - bit us once already)
linger=$(loginctl show-user pramod -p Linger 2>/dev/null)
[ "$linger" != "Linger=yes" ] && problems+=("systemd linger is disabled for pramod ($linger) - user services will die on logout")

# Backup freshness: backup_vaultwarden.sh/backup_homeassistant.sh run daily
# via cron and report success into backup.log, but nothing was checking
# whether they actually succeeded - an expired rclone token or a full
# remote could fail them silently for weeks until a backup is needed.
BACKUP_LOG="$SCRIPT_DIR/backup.log"
MAX_BACKUP_AGE_HOURS=30  # daily cadence + generous slack, not tied to time-of-day

check_backup_freshness() {
  local label="$1" pattern="$2"
  local last_line last_ts last_epoch age_hours
  last_line=$(grep -F "$pattern" "$BACKUP_LOG" 2>/dev/null | tail -1)
  if [ -z "$last_line" ]; then
    problems+=("$label backup: no successful run ever found in backup.log")
    return
  fi
  last_ts=$(echo "$last_line" | grep -oP '(?<=\[)[^]]+(?=\])')
  if ! last_epoch=$(date -d "$last_ts" +%s 2>/dev/null); then
    problems+=("$label backup: couldn't parse timestamp '$last_ts' from log")
    return
  fi
  age_hours=$(( ($(date +%s) - last_epoch) / 3600 ))
  [ "$age_hours" -ge "$MAX_BACKUP_AGE_HOURS" ] && problems+=("$label backup hasn't succeeded in ${age_hours}h (last: $last_ts)")
}

if [ -f "$BACKUP_LOG" ]; then
  check_backup_freshness "Vaultwarden" "Backup complete: vaultwarden_"
  check_backup_freshness "Home Assistant" "] Done."
else
  problems+=("backup.log not found at $BACKUP_LOG - can't verify backup freshness")
fi

# Heartbeat: proves this script ran to completion, regardless of what it
# found. If the machine hard-locks (e.g. the ZFS+postgres freeze from
# 2026-06-29) and cron itself stops running, this ping goes silent and
# healthchecks.io alerts on the missing check-in - the one failure mode a
# script running ON this machine can never detect about itself.
curl -fsS -m 10 --retry 3 "$HEALTHCHECK_PING_URL" -o /dev/null || true

send_email() {
  python3 - "$1" "$2" <<'EOF'
import os, smtplib, sys
from email.mime.text import MIMEText

subject, body = sys.argv[1], sys.argv[2]
user = os.environ["GMAIL_USER"]
password = os.environ["GMAIL_APP_PASSWORD"]

msg = MIMEText(body)
msg["Subject"] = subject
msg["From"] = user
msg["To"] = user

with smtplib.SMTP("smtp.gmail.com", 587) as s:
    s.starttls()
    s.login(user, password)
    s.send_message(msg)
EOF
}

# Only email on a *change* from the last alert (new/different problems, or a
# prior problem clearing) - not on every repeat of the same ongoing issue.
# Otherwise an unresolved problem (like the ZFS corruption found while
# building this) would re-email every 15 minutes forever.
STATE_FILE="$SCRIPT_DIR/.healthcheck_state"
previous=""
[ -f "$STATE_FILE" ] && previous=$(cat "$STATE_FILE")

if [ ${#problems[@]} -eq 0 ]; then
  if [ -n "$previous" ]; then
    send_email "[homelab] healthcheck: all clear" "Previously reported issue(s) resolved:"$'\n\n'"$previous"
    rm -f "$STATE_FILE"
  fi
  exit 0
fi

current=$(printf '%s\n\n' "${problems[@]}")
if [ "$current" != "$previous" ]; then
  send_email "[homelab] healthcheck found problems" "$current"
  printf '%s' "$current" > "$STATE_FILE"
fi
