#!/usr/bin/env bash
# Tests projects/spotifyd/watchdog_spotifyd.sh's journal-driven restarts
# without touching the real spotifyd. systemctl, journalctl, ss and logger are
# stubbed earlier in PATH; HOME points at a temp dir so the state files
# (restarts.log, down-since) are the test's own. A restart is "systemctl
# restart was called", recorded by the stub.
set -uo pipefail

SCRIPT="$(dirname "$(readlink -f "$0")")/watchdog_spotifyd.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
fails=0

cat > "$TMP/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *show*MainPID*) echo 4242 ;;
  *restart*) echo restart >> "$WD_TEST_CALLS" ;;
esac
STUB
cat > "$TMP/bin/journalctl" <<'STUB'
#!/usr/bin/env bash
cat "$WD_TEST_JOURNAL"
STUB
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/ss"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/logger"
chmod +x "$TMP/bin"/*

now=$(date +%s)
line() { # seconds_ago message
  echo "$((now - $1)).123456 wol-sender spotifyd[4242]: $2"
}

run() { # name expect(restart|none) - journal on stdin
  cat > "$TMP/journal"
  rm -f "$TMP/calls"
  HOME="$TMP/home" PATH="$TMP/bin:$PATH" WD_TEST_JOURNAL="$TMP/journal" \
    WD_TEST_CALLS="$TMP/calls" "$SCRIPT"
  got=none; [ -s "$TMP/calls" ] && got=restart
  if [ "$got" = "$2" ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (expected $2, got $got)"; fails=$((fails+1))
  fi
}

{ line 7200 "[INFO] Authenticated as 'x' !"; } \
  | run "healthy session is left alone" none

{ line 7200 "[INFO] Authenticated as 'x' !"
  line 3600 "[ERROR] Connection to server closed."; } \
  | run "closed an hour ago, never re-authenticated -> restart" restart

{ line 7200 "[INFO] Authenticated as 'x' !"
  line 60 "[ERROR] Connection to server closed."; } \
  | run "closed a minute ago -> still within grace" none

{ line 7200 "[INFO] Authenticated as 'x' !"
  line 3600 "[ERROR] Connection to server closed."
  line 3500 "[INFO] Authenticated as 'x' !"; } \
  | run "closed then re-authenticated (the 2026-10-26 11:08 recovery) -> left alone" none

{ line 7200 "[WARN] Setting up dns-sd failed: No such device (os error 19)"
  line 7100 "[INFO] Authenticated as 'x' !"; } \
  | run "zeroconf failure still restarts on sight" restart

: | run "empty journal (fresh start) -> left alone" none

if grep -q . "$TMP/home/.cache/spotifyd-watchdog/restarts.log" 2>/dev/null; then
  echo "PASS: restarts are appended to restarts.log"
else
  echo "FAIL: restarts.log is empty"; fails=$((fails+1))
fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
