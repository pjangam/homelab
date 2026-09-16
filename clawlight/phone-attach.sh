#!/usr/bin/env bash
# Attaches an ssh session from the iPhone to the tmux pane tapped on the
# clawlight page ("jump to console" from the phone).
#
# Set as the startup command of the saved Termius host for this machine (one
# per host, xero and the Mac). Termius links can only open a host, not pass a
# command, so the target can't travel in the link: the page records it on the
# server, and this claims it once connected. See the phone section of
# clawlight/README.md.
#
# With no request pending (a plain Termius connect, or one more than 60s after
# the tap) it says so and leaves you at the shell.
#
# Environment - the same variables set-status.sh uses on this machine, which
# the Termius session picks up from your shell profile:
#   CLAWLIGHT_SERVER_URL  - default http://localhost:8126
#   CLAWLIGHT_HOST_NAME   - must match what set-status.sh reports here
set -u

# A command run over ssh can get a shorter PATH than your terminal does, and
# Homebrew's tmux and jq live outside the macOS default.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

server_url="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
host="${CLAWLIGHT_HOST_NAME:-$(hostname)}"

say() { printf 'clawlight: %s\n' "$*" >&2; }

if [ -n "${TMUX:-}" ]; then
  say "already inside tmux, not nesting another client"
  exit 1
fi

body="$(jq -nc --arg host "$host" '{host: $host}')"
if ! resp="$(curl -fsS -m 5 -X POST "$server_url/clawlight/api/phone-claim" \
    -H 'Content-Type: application/json' -d "$body")"; then
  say "server unreachable at $server_url"
  exit 1
fi

sock="$(printf '%s' "$resp" | jq -r '.tmux_socket // empty')"
pane="$(printf '%s' "$resp" | jq -r '.tmux_pane // empty')"
if [ -z "$pane" ]; then
  say "no jump requested for $host in the last minute"
  exit 0
fi

# The server validated these when the session reported them, but they become
# command arguments here, so check the shape again.
case "$pane" in %[0-9]*) ;; *) say "bad pane from server: $pane"; exit 1 ;; esac
case "$sock" in /*) ;; *) say "bad socket from server: $sock"; exit 1 ;; esac

# Two calls rather than one with a separator: tmux prints a tab in a format as
# `_`, and a session name that comes out wrong is not an error - `new-session
# -t` with an unknown name quietly starts a new group with a fresh shell.
if ! session="$(tmux -S "$sock" display-message -p -t "$pane" '#{session_name}' 2>/dev/null)"; then
  say "pane $pane is gone (session ended since the tap?)"
  exit 1
fi
window="$(tmux -S "$sock" display-message -p -t "$pane" '#{window_id}')"
if ! tmux -S "$sock" has-session -t "=$session" 2>/dev/null; then
  say "could not resolve the session for pane $pane"
  exit 1
fi

# A grouped session shares the windows but keeps its own current window, so
# the phone switching to this window doesn't switch the desk terminal too.
# It is thrown away when the phone detaches.
#
# Not avoidable: selecting the pane changes the window's active pane for every
# client, and with window-size `latest` the window takes the phone's size until
# the desk client is used again.
name="phone-$$"
exec tmux -S "$sock" new-session -s "$name" -t "=$session" \; \
  set-option destroy-unattached on \; \
  select-window -t "$name:$window" \; \
  select-pane -t "$pane"
