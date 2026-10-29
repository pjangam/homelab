#!/usr/bin/env bash
# Behavioural check of the copy-mode mouse bindings that dotfiles/tmux/tmux.conf
# installs. test_setup_tmux_shell.sh tests the *installer*; this tests what the
# installed config actually does, so it needs a running tmux server and the
# config already sourced into it (setup-tmux-shell.sh does that on install).
#
#   tools/dev-shell/test_tmux_copy_mode.sh
#
# Mouse events cannot be synthesised, so each test reads the body of the
# binding a real drag (or Escape) would fire out of the live server and runs it
# against a scratch session. That way the test fails if the binding changes,
# not just if tmux does.
set -euo pipefail

S=tmuxcopytest-$$
pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1 (want $3, got $2)"; }
cleanup() { tmux kill-session -t "$S" 2>/dev/null || true; }
trap cleanup EXIT

command -v tmux >/dev/null || { echo "tmux not installed"; exit 2; }
# `tmux info` needs an attached client on 3.4, so it fails over plain ssh.
tmux ls >/dev/null 2>&1 || { echo "no tmux server running"; exit 2; }

tmux new-session -d -s "$S" -x 80 -y 24 'seq 1 500; sleep 120'
sleep 0.5

TABLE=copy-mode
[ "$(tmux show -gv mode-keys)" = vi ] && TABLE=copy-mode-vi

# Run what a key in the copy-mode table is bound to, pointed at the scratch
# pane. The mouse's own target (-t =) only exists for a real mouse event, so
# every `send -X` gets an explicit one instead.
fire() {
  local body
  # Filter the whole table: `list-keys -T table key` prints nothing on 3.7.
  body=$(tmux list-keys -T "$TABLE" | sed -nE "s/^bind-key +-T $TABLE +$1 +//p")
  [ -n "$body" ] || { bad "$1 is not bound in $TABLE"; return; }
  body=${body//send-keys -X/send-keys -t $S -X}
  body=${body//send -X/send -t $S -X}
  body=${body//select-pane/select-pane -t $S}
  body=${body//if-shell -F/if-shell -t $S -F}
  eval "tmux $body"
}
mode() { tmux display -p -t "$S" '#{pane_in_mode}'; }
pos()  { tmux display -p -t "$S" '#{scroll_position}'; }
# Empty outside copy-mode; normalise to 0 - no copy-mode is no selection.
sel()  { local v; v=$(tmux display -p -t "$S" '#{selection_present}'); echo "${v:-0}"; }
buf()  { tmux show-buffer 2>/dev/null || true; }

echo "== drag-select while scrolled back: copies, stays put, stays highlighted =="
tmux copy-mode -t "$S"
tmux send -t "$S" -X -N 10 scroll-up
tmux send -t "$S" -X begin-selection
tmux send -t "$S" -X -N 5 cursor-right
before=$(pos)
tmux set-buffer -- "sentinel-$$"
fire MouseDragEnd1Pane
is "drag-end stays in copy-mode" "$(mode)" 1
is "scroll position kept" "$(pos)" "$before"
is "selection still highlighted" "$(sel)" 1
[ "$(buf)" != "sentinel-$$" ] && ok "selection copied to the tmux buffer" \
  || bad "selection copied to the tmux buffer (buffer unchanged)"
[ "$before" -ne 0 ] && ok "still scrolled back, not snapped to the bottom" \
  || bad "test set up wrong: pane was already at the bottom"

# stop-selection is what keeps the highlight from growing: without it the
# selection end follows the cursor, and scrolling moves the cursor.
copied=$(buf)
tmux send -t "$S" -X -N 3 scroll-up
tmux send -t "$S" -X -N 4 cursor-down
fire MouseDragEnd1Pane
is "scrolling after the copy does not grow the selection" "$(buf)" "$copied"

echo "== Escape clears the selection first, leaves copy-mode second =="
if [ "$TABLE" = copy-mode ]; then
  fire Escape
  is "first Escape clears the selection" "$(sel)" 0
  is "first Escape stays in copy-mode" "$(mode)" 1
  fire Escape
  is "second Escape leaves copy-mode" "$(mode)" 0
else
  fire Escape
  is "Escape clears the selection" "$(sel)" 0
  is "Escape stays in copy-mode" "$(mode)" 1
  tmux send -t "$S" -X cancel
fi

echo "== double-click copies a word and stays =="
tmux copy-mode -t "$S"
tmux send -t "$S" -X -N 10 scroll-up
before=$(pos)
fire DoubleClick1Pane
is "double-click stays in copy-mode" "$(mode)" 1
is "double-click keeps scroll position" "$(pos)" "$before"
is "double-click leaves the word highlighted" "$(sel)" 1

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
