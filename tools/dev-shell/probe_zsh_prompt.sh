#!/usr/bin/env bash
# Show what the prompt plugins actually render at a live prompt.
#
# check_zsh_prompt_plugins.sh answers "is it set up right". This answers the
# different question "but I still see nothing": it drives a real interactive
# zsh inside a throwaway tmux server, types a partial command, and prints the
# screen, so you compare against what you expected to see.
#
#   zsh-autosuggestions  the rest of the line appears after what you typed
#                        (grey on screen, SGR 90 with -e)
#   zsh-autocomplete     a list of matches appears BELOW the prompt
#
# Pass -e to show escape codes, which is the only way to tell a grey suggestion
# from text really in the buffer. The two look identical in a plain capture.
#
# Usage: probe_zsh_prompt.sh ['text to type'] [start dir] [-e]
#
# Uses its own tmux socket (-L acprobe) so it cannot touch the real sessions.
set -uo pipefail

typed=${1:-"git sta"}
startdir=${2:-$HOME}
sock=acprobe
cleanup() { tmux -L $sock kill-server 2>/dev/null; }
trap cleanup EXIT
cleanup

tmux -L $sock new-session -d -s probe -x 100 -y 30 -c "$startdir" "NO_TMUX=1 zsh -i"
# Wait for the first prompt: zsh-autocomplete does its real init in a precmd
# hook, so sending keys too early tests nothing.
for _ in $(seq 40); do
  tmux -L $sock capture-pane -p -t probe 2>/dev/null | grep -q '[%$>]' && break
  sleep 0.25
done
sleep 1

tmux -L $sock send-keys -t probe "$typed"
sleep 3

echo "===== screen after typing '$typed' (no Enter, no Tab) ====="
if [[ ${3:-} == -e ]]; then
  # cat -v, not sed: a sed regex over the themed prompt dies with
  # "RE error: illegal byte sequence" on macOS.
  tmux -L $sock capture-pane -e -p -t probe | cat -v | LC_ALL=C grep -av '^$'
else
  tmux -L $sock capture-pane -p -t probe | LC_ALL=C grep -av '^$'
fi
echo "===== end ====="

echo
echo "-- plugin state in that shell --"
tmux -L $sock send-keys -t probe C-c
sleep 0.5
tmux -L $sock send-keys -t probe 'print "AUTOSUGGEST=${+functions[_zsh_autosuggest_start]} AUTOCOMPLETE_WIDGETS=${#${(M)${(k)widgets}:#*autocomplete*}} SYNTAX_HL=${+ZSH_HIGHLIGHT_VERSION} TERM=$TERM"' Enter
sleep 1.5
tmux -L $sock capture-pane -p -t probe | LC_ALL=C grep -a "AUTOSUGGEST=" | tail -1
