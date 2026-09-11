#!/usr/bin/env bash
# Tests scripts/wait_for_network.sh without touching the real network.
#
# The no-network path is exercised by shadowing `ip` with a stub earlier in
# PATH. A network namespace would be more faithful, but unprivileged userns
# is disabled on this host (`unshare -rn` -> "write failed /proc/self/uid_map"),
# and the script's only real contract is "loop until `ip ... scope global up`
# prints something, else time out".
set -uo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/wait_for_network.sh"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
fails=0

check() { # name expected_rc actual_rc
  if [ "$2" = "$3" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (expected rc=$2, got rc=$3)"; fails=$((fails+1))
  fi
}

# 1. Real network present -> succeeds, and fast.
start=$(date +%s)
"$SCRIPT" 10; rc=$?
elapsed=$(( $(date +%s) - start ))
check "returns 0 when a global IPv4 address exists" 0 "$rc"
if [ "$elapsed" -le 2 ]; then
  echo "PASS: returns promptly (${elapsed}s) rather than polling to the deadline"
else
  echo "FAIL: took ${elapsed}s with the network up"; fails=$((fails+1))
fi

# 2. No usable interface -> times out non-zero, after roughly the timeout.
cat > "$STUB_DIR/ip" <<'STUB'
#!/usr/bin/env bash
exit 0   # prints nothing: no address matches
STUB
chmod +x "$STUB_DIR/ip"

start=$(date +%s)
PATH="$STUB_DIR:$PATH" "$SCRIPT" 3 2>/dev/null; rc=$?
elapsed=$(( $(date +%s) - start ))
check "returns non-zero when no address ever appears" 1 "$rc"
if [ "$elapsed" -ge 3 ] && [ "$elapsed" -le 6 ]; then
  echo "PASS: waited out the full timeout (${elapsed}s for a 3s limit)"
else
  echo "FAIL: timeout path took ${elapsed}s, expected ~3s"; fails=$((fails+1))
fi

# 3. Address appears late -> still succeeds, without waiting the whole timeout.
cat > "$STUB_DIR/ip" <<'STUB'
#!/usr/bin/env bash
MARKER="$WFN_TEST_MARKER"
n=$(cat "$MARKER" 2>/dev/null || echo 0)
echo $((n+1)) > "$MARKER"
[ "$n" -ge 2 ] && echo "enp1s0  UP  192.168.1.123/24"
exit 0
STUB
chmod +x "$STUB_DIR/ip"
export WFN_TEST_MARKER="$STUB_DIR/calls"

start=$(date +%s)
PATH="$STUB_DIR:$PATH" "$SCRIPT" 20; rc=$?
elapsed=$(( $(date +%s) - start ))
check "returns 0 once a late address shows up" 0 "$rc"
if [ "$elapsed" -ge 2 ] && [ "$elapsed" -le 6 ]; then
  echo "PASS: returned as soon as the address appeared (${elapsed}s), not at the deadline"
else
  echo "FAIL: late-address path took ${elapsed}s"; fails=$((fails+1))
fi

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; exit 1
