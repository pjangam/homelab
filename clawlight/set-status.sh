#!/usr/bin/env bash
# Reports this session's clawlight state to the server. Called from Claude Code
# hooks (see ~/.claude/settings.json) with the new state as $1:
#   active | waiting | input_needed | end
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
cwd="$(printf '%s' "$hook_input" | jq -r '.cwd // empty' 2>/dev/null)"
host="${CLAWLIGHT_HOST_NAME:-$(hostname)}"

# tmux coordinates, so the light can jump you to the console that needs you
# (see focus-agent.sh). $TMUX is "socketpath,serverpid,sessionid" - only the
# socket matters, because a pane id (%N) is already unique across the whole
# tmux server. Both are empty outside tmux, which just makes this session
# non-focusable rather than breaking anything.
tmux_socket="${TMUX%%,*}"
tmux_pane="${TMUX_PANE:-}"

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
  --arg tmux_socket "$tmux_socket" --arg tmux_pane "$tmux_pane" \
  '{session_id: $session_id, host: $host, state: $state, cwd: $cwd,
    tmux_socket: $tmux_socket, tmux_pane: $tmux_pane}' 2>/dev/null)"

[ -n "$payload" ] && curl -fsS -m 3 -X POST "$server_url/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "$payload" >/dev/null 2>&1

exit 0
