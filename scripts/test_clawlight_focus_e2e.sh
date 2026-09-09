#!/usr/bin/env bash
# End-to-end test of clawlight's jump-to-console, against the RUNNING server.
#
# scripts/test_clawlight_focus.py covers the routing logic in isolation; this
# covers the parts that only exist when it's really wired up - the SSE stream
# actually delivering to the agent, and the agent's tmux commands actually
# moving an attached client. Those are exactly the bits that look fine in unit
# tests and still do nothing in practice.
#
# Deliberately uses a throwaway tmux server on its own socket and a fake host
# label, so running this never yanks the terminal you're sitting in.
#
# Run: scripts/test_clawlight_focus_e2e.sh
set -u

SERVER_URL="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
SOCK="/tmp/clawlight-e2e-tmux.$$"
HOST_LABEL="clawlight-e2e-$$"
SESSION_ID="e2e-$$"
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
  # Remove the fake session from the light, or it would sit there as a
  # phantom console until the server's 30-minute staleness prune.
  curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/report" \
    -H 'Content-Type: application/json' \
    -d "{\"session_id\":\"$SESSION_ID\",\"host\":\"$HOST_LABEL\",\"state\":\"end\"}" >/dev/null 2>&1
  # The agent is `curl | while read`, so killing the script leaves the curl
  # holding the SSE stream open - which keeps the server counting a focus
  # listener for a host that no longer exists. Kill its children too, and
  # sweep by the run-unique host label in case the pipeline outlived it.
  if [ -n "${agent_pid:-}" ]; then
    pkill -P "$agent_pid" 2>/dev/null
    kill "$agent_pid" 2>/dev/null
  fi
  pkill -f "host=$HOST_LABEL" 2>/dev/null
  # `script` holds the pty in raw mode and doesn't always act on SIGTERM, so
  # follow up with SIGKILL and a sweep by the run-unique socket path - an
  # orphan here would sit around holding a pty for the rest of the session.
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

# --- a throwaway tmux server with two windows -------------------------------
# `sleep`, not a shell: a detached `sh` reads EOF and exits immediately, taking
# its window with it, which silently leaves nothing to switch between.
tmux -S "$SOCK" new-session -d -s e2e -n target sleep 600
tmux -S "$SOCK" new-window -t e2e -n decoy sleep 600
target_pane="$(tmux -S "$SOCK" list-panes -t e2e:target -F '#{pane_id}')"

# Attach a real client, so switch-client has something to move. `script`
# gives it the pty tmux insists on without needing a terminal of our own.
script -qc "tmux -S '$SOCK' attach -t e2e" /dev/null >/dev/null 2>&1 &
client_pid=$!
disown "$client_pid" 2>/dev/null  # else the shell prints "Killed" job noise at teardown
sleep 1

tmux -S "$SOCK" select-window -t e2e:decoy
check "starts on the decoy window" \
  "$(tmux -S "$SOCK" display-message -p -t e2e '#{window_name}')" "decoy"

# --- register a fake session pointing at that pane --------------------------
curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SESSION_ID\",\"host\":\"$HOST_LABEL\",\"state\":\"waiting\",
       \"cwd\":\"/tmp/e2e\",\"tmux_socket\":\"$SOCK\",\"tmux_pane\":\"$target_pane\"}" >/dev/null

check "the session reports as reachable" \
  "$(curl -fsS -m 3 "$SERVER_URL/clawlight/api/status" | jq -r ".sessions[] | select(.id==\"$SESSION_ID\") | .reachable")" \
  "true"

# --- run the agent for that fake host ---------------------------------------
CLAWLIGHT_SERVER_URL="$SERVER_URL" CLAWLIGHT_HOST_NAME="$HOST_LABEL" \
  "$(dirname "$0")/../clawlight/focus-agent.sh" >/dev/null 2>&1 &
agent_pid=$!
sleep 2

# --- the actual click -------------------------------------------------------
check "the server accepts the jump" \
  "$(curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/focus" \
      -H 'Content-Type: application/json' \
      -d "{\"session_id\":\"$SESSION_ID\"}" | jq -r '.ok')" \
  "true"

sleep 2
check "the agent moved tmux to the target window" \
  "$(tmux -S "$SOCK" display-message -p -t e2e '#{window_name}')" "target"
check "...and to the target pane" \
  "$(tmux -S "$SOCK" display-message -p -t e2e '#{pane_id}')" "$target_pane"
check "the attached client is on that session" \
  "$(tmux -S "$SOCK" list-clients -F '#{client_session}' | head -1)" "e2e"

# --- a jump for a host with no agent must not queue up forever --------------
tmux -S "$SOCK" select-window -t e2e:decoy
curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SESSION_ID-off\",\"host\":\"$HOST_LABEL-off\",\"state\":\"waiting\",
       \"cwd\":\"/tmp/e2e\",\"tmux_socket\":\"$SOCK\",\"tmux_pane\":\"$target_pane\"}" >/dev/null
check "a jump to a host with no agent is refused, not flashed as success" \
  "$(curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/focus" \
      -H 'Content-Type: application/json' \
      -d "{\"session_id\":\"$SESSION_ID-off\"}" | jq -r '.reason')" \
  "no focus agent running on $HOST_LABEL-off"
sleep 2
check "...and nothing moves" \
  "$(tmux -S "$SOCK" display-message -p -t e2e '#{window_name}')" "decoy"
curl -fsS -m 3 -X POST "$SERVER_URL/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SESSION_ID-off\",\"host\":\"$HOST_LABEL-off\",\"state\":\"end\"}" >/dev/null

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
