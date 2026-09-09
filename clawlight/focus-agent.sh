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

# Resolved once, by path as well as by PATH. macOS keeps lsof in /usr/sbin,
# which is not on a launchd agent's PATH - so "command -v lsof" alone reported
# it missing on a machine that had it all along, and the ssh half of every
# cross-host jump silently did nothing.
LSOF="$(command -v lsof 2>/dev/null || true)"
if [ -z "$LSOF" ]; then
  for candidate in /usr/sbin/lsof /usr/bin/lsof /sbin/lsof /bin/lsof; do
    [ -x "$candidate" ] && { LSOF="$candidate"; break; }
  done
fi

log() { printf '%s clawlight-focus-agent: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

# tmux against a named socket, or the default one when the socket is empty.
# The default matters for the raise path: that runs against THIS machine's own
# tmux server, and under launchd there is no $TMUX to read a socket out of.
tmuxc() {
  local sock="$1"; shift
  if [ -n "$sock" ]; then tmux -S "$sock" "$@"; else tmux "$@"; fi
}

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

# Set by tmux_focus_pane to the tty of the client that ended up on the pane.
FOCUS_TTY=""

tmux_focus_pane() {
  local sock="$1" pane="$2" session target_tty ctty csess

  # Order matters: make the pane current within its window, then its window
  # current within its session, and only then move a client to that session.
  # Doing it the other way round lands you on the session's previously-current
  # window instead of the one that wants you.
  tmuxc "$sock" select-pane -t "$pane" 2>/dev/null || { log "no pane $pane"; return; }
  tmuxc "$sock" select-window -t "$pane" 2>/dev/null || return

  session="$(tmuxc "$sock" display-message -p -t "$pane" '#{session_name}' 2>/dev/null)"
  [ -n "$session" ] || return

  # Prefer a client already attached to this session, and switch nothing. The
  # earlier version switched EVERY client, which on a setup where each terminal
  # tab attaches its own session dragged all of them onto one - destroying the
  # arrangement in order to reach one pane.
  target_tty=""
  while read -r ctty csess; do
    [ "$csess" = "$session" ] && { target_tty="$ctty"; break; }
  done <<CLIENTS
$(tmuxc "$sock" list-clients -F '#{client_tty} #{client_session}' 2>/dev/null)
CLIENTS

  # Nobody is showing it, so move the most recently used client - the one you
  # were last looking at, which is the least surprising to repurpose.
  if [ -z "$target_tty" ]; then
    target_tty="$(tmuxc "$sock" list-clients -F '#{client_activity} #{client_tty}' 2>/dev/null \
                  | sort -rn | head -1 | cut -d' ' -f2)"
    [ -n "$target_tty" ] && tmuxc "$sock" switch-client -c "$target_tty" -t "$session" 2>/dev/null
  fi

  FOCUS_TTY="$target_tty"
  log "focused $session ($pane) on ${target_tty:-no client}"
}

# If the client we just moved reached this host over ssh, the terminal tab that
# actually shows it is on the machine at the other end. Announce the connection
# so that machine can surface it - see the server's SSH_PEER_RE comment.
#
# Reads the client process's environment, which is Linux-only. That is the
# right scope: on macOS the client is a local tab, already handled directly.
announce_ssh_client() {
  local sock="$1" tty="$2" cpid conn ip port peer_ip peer_port

  [ -n "$tty" ] || return 0
  [ -r /proc/self/environ ] || return 0

  cpid="$(tmuxc "$sock" list-clients -F '#{client_tty} #{client_pid}' 2>/dev/null \
          | awk -v t="$tty" '$1 == t { print $2; exit }')"
  [ -n "$cpid" ] || return 0

  conn="$(tr '\0' '\n' < "/proc/$cpid/environ" 2>/dev/null | sed -n 's/^SSH_CONNECTION=//p' | head -1)"
  [ -n "$conn" ] || return 0   # a local client; nothing to raise elsewhere

  # "<client ip> <client port> <server ip> <server port>"
  ip="$(printf '%s' "$conn" | cut -d' ' -f1)"
  port="$(printf '%s' "$conn" | cut -d' ' -f2)"
  peer_ip="$(printf '%s' "$conn" | cut -d' ' -f3)"
  peer_port="$(printf '%s' "$conn" | cut -d' ' -f4)"
  case "$port" in ''|*[!0-9]*) return 0 ;; esac

  log "client came over ssh from $ip:$port - asking other hosts to surface it"
  curl -fsS -m 3 -X POST "$server_url/clawlight/api/raise-ssh" \
    -H 'Content-Type: application/json' \
    -d "{\"source_port\":$port,\"peer\":\"$peer_ip:$peer_port\",\"from_host\":\"$host\"}" \
    >/dev/null 2>&1
}

# The other end of that announcement. Find the local ssh process holding this
# source port, work out which terminal tab it is running in, and surface it.
# On a machine that does not own the port this finds nothing and returns.
raise_ssh_tab() {
  local port="$1" peer="$2" pid tty pane_line pane sess

  if [ -z "$LSOF" ]; then
    log "lsof not found on PATH ($PATH) nor in /usr/sbin - cannot surface ssh tabs"
    return 0
  fi

  # Match on "<local port>-><peer>" so a coincidental remote port can't hit.
  pid="$("$LSOF" -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null \
         | awk -v m=":$port->$peer" 'index($0, m) { print $2; exit }')"
  if [ -z "$pid" ]; then
    # Expected on every machine that isn't the one holding the connection -
    # that is how the broadcast self-selects. Logged anyway: when the jump
    # doesn't land, "not owned here" on every host is the thing that says so.
    log "ssh :$port -> $peer not owned here"
    return 0
  fi

  tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [ -z "$tty" ] || [ "$tty" = "??" ]; then
    log "ssh :$port is pid $pid but has no controlling tty - cannot place it"
    return 0
  fi
  tty="/dev/$tty"

  # That tty may itself be a local tmux pane (ssh running inside tmux here, not
  # just in a bare tab). If so, jump to that pane first and then aim the tab
  # selection at the local client's tty rather than the pane's.
  pane_line="$(tmuxc "" list-panes -a -F '#{pane_tty} #{pane_id}' 2>/dev/null \
               | awk -v t="$tty" '$1 == t { print $2; exit }')"
  if [ -n "$pane_line" ]; then
    log "ssh runs inside local tmux pane $pane_line - jumping there first"
    tmux_focus_pane "" "$pane_line"
    [ -n "$FOCUS_TTY" ] && tty="$FOCUS_TTY"
  fi

  log "surfacing the tab that owns $tty (ssh :$port -> $peer)"
  select_terminal_tab "$tty"
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
    kind="$(printf '%s' "$payload" | jq -r '.kind // "tmux"' 2>/dev/null)"
    case "$kind" in
      raise_ssh)
        port="$(printf '%s' "$payload" | jq -r '.source_port // empty' 2>/dev/null)"
        peer="$(printf '%s' "$payload" | jq -r '.peer // empty' 2>/dev/null)"
        case "$port" in ''|*[!0-9]*) port="" ;; esac
        case "$peer" in *[!0-9a-fA-F.:]*|'') peer="" ;; esac
        if [ -n "$port" ] && [ -n "$peer" ]; then
          raise_ssh_tab "$port" "$peer"
        else
          log "ignoring malformed raise request"
        fi
        ;;
      *)
        sock="$(printf '%s' "$payload" | jq -r '.tmux_socket // empty' 2>/dev/null)"
        pane="$(printf '%s' "$payload" | jq -r '.tmux_pane // empty' 2>/dev/null)"
        if valid_target "$sock" "$pane"; then
          tmux_focus_pane "$sock" "$pane"
          select_terminal_tab "$FOCUS_TTY"
          announce_ssh_client "$sock" "$FOCUS_TTY"
        else
          log "ignoring malformed focus request"
        fi
        ;;
    esac
  done

  # Reconnect, but not in a tight spin if the server is down for a while.
  sleep 3
done
