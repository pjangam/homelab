#!/usr/bin/env bash
# Show what zsh-autocomplete actually renders at a live prompt.
#
# check_zsh_autocomplete.sh proves the plugin loaded and its widgets bound.
# This answers the different question "but I still see nothing": it drives a
# real interactive zsh inside a throwaway tmux server, types a partial command,
# and prints the screen. If the menu is working you see a completion list under
# the prompt; if you see only the prompt, the widgets are loaded but not
# drawing.
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
tmux -L $sock capture-pane -p -t probe | sed -e 's/[[:space:]]*$//' -e '/^$/d'
echo "===== end ====="

echo
echo "-- plugin state in that shell --"
tmux -L $sock send-keys -t probe C-c
sleep 0.5
tmux -L $sock send-keys -t probe 'print "WIDGETS=${#${(M)${(k)widgets}:#*autocomplete*}} TERM=$TERM ASYNC=${+functions[.autocomplete__async]}"' Enter
sleep 1.5
tmux -L $sock capture-pane -p -t probe | grep -a "WIDGETS=" | tail -2
