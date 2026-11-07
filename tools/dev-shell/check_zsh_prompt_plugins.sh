#!/usr/bin/env bash
# Check the Mac's zsh prompt plugins are actually live, not merely installed,
# and loading in the right order.
#
# The two get confused for each other constantly, so this checks both:
#   zsh-autosuggestions  grey ghost text completing the line from history,
#                        accepted with ->. This is the one in use.
#   zsh-autocomplete     a menu that drops down BELOW the prompt. Installed with
#                        brew but deliberately NOT sourced -- see the README.
#
# Why it exists: brew only drops files on disk for either of these. Nothing
# sources them, there is no error when nothing does, and zsh-autocomplete sat
# installed and inert from 2026-09-19 to 2026-11-08 for exactly that reason.
set -uo pipefail

fail=0
say() { printf '%-34s %s\n' "$1" "$2"; }
bad() { say "$1" "$2"; fail=1; }

zshrc=$HOME/.zshrc
custom=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
as_share=/usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
as_shim=$custom/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh

echo "-- zsh-autosuggestions (the one in use) --"
[[ -r $as_share ]] \
  && say "brew install:" "$(ls /usr/local/Cellar/zsh-autosuggestions 2>/dev/null | tail -1) at ${as_share%/*}" \
  || bad "brew install:" "NO -- brew install zsh-autosuggestions"

# brew ships no .plugin.zsh, so OMZ's plugins=() cannot see it without a shim.
[[ -r $as_shim ]] \
  && say "oh-my-zsh shim:" "yes, $as_shim" \
  || bad "oh-my-zsh shim:" "NO -- plugins=() cannot load it without one"

# Order: zsh-syntax-highlighting installs a zle-line-pre-redraw hook and must
# register after anything else that modifies the buffer, so it has to be last.
pl=$(awk '/^plugins=\(/,/^\)/' "$zshrc" | grep -vE '^\s*#' | tr -d '\t ')
as_at=$(grep -n '^[[:space:]]*zsh-autosuggestions[[:space:]]*$' "$zshrc" | head -1 | cut -d: -f1)
sh_at=$(grep -n '^[[:space:]]*zsh-syntax-highlighting[[:space:]]*$' "$zshrc" | head -1 | cut -d: -f1)
if [[ -n ${as_at:-} && -n ${sh_at:-} ]]; then
  (( as_at < sh_at )) \
    && say "order in plugins=():" "ok (autosuggestions $as_at, syntax-highlighting $sh_at)" \
    || bad "order in plugins=():" "WRONG -- syntax-highlighting must come last"
elif [[ -n ${as_at:-} ]]; then
  say "order in plugins=():" "autosuggestions at $as_at, no syntax-highlighting"
else
  bad "in plugins=():" "NO -- not listed (found: ${pl//$'\n'/ })"
fi

# A bare `source` line would load it after oh-my-zsh.sh, i.e. after z-sy-h.
grep -q "source .*zsh-autosuggestions.zsh" "$zshrc" \
  && bad "stray source line:" "yes in ~/.zshrc -- loads after syntax-highlighting, remove it"

echo
echo "-- zsh-autocomplete (installed, intentionally dormant) --"
[[ -r /usr/local/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh ]] \
  && say "brew install:" "$(ls /usr/local/Cellar/zsh-autocomplete 2>/dev/null | tail -1) (on disk)" \
  || say "brew install:" "absent"
grep -q "zsh-autocomplete.plugin.zsh" "$zshrc" \
  && say "sourced:" "YES -- expected dormant; both plugins at once was not the choice" \
  || say "sourced:" "no (expected -- README says why)"

echo
echo "-- live, in a real interactive zsh --"
# Needs a pty and a real prompt: the widgets bind from a precmd hook, so
# `zsh -i -c ...` has no line editor, no prompt, no precmd, and proves nothing.
sock=zpluginscheck
tmux -V >/dev/null 2>&1 || { echo "tmux missing, skipping live check"; exit $(( fail )); }
tmux -L $sock kill-server 2>/dev/null
tmux -L $sock new-session -d -s p -x 100 -y 20 -c "$HOME" "NO_TMUX=1 zsh -i" 2>/dev/null
for _ in $(seq 40); do
  tmux -L $sock capture-pane -p -t p 2>/dev/null | LC_ALL=C grep -qa '~' && break
  sleep 0.25
done
sleep 1.5

# Suggest from history, so use a command the history actually holds.
seed=$(LC_ALL=C grep -ah ';cd ' "$HOME/.zsh_history" 2>/dev/null | tail -1 | sed 's/.*;//')
typed=${seed:0:5}
[[ -z $typed ]] && typed="cd co"
tmux -L $sock send-keys -t p "$typed"
sleep 3
screen=$(tmux -L $sock capture-pane -e -p -t p | cat -v)
tmux -L $sock kill-server 2>/dev/null

# SGR 90 (bright black) is the default ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE.
if LC_ALL=C grep -qa '\[90m' <<<"$screen"; then
  say "grey suggestion drawn:" "yes (SGR 90, after typing '$typed')"
else
  bad "grey suggestion drawn:" "NO -- nothing ghosted after typing '$typed'"
fi
if LC_ALL=C grep -qaE '\[(32|31|4)m' <<<"$screen"; then
  say "syntax highlighting:" "yes (still colouring after the reorder)"
else
  bad "syntax highlighting:" "NO colour -- the reorder may have broken z-sy-h"
fi

echo
(( fail )) && { echo "Something is off -- see the NO/WRONG lines above."; exit 1; }
echo "Prompt plugins are correct. New shells only: run exec zsh, and note that"
echo "a new iTerm tab on an existing session shares its pane (see the README)."
