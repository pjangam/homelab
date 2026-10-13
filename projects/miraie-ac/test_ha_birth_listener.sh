#!/usr/bin/env bash
# Tests ha_birth_listener.sh with the subscriber, the AC check and the fix all
# stubbed, so it never touches the broker, HA or node-red:
#   - `online` with the entity down runs the fix once
#   - `online` with the entity fine does not
#   - anything other than `online` is ignored without even checking
#   - a burst of births right after one fix does not fix again
#   - a check that cannot tell is retried, then left alone
#   - a Fix AC press runs the fix with no check, a queued re-press does not,
#     and the button's discovery config is published retained
#
#   projects/miraie-ac/test_ha_birth_listener.sh
set -uo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0

# The check exits with whatever $T/check_rc holds; the fix records the call
# and, like the real re-delivered `online`, makes the next check healthy.
printf '#!/usr/bin/env bash\necho check >> "%s/calls"; exit "$(cat "%s/check_rc")"\n' "$T" "$T" > "$T/check"
printf '#!/usr/bin/env bash\necho fix >> "%s/calls"; echo 0 > "%s/check_rc"\n' "$T" "$T" > "$T/fix"
chmod +x "$T/check" "$T/fix"

run() {  # run <check rc> <payloads...>  (a bare payload is a birth; press:<p> is a button press)
  echo "$1" > "$T/check_rc"; shift
  : > "$T/calls"; : > "$T/pubs"
  local m
  for m in "$@"; do
    case "$m" in
      press:*) echo "homelab/miraie-ac/fix ${m#press:}" ;;
      *)       echo "homeassistant/status $m" ;;
    esac
  done > "$T/payloads"
  SUB_CMD="cat $T/payloads" PUB_CMD="echo \"\$1\" >> $T/pubs" \
    CHECK="$T/check" FIX="$T/fix" SETTLE_S=0 CHECK_RETRY_S=0 \
    LISTENER_ONCE=1 bash "$DIR/ha_birth_listener.sh" > "$T/out" 2>&1
}
count() { grep -c "^$1$" "$T/calls"; }
expect() {  # expect <name> <checks> <fixes>
  local c f; c=$(count check); f=$(count fix)
  if [ "$c" = "$2" ] && [ "$f" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 - expected $2 checks/$3 fixes, got $c/$f"; sed 's/^/    /' "$T/out"
    fails=$((fails + 1))
  fi
}

run 1 online;                 expect "birth with entity down fixes"          1 1
run 0 online;                 expect "birth with entity fine does nothing"   1 0
run 1 offline "";             expect "non-birth payloads are ignored"        0 0
run 1 online online online;   expect "burst of births fixes only once"       3 1
run 2 online;                 expect "can't-tell check retried, not fixed"   4 0
run 0 press:force;            expect "button press fixes without checking"   0 1
run 0 press:force press:force; expect "queued re-press does not fix again"   0 1
run 0 press:other;            expect "unknown button payload is ignored"     0 0

if grep -qx "homeassistant/button/miraie_ac_fix/config" "$T/pubs"; then
  echo "PASS: button discovery config published"
else
  echo "FAIL: button discovery config not published"; fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
