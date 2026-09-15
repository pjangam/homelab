#!/bin/bash
# Synthetic healthcheck for the homelab. Checks containers, systemd units,
# ZFS pool health, disk space, and linger (the systemd --user gotcha that
# broke white-noise). Emails pjangam2015@gmail.com only when something's
# actually wrong - silent on success to avoid alert fatigue.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
set -a
source "$SCRIPT_DIR/.env.healthcheck"
source "$SCRIPT_DIR/.env.mqtt"
# Optional: push alerts to self-hosted ntfy as well as email. Guarded because
# this file only exists on xero, where ntfy runs.
[ -f "$SCRIPT_DIR/.env.ntfy" ] && source "$SCRIPT_DIR/.env.ntfy"
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

# TLS cert expiry - see projects/certs-backup/check_certs.sh for why this is an independent
# check rather than something renew_certs.sh reports on itself.
while IFS= read -r cert_problem; do
  [ -n "$cert_problem" ] && problems+=("$cert_problem")
done < <("$SCRIPT_DIR/projects/certs-backup/check_certs.sh")

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

# spotifyd Connect advertisement. The checks above are all watchdog-derived,
# so they only see failures the watchdog already noticed - which is exactly
# how spotifyd sat for five days in Sept 2026 advertising nothing while every
# signal here stayed green (stuck_now false, restarts_24h 0, unit active).
# This asks the end-state question instead: is it actually discoverable?
#
# Alerting needs the fault to persist across two consecutive runs (~15min).
# A single miss is expected and harmless - the watchdog restarts spotifyd on
# its own, and there's a ~10s window mid-restart where it genuinely isn't
# advertising yet. Alerting on that would page for something already fixed.
# The dashboard flag, by contrast, reflects the latest observation
# immediately: a tile is for looking at, an email is for interrupting you.
SPOTIFYD_ADVERT_FAIL_FILE="$SPOTIFYD_STATE_DIR/advert-failing-since"
mkdir -p "$SPOTIFYD_STATE_DIR"

spotifyd_advertising=true
"$SCRIPT_DIR/projects/spotifyd/check_spotifyd_advertising.sh" >/dev/null 2>&1
advert_rc=$?

if [ "$advert_rc" -eq 1 ]; then
  spotifyd_advertising=false
  if [ -f "$SPOTIFYD_ADVERT_FAIL_FILE" ]; then
    advert_since=$(cat "$SPOTIFYD_ADVERT_FAIL_FILE")
    advert_mins=$(( ($(date +%s) - advert_since) / 60 ))
    problems+=("spotifyd is running but has not advertised itself as a Spotify Connect device for ${advert_mins}m - it will not appear in the Spotify app and spotcast/HA scripts targeting it will fail. Check: journalctl --user -u spotifyd -b | grep dns-sd")
  else
    date +%s > "$SPOTIFYD_ADVERT_FAIL_FILE"
  fi
else
  # Clear on recovery, and also on rc=2 (not running / can't verify) so a
  # deliberate stop doesn't leave a stale countdown to alert on at restart.
  rm -f "$SPOTIFYD_ADVERT_FAIL_FILE"
fi

# MirAIe AC: is the climate entity actually usable in HA? Nothing watched
# this until 2026-09-11, when it broke twice in one evening from two
# unrelated causes (the indoor unit going silent to the MirAIe cloud, then an
# HA restart losing the retain=false availability) for nearly two hours
# combined. Every signal this script already had stayed green throughout -
# node-red is on the Pi so it is not even in the docker check above, and the
# container was `Up (healthy)` either way.
#
# Nothing happens on the first unavailable run. A brief unavailable is normal
# and self-healing: HA marks MQTT entities unavailable for a second or two
# whenever discovery re-registers, and every node-red restart drops the entity
# for ~20s. Two consecutive runs of this */15 cron seeing it is a real outage.
#
# Then fix_miraie_ac.sh --force runs, ONCE per outage, before anyone is
# alerted. Until 2026-09-15 this only alerted and a human ran that same
# script: that day the watchdog on the Pi restarted node-red at 15:40, HA
# missed the retain=false availability on the reconnect, and the entity sat
# unavailable for 75m with the unit online the whole time - which the fix
# script cures in a minute by re-delivering the `online` it sees. Only once,
# because its other verdicts are not restart-shaped: exit 2 is an indoor unit
# that is off the MirAIe cloud, and exit 3 is HA-side. Retrying those every
# 15 minutes would just knock the bridge over for nothing.
#
# The alert, when the fix does not cure it, says which of those it is, and
# says "since HH:MM" rather than a running minute count so the text is stable
# and the dedup at the bottom mails it once instead of every run. As with the
# spotifyd tile, the dashboard flag reflects the latest observation
# immediately - a tile is for looking at, an alert is for interrupting you.
MIRAIE_AC_STATE_DIR="$HOME/.cache/healthcheck"
MIRAIE_AC_FAIL_FILE="$MIRAIE_AC_STATE_DIR/miraie-ac-unavailable-since"
# Present = this outage already had its one fix attempt; holds its exit code.
MIRAIE_AC_FIX_RC_FILE="$MIRAIE_AC_STATE_DIR/miraie-ac-autofix-rc"
# One line per attempt ("<epoch> <rc>"), for the tile and the flapping alert.
MIRAIE_AC_FIX_LOG="$MIRAIE_AC_STATE_DIR/miraie-ac-autofixes.log"
MIRAIE_AC_FIX_AFTER_MIN=10
MIRAIE_AC_FIX_TIMEOUT_S=300
MIRAIE_AC_FIXES_THRESHOLD=3
mkdir -p "$MIRAIE_AC_STATE_DIR"

miraie_ac_check() {
  miraie_ac_detail="$("$SCRIPT_DIR/projects/miraie-ac/check_miraie_ac_available.sh" 2>/dev/null)"
  miraie_ac_rc=$?
}

miraie_ac_ok=true
miraie_ac_unavailable_minutes=""
miraie_ac_check

if [ "$miraie_ac_rc" -eq 1 ] && [ ! -f "$MIRAIE_AC_FAIL_FILE" ]; then
  date +%s > "$MIRAIE_AC_FAIL_FILE"
  miraie_ac_ok=false
  miraie_ac_unavailable_minutes=0
elif [ "$miraie_ac_rc" -eq 1 ]; then
  miraie_ac_ok=false
  miraie_ac_since=$(cat "$MIRAIE_AC_FAIL_FILE")
  miraie_ac_unavailable_minutes=$(( ($(date +%s) - miraie_ac_since) / 60 ))

  if [ "$miraie_ac_unavailable_minutes" -ge "$MIRAIE_AC_FIX_AFTER_MIN" ] && [ ! -f "$MIRAIE_AC_FIX_RC_FILE" ]; then
    echo "[$(date '+%F %T')] MirAIe AC unavailable ${miraie_ac_unavailable_minutes}m - running fix_miraie_ac.sh --force"
    timeout "$MIRAIE_AC_FIX_TIMEOUT_S" "$SCRIPT_DIR/projects/miraie-ac/fix_miraie_ac.sh" --force 2>&1 | sed 's/^/  /'
    miraie_ac_fix_rc=${PIPESTATUS[0]}
    echo "[$(date '+%F %T')] fix_miraie_ac.sh exited $miraie_ac_fix_rc"
    echo "$miraie_ac_fix_rc" > "$MIRAIE_AC_FIX_RC_FILE"
    echo "$(date +%s) $miraie_ac_fix_rc" >> "$MIRAIE_AC_FIX_LOG"
    miraie_ac_check
  fi

  if [ "$miraie_ac_rc" -ne 1 ]; then
    echo "[$(date '+%F %T')] MirAIe AC recovered after the fix"
    miraie_ac_ok=true
    miraie_ac_unavailable_minutes=""
    rm -f "$MIRAIE_AC_FAIL_FILE" "$MIRAIE_AC_FIX_RC_FILE"
  elif [ -f "$MIRAIE_AC_FIX_RC_FILE" ]; then
    miraie_ac_since_hm=$(date -d "@$miraie_ac_since" '+%H:%M')
    case "$(cat "$MIRAIE_AC_FIX_RC_FILE")" in
      2) miraie_ac_why="the Node-RED bridge is fine but the indoor unit is not reporting to the MirAIe cloud. Switch the AC on (or power-cycle it at the wall) - restarting cannot fix this." ;;
      3) miraie_ac_why="the bridge and the unit are both fine but HA will not take the entity back. Restart HA's MQTT integration (or HA)." ;;
      1) miraie_ac_why="the Node-RED bridge on the Pi did not reconnect (DNS, credentials or the MirAIe cloud). Check: ssh pramod@192.168.1.124 'docker logs --tail 30 node-red'" ;;
      124) miraie_ac_why="the fix script timed out after ${MIRAIE_AC_FIX_TIMEOUT_S}s. Run projects/miraie-ac/fix_miraie_ac.sh --force by hand." ;;
      *) miraie_ac_why="fix_miraie_ac.sh --force reported success but HA still shows it unavailable. Check HA directly." ;;
    esac
    problems+=("MirAIe AC has been unavailable in Home Assistant since $miraie_ac_since_hm (${miraie_ac_detail:-unavailable}) and the automatic fix did not bring it back: $miraie_ac_why Fix output is in healthcheck.log.")
  fi
else
  # Clear on recovery, and on rc=2 (can't tell) so a missing token or an HA
  # that was briefly down does not leave a countdown primed to fire later.
  rm -f "$MIRAIE_AC_FAIL_FILE" "$MIRAIE_AC_FIX_RC_FILE"
fi

# A fix that works every time can still hide an AC that keeps dropping - the
# same reason spotifyd's silent watchdog restarts are counted.
miraie_ac_autofixes_24h=0
miraie_ac_last_autofix=""
if [ -f "$MIRAIE_AC_FIX_LOG" ]; then
  miraie_ac_cutoff=$(( $(date +%s) - 86400 ))
  while read -r ts rc; do
    [ -n "$ts" ] || continue
    miraie_ac_last_autofix="$(date -d "@$ts" '+%F %T') exit $rc"
    [ "$ts" -ge "$miraie_ac_cutoff" ] && miraie_ac_autofixes_24h=$((miraie_ac_autofixes_24h + 1))
  done < "$MIRAIE_AC_FIX_LOG"
  tail -n 50 "$MIRAIE_AC_FIX_LOG" > "$MIRAIE_AC_FIX_LOG.tmp" && mv "$MIRAIE_AC_FIX_LOG.tmp" "$MIRAIE_AC_FIX_LOG"
fi
if [ "$miraie_ac_autofixes_24h" -ge "$MIRAIE_AC_FIXES_THRESHOLD" ]; then
  problems+=("MirAIe AC needed the automatic fix $miraie_ac_autofixes_24h times in the last 24h (threshold $MIRAIE_AC_FIXES_THRESHOLD) - something keeps knocking it out, investigate. Attempts are in healthcheck.log.")
fi

# Power watchdog (watchdog_power.sh): surfaces whether enp1s0 is currently
# down (proxy for "on UPS battery") on the dashboard, not just in
# power-watchdog.log/journalctl. Dashboard-only signal, not added to
# problems[] - a carrier-loss email already fires directly from
# watchdog_power.sh (see projects/power-watchdog/watchdog_power.sh) so this wouldn't add
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
  [ "$spotifyd_advertising" = false ] && spotifyd_problem_bool=true

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
    --argjson spotifyd_advertising "$spotifyd_advertising" \
    --argjson miraie_ac_ok "$miraie_ac_ok" \
    --arg miraie_ac_unavailable_minutes "${miraie_ac_unavailable_minutes:-}" \
    --arg miraie_ac_autofixes_24h "$miraie_ac_autofixes_24h" \
    --arg miraie_ac_last_autofix "$miraie_ac_last_autofix" \
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
      spotifyd_advertising: $spotifyd_advertising,
      miraie_ac_ok: $miraie_ac_ok,
      miraie_ac_unavailable_minutes: (if $miraie_ac_unavailable_minutes == "" then null else ($miraie_ac_unavailable_minutes|tonumber) end),
      miraie_ac_autofixes_24h: ($miraie_ac_autofixes_24h|tonumber),
      miraie_ac_last_autofix: (if $miraie_ac_last_autofix == "" then null else $miraie_ac_last_autofix end),
      power_on_battery: $power_on_battery,
      power_down_minutes: (if $power_down_minutes == "" then null else ($power_down_minutes|tonumber) end)
    }' | "$SCRIPT_DIR/projects/healthcheck/publish_healthcheck_mqtt.py"
} || true

# Verify the dashboard actually received all of the above. Runs after the
# publish, so a problem found here is intentionally NOT in the `problems`
# list that was just published - if the board is broken, publishing a problem
# about the board to that same board is not a plan. It reaches email/ntfy,
# which don't depend on MQTT or HA at all.
#
# Two consecutive failures (~30min) before alerting. HA marks every MQTT
# entity unavailable for a second or two whenever discovery re-registers -
# that happened at 19:35 on 2026-09-11 and self-healed in 2s. Paging for a
# blip that's over before you can read the alert is how alerts get ignored.
DASHBOARD_STATE_DIR="$HOME/.cache/healthcheck"
DASHBOARD_FAIL_FILE="$DASHBOARD_STATE_DIR/dashboard-failing-since"
mkdir -p "$DASHBOARD_STATE_DIR"

dashboard_faults=$("$SCRIPT_DIR/projects/healthcheck/verify_healthcheck_entities.sh" 2>/dev/null)
dashboard_rc=$?

if [ "$dashboard_rc" -eq 1 ] && [ -n "$dashboard_faults" ]; then
  if [ -f "$DASHBOARD_FAIL_FILE" ]; then
    dash_since=$(cat "$DASHBOARD_FAIL_FILE")
    dash_mins=$(( ($(date +%s) - dash_since) / 60 ))
    while IFS= read -r fault; do
      [ -n "$fault" ] && problems+=("$fault (ongoing ${dash_mins}m)")
    done <<< "$dashboard_faults"
  else
    date +%s > "$DASHBOARD_FAIL_FILE"
  fi
else
  # Clear on recovery, and on rc=2 (can't verify) so a missing token doesn't
  # leave a countdown primed to fire the moment it comes back.
  rm -f "$DASHBOARD_FAIL_FILE"
fi

source "$SCRIPT_DIR/tools/notify/send_email.sh"

source "$SCRIPT_DIR/tools/notify/push_ntfy.sh"

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
    push_ntfy "homelab: all clear" "Previously reported issue(s) resolved." 3 white_check_mark
    rm -f "$STATE_FILE"
  fi
  exit 0
fi

current=$(printf '%s\n\n' "${problems[@]}")
if [ "$current" != "$previous" ]; then
  send_email "[homelab] healthcheck found problems" "$current"
  push_ntfy "homelab: healthcheck found problems" "$current"
  printf '%s' "$current" > "$STATE_FILE"
fi
