#!/usr/bin/env bash
# Points this Mac's clawlight at a git clone of the homelab repo. RUN THIS ON
# THE MAC, from inside the clone:
#
#   git clone https://github.com/pjangam/homelab.git ~/code/homelab
#   bash ~/code/homelab/clawlight/setup-mac-focus-agent.sh --dry-run   # show what it would do
#   bash ~/code/homelab/clawlight/setup-mac-focus-agent.sh
#
# After this, `git pull` in the clone is the deploy: the hooks run the clone's
# set-status.sh directly, so a change to it applies on the next hook event.
# focus-agent.sh is a long-running process, so a change to it also needs
#   launchctl kickstart -k gui/$(id -u)/dev.clawlight.focus-agent
# Re-run this script only if clawlight/ moves inside the repo (the hooks and the
# plist hold its path), or to redo the terminal-app detection.
#
# It used to scp both scripts from xero into wherever the hooks pointed. That
# made "committed" and "deployed" two different things on this one machine,
# which cost three debugging rounds on stale copies (2026-09-09).
#
# It needs no arguments: CLAWLIGHT_SERVER_URL and CLAWLIGHT_HOST_NAME are read
# back out of the existing hooks, so the agent can't disagree with them.
#
# What it does:
#   1. finds the clawlight hooks in ~/.claude/settings.json
#   2. reads CLAWLIGHT_SERVER_URL / CLAWLIGHT_HOST_NAME back out of them
#   3. rewrites each hook's set-status.sh path to this clone's copy (backing
#      settings.json up first), and checks every hook clawlight needs is there
#   4. works out the terminal app's AppleScript name AND verifies it activates
#   5. writes and loads the launchd plist for the clone's focus-agent.sh, then
#      checks the agent connected
#
# Re-runnable: it unloads an existing agent before reloading, and rewriting a
# path that already points at the clone changes nothing.
set -u

CLAWLIGHT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_STATUS="$CLAWLIGHT_DIR/set-status.sh"
FOCUS_AGENT="$CLAWLIGHT_DIR/focus-agent.sh"
SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/dev.clawlight.focus-agent.plist"
LOG="/tmp/clawlight-focus-agent.log"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
run() { if [ "$dry_run" = 1 ]; then printf '  would run: %s\n' "$*"; else "$@"; fi; }

[ "$(uname)" = "Darwin" ] || die "this is the macOS half of the setup; run it on the Mac"
git -C "$CLAWLIGHT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$CLAWLIGHT_DIR is not inside a git clone - run this from the cloned repo, not a copy"
[ -f "$SET_STATUS" ] && [ -f "$FOCUS_AGENT" ] || die "set-status.sh / focus-agent.sh missing next to this script"
[ -f "$SETTINGS" ] || die "no $SETTINGS - are the clawlight hooks set up on this machine?"
command -v jq >/dev/null || die "jq not installed (brew install jq)"
command -v tmux >/dev/null || die "tmux not installed (brew install tmux)"
command -v curl >/dev/null || die "curl not installed"

say "clone:              $CLAWLIGHT_DIR"

# --- 1. the existing hooks ---------------------------------------------------
hook_cmds="$(jq -r '.hooks | .. | .command? // empty' "$SETTINGS" 2>/dev/null | grep set-status.sh || true)"
[ -n "$hook_cmds" ] || die "no set-status.sh hooks found in $SETTINGS - wire them first (clawlight/README.md, 'Setup on another machine')"

old_paths="$(printf '%s\n' "$hook_cmds" | grep -o '[^ "]*set-status\.sh' | sort -u)"

# --- 2. reuse the hooks' own env, so the agent cannot disagree with them -----
server_url="$(printf '%s\n' "$hook_cmds" | grep -o 'CLAWLIGHT_SERVER_URL=[^ ]*' | head -1 | cut -d= -f2-)"
host_name="$(printf '%s\n' "$hook_cmds" | grep -o 'CLAWLIGHT_HOST_NAME=[^ ]*' | head -1 | cut -d= -f2-)"
[ -n "$server_url" ] || die "no CLAWLIGHT_SERVER_URL in the hook commands in $SETTINGS - set it there first, it is what the agent and the hooks must agree on"
[ -n "$host_name" ] || host_name="$(hostname)"
say "server:             $server_url"
say "host label:         $host_name   (must match what the hooks report)"

# --- 3. point the hooks at the clone -----------------------------------------
say
say "hooks currently run:"
printf '%s\n' "$old_paths" | sed 's/^/  /'

# Every event clawlight depends on, with the state it must send. A wrong state
# fails silently (e.g. Notification -> waiting means no push, ever), so check
# the mapping, not just that a hook exists.
missing=""
for pair in UserPromptSubmit:active Stop:waiting Notification:input_needed \
            PermissionRequest:input_needed PostToolUse:active SessionEnd:end \
            SubagentStart:task_start SubagentStop:task_end \
            TaskCreated:task_start TaskCompleted:task_end; do
  event="${pair%%:*}"; want="${pair#*:}"
  jq -e --arg e "$event" --arg w "set-status.sh $want" \
    '[.hooks[$e][]?.hooks[]?.command // empty | select(endswith($w))] | length > 0' \
    "$SETTINGS" >/dev/null 2>&1 || missing="$missing $event($want)"
done

new_settings="$(jq --arg p "$SET_STATUS" '
  .hooks |= walk(
    if type == "object" and ((.command? // "") | test("set-status\\.sh"))
    then .command |= sub("[^ \"]*set-status\\.sh"; $p)
    else . end)' "$SETTINGS")" || die "could not rewrite $SETTINGS (jq 1.6+ needed for walk)"

if [ "$new_settings" = "$(jq . "$SETTINGS")" ]; then
  say "hooks already point at this clone"
else
  backup="$SETTINGS.bak-clawlight-$(date +%Y%m%d-%H%M%S)"
  say "rewriting them to:  $SET_STATUS"
  say "backup:             $backup"
  if [ "$dry_run" = 0 ]; then
    cp "$SETTINGS" "$backup"
    printf '%s\n' "$new_settings" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  fi
fi
if [ -n "$missing" ]; then
  say
  say "WARNING: no hook sending the right state for:$missing"
  say "         add these in $SETTINGS (see clawlight/README.md) - this script does not invent them."
fi
run chmod +x "$SET_STATUS" "$FOCUS_AGENT"

# --- 4. the terminal app, by name that AppleScript actually accepts ---------
# The frontmost app while this runs is the terminal you launched it from. Its
# System Events process name is not always its AppleScript name (iTerm2's
# process is "iTerm2", but `tell application "iTerm2"` fails), so every
# candidate is tried for real rather than assumed.
say
frontmost="$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)"
focus_app=""
for candidate in "$frontmost" "${frontmost%2}" "iTerm" "Ghostty" "WezTerm" "kitty" "Alacritty" "Terminal"; do
  [ -n "$candidate" ] || continue
  if osascript -e "tell application \"$candidate\" to activate" >/dev/null 2>&1; then
    focus_app="$candidate"
    break
  fi
done
if [ -n "$focus_app" ]; then
  say "terminal app:       $focus_app   (verified: it activates)"
else
  say "terminal app:       COULD NOT DETECT - the jump will switch the tmux"
  say "                    window but leave the terminal behind your browser."
  say "                    Set CLAWLIGHT_FOCUS_APP in $PLIST by hand."
fi

# --- 5. write and load the launchd agent ------------------------------------
say
say "writing $PLIST"
if [ "$dry_run" = 1 ]; then
  say "  would write it to run $FOCUS_AGENT with the values above"
else
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Generated by clawlight/setup-mac-focus-agent.sh - re-run it rather than
     hand-editing, so these values stay in step with the Claude Code hooks. -->
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.clawlight.focus-agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>$FOCUS_AGENT</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAWLIGHT_SERVER_URL</key>
    <string>$server_url</string>
    <key>CLAWLIGHT_HOST_NAME</key>
    <string>$host_name</string>
    <key>CLAWLIGHT_FOCUS_APP</key>
    <string>$focus_app</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
</dict>
</plist>
PLIST_EOF
  plutil -lint "$PLIST" >/dev/null || die "generated plist is malformed"
fi

say "loading the agent"
run launchctl unload "$PLIST" 2>/dev/null
run launchctl load "$PLIST"

# --- the old scp'd copies -----------------------------------------------------
# Left in place rather than deleted: a session started before this ran still
# has the old hook paths loaded, and deleting under it would break its hooks.
stale=""
for p in $old_paths; do
  [ "$p" = "$SET_STATUS" ] && continue
  for f in "$p" "$(dirname "$p")/focus-agent.sh"; do
    [ -e "$f" ] && stale="$stale $f"
  done
done

[ "$dry_run" = 1 ] && { say; say "dry run - nothing changed"; exit 0; }

# --- verify, rather than claiming success -----------------------------------
say
sleep 2
if grep -q "watching .* for host=$host_name" "$LOG" 2>/dev/null; then
  say "agent is running from the clone and watching as host=$host_name"
else
  say "agent did not report in - check $LOG"
  tail -5 "$LOG" 2>/dev/null
  exit 1
fi

say
say "Done. From now on, 'git pull' in the clone updates clawlight on this Mac."
say "Already-running Claude sessions keep their old hook paths until restarted."
if [ -n "$stale" ]; then
  say "The old scp'd copies are no longer used - delete them once those sessions are gone:"
  for f in $stale; do say "  rm $f"; done
fi
say "Check with:  curl -s $server_url/clawlight/api/status | jq '.sessions'"
