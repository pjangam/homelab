#!/usr/bin/env bash
# Exercises ssd_temp_guard.sh against a fake sensor and a fake tunable, so it
# can be run anywhere without a hot disk, root, or ZFS loaded. Each case
# plays a temperature sequence (one reading per second) and checks what the
# guard did: whether it clamped, whether it released, and what it left in the
# tunable afterwards.
#
#   projects/ssd-temp-guard/test_ssd_temp_guard.sh
#
# Run it on xero. It needs GNU `timeout` to stop the guard's loop, which
# macOS does not have - without this check the no-clamp cases "pass" by
# never running the guard at all.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
command -v timeout >/dev/null || {
  echo "needs GNU timeout (coreutils) - run this on xero, not the Mac" >&2
  exit 2
}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

fail=0
run_case() {  # name "temps..." expect_clamp expect_release expect_final_param
  local name=$1 temps=$2 want_clamp=$3 want_release=$4 want_param=$5
  echo 1000 > "$t/param"
  set -- $temps
  echo "$(( $1 * 1000 ))" > "$t/temp"

  # Play the rest of the sequence, one reading a second, while the guard runs.
  ( shift; for c in "$@"; do sleep 1; echo "$(( c * 1000 ))" > "$t/temp.new"; mv "$t/temp.new" "$t/temp"; done ) &
  local ticker=$!
  local secs=$(( $(wc -w <<< "$temps") + 2 ))

  INTERVAL=1 CLAMP_SAMPLES=2 NTFY_HEALTH_TOKEN= \
    TEMP_FILE=$t/temp PARAM_FILE=$t/param HOME=$t \
    timeout "$secs" "$here/ssd_temp_guard.sh" > "$t/log" 2>&1
  kill $ticker 2>/dev/null; wait $ticker 2>/dev/null

  local got_clamp=no got_release=no got_param
  grep -q CLAMPED "$t/log" && got_clamp=yes
  # "released on exit:" is the trap unwinding, not a real in-run release.
  grep -q "released:" "$t/log" && got_release=yes
  got_param=$(cat "$t/param")

  if [ "$got_clamp" = "$want_clamp" ] && [ "$got_release" = "$want_release" ] \
     && [ "$got_param" = "$want_param" ]; then
    printf 'ok   %-34s clamp=%-3s release=%-3s param=%s\n' "$name" "$got_clamp" "$got_release" "$got_param"
  else
    printf 'FAIL %-34s clamp=%s (want %s) release=%s (want %s) param=%s (want %s)\n' \
      "$name" "$got_clamp" "$want_clamp" "$got_release" "$want_release" "$got_param" "$want_param"
    sed 's/^/       /' "$t/log"
    fail=1
  fi
}

# Normal running: nothing near the limit, so the tunable is never touched.
run_case "cool throughout"        "45 48 50 47"       no  no  1000
# One reading over the line is not enough - CLAMP_SAMPLES is 2.
run_case "single spike ignored"   "50 72 50 48"       no  no  1000
# Sustained over the rating: clamp. The trap restores on exit, so the final
# value is NORMAL even though it clamped mid-run - the log is the evidence.
run_case "sustained hot clamps"   "50 72 74 76 78"    yes no  1000
# Hot then properly cool: clamps, then releases while still running.
run_case "clamps then releases"   "50 72 74 55 50"    yes yes 1000
# Hysteresis: 65 is below the clamp point but above the release point, so it
# must stay clamped rather than flapping back.
run_case "65C stays clamped"      "50 72 74 65 65 65" yes no  1000

# Starting up while already clamped must not remember the throttle as normal.
echo 4 > "$t/param"; echo 50000 > "$t/temp"
INTERVAL=1 NTFY_HEALTH_TOKEN= TEMP_FILE=$t/temp PARAM_FILE=$t/param HOME=$t \
  timeout 3 "$here/ssd_temp_guard.sh" > "$t/log" 2>&1
if grep -q "release below 62°C to 1000" "$t/log"; then
  echo "ok   restart while clamped          falls back to NORMAL=1000"
else
  echo "FAIL restart while clamped          did not fall back to 1000"; sed 's/^/       /' "$t/log"; fail=1
fi

[ "$fail" = 0 ] && echo "all passed" || echo "FAILURES"
exit $fail
