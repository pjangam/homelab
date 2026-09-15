#!/usr/bin/env bash
# Tests the MirAIe AC auto-fix in projects/healthcheck/healthcheck.sh: a
# single unavailable run does nothing, a sustained one runs
# fix_miraie_ac.sh --force exactly once per outage, a cured outage never
# alerts, an uncured one alerts once with the fix's verdict, and repeated
# fixes in a day raise their own alert.
#
# Same mirror-repo approach as projects/spotifyd/test_healthcheck_spotifyd_advertising.sh -
# runs the real healthcheck.sh with the AC check, the fix script, both alert
# senders and the MQTT publisher stubbed, so a test never restarts node-red,
# mails, pushes, or writes to the live broker.
#
#   projects/miraie-ac/test_healthcheck_miraie_ac_autofix.sh
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/home/.cache"
# Mirror projects/ and tools/ as REAL directories holding per-file symlinks.
# A symlinked directory would make the `rm -f` + stub writes below go straight
# through to the real repo, deleting and replacing the live cron-called
# scripts.
for top in projects tools; do
  (cd "$REPO" && find "$top" -name node_modules -prune -o -name __pycache__ -prune -o -type d -print) | while read -r d; do mkdir -p "$T/repo/$d"; done
  (cd "$REPO" && find "$top" -name node_modules -prune -o -name __pycache__ -prune -o -type f -print) | while read -r f; do ln -sf "$REPO/$f" "$T/repo/$f"; done
done
for f in "$REPO"/.env*; do [ -f "$f" ] && ln -sf "$f" "$T/repo/$(basename "$f")"; done

stub() {  # stub <repo-relative path> <body>
  rm -f "$T/repo/$1"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/repo/$1"
  chmod +x "$T/repo/$1"
}

CHECK_RC="$T/check_rc"; FIX_RC="$T/fix_rc"; FIX_CURES="$T/fix_cures"; FIX_CALLS="$T/fix_calls"
stub projects/miraie-ac/check_miraie_ac_available.sh \
  '[ "$(cat "$CHECK_RC")" = 1 ] && echo "climate.panasonic_ac_panasonic_ac is unavailable"; exit "$(cat "$CHECK_RC")"'
# The fix records that it ran and, when FIX_CURES says so, makes the next
# check healthy - which is what a real re-delivered `online` does.
stub projects/miraie-ac/fix_miraie_ac.sh \
  'echo run >> "$FIX_CALLS"; [ "$(cat "$FIX_CURES")" = yes ] && echo 0 > "$CHECK_RC"; exit "$(cat "$FIX_RC")"'
# Keep the neighbouring checks healthy so they can't muddy these results.
stub projects/spotifyd/check_spotifyd_advertising.sh 'exit 0'
stub projects/healthcheck/verify_healthcheck_entities.sh 'exit 0'
rm -f "$T/repo/tools/notify/send_email.sh" "$T/repo/tools/notify/push_ntfy.sh"
echo 'send_email() { printf "EMAIL|%s|%s\n" "$1" "$(printf "%s" "$2" | tr "\n" " ")" >> "$ALERT_LOG"; }' > "$T/repo/tools/notify/send_email.sh"
echo 'push_ntfy() { printf "NTFY|%s|%s\n" "$1" "$(printf "%s" "$2" | tr "\n" " ")" >> "$ALERT_LOG"; }' > "$T/repo/tools/notify/push_ntfy.sh"
stub projects/healthcheck/publish_healthcheck_mqtt.py 'cat > "$MQTT_LOG"'

export ALERT_LOG="$T/alerts.log" MQTT_LOG="$T/mqtt.json" CHECK_RC FIX_RC FIX_CURES FIX_CALLS
STATE="$T/home/.cache/healthcheck"

run() { HOME="$T/home" bash "$T/repo/projects/healthcheck/healthcheck.sh" >> "$T/healthcheck.log" 2>&1; }
reset() { : > "$ALERT_LOG"; : > "$FIX_CALLS"; }
backdate() { echo $(( $(date +%s) - $1 * 60 )) > "$STATE/miraie-ac-unavailable-since"; }
fix_calls() { wc -l < "$FIX_CALLS" | tr -d ' '; }
ac_alerts() { grep -c "$1" "$ALERT_LOG" 2>/dev/null | head -1; }
mqtt() { jq -r "$1" "$MQTT_LOG"; }
expect() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; fails=$((fails+1)); fi; }

# 1. Healthy -> nothing.
reset; echo 0 > "$CHECK_RC"; echo 0 > "$FIX_RC"; echo yes > "$FIX_CURES"; run
expect "healthy AC runs no fix" "0" "$(fix_calls)"
expect "healthy AC raises nothing" "0" "$(ac_alerts "MirAIe AC")"

# 2. First unavailable run -> no fix yet (could be a discovery blip or a
#    node-red restart already in progress), but the tile shows it.
reset; echo 1 > "$CHECK_RC"; run
expect "a single unavailable run does NOT run the fix" "0" "$(fix_calls)"
expect "  ...nor alert" "0" "$(ac_alerts "MirAIe AC")"
expect "  ...but the tile shows it" "false" "$(mqtt .miraie_ac_ok)"

# 3. Second run, 15m on, and the fix cures it (2026-09-15's case) -> fixed,
#    no alert, countdown cleared, attempt counted on the tile.
reset; backdate 15; run
expect "sustained outage runs the fix once" "1" "$(fix_calls)"
expect "  ...a cured outage never alerts" "0" "$(ac_alerts "MirAIe AC")"
expect "  ...the tile is back to ok" "true" "$(mqtt .miraie_ac_ok)"
expect "  ...and counts the attempt" "1" "$(mqtt .miraie_ac_autofixes_24h)"
[ -e "$STATE/miraie-ac-unavailable-since" ] || [ -e "$STATE/miraie-ac-autofix-rc" ] \
  && { echo "FAIL: cure left countdown/attempt state behind"; fails=$((fails+1)); } \
  || echo "PASS:   ...and clears the countdown and attempt marker"

# 4. A new outage where the unit is off the cloud (fix exit 2) -> one alert on
#    both channels that says to switch the AC on.
reset; echo 1 > "$CHECK_RC"; echo 2 > "$FIX_RC"; echo no > "$FIX_CURES"; run; backdate 15; run
expect "unit-off outage runs the fix once" "1" "$(fix_calls)"
expect "  ...alerts by email" "1" "$(grep '^EMAIL|' "$ALERT_LOG" | grep -c 'Switch the AC on')"
expect "  ...and by ntfy" "1" "$(grep '^NTFY|' "$ALERT_LOG" | grep -c 'Switch the AC on')"

# 5. Still down 15m later -> no second fix, and no second alert (the text is
#    stable, so the dedup holds it).
#    (Not backdated again: moving the start would change "since HH:MM", which
#    a real outage never does.)
reset; run
expect "the fix is not retried within the same outage" "0" "$(fix_calls)"
expect "  ...and the alert is not re-sent" "0" "$(ac_alerts "MirAIe AC")"

# 6. Someone switches it on -> recovery clears the attempt marker, so the next
#    outage gets its own attempt.
reset; echo 0 > "$CHECK_RC"; run
[ -e "$STATE/miraie-ac-autofix-rc" ] \
  && { echo "FAIL: recovery left the attempt marker behind"; fails=$((fails+1)); } \
  || echo "PASS: recovery clears the attempt marker"

# 7. HA-side verdict (exit 3) names the MQTT integration.
reset; echo 1 > "$CHECK_RC"; echo 3 > "$FIX_RC"; run; backdate 15; run
expect "a new outage gets its own attempt" "1" "$(fix_calls)"
expect "  ...exit 3 says restart HA's MQTT integration" "1" "$(grep '^EMAIL|' "$ALERT_LOG" | grep -c "Restart HA's MQTT integration")"

# 8. That was the third attempt today -> the flapping alert fires.
expect "3 fixes in 24h raises the flapping alert" "1" "$(grep '^EMAIL|' "$ALERT_LOG" | grep -c 'needed the automatic fix 3 times')"

# 9. rc=2 from the check ("can't tell") never runs the fix or alerts.
reset; echo 0 > "$CHECK_RC"; run
reset; : > "$STATE/miraie-ac-autofixes.log"; echo 2 > "$CHECK_RC"; run; run
expect "check rc=2 never runs the fix" "0" "$(fix_calls)"
expect "  ...nor alerts about the AC" "0" "$(grep -c 'MirAIe AC has been unavailable' "$ALERT_LOG" | head -1)"

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; echo "healthcheck output:"; sed 's/^/  /' "$T/healthcheck.log" | tail -40; exit 1
