#!/usr/bin/env bash
# One-shot setup for clawlight's jump-to-console on a Mac. RUN THIS ON THE MAC.
#
#   scp <user>@xero.<your-tailnet-suffix>:/path/to/homelab/clawlight/setup-mac-focus-agent.sh /tmp/
#   bash /tmp/setup-mac-focus-agent.sh --dry-run   # show what it would do
#   bash /tmp/setup-mac-focus-agent.sh
#
# It needs no arguments: the server to pull from is derived from the same
# CLAWLIGHT_SERVER_URL the hooks already use, so there is nothing to keep in
# sync by hand. XERO_SSH / XERO_REPO override it if your layout differs.
#
# Exists because the launchd plist needs four values, and two of them are
# genuinely unknowable from xero: where set-status.sh was copied to on this
# Mac, and the AppleScript name of the terminal you run tmux in. Both are
# discoverable here, so discover them rather than hand-editing a template and
# finding out later that a click does nothing.
#
# What it does:
#   1. finds the existing set-status.sh from the Claude Code hooks that call it
#   2. pulls the updated set-status.sh + focus-agent.sh from xero next to it
#   3. reads CLAWLIGHT_SERVER_URL / CLAWLIGHT_HOST_NAME back out of those hooks,
#      so the agent can't disagree with what the hooks report
#   4. works out the terminal app's AppleScript name AND verifies it activates
#   5. writes and loads the launchd plist, then checks the agent connected
#
# Re-runnable: it unloads an existing agent before reloading.
set -u

REPO="${XERO_REPO:-/home/pramod/code/homelab}"
SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/dev.clawlight.focus-agent.plist"
LOG="/tmp/clawlight-focus-agent.log"

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
run() { if [ "$dry_run" = 1 ]; then printf '  would run: %s\n' "$*"; else "$@"; fi; }

[ "$(uname)" = "Darwin" ] || die "this is the macOS half of the setup; run it on the Mac"
[ -f "$SETTINGS" ] || die "no $SETTINGS - are the clawlight hooks set up on this machine?"
command -v jq >/dev/null || die "jq not installed (brew install jq)"
command -v tmux >/dev/null || die "tmux not installed (brew install tmux)"

# --- 1. where set-status.sh already lives -----------------------------------
# The hooks are the authority: whatever path they invoke is the copy that
# actually reports state, so that is the one to update.
hook_cmds="$(jq -r '.hooks | .. | .command? // empty' "$SETTINGS" 2>/dev/null | grep set-status.sh || true)"
[ -n "$hook_cmds" ] || die "no set-status.sh hooks found in $SETTINGS"

dest="$(printf '%s\n' "$hook_cmds" | grep -o '/[^ "]*set-status\.sh' | head -1)"
[ -n "$dest" ] || die "could not parse the set-status.sh path out of $SETTINGS"
dir="$(dirname "$dest")"
say "set-status.sh:      $dest"

# --- 3. reuse the hooks' own env, so the agent cannot disagree with them -----
# Read before copying, since these live in the hook command lines, not the file.
server_url="$(printf '%s\n' "$hook_cmds" | grep -o 'CLAWLIGHT_SERVER_URL=[^ ]*' | head -1 | cut -d= -f2-)"
host_name="$(printf '%s\n' "$hook_cmds" | grep -o 'CLAWLIGHT_HOST_NAME=[^ ]*' | head -1 | cut -d= -f2-)"
[ -n "$server_url" ] || die "no CLAWLIGHT_SERVER_URL in the hook commands in $SETTINGS - set it there first, it is what the agent and the hooks must agree on"
[ -n "$host_name" ] || host_name="$(hostname)"

# Pull from whatever host already serves clawlight, rather than carrying a
# second copy of that address here for the two to drift apart.
xero_host="${server_url#*://}"; xero_host="${xero_host%%/*}"; xero_host="${xero_host%%:*}"
XERO="${XERO_SSH:-$USER@$xero_host}"

say "server:             $server_url"
say "pulling over ssh:   $XERO   (override with XERO_SSH=)"
say "host label:         $host_name   (must match what the hooks report)"

# --- 4. the terminal app, by name that AppleScript actually accepts ---------
# The frontmost app while this runs is the terminal you launched it from. Its
# System Events process name is not always its AppleScript name (iTerm2's
# process is "iTerm2", but `tell application "iTerm2"` fails), so every
# candidate is tried for real rather than assumed.
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

# --- 2. pull the two scripts from xero --------------------------------------
say
say "copying from $XERO:$REPO/clawlight/ ..."
run scp "$XERO:$REPO/clawlight/set-status.sh" "$dest"
run scp "$XERO:$REPO/clawlight/focus-agent.sh" "$dir/focus-agent.sh"
run chmod +x "$dest" "$dir/focus-agent.sh"

# --- 5. write and load the launchd agent ------------------------------------
say
say "writing $PLIST"
if [ "$dry_run" = 1 ]; then
  say "  would write it with the values above"
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
    <string>$dir/focus-agent.sh</string>
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

[ "$dry_run" = 1 ] && { say; say "dry run - nothing changed"; exit 0; }

# --- verify, rather than claiming success -----------------------------------
say
sleep 2
if grep -q "watching .* for host=$host_name" "$LOG" 2>/dev/null; then
  say "agent is running and watching as host=$host_name"
else
  say "agent did not report in - check $LOG"
  tail -5 "$LOG" 2>/dev/null
  exit 1
fi

say
say "Sessions on this Mac become clickable on their next hook event."
say "Check with:  curl -s $server_url/clawlight/api/status | jq '.sessions'"
say "A session here should show \"reachable\": true once it next does anything."
