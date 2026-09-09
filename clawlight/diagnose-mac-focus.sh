#!/usr/bin/env bash
# Works out why a jump to an ssh-reached session isn't landing. RUN ON THE MAC.
#
#   scp <user>@xero.<your-tailnet-suffix>:/path/to/homelab/clawlight/diagnose-mac-focus.sh /tmp/
#   bash /tmp/diagnose-mac-focus.sh
#
# The jump to a session on another host takes four steps on this machine, and
# when it fails all four look the same from the browser: nothing happens. This
# walks them in order and stops at the first one that breaks.
#
#   1. is the agent running, and does it have the ssh-raise code at all?
#   2. does lsof see the ssh connection the other host announced?
#   3. does that process resolve to a tty (via a local tmux pane, if nested)?
#   4. does the terminal own a tab for that tty?
set -u

SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/dev.clawlight.focus-agent.plist"
LOG="/tmp/clawlight-focus-agent.log"
fail=0

ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fail=1; }
note() { printf '        %s\n' "$*"; }
hdr()  { printf '\n%s\n' "$*"; }

[ "$(uname)" = "Darwin" ] || { echo "run this on the Mac"; exit 1; }

# --- 1. the agent itself ----------------------------------------------------
hdr "1. agent"
agent=""
if [ -f "$PLIST" ]; then
  agent="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST" 2>/dev/null || true)"
fi
if [ -z "$agent" ] || [ ! -f "$agent" ]; then
  bad "no focus-agent.sh found via $PLIST"
  note "run setup-mac-focus-agent.sh first"
  exit 1
fi
ok "agent script: $agent"

if grep -q raise_ssh_tab "$agent"; then
  ok "it has the ssh-raise code"
else
  bad "this copy PREDATES the ssh-raise feature - that alone explains it"
  note "re-run setup-mac-focus-agent.sh to pull the current one, then retry"
  exit 1
fi

if launchctl list 2>/dev/null | grep -q dev.clawlight.focus-agent; then
  ok "launchd agent is loaded"
else
  bad "launchd agent is not loaded"
  note "launchctl load $PLIST"
fi

app="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:CLAWLIGHT_FOCUS_APP' "$PLIST" 2>/dev/null || true)"
case "$app" in
  ""|REPLACE-ME*) bad "CLAWLIGHT_FOCUS_APP is unset - no tab can be selected"; app="" ;;
  *) ok "terminal app: $app" ;;
esac

# --- 2. the ssh connection --------------------------------------------------
hdr "2. ssh connections to port 22 this Mac holds"
conns="$(lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk '$NF ~ /->.*:22$/ { print $2, $NF }')"
if [ -z "$conns" ]; then
  bad "none - is the ssh session to the other host still open?"
  note "the announced connection must be live when you click, not a stale one"
  exit 1
fi
printf '%s\n' "$conns" | while read -r pid name; do
  note "pid $pid  $name"
done
note "the agent matches the substring \":<port>-><peer ip>:22\" against these"

# --- 3. tty resolution ------------------------------------------------------
hdr "3. tty each ssh process resolves to"
printf '%s\n' "$conns" | while read -r pid name; do
  tty="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [ -z "$tty" ] || [ "$tty" = "??" ]; then
    bad "pid $pid ($name) has no controlling tty - it cannot be placed in a tab"
    continue
  fi
  tty="/dev/$tty"
  pane="$(tmux list-panes -a -F '#{pane_tty} #{pane_id} #{session_name}' 2>/dev/null \
          | awk -v t="$tty" '$1 == t { print $2, $3; exit }')"
  if [ -n "$pane" ]; then
    ok "pid $pid -> $tty, which is local tmux pane $pane"
    note "nested case: the agent jumps to that pane, then aims at its client's tty"
    ctty="$(tmux list-clients -F '#{client_tty} #{client_session}' 2>/dev/null \
            | awk -v s="$(printf '%s' "$pane" | cut -d' ' -f2)" '$2 == s { print $1; exit }')"
    [ -n "$ctty" ] && note "that session's client tty: $ctty" \
                   || note "NO client attached to that session - nothing is displaying it"
  else
    ok "pid $pid -> $tty (a bare terminal tab, not inside local tmux)"
  fi
done

# --- 4. does the terminal own a tab for it ----------------------------------
hdr "4. terminal tabs and their ttys"
if [ -z "$app" ]; then
  bad "skipped - CLAWLIGHT_FOCUS_APP is unset"
else
  case "$app" in
    iTerm|iTerm2)
      tabs="$(osascript <<'APPLESCRIPT' 2>&1
set out to ""
tell application "iTerm"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set out to out & (tty of s) & linefeed
      end repeat
    end repeat
  end repeat
end tell
return out
APPLESCRIPT
)"
      if [ -z "$tabs" ]; then
        bad "iTerm reported no tabs - is automation permission granted?"
        note "System Settings > Privacy & Security > Automation, allow the agent to control iTerm"
      else
        printf '%s\n' "$tabs" | grep -v '^$' | while read -r t; do note "tab tty: $t"; done
        note "one of these must equal the tty from step 3 for the jump to land"
      fi
      ;;
    *) note "no tab enumeration implemented for $app - only the app is raised" ;;
  esac
fi

# --- recent log -------------------------------------------------------------
hdr "5. last agent log lines"
if [ -f "$LOG" ]; then
  tail -12 "$LOG" | sed 's/^/        /'
else
  bad "no $LOG yet - the agent has never run"
fi

hdr "verdict"
if [ "$fail" = 0 ]; then
  echo "  no broken step found. Click a session on the other host now, then"
  echo "  re-run this - step 5 will show what the agent decided."
else
  echo "  fix the FAIL above and retry."
fi
