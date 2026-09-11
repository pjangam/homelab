#!/usr/bin/env bash
# Tests the spotifyd-advertising escalation in cron/healthcheck.sh: one miss
# stays quiet, two consecutive misses alert, and recovery clears the state.
#
# Runs the REAL healthcheck.sh, not a copy of its logic, inside a mirror repo
# of symlinks with four files overridden: the advertising check (to simulate
# the fault), send_email and push_ntfy (so a test never mails or pushes), and
# the MQTT publisher (so test data never reaches the live broker, which would
# put a fake red tile on the real dashboard). HOME is redirected too, so the
# watchdog state files under ~/.cache are untouched.
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/repo/cron" "$T/repo/scripts" "$T/home/.cache"
for f in "$REPO"/cron/*; do ln -sf "$f" "$T/repo/cron/$(basename "$f")"; done
for f in "$REPO"/scripts/*; do ln -sf "$f" "$T/repo/scripts/$(basename "$f")"; done
for f in "$REPO"/.env*; do [ -f "$f" ] && ln -sf "$f" "$T/repo/$(basename "$f")"; done

# Overrides (rm the symlink first so we don't write through to the real file).
ADVERT_RC_FILE="$T/advert_rc"
rm -f "$T/repo/scripts/check_spotifyd_advertising.sh"
cat > "$T/repo/scripts/check_spotifyd_advertising.sh" <<'S'
#!/usr/bin/env bash
exit "$(cat "$ADVERT_RC_FILE")"
S
chmod +x "$T/repo/scripts/check_spotifyd_advertising.sh"

rm -f "$T/repo/scripts/send_email.sh"
cat > "$T/repo/scripts/send_email.sh" <<'S'
send_email() { printf 'EMAIL|%s|%s\n' "$1" "$(printf '%s' "$2" | tr '\n' ' ')" >> "$ALERT_LOG"; }
S
rm -f "$T/repo/scripts/push_ntfy.sh"
cat > "$T/repo/scripts/push_ntfy.sh" <<'S'
push_ntfy() { printf 'NTFY|%s|%s\n' "$1" "$(printf '%s' "$2" | tr '\n' ' ')" >> "$ALERT_LOG"; }
S
rm -f "$T/repo/scripts/publish_healthcheck_mqtt.py"
cat > "$T/repo/scripts/publish_healthcheck_mqtt.py" <<'S'
#!/usr/bin/env bash
cat > "$MQTT_LOG"
S
chmod +x "$T/repo/scripts/publish_healthcheck_mqtt.py"

export ADVERT_RC_FILE
export ALERT_LOG="$T/alerts.log"
export MQTT_LOG="$T/mqtt.json"
: > "$ALERT_LOG"

run() { HOME="$T/home" ADVERT_RC_FILE="$ADVERT_RC_FILE" ALERT_LOG="$ALERT_LOG" \
        MQTT_LOG="$MQTT_LOG" bash "$T/repo/cron/healthcheck.sh" >/dev/null 2>&1; }

# Count only advertising alerts, and only those raised since the last reset.
# The sandbox's fresh HOME makes unrelated checks (e.g. backup freshness)
# report problems too, so a bare email count would not be attributable here.
advert_alerts() { grep -c "not advertised itself as a Spotify Connect device" "$ALERT_LOG" 2>/dev/null | head -1; }
advert_by_channel() { grep "^$1|" "$ALERT_LOG" 2>/dev/null | grep -c "not advertised itself as a Spotify Connect device" | head -1; }
reset_alerts() { : > "$ALERT_LOG"; }
mqtt_advertising() { python3 -c "import json,sys;print(json.load(open('$MQTT_LOG'))['spotifyd_advertising'])" 2>/dev/null || echo "MISSING"; }

expect() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1 (expected '$2', got '$3')"; fails=$((fails+1)); fi
}

# --- 1. Healthy: advertising fine.
reset_alerts; echo 0 > "$ADVERT_RC_FILE"; run
expect "healthy run reports advertising=true to MQTT" "True" "$(mqtt_advertising)"
expect "healthy run raises no advertising alert" "0" "$(advert_alerts)"

# --- 2. First miss: dashboard flips, but no alert yet.
reset_alerts; echo 1 > "$ADVERT_RC_FILE"; run
expect "first miss flips the dashboard flag immediately" "False" "$(mqtt_advertising)"
expect "first miss does NOT alert (could be a mid-restart blip)" "0" "$(advert_alerts)"

# --- 3. Second consecutive miss: now it alerts, on both channels.
reset_alerts; run
expect "second consecutive miss raises the alert" "2" "$(advert_alerts)"
expect "  ...via email" "1" "$(advert_by_channel EMAIL)"
expect "  ...and via ntfy" "1" "$(advert_by_channel NTFY)"

# --- 4. Recovery clears the countdown.
echo 0 > "$ADVERT_RC_FILE"; run
expect "recovery restores the dashboard flag" "True" "$(mqtt_advertising)"
[ -f "$T/home/.cache/spotifyd-watchdog/advert-failing-since" ] \
  && { echo "FAIL: recovery left the countdown file behind"; fails=$((fails+1)); } \
  || echo "PASS: recovery clears the countdown file"

# --- 5. A fresh single miss after recovery must be quiet again, not instant.
reset_alerts; echo 1 > "$ADVERT_RC_FILE"; run
expect "post-recovery single miss is quiet again (countdown really reset)" "0" "$(advert_alerts)"

# --- 6. rc=2 (spotifyd stopped / can't verify) must never alert.
rm -f "$T/home/.cache/spotifyd-watchdog/advert-failing-since"
reset_alerts; echo 2 > "$ADVERT_RC_FILE"; run; run
expect "rc=2 never alerts, even twice running" "0" "$(advert_alerts)"
expect "rc=2 does not report a false advertising failure" "True" "$(mqtt_advertising)"

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; exit 1
