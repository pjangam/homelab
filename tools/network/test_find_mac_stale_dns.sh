#!/usr/bin/env bash
# Exercises find_mac_stale_dns.sh on Linux against stubbed macOS tools.
#
# Same reason as test_mac_dns_recorder.sh: this only ever runs on the MacBook,
# which xero cannot ssh into, so without this it ships unexercised. It proves
# the three verdicts are reported correctly - and in particular that a section
# which could not be checked says SKIPPED rather than passing as clean, which
# is the whole failure this tool exists to stop repeating.
set -u

SUT="$(cd "$(dirname "$0")" && pwd)/find_mac_stale_dns.sh"
TMP=$(mktemp -d)
BIN="$TMP/bin"; mkdir -p "$BIN"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
check() { # check <description> <condition-as-command>
  if "${@:2}" >/dev/null 2>&1; then printf '  ok    %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi
}

# --- stubs -----------------------------------------------------------------
# plutil prints whatever $TMP/plist holds, so a test can plant a hit or not.
cat > "$BIN/plutil" <<'STUB'
#!/usr/bin/env bash
cat "$TMP/plist" 2>/dev/null
STUB
printf '#!/usr/bin/env bash\ncase "${1:-}" in -listlocations) echo Automatic;; -getcurrentlocation) echo Automatic;; esac\n' > "$BIN/networksetup"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/profiles"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/scutil"
printf '#!/usr/bin/env bash\necho 15.0\n' > "$BIN/sw_vers"
chmod +x "$BIN"/*
export TMP
export PATH="$BIN:$PATH"
# Point the persistent-store paths at fixtures; macOS keeps them under
# /Library, which does not exist here.
export SCPREF="$TMP/preferences.plist" NETIF="$TMP/NetworkInterfaces.plist"
: > "$SCPREF"; : > "$NETIF"

run() { bash "$SUT" "$@" 2>&1; }

echo "== a clean persistent store =="
echo '  "ServerAddresses" => 192.168.1.123' > "$TMP/plist"
out=$(run)
check "reports the plist as clean"          grep -q "clean      no match anywhere" <<<"$out"
check "concludes it is written at runtime"  grep -q "written at runtime" <<<"$out"
check "points at the recorder as the fix"   grep -q "setup-mac-dns-recorder.sh" <<<"$out"

echo
echo "== the bad pair parked in the persistent store =="
cat > "$TMP/plist" <<'PLIST'
  "UserDefinedName" => "Wi-Fi"
  "ServerAddresses" => [
    0 => 192.168.0.2
    1 => 192.169.0.2
  ]
PLIST
out=$(run)
check "reports FOUND"                       grep -q ">>> FOUND" <<<"$out"
check "names the persistent store"          grep -q "preferences.plist" <<<"$out"
check "says the toggle will not fix it"     grep -q "not with the toggle" <<<"$out"
check "does not still claim runtime-only"   bash -c "! grep -q 'written at runtime' <<<\"\$0\"" "$out"

echo
echo "== an unreadable section must say SKIPPED, not clean =="
rm -f "$BIN/profiles"        # profiles now absent entirely
echo '  "ServerAddresses" => 192.168.1.123' > "$TMP/plist"
out=$(run)
check "absent profiles reports SKIPPED"     grep -q "SKIPPED    profiles show returned nothing" <<<"$out"
check "the log sweep is SKIPPED by default" grep -q "SKIPPED    not searched" <<<"$out"
check "the summary warns about SKIPPED"     grep -q "Sections marked SKIPPED" <<<"$out"

echo
echo "== --pattern retargets the hunt =="
echo '  "ServerAddresses" => 10.9.9.9' > "$TMP/plist"
out=$(run --pattern '10\.9\.9\.9')
check "a custom pattern is matched"         grep -q ">>> FOUND" <<<"$out"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
