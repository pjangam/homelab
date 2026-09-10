#!/usr/bin/env bash
# Exercises mac-dns-recorder.sh on Linux against stubbed macOS tools.
#
# The recorder only ever runs on the MacBook, which xero cannot ssh into, so
# without this it would ship completely unexercised. This does not prove the
# scutil output parses correctly on a real Mac - it proves the change
# detection, the snapshot writing, and the two report views work at all.
set -u

REC="$(cd "$(dirname "$0")" && pwd)/mac-dns-recorder.sh"
TMP=$(mktemp -d)
BIN="$TMP/bin"; mkdir -p "$BIN"
export DNS_RECORDER_DIR="$TMP/state"
export DNS_RECORDER_INTERVAL=1
LOG="$DNS_RECORDER_DIR/snapshots.log"

pass=0; fail=0
check() { # check <description> <condition-as-command>
  if "${@:2}" >/dev/null 2>&1; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}

# --- stubs: the resolver config lives in $TMP/dns so a test can change it ----
cat > "$BIN/scutil" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--dns" ]; then cat "$TMP/dns"; exit 0; fi
if [ "${1:-}" = "--nc" ]; then echo "(no VPN services)"; exit 0; fi
input=$(cat)
case "$input" in
  list) echo "  subKey [0] = Setup:/Network/Service/ABC/DNS"
        echo "  subKey [1] = State:/Network/Service/ABC/DNS" ;;
  "show Setup:"*) echo "  ServerAddresses : <array> {"; echo "    0 : 192.168.1.123"; echo "  }" ;;
  "show State:"*) sed -n 's/^ *nameserver\[0\] : /    0 : /p' "$TMP/dns" | head -1 ;;
esac
STUB
for t in networksetup ipconfig route ping ifconfig; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/$t"
done
printf '#!/usr/bin/env bash\necho "Current Wi-Fi Network: TestNet"\n' > "$BIN/networksetup"
printf '#!/usr/bin/env bash\necho "  interface: en0"\n' > "$BIN/route"
chmod +x "$BIN"/*
export TMP
export SCUTIL="$BIN/scutil" NETWORKSETUP="$BIN/networksetup" IPCONFIG="$BIN/ipconfig"
export ROUTE="$BIN/route" PING="$BIN/ping" IFCONFIG="$BIN/ifconfig"

set_dns() { printf '  nameserver[0] : %s\n' "$1" > "$TMP/dns"; }

echo "== healthy resolver =="
set_dns 192.168.1.123
"$REC" --once >/dev/null
check "a forced snapshot is written"            test -s "$LOG"
check "it records the configured resolver"      grep -q "192.168.1.123" "$LOG"
check "it records the Setup/State ownership"    grep -q "State (runtime: DHCP or VPN)" "$LOG"

echo
echo "== the loop: silence when nothing changes, a snapshot when it does =="
"$REC" & LOOP=$!
sleep 3
before=$(grep -c '^SNAPSHOT' "$LOG")
sleep 3
check "an unchanged config records nothing new" test "$(grep -c '^SNAPSHOT' "$LOG")" = "$before"

# the actual failure mode: en0 pointed at an off-LAN server
set_dns 192.168.0.2
sleep 4
kill $LOOP 2>/dev/null; wait $LOOP 2>/dev/null
check "a changed resolver is snapshotted"       test "$(grep -c '^SNAPSHOT' "$LOG")" -gt "$before"
check "the new bad server is captured"          grep -q "192.168.0.2" "$LOG"
check "the change is labelled as a change"      grep -q "resolver configuration CHANGED" "$LOG"

echo
echo "== reports =="
check "--show reports the recorder as alive"    bash -c "'$REC' --show | grep -q 'ALIVE'"
check "--show prints a snapshot"                bash -c "'$REC' --show | grep -q 'SNAPSHOT'"
check "--timeline lists the changes"            bash -c "'$REC' --timeline | grep -q '192.168.0.2'"

# The distinction watch-peer-dns.sh had to learn: a dead watcher must not look
# like a quiet one.
echo 1 > "$DNS_RECORDER_DIR/.last-poll"
check "a dead recorder reports STALE, not quiet" bash -c "'$REC' --show | grep -q 'STALE'"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
rm -rf "$TMP"
[ "$fail" = 0 ]
