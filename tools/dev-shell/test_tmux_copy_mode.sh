#!/usr/bin/env bash
# Behavioural check of the copy-mode mouse bindings that dotfiles/tmux/tmux.conf
# installs. test_setup_tmux_shell.sh tests the *installer*; this tests what the
# installed config actually does, so it needs a running tmux server and the
# config already sourced into it (setup-tmux-shell.sh does that on install).
#
#   tools/dev-shell/test_tmux_copy_mode.sh
#
# Mouse events cannot be synthesised, so each test runs the body of the binding
# that a real drag would fire, against a scratch session. `copy-mode -M` is the
# one part that cannot be reproduced - it means "begin a mouse drag" and needs a
# real one - so the tests enter with plain `copy-mode -e`, which is the half of
# `-eM` whose behaviour is under test anyway.
set -euo pipefail

S=tmuxcopytest-$$
pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want $3, got $2)"; }
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; }
trap cleanup EXIT

command -v tmux >/dev/null || { echo "tmux not installed"; exit 2; }
tmux has-session -t 0 2>/dev/null || tmux info >/dev/null 2>&1 || { echo "no tmux server running"; exit 2; }

tmux new-session -d -s "$S" -x 80 -y 24 'seq 1 500; sleep 120'
sleep 0.5

# The binding's body, with the mouse's `-t =` replaced by an explicit target.
dragend() {
  tmux if-shell -F -t "$S" '#{scroll_position}' \
    "send -t $S -X copy-selection-no-clear" \
    "send -t $S -X copy-selection-and-cancel"
}
mode() { tmux display -p -t "$S" '#{pane_in_mode}'; }
pos()  { tmux display -p -t "$S" '#{scroll_position}'; }

echo "== drag-select at the live bottom leaves copy-mode =="
tmux copy-mode -e -t "$S"
is "enters copy-mode" "$(mode)" 1
is "at the bottom" "$(pos)" 0
tmux send -t "$S" -X begin-selection
tmux send -t "$S" -X -N 5 cursor-right
dragend
is "drag-end exits copy-mode" "$(mode)" 0

echo "== drag-select while scrolled back stays put =="
tmux copy-mode -e -t "$S"
tmux send -t "$S" -X -N 10 scroll-up
is "scrolled back" "$(pos)" 10
tmux send -t "$S" -X begin-selection
tmux send -t "$S" -X -N 5 cursor-right
# Moving the cursor can nudge the view itself, which is the test's doing and not
# the binding's - so compare against where we actually were when the drag ended.
before=$(pos)
dragend
is "drag-end stays in copy-mode" "$(mode)" 1
is "scroll position kept" "$(pos)" "$before"
[ "$before" -ne 0 ] && ok "still scrolled back, not snapped to the bottom" \
  || bad "test set up wrong: pane was already at the bottom"

echo "== the wheel alone gets you back out (-e on the drag entry) =="
tmux send -t "$S" -X -N 11 scroll-down
is "scrolling to the bottom exits copy-mode" "$(mode)" 0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
