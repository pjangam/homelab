#!/bin/bash
# Synthetic healthcheck for the homelab. Checks containers, systemd units,
# ZFS pool health, disk space, and linger (the systemd --user gotcha that
# broke white-noise). Emails pjangam2015@gmail.com only when something's
# actually wrong - silent on success to avoid alert fatigue.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
set -a
source "$SCRIPT_DIR/.env.healthcheck"
source "$SCRIPT_DIR/.env.mqtt"
set +a

# cron runs with no XDG_RUNTIME_DIR, so `systemctl --user` fails with
# "Failed to connect to bus" and (since we redirect stderr) would silently
# report zero failed units regardless of actual state. Same env this repo's
# other scripts (white-noise-mqtt.py) already set for the same reason.
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

# cron's PATH doesn't include ~/.local/bin, so publish_healthcheck_mqtt.py's
# `#!/usr/bin/env -S uv run --script` shebang can't find uv - it fails with
# "uv: No such file or directory" on every run, silently going nowhere since
# the publish step is wrapped in `|| true` below.
export PATH="$HOME/.local/bin:$PATH"

problems=()
docker_bad_containers=()

# Docker containers: anything not running, or running but unhealthy
while IFS=$'\t' read -r name state status; do
  [ -z "$name" ] && continue
  if [ "$state" != "running" ]; then
    problems+=("Container $name is $state ($status)")
    docker_bad_containers+=("$name")
  fi
done < <(docker ps -a --format '{{.Names}}	{{.State}}	{{.Status}}')

while read -r name; do
  [ -z "$name" ] && continue
  problems+=("Container $name is unhealthy")
  docker_bad_containers+=("$name")
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
disk_root_pct=""
disk_datapool_pct=""
while read -r mount pct; do
  pct_num="${pct%\%}"
  case "$mount" in
    /) disk_root_pct="$pct_num" ;;
    /datapool) disk_datapool_pct="$pct_num" ;;
  esac
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
  local label="$1" pattern="$2" outvar="$3"
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
  printf -v "$outvar" '%s' "$age_hours"
  [ "$age_hours" -ge "$MAX_BACKUP_AGE_HOURS" ] && problems+=("$label backup hasn't succeeded in ${age_hours}h (last: $last_ts)")
}

backup_vw_age_hours=""
backup_ha_age_hours=""
if [ -f "$BACKUP_LOG" ]; then
  check_backup_freshness "Vaultwarden" "Backup complete: vaultwarden_" backup_vw_age_hours
  check_backup_freshness "Home Assistant" "] Done." backup_ha_age_hours
else
  problems+=("backup.log not found at $BACKUP_LOG - can't verify backup freshness")
fi

# spotifyd watchdog (watchdog_spotifyd.sh): it silently self-heals a single
# stuck-connection hang by restarting the service, which never shows up as a
# failed systemd unit. Two things surface here: "stuck right now" (the
# watchdog is mid-countdown, for the dashboard tile) and "flapped repeatedly"
# (restarting every few minutes means something's actually wrong, e.g. a
# network issue, not a one-off - that's worth an email, not just a tile).
SPOTIFYD_STATE_DIR="$HOME/.cache/spotifyd-watchdog"
SPOTIFYD_DOWN_SINCE_FILE="$SPOTIFYD_STATE_DIR/down-since"
SPOTIFYD_RESTART_LOG="$SPOTIFYD_STATE_DIR/restarts.log"
SPOTIFYD_RESTART_THRESHOLD=3

spotifyd_stuck_now=false
[ -f "$SPOTIFYD_DOWN_SINCE_FILE" ] && spotifyd_stuck_now=true

spotifyd_restarts_24h=0
if [ -f "$SPOTIFYD_RESTART_LOG" ]; then
  cutoff_epoch=$(date -d "-24 hours" +%s)
  while read -r ts; do
    [ -z "$ts" ] && continue
    ts_epoch=$(date -d "$ts" +%s 2>/dev/null) || continue
    [ "$ts_epoch" -ge "$cutoff_epoch" ] && spotifyd_restarts_24h=$((spotifyd_restarts_24h + 1))
  done < "$SPOTIFYD_RESTART_LOG"
fi

if [ "$spotifyd_restarts_24h" -ge "$SPOTIFYD_RESTART_THRESHOLD" ]; then
  problems+=("spotifyd watchdog restarted it $spotifyd_restarts_24h times in the last 24h (threshold $SPOTIFYD_RESTART_THRESHOLD) - investigate")
fi

# Power watchdog (watchdog_power.sh): surfaces whether enp1s0 is currently
# down (proxy for "on UPS battery") on the dashboard, not just in
# power-watchdog.log/journalctl. Dashboard-only signal, not added to
# problems[] - a carrier-loss email already fires directly from
# watchdog_power.sh (see cron/watchdog_power.sh) so this wouldn't add
# anything except a duplicate alert.
POWER_STATE_DIR="$HOME/.cache/power-watchdog"
POWER_DOWN_SINCE_FILE="$POWER_STATE_DIR/down-since"

power_on_battery=false
power_down_minutes=""
if [ -f "$POWER_DOWN_SINCE_FILE" ]; then
  power_on_battery=true
  power_down_since=$(cat "$POWER_DOWN_SINCE_FILE")
  power_down_minutes=$(( ($(date +%s) - power_down_since) / 60 ))
fi

# Heartbeat: proves this script ran to completion, regardless of what it
# found. If the machine hard-locks (e.g. the ZFS+postgres freeze from
# 2026-06-29) and cron itself stops running, this ping goes silent and
# healthchecks.io alerts on the missing check-in - the one failure mode a
# script running ON this machine can never detect about itself.
curl -fsS -m 10 --retry 3 "$HEALTHCHECK_PING_URL" -o /dev/null || true

# Publish results to MQTT (HA discovery) for the consolidated status
# dashboard - independent of the email-dedup logic below, so it runs on
# every invocation including all-clear ones. A publish failure here must
# never break the actual alerting this script exists for.
{
  docker_problem_bool=false
  [ ${#docker_bad_containers[@]} -gt 0 ] && docker_problem_bool=true
  systemd_problem_bool=false
  { [ -n "$user_failed" ] || [ -n "$sys_failed" ]; } && systemd_problem_bool=true
  zfs_ok_bool=true
  [ "$zfs_status" != "all pools are healthy" ] && zfs_ok_bool=false
  overall_problem_bool=false
  [ ${#problems[@]} -gt 0 ] && overall_problem_bool=true

  spotifyd_problem_bool=$spotifyd_stuck_now
  [ "$spotifyd_restarts_24h" -ge "$SPOTIFYD_RESTART_THRESHOLD" ] && spotifyd_problem_bool=true

  docker_bad_json=$(jq -n --args '$ARGS.positional' "${docker_bad_containers[@]}")
  problems_json=$(jq -n --args '$ARGS.positional' "${problems[@]}")

  jq -n \
    --argjson docker_problem "$docker_problem_bool" \
    --argjson docker_bad "$docker_bad_json" \
    --argjson systemd_problem "$systemd_problem_bool" \
    --arg systemd_failed_text "$(printf '%s\n%s' "$user_failed" "$sys_failed" | sed '/^$/d')" \
    --argjson zfs_ok "$zfs_ok_bool" \
    --arg zfs_status "$zfs_status" \
    --argjson overall_problem "$overall_problem_bool" \
    --argjson problems "$problems_json" \
    --arg disk_root "${disk_root_pct:-}" \
    --arg disk_datapool "${disk_datapool_pct:-}" \
    --arg backup_vw_age "${backup_vw_age_hours:-}" \
    --arg backup_ha_age "${backup_ha_age_hours:-}" \
    --argjson spotifyd_problem "$spotifyd_problem_bool" \
    --argjson spotifyd_stuck_now "$spotifyd_stuck_now" \
    --arg spotifyd_restarts_24h "$spotifyd_restarts_24h" \
    --argjson power_on_battery "$power_on_battery" \
    --arg power_down_minutes "${power_down_minutes:-}" \
    '{
      docker_problem: $docker_problem,
      docker_bad: $docker_bad,
      systemd_problem: $systemd_problem,
      systemd_failed_text: $systemd_failed_text,
      zfs_ok: $zfs_ok,
      zfs_status: $zfs_status,
      overall_problem: $overall_problem,
      problems: $problems,
      disk_root: (if $disk_root == "" then null else ($disk_root|tonumber) end),
      disk_datapool: (if $disk_datapool == "" then null else ($disk_datapool|tonumber) end),
      backup_vw_age_hours: (if $backup_vw_age == "" then null else ($backup_vw_age|tonumber) end),
      backup_ha_age_hours: (if $backup_ha_age == "" then null else ($backup_ha_age|tonumber) end),
      spotifyd_problem: $spotifyd_problem,
      spotifyd_stuck_now: $spotifyd_stuck_now,
      spotifyd_restarts_24h: ($spotifyd_restarts_24h|tonumber),
      power_on_battery: $power_on_battery,
      power_down_minutes: (if $power_down_minutes == "" then null else ($power_down_minutes|tonumber) end)
    }' | "$SCRIPT_DIR/scripts/publish_healthcheck_mqtt.py"
} || true

source "$SCRIPT_DIR/scripts/send_email.sh"

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
