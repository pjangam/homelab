#!/usr/bin/env bash
# Tests renew_miraie_login.sh's decisions with ssh, the fix script and both
# alert senders faked: nothing touches the Pi, node-red, mail or ntfy.
#
#   projects/miraie-ac/test_renew_miraie_login.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

mkdir -p "$T/bin" "$T/notify"
# Fake ssh answers `docker inspect` with whatever start time the test set.
cat > "$T/bin/ssh" <<'S'
#!/usr/bin/env bash
[ -f "$T/pi_down" ] && exit 255
cat "$T/started_at"
S
# Fake fix: records the call, exits FIX_RC, and "restarts" (moves the start
# time to now) unless told not to.
cat > "$T/fix" <<'S'
#!/usr/bin/env bash
echo run >> "$T/fix_calls"
[ -f "$T/no_restart" ] || date -u +%Y-%m-%dT%H:%M:%SZ > "$T/started_at"
echo "fake fix output"
exit "$(cat "$T/fix_rc")"
S
chmod +x "$T/bin/ssh" "$T/fix"
echo 'send_email() { echo "EMAIL|$1" >> "$T/alerts"; }' > "$T/notify/send_email.sh"
echo 'push_ntfy() { echo "NTFY|$1" >> "$T/alerts"; }' > "$T/notify/push_ntfy.sh"

export T PATH="$T/bin:$PATH" FIX_SCRIPT="$T/fix" NOTIFY_DIR="$T/notify"

start_days_ago() { date -u -d "-$1 days" +%Y-%m-%dT%H:%M:%SZ > "$T/started_at"; }
reset() { : > "$T/fix_calls"; : > "$T/alerts"; rm -f "$T/no_restart" "$T/pi_down"; echo 0 > "$T/fix_rc"; }
run() { "$HERE/renew_miraie_login.sh" "$@" > "$T/out" 2>&1; echo $?; }
calls() { wc -l < "$T/fix_calls" | tr -d ' '; }
alerts() { wc -l < "$T/alerts" | tr -d ' '; }
expect() { if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; sed 's/^/    /' "$T/out"; fails=$((fails+1)); fi; }

reset; start_days_ago 10
expect "10-day-old login: not due, exit 0" "0" "$(run)"
expect "  ...no restart" "0" "$(calls)"

reset; start_days_ago 69
expect "69 days: still not due" "0" "$(run)"
expect "  ...no restart" "0" "$(calls)"

reset; start_days_ago 71
expect "71 days (under 2 weeks to expiry): renews, exit 0" "0" "$(run)"
expect "  ...restarts once" "1" "$(calls)"
expect "  ...no alert" "0" "$(alerts)"

reset; start_days_ago 5
expect "--force renews a fresh login" "0" "$(run --force)"
expect "  ...restarts once" "1" "$(calls)"

reset; start_days_ago 71; echo 2 > "$T/fix_rc"
expect "fix exit 2 (AC off) still counts as renewed" "0" "$(run)"
expect "  ...no alert" "0" "$(alerts)"

reset; start_days_ago 71; echo 1 > "$T/fix_rc"
expect "fix exit 1 (bridge down): renewal fails, exit 1" "1" "$(run)"
expect "  ...alerts by email and ntfy" "2" "$(alerts)"

reset; start_days_ago 71; touch "$T/no_restart"
expect "fix exit 0 but node-red start time unchanged: fails" "1" "$(run)"

reset; start_days_ago 71; touch "$T/pi_down"
expect "Pi unreachable: exit 2" "2" "$(run)"
expect "  ...no restart, no alert" "0 0" "$(calls) $(alerts)"

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; exit 1
