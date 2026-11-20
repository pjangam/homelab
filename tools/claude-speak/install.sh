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

# Rewrite settings.json through jq, keeping a backup of the previous version
edit_settings() {
  local tmp
  tmp=$(mktemp)
  jq "$1" "$settings" > "$tmp"
  cp "$settings" "$settings.bak-speak"
  mv "$tmp" "$settings"
}

if [ "$mode" = uninstall ]; then
  edit_settings '
    if .hooks.Stop then
      .hooks.Stop |= map(select([.hooks[]?.command] | index("'"$hook"'") | not))
      | if .hooks.Stop == [] then del(.hooks.Stop) else . end
    else . end'
  rm -f "$hook" "$toggle"
  echo "removed: $hook, its Stop entry in $settings, and $toggle"
  exit 0
fi

mkdir -p "$hook_dir"
install -m 755 "$here/speak-reply.sh" "$hook"
echo "installed $hook"

registered=$(jq --arg c "$hook" '[.hooks.Stop[]?.hooks[]?.command] | index($c) != null' "$settings")
if [ "$registered" = true ]; then
  echo "Stop hook already registered in $settings"
else
  edit_settings '.hooks.Stop += [{"hooks":[{"type":"command","command":"'"$hook"'"}]}]'
  echo "registered the Stop hook in $settings (backup: $settings.bak-speak)"
fi

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
