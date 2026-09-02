#!/usr/bin/env bash
# Reports this session's clawlight state to the server. Called from Claude Code
# hooks (see ~/.claude/settings.json) with the new state as $1:
#   active | waiting | end
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
# Never fails the hook on a network error - a status report is best-effort and
# must not block or break the actual Claude Code turn.
set -u

state="${1:?usage: set-status.sh <active|waiting|end>}"
server_url="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"

hook_input="$(cat)"
session_id="$(printf '%s' "$hook_input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
cwd="$(printf '%s' "$hook_input" | jq -r '.cwd // empty' 2>/dev/null)"
host="${CLAWLIGHT_HOST_NAME:-$(hostname)}"

payload="$(jq -n --arg session_id "$session_id" --arg host "$host" --arg state "$state" --arg cwd "$cwd" \
  '{session_id: $session_id, host: $host, state: $state, cwd: $cwd}' 2>/dev/null)"

[ -n "$payload" ] && curl -fsS -m 3 -X POST "$server_url/clawlight/api/report" \
  -H 'Content-Type: application/json' \
  -d "$payload" >/dev/null 2>&1

exit 0
