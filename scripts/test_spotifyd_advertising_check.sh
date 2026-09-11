#!/usr/bin/env bash
# Tests scripts/check_spotifyd_advertising.sh without touching the real
# spotifyd, avahi, or the alerting path. Faults are simulated by shadowing
# avahi-browse / systemctl with stubs earlier in PATH.
set -uo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT="$DIR/check_spotifyd_advertising.sh"
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
fails=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS: $1"
  else echo "FAIL: $1 (expected rc=$2, got rc=$3)"; fails=$((fails+1)); fi
}

# Stub systemctl so every case below agrees spotifyd and avahi-daemon are up;
# individual cases override avahi-browse to vary what's being advertised.
cat > "$STUB/systemctl" <<'S'
#!/usr/bin/env bash
# --user is-active spotifyd -> active; system is-active avahi-daemon -> active
exit ${STUB_SYSTEMCTL_RC:-0}
S
chmod +x "$STUB/systemctl"

adv_stub() { printf '#!/usr/bin/env bash\n%s\nexit 0\n' "$1" > "$STUB/avahi-browse"; chmod +x "$STUB/avahi-browse"; }

# 1. Advertising normally -> healthy.
adv_stub 'echo "+;enp1s0;IPv4;xero;_spotify-connect._tcp;local"'
PATH="$STUB:$PATH" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=0 when the host is advertising" 0 $?

# 2. The actual Sept 2026 fault: running, but advertising nothing.
adv_stub 'true'
PATH="$STUB:$PATH" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=1 when running but advertising nothing" 1 $?

# 3. Only a *different* host is advertising - must not count as ours.
adv_stub 'echo "+;enp1s0;IPv4;some-speaker;_spotify-connect._tcp;local"'
PATH="$STUB:$PATH" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=1 when only another device advertises" 1 $?

# 4. Prefix collision must not satisfy the check (exact field match, not grep).
adv_stub 'echo "+;enp1s0;IPv4;xero-speaker;_spotify-connect._tcp;local"'
PATH="$STUB:$PATH" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=1 when a similarly-named device advertises (no substring match)" 1 $?

# 5. A removal line (-) must not be read as present.
adv_stub 'echo "-;enp1s0;IPv4;xero;_spotify-connect._tcp;local"'
PATH="$STUB:$PATH" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=1 on a removal event rather than an add" 1 $?

# 6. spotifyd not running -> rc=2, "not applicable", never an alert.
adv_stub 'true'
STUB_SYSTEMCTL_RC=1 PATH="$STUB:$PATH" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=2 (not rc=1) when spotifyd isn't running" 2 $?

# 7. avahi-browse missing entirely -> rc=2, can't verify, don't blame spotifyd.
# Built as a minimal bin holding every tool the script needs *except*
# avahi-browse, so this tests a missing avahi rather than a missing coreutils
# (an empty PATH just yields 127 and proves nothing).
MINIMAL="$STUB/minimal"; mkdir -p "$MINIMAL"
for t in bash sh id hostname timeout awk cat date grep; do
  real=$(command -v "$t") && ln -sf "$real" "$MINIMAL/$t"
done
cp "$STUB/systemctl" "$MINIMAL/systemctl"
PATH="$MINIMAL" "$SCRIPT" 5 xero >/dev/null 2>&1
check "rc=2 when avahi-browse is unavailable" 2 $?

echo
[ "$fails" -eq 0 ] && { echo "All checks passed."; exit 0; }
echo "$fails check(s) failed."; exit 1
