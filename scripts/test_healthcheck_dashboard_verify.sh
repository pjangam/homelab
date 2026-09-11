#!/usr/bin/env bash
# Tests the dashboard read-back escalation in cron/healthcheck.sh: a blip
# stays quiet, a sustained fault alerts on both channels, "can't verify"
# never alerts, and recovery resets the countdown.
#
# Same mirror-repo approach as test_healthcheck_spotifyd_advertising.sh -
# runs the real healthcheck.sh with the verifier, both alert senders and the
# MQTT publisher stubbed, so a test never mails, pushes, or writes to the
# live broker.
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/repo/cron" "$T/repo/scripts" "$T/home/.cache"
for f in "$REPO"/cron/*; do ln -sf "$f" "$T/repo/cron/$(basename "$f")"; done
for f in "$REPO"/scripts/*; do ln -sf "$f" "$T/repo/scripts/$(basename "$f")"; done
for f in "$REPO"/.env*; do [ -f "$f" ] && ln -sf "$f" "$T/repo/$(basename "$f")"; done

VERIFY_RC="$T/verify_rc"; VERIFY_MSG="$T/verify_msg"
rm -f "$T/repo/scripts/verify_healthcheck_entities.sh"
cat > "$T/repo/scripts/verify_healthcheck_entities.sh" <<'S'
#!/usr/bin/env bash
cat "$VERIFY_MSG" 2>/dev/null
exit "$(cat "$VERIFY_RC")"
S
chmod +x "$T/repo/scripts/verify_healthcheck_entities.sh"

# Keep the spotifyd advertising check healthy so it can't muddy these results.
rm -f "$T/repo/scripts/check_spotifyd_advertising.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/repo/scripts/check_spotifyd_advertising.sh"
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
printf '#!/usr/bin/env bash\ncat > "$MQTT_LOG"\n' > "$T/repo/scripts/publish_healthcheck_mqtt.py"
chmod +x "$T/repo/scripts/publish_healthcheck_mqtt.py"

export ALERT_LOG="$T/alerts.log" MQTT_LOG="$T/mqtt.json" VERIFY_RC VERIFY_MSG
FAULT="Health dashboard entities are 'unavailable' in Home Assistant - tiles are not reflecting reality (check the MQTT bridge)"
printf '%s\n' "$FAULT" > "$VERIFY_MSG"

run() { HOME="$T/home" bash "$T/repo/cron/healthcheck.sh" >/dev/null 2>&1; }
reset_alerts() { : > "$ALERT_LOG"; }
dash_alerts() { grep -c "tiles are not reflecting reality" "$ALERT_LOG" 2>/dev/null | head -1; }
dash_channel() { grep "^$1|" "$ALERT_LOG" 2>/dev/null | grep -c "tiles are not reflecting reality" | head -1; }
expect() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; fails=$((fails+1)); fi; }

# 1. Dashboard healthy -> quiet.
reset_alerts; echo 0 > "$VERIFY_RC"; run
expect "healthy dashboard raises nothing" "0" "$(dash_alerts)"

# 2. First failure -> still quiet (this is tonight's 2-second blip).
reset_alerts; echo 1 > "$VERIFY_RC"; run
expect "a single blip does NOT alert" "0" "$(dash_alerts)"

# 3. Second consecutive failure -> alert on both channels.
reset_alerts; run
expect "sustained fault alerts" "2" "$(dash_alerts)"
expect "  ...via email" "1" "$(dash_channel EMAIL)"
expect "  ...and via ntfy" "1" "$(dash_channel NTFY)"

# 4. The alert says how long it has been broken.
grep -q "ongoing [0-9]*m" "$ALERT_LOG" && echo "PASS: alert includes the duration" \
  || { echo "FAIL: alert has no duration"; fails=$((fails+1)); }

# 5. Recovery clears the countdown.
reset_alerts; echo 0 > "$VERIFY_RC"; run
[ -f "$T/home/.cache/healthcheck/dashboard-failing-since" ] \
  && { echo "FAIL: recovery left the countdown behind"; fails=$((fails+1)); } \
  || echo "PASS: recovery clears the countdown"

# 6. And a fresh single failure is quiet again.
reset_alerts; echo 1 > "$VERIFY_RC"; run
expect "post-recovery single failure is quiet again" "0" "$(dash_alerts)"

# 7. rc=2 ("can't verify") must never alert, however often it repeats.
reset_alerts; rm -f "$T/home/.cache/healthcheck/dashboard-failing-since"
echo 2 > "$VERIFY_RC"; run; run
expect "rc=2 never alerts, even twice running" "0" "$(dash_alerts)"

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; exit 1
