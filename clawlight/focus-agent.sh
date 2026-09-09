#!/usr/bin/env bash
# Jumps this machine's terminal to the Claude Code session you clicked on the
# clawlight page ("jump to console"). Runs as a long-lived agent on EVERY host
# that has Claude Code sessions - xero and the MacBook - because the tmux
# commands have to run on the machine the pane actually lives on. The server
# only routes: it holds a pending request per host, and this agent collects it
# over SSE (`/api/focus-stream?host=...`) and does the work locally.
#
# Deliberately the same script on Linux and macOS. The only platform-specific
# bit is raising the terminal application itself (macOS), which is opt-in via
# CLAWLIGHT_FOCUS_APP.
#
# Environment (same variables set-status.sh already uses on this machine):
#   CLAWLIGHT_SERVER_URL  - default http://localhost:8126; xero's tailnet URL
#                           on any other machine.
#   CLAWLIGHT_HOST_NAME   - this host's label as reported by set-status.sh.
#                           MUST match, or requests route to a host that isn't
#                           listening and the click does nothing.
#   CLAWLIGHT_FOCUS_APP   - optional macOS terminal app to bring to the front.
#                           Switching the tmux window is useless if the
#                           terminal is behind your browser. This is the
#                           AppleScript name, which is not always the name on
#                           the app icon - iTerm2 is "iTerm". Verify with
#                           `osascript -e 'tell application "X" to activate'`.
#
# Needs `curl`, `jq` and `tmux`. Sessions started outside tmux are reported as
# unreachable by the server and never reach this script.
set -u

server_url="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
host="${CLAWLIGHT_HOST_NAME:-$(hostname)}"
focus_app="${CLAWLIGHT_FOCUS_APP:-}"

log() { printf '%s clawlight-focus-agent: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

# The server validates these before queueing, but this script turns them into
# command arguments, so it checks them again rather than trusting the stream.
valid_target() {
  case "$2" in %[0-9]*) ;; *) return 1 ;; esac
  case "$1" in /*) ;; *) return 1 ;; esac
  return 0
}

# Bring the terminal tab that owns this tty to the front.
#
# Activating the app is NOT enough when each terminal tab holds its own tmux
# client: the app comes forward still showing whichever tab you left it on, so
# the jump lands you in the wrong place while looking like it worked. tmux
# cannot help here - it has no idea which GUI tab wraps a given client - so the
# terminal itself has to be asked to select the tab whose tty matches.
select_terminal_tab() {
  local tty="$1"

  [ -n "$focus_app" ] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  # This is interpolated into AppleScript, so accept only what tmux emits.
  case "$tty" in
    /dev/[A-Za-z0-9/]*) ;;
    *) tty="" ;;
  esac

  if [ -n "$tty" ]; then
    case "$focus_app" in
      iTerm|iTerm2)
        if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "iTerm"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      repeat with theSession in sessions of t
        if tty of theSession is "$tty" then
          select w
          select t
          select theSession
          return
        end if
      end repeat
    end repeat
  end repeat
  error "no tab owns $tty"
end tell
APPLESCRIPT
        then
          return 0
        fi
        # Falls through to a plain activate below. Expected whenever the tmux
        # client is remote (an ssh session into another host's tmux): its tty
        # is a pty on that machine, so no local tab owns it.
        log "no $focus_app tab owns $tty - raising the app only"
        ;;
    esac
  fi

  # Loud on failure: a wrong app name (iTerm2's AppleScript name is "iTerm",
  # not "iTerm2") otherwise fails invisibly, and the jump looks broken for a
  # reason nothing reports.
  if ! osascript -e "tell application \"$focus_app\" to activate" >/dev/null 2>&1; then
    log "could not activate \"$focus_app\" - check CLAWLIGHT_FOCUS_APP"
  fi
}

focus() {
  local sock="$1" pane="$2" session target_tty ctty csess

  # Order matters: make the pane current within its window, then its window
  # current within its session, and only then move a client to that session.
  # Doing it the other way round lands you on the session's previously-current
  # window instead of the one that wants you.
  tmux -S "$sock" select-pane -t "$pane" 2>/dev/null || { log "no pane $pane"; return; }
  tmux -S "$sock" select-window -t "$pane" 2>/dev/null || return

  session="$(tmux -S "$sock" display-message -p -t "$pane" '#{session_name}' 2>/dev/null)"
  [ -n "$session" ] || return

  # Prefer a client already attached to this session, and switch nothing. The
  # earlier version switched EVERY client, which on a setup where each terminal
  # tab attaches its own session dragged all of them onto one - destroying the
  # arrangement in order to reach one pane.
  target_tty=""
  while read -r ctty csess; do
    [ "$csess" = "$session" ] && { target_tty="$ctty"; break; }
  done <<CLIENTS
$(tmux -S "$sock" list-clients -F '#{client_tty} #{client_session}' 2>/dev/null)
CLIENTS

  # Nobody is showing it, so move the most recently used client - the one you
  # were last looking at, which is the least surprising to repurpose.
  if [ -z "$target_tty" ]; then
    target_tty="$(tmux -S "$sock" list-clients -F '#{client_activity} #{client_tty}' 2>/dev/null \
                  | sort -rn | head -1 | cut -d' ' -f2)"
    [ -n "$target_tty" ] && tmux -S "$sock" switch-client -c "$target_tty" -t "$session" 2>/dev/null
  fi

  select_terminal_tab "$target_tty"

  log "focused $session ($pane) on ${target_tty:-no client}"
}

log "watching $server_url for host=$host"

while :; do
  # --speed-limit/--speed-time trip on a connection that died without closing:
  # the server's keepalive comments keep the stream above 1 byte/sec, so
  # falling under that for 45s means the link is gone, not merely quiet.
  curl -fsS -N --connect-timeout 5 --speed-limit 1 --speed-time 45 \
    "$server_url/clawlight/api/focus-stream?host=$host" 2>/dev/null |
  while IFS= read -r line; do
    case "$line" in
      data:*) ;;
      *) continue ;;
    esac
    payload="${line#data:}"
    sock="$(printf '%s' "$payload" | jq -r '.tmux_socket // empty' 2>/dev/null)"
    pane="$(printf '%s' "$payload" | jq -r '.tmux_pane // empty' 2>/dev/null)"
    if valid_target "$sock" "$pane"; then
      focus "$sock" "$pane"
    else
      log "ignoring malformed focus request"
    fi
  done

  # Reconnect, but not in a tight spin if the server is down for a while.
  sleep 3
done
