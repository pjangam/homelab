#!/usr/bin/env bash
# End-to-end test of clawlight's jump-to-console from the phone, against the
# RUNNING server.
#
# test_clawlight_phone_jump.py covers the server logic. This runs the real
# phone-attach.sh the way Termius would - in a terminal, after a tap - and
# checks where it lands: a grouped session on the tapped window and pane, with
# the desk session's own current window left alone.
#
# Uses a throwaway tmux server on its own socket and a fake host label, so it
# never touches a real session. The Termius side can only be tested on the phone.
#
# Run: scripts/clawlight/test_clawlight_phone_jump_e2e.sh
set -u

SERVER_URL="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
SOCK="/tmp/clawlight-phone-e2e-tmux.$$"
HOST_LABEL="clawlight-phone-e2e-$$"
SESSION_ID="phone-e2e-$$"
ATTACH="$(cd "$(dirname "$0")/../../clawlight" && pwd)/phone-attach.sh"
failures=0

check() {
  local desc="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    printf 'PASS  %s\n' "$desc"
  else
    printf 'FAIL  %s\n        expected %s, got %s\n' "$desc" "$want" "$got"
    failures=$((failures + 1))
  fi
}

cleanup() {
  curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/report" \
    -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"$SESSION_ID\",\"host\":\"$HOST_LABEL\",\"state\":\"end\"}" >/dev/null 2>&1
  # `script` doesn't always act on SIGTERM - see test_clawlight_focus_e2e.sh.
  if [ -n "${client_pid:-}" ]; then
    kill "$client_pid" 2>/dev/null
    sleep 0.2
    kill -9 "$client_pid" 2>/dev/null
  fi
  tmux -S "$SOCK" kill-server 2>/dev/null
  pkill -9 -f "$SOCK" 2>/dev/null
  rm -f "$SOCK"
}
trap cleanup EXIT

command -v tmux >/dev/null || { echo "tmux not installed"; exit 1; }
curl -fsS -m 3 "$SERVER_URL/clawlight/api/status" >/dev/null || {
  echo "clawlight server not reachable at $SERVER_URL"; exit 1; }

# Runs phone-attach.sh in a pty, as the phone's ssh session would, with its
# output captured. Outside tmux on purpose: the script refuses to nest.
run_attach() {
  env -u TMUX CLAWLIGHT_SERVER_URL="$SERVER_URL" CLAWLIGHT_HOST_NAME="$HOST_LABEL" \
    script -qfc "$ATTACH" "$1" >/dev/null 2>&1 &
  client_pid=$!
  disown "$client_pid" 2>/dev/null
}

# --- the "desk" session: two windows, the target pane in a split ------------
tmux -S "$SOCK" new-session -d -s desk -n target sleep 600
tmux -S "$SOCK" split-window -t desk:target sleep 600
target_pane="$(tmux -S "$SOCK" list-panes -t desk:target -F '#{pane_id}' | head -1)"
tmux -S "$SOCK" new-window -t desk -n decoy sleep 600
tmux -S "$SOCK" select-window -t desk:decoy
tmux -S "$SOCK" select-pane -t desk:target.1

curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SESSION_ID\",\"host\":\"$HOST_LABEL\",\"state\":\"waiting\",
       \"cwd\":\"/tmp/phone-e2e\",\"tmux_socket\":\"$SOCK\",\"tmux_pane\":\"$target_pane\"}" >/dev/null

# --- no tap: the script says so and attaches nothing ------------------------
out="$(mktemp)"
run_attach "$out"
sleep 2
check "with no request, it explains instead of attaching" \
  "$(grep -c 'no jump requested' "$out")" "1"
check "...and creates no session" \
  "$(tmux -S "$SOCK" list-sessions -F '#{session_name}' | grep -c '^phone-')" "0"

# --- the tap, then the connect ----------------------------------------------
check "the server accepts the phone jump" \
  "$(curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/phone-jump" \
      -H 'Content-Type: application/json' \
      -d "{\"session_id\":\"$SESSION_ID\"}" | jq -r '.ok')" \
  "true"

run_attach "$out"
sleep 2
phone_session="$(tmux -S "$SOCK" list-sessions -F '#{session_name}' | grep '^phone-' | head -1)"
check "a grouped phone session exists" "${phone_session:+yes}" "yes"
check "...in the desk session's group" \
  "$(tmux -S "$SOCK" display-message -p -t "$phone_session" '#{session_group}')" \
  "$(tmux -S "$SOCK" display-message -p -t desk '#{session_group}')"
check "...with a client attached" \
  "$(tmux -S "$SOCK" list-clients -F '#{client_session}' | head -1)" "$phone_session"
check "...showing the tapped window" \
  "$(tmux -S "$SOCK" display-message -p -t "$phone_session" '#{window_name}')" "target"
check "...on the tapped pane" \
  "$(tmux -S "$SOCK" display-message -p -t "$phone_session" '#{pane_id}')" "$target_pane"
check "the desk session stays on its own window" \
  "$(tmux -S "$SOCK" display-message -p -t desk '#{window_name}')" "decoy"
check "the request was consumed" \
  "$(curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/phone-claim" \
      -H 'Content-Type: application/json' -d "{\"host\":\"$HOST_LABEL\"}" | jq -r '.ok')" \
  "false"

# --- detaching throws the phone session away ---------------------------------
tmux -S "$SOCK" detach-client -s "$phone_session"
sleep 1
check "detaching removes the phone session" \
  "$(tmux -S "$SOCK" list-sessions -F '#{session_name}' | grep -c '^phone-')" "0"
check "...and leaves the desk session" \
  "$(tmux -S "$SOCK" has-session -t desk 2>/dev/null && echo yes)" "yes"

rm -f "$out"
echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
