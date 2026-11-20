#!/bin/bash
# Install (or update) the speak-reply Stop hook into this Mac's Claude Code.
#
#   install.sh             # copy the hook, register it, leave speech as it was
#   install.sh --on        # ... and turn speech on
#   install.sh --uninstall # remove the hook and its settings entry
#
# Re-running is the update path: the hook is overwritten from the repo copy and
# the settings entry is added only if it is missing. See README.md.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
hook_dir="$HOME/.claude/hooks"
hook="$hook_dir/speak-reply.sh"
stop_hook="$hook_dir/speak-stop.sh"
settings="$HOME/.claude/settings.json"
toggle="$HOME/.claude/speak"
voice=Samantha  # must match the default in speak-reply.sh

mode=install
case "${1:-}" in
  "") ;;
  --on) mode=on ;;
  --uninstall) mode=uninstall ;;
  *) echo "usage: $0 [--on|--uninstall]" >&2; exit 2 ;;
esac

[ "$(uname)" = Darwin ] || { echo "macOS only: the hook speaks with 'say'" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 1; }

mkdir -p "$hook_dir"
[ -f "$settings" ] || echo '{}' > "$settings"

# Rewrite settings.json through jq; the first edit of a run backs up the original
edit_settings() {
  local tmp
  tmp=$(mktemp)
  jq "$1" "$settings" > "$tmp"
  [ -n "${backed_up:-}" ] || { cp "$settings" "$settings.bak-speak"; backed_up=1; }
  mv "$tmp" "$settings"
}

# unregister EVENT COMMAND: drop the entry running COMMAND, and the event if it empties
unregister() {
  edit_settings '
    if .hooks["'"$1"'"] then
      .hooks["'"$1"'"] |= map(select([.hooks[]?.command] | index("'"$2"'") | not))
      | if .hooks["'"$1"'"] == [] then del(.hooks["'"$1"'"]) else . end
    else . end'
}

# register EVENT COMMAND: add an entry running COMMAND unless one already does
register() {
  local found
  found=$(jq --arg e "$1" --arg c "$2" '[.hooks[$e][]?.hooks[]?.command] | index($c) != null' "$settings")
  if [ "$found" = true ]; then
    echo "$1 hook already registered"
  else
    edit_settings '.hooks["'"$1"'"] += [{"hooks":[{"type":"command","command":"'"$2"'"}]}]'
    echo "registered the $1 hook in $settings (backup: $settings.bak-speak)"
  fi
}

if [ "$mode" = uninstall ]; then
  unregister Stop "$hook"
  unregister UserPromptSubmit "$stop_hook"
  rm -f "$hook" "$stop_hook" "$toggle"
  echo "removed: both hooks, their entries in $settings, and $toggle"
  exit 0
fi

install -m 755 "$here/speak-reply.sh" "$hook"
install -m 755 "$here/speak-stop.sh" "$stop_hook"
echo "installed $hook and $stop_hook"
register Stop "$hook"
register UserPromptSubmit "$stop_hook"  # sending a message cuts off the reply being read

# A missing or half-downloaded voice makes say exit 0 and render silence, so
# check the rendered size rather than the exit code.
probe=$(mktemp -t claude-speak-probe).aiff
if say -v "$voice" -o "$probe" "hello there, this is a test" 2>/dev/null \
   && [ "$(stat -f%z "$probe")" -gt 20000 ]; then
  echo "voice $voice renders audio"
else
  echo "WARNING: voice $voice renders no audio here. Pick one that does from 'say -v ?'" >&2
  echo "         and put e.g. '-v Daniel -r 210' in $toggle" >&2
fi
rm -f "$probe"

if [ "$mode" = on ]; then
  touch "$toggle"
  echo "speech is ON (rm $toggle to turn it off)"
elif [ -f "$toggle" ]; then
  echo "speech is ON (rm $toggle to turn it off)"
else
  echo "speech is OFF (touch $toggle to turn it on)"
fi
echo "Restart running Claude Code sessions to pick up a newly registered hook."
