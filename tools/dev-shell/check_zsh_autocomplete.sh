#!/usr/bin/env bash
# Verify zsh-autocomplete is actually live, not merely installed.
#
# Why this exists: brew's zsh-autocomplete only drops files under
# $(brew --prefix)/share/zsh-autocomplete. Nothing sources them -- it is not an
# oh-my-zsh plugin, so it does not get picked up by plugins=(). It sat installed
# and inert on this Mac from 2026-09-19 until 2026-11-08 for exactly that reason.
#
# The widget check needs a real pty: zsh-autocomplete installs its ZLE widgets
# from a precmd hook, so `zsh -i -c ...` (no line editor, no prompt, no precmd)
# always reports zero widgets even when the setup is perfect.
set -uo pipefail

prefix=/usr/local/share/zsh-autocomplete
plugin=$prefix/zsh-autocomplete.plugin.zsh
fail=0

say() { printf '%-28s %s\n' "$1" "$2"; }

if [[ -r $plugin ]]; then
  say "installed:" "$(readlink "$plugin" | sed -n 's|.*/\([0-9.]*\)/share.*|\1|p') at $prefix"
else
  say "installed:" "NO -- $plugin missing (brew install zsh-autocomplete)"
  fail=1
fi

if grep -q "zsh-autocomplete.plugin.zsh" "$HOME/.zshrc"; then
  say "sourced from ~/.zshrc:" "yes (line $(grep -n 'zsh-autocomplete.plugin.zsh' "$HOME/.zshrc" | head -1 | cut -d: -f1))"
else
  say "sourced from ~/.zshrc:" "NO -- this is the usual cause of 'installed but no completions'"
  fail=1
fi

# Order matters: oh-my-zsh.sh runs compinit unconditionally and binds keys, so
# Autocomplete has to be sourced after it or OMZ clobbers its widgets.
omz=$(grep -n '^source \$ZSH/oh-my-zsh.sh' "$HOME/.zshrc" | head -1 | cut -d: -f1)
ac=$(grep -n 'zsh-autocomplete.plugin.zsh' "$HOME/.zshrc" | head -1 | cut -d: -f1)
if [[ -n ${omz:-} && -n ${ac:-} ]]; then
  if (( ac > omz )); then
    say "after oh-my-zsh.sh:" "yes (oh-my-zsh $omz, autocomplete $ac)"
  else
    say "after oh-my-zsh.sh:" "NO -- oh-my-zsh at $omz will clobber autocomplete at $ac"
    fail=1
  fi
fi

# Live widget count, via a throwaway ZDOTDIR that chains the real ~/.zshrc and
# then reports from its own precmd hook. `script` supplies the pty.
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
out=$probe/result
cat > "$probe/.zshrc" <<ZRC
NO_TMUX=1
ZDOTDIR=\$HOME
source \$HOME/.zshrc
_probe() {
  print "widgets=\${#\${(M)\${(k)widgets}:#*autocomplete*}}" > $out
  print "tab=\$(bindkey '^I')" >> $out
  exit 0
}
autoload -Uz add-zsh-hook && add-zsh-hook precmd _probe
ZRC

NO_TMUX=1 ZDOTDIR=$probe script -q /dev/null zsh -i >/dev/null 2>&1 </dev/null

if [[ -r $out ]]; then
  n=$(sed -n 's/^widgets=//p' "$out")
  if (( n > 0 )); then
    say "live ZLE widgets:" "$n"
    say "Tab is bound to:" "$(sed -n 's/^tab=//p' "$out")"
  else
    say "live ZLE widgets:" "NO -- sourced but no widgets installed"
    fail=1
  fi
else
  say "live ZLE widgets:" "could not probe (pty check did not report)"
fi

(( fail )) && { echo; echo "zsh-autocomplete is NOT fully active."; exit 1; }
echo; echo "zsh-autocomplete is active. Open a new tab, or run: exec zsh"
