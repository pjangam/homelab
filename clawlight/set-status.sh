#!/usr/bin/env bash
# Reports this session's clawlight state to the server. Called from Claude Code
# hooks (see ~/.claude/settings.json) with the new state as $1:
#   active | waiting | input_needed | end
# (`waiting` is sent on as `shells` when the turn ended with its own background
# shells still running - see background_shells below.)
#
# `waiting` (Stop) and `input_needed` (Notification/PermissionRequest) both turn
# the light red. Only `input_needed` can send a push: Stop fires at the end of
# every message, and a phone buzz per message is noise rather than a signal.
#
# Reads the hook event JSON Claude Code pipes to stdin to get session_id.
#
# CLAWLIGHT_SERVER_URL defaults to the local server (for sessions running on
# xero, where the server itself runs). On other machines (e.g. the MacBook),
# set it in your shell profile to xero's tailnet URL (xero.$TAILNET_SUFFIX,
# see .env / Readme.md), e.g.:
#   export CLAWLIGHT_SERVER_URL=https://xero.<your-tailnet-suffix>
#
# CLAWLIGHT_HOST_NAME overrides the reported host label (default: `hostname`,
# which can be an ugly DHCP/cloud-provider name like
# ip-192-168-1-101.ec2.internal) - set it in your shell profile for a friendly
# display name without touching the machine's actual system hostname, e.g.:
#   export CLAWLIGHT_HOST_NAME=mac
#
# A single session can be hidden from the light by creating a marker file named
# after its session id (CLAWLIGHT_IGNORE_DIR overrides the location):
#   touch ~/.claude/clawlight-ignore/<session_id>
# Per-session rather than per-machine, so one noisy session can be silenced
# without dropping the hooks for every other session on the same host. Delete
# the marker to unhide.
#
# Also reports this session's tmux pane, if it has one, so the light can jump
# you straight to the console that needs input (see focus-agent.sh).
#
# Never fails the hook on a network error - a status report is best-effort and
# must not block or break the actual Claude Code turn.
set -u

state="${1:?usage: set-status.sh <active|waiting|input_needed|end>}"
server_url="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
ignore_dir="${CLAWLIGHT_IGNORE_DIR:-$HOME/.claude/clawlight-ignore}"

hook_input="$(cat)"
session_id="$(printf '%s' "$hook_input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
# The label is the project, not wherever the shell happens to be: the hook's
# `cwd` follows every `cd` Claude makes, so a session in ~/code/foo read as
# `foo`, then `web`, then `scripts`. Claude Code sets CLAUDE_PROJECT_DIR for
# hooks to the directory the session started in; cwd is only the fallback.
cwd="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$hook_input" | jq -r '.cwd // empty' 2>/dev/null)}"
host="${CLAWLIGHT_HOST_NAME:-$(hostname)}"

# tmux coordinates, so the light can jump you to the console that needs you
# (see focus-agent.sh). $TMUX is "socketpath,serverpid,sessionid" - only the
# socket matters, because a pane id (%N) is already unique across the whole
# tmux server. Both are empty outside tmux, which just makes this session
# non-focusable rather than breaking anything.
tmux_socket="${TMUX%%,*}"
tmux_pane="${TMUX_PANE:-}"
# The tmux session's name, for display only (e.g. `homelab:clock` on the Pi's
# screensaver clock). A grouped session's own name carries a `-N` suffix, so
# prefer the group name, which is the one you typed.
tmux_session=""
if [ -n "$tmux_pane" ]; then
  tmux_session="$(tmux -S "$tmux_socket" display-message -p -t "$tmux_pane" \
    '#{?session_group,#{session_group},#{session_name}}' 2>/dev/null)"
fi

# How many of this session's background shells (Bash run_in_background, Monitor)
# are still alive. No hook fires when one starts or ends, so this asks the
# process table instead: every shell Claude Code runs a command in is a direct
# child of the claude process, and its command line sources a file from
# ~/.claude/shell-snapshots/. By the time `Stop` fires no foreground command can
# still be running, so any such child left over is a background one.
#
# The hook reaches us as claude -> sh -c -> this script, but `sh -c` may exec
# straight into the script instead (bash does, dash doesn't), so walk up to the
# nearest claude ancestor rather than counting levels. Stopping at the nearest
# one matters: a claude started from another session's Bash tool is itself
# inside a snapshot shell, which the outer claude would count.
background_shells() {
  local pid="$PPID" comm cmd i
  for i in 1 2 3 4; do
    [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || break
    # Both names, because they disagree across installs: the native binary is a
    # file named after its version (versions/2.1.273), renames its process to
    # `claude` on Linux, and macOS `comm` may still show the file name. argv[0]
    # is `claude` whenever it was launched as `claude`.
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
    cmd="$(ps -o args= -p "$pid" 2>/dev/null)"; cmd="${cmd%% *}"
    case "${comm##*/} ${cmd##*/}" in
      claude\ * | *\ claude | node\ *)
        ps -A -o ppid=,args= 2>/dev/null |
          awk -v p="$pid" '$1 == p && /shell-snapshots\/snapshot-/' | wc -l | tr -d ' '
        return ;;
    esac
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
  done
  echo 0
}

# A turn that ends with its own shells still running is not waiting on you:
# Claude is re-invoked when they finish. Report that as its own state (amber)
# rather than red. That covers `Stop`, and also the idle nudge: ~60s after a
# turn ends Claude Code sends a `Notification` ("Claude is waiting for your
# input"), which would otherwise flip an amber session to red - and push - while
# its build was still running. Any other `input_needed` (a permission prompt)
# is a real prompt and stays red.
# CLAWLIGHT_BACKGROUND_SHELLS overrides the count, for the tests.
idle_nudge=false
if [ "$state" = "input_needed" ] && printf '%s' "$hook_input" | jq -e '
     .hook_event_name == "Notification"
     and (.notification_type == "idle_prompt"
          or ((.message // "") | test("waiting for your input"; "i")))' >/dev/null 2>&1; then
  idle_nudge=true
fi
if { [ "$state" = "waiting" ] || [ "$idle_nudge" = true ]; } \
   && [ "${CLAWLIGHT_BACKGROUND_SHELLS:-$(background_shells)}" -gt 0 ] 2>/dev/null; then
  state="shells"
fi

# A hidden session reports `end` rather than simply going quiet: going quiet
# would leave whatever state it last reported sitting on the light until the
# server's 30-minute staleness prune, so hiding a `waiting` session would keep
# the light red for half an hour. `end` removes it on the very next hook event,
# and re-sending it on subsequent events is a harmless no-op server-side.
#
# The session id becomes a filename here, so ignore anything that isn't a plain
# token rather than letting a `/` or `..` walk the path somewhere unintended.
case "$session_id" in
  "" | *[!A-Za-z0-9_-]*) ;;
  *) if [ -e "$ignore_dir/$session_id" ]; then state="end"; fi ;;
esac

payload="$(jq -n --arg session_id "$session_id" --arg host "$host" --arg state "$state" --arg cwd "$cwd" \
  --arg tmux_socket "$tmux_socket" --arg tmux_pane "$tmux_pane" --arg tmux_session "$tmux_session" \
  '{session_id: $session_id, host: $host, state: $state, cwd: $cwd,
    tmux_socket: $tmux_socket, tmux_pane: $tmux_pane, tmux_session: $tmux_session}' 2>/dev/null)"

[ -n "$payload" ] && curl -fsS -m 3 -X POST "$server_url/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "$payload" >/dev/null 2>&1

exit 0
