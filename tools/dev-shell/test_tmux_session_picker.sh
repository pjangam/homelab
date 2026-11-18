#!/usr/bin/env bash
# Behavioural check of the session picker's menu (dotfiles/zsh/tmux-session-picker.zsh):
# what each answer does. tmux and ssh are stubbed as zsh functions that log
# their arguments, so nothing attaches or connects.
#
#   tools/dev-shell/test_tmux_session_picker.sh
set -euo pipefail

PICKER="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/dotfiles/zsh/tmux-session-picker.zsh"
pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

command -v zsh >/dev/null || { echo "zsh not installed"; exit 2; }

# Feed $1 to the picker as keyboard input and print what the stubs logged. $2
# is zsh run before the picker is sourced. TERM_PROGRAM and LC_TERMINAL are
# unset so sourcing the file does not start the picker itself, and
# SSH_CONNECTION so the ssh option is offered (a prelude can set it again).
run() {
  printf '%b' "$1" | env -u TERM_PROGRAM -u LC_TERMINAL -u LC_TMUX_PICKER -u SSH_CONNECTION zsh -f -c '
    eval "$1"
    tmux() { case $1 in ls) print "work:2:detached:Thu Sep 10 13:03:01 2026" ;;
                        has-session) return 1 ;;
                        *) print "TMUX $*" ;; esac }
    ssh()  { print "SSH $*"; }
    source "$0"
    _tmux_session_picker
    print END
  ' "$PICKER" "${2:-}" 2>&1 | grep -E '^(TMUX|SSH|END)' | tr '\n' '|'
}

check() {  # name, input, want[, zsh prelude]
  local got; got=$(run "$2" "${4:-}")
  [ "$got" = "$3" ] && ok "$1" || bad "$1 (want '$3', got '$got')"
}

check "Enter gives a plain shell"            '\n'                  'END|'
check "! gives a plain shell"                '!\n'                 'END|'
check "number attaches"                      '1\n'                 'TMUX attach -t =work|'
check "s then Enter takes the first host"    's\n\n'               'SSH pramod@xero.local|END|'
check "s then 2 takes the second host"       's\n2\n'              'SSH pramod@192.168.1.124|END|'
check "s then n asks for a new host"         's\nn\nme@new.local\n' 'SSH me@new.local|END|'
check "s, n, empty answer asks again"        's\nn\n\n1\n'          'SSH pramod@xero.local|END|'
check "s takes a typed user@host"            's\nroot@pi.local\n'  'SSH root@pi.local|END|'
check "s passes extra words through"         's\n-p 2222 me@h\n'   'SSH -p 2222 me@h|END|'
check "s re-asks on an out-of-range number"  's\n9\n1\n'           'SSH pramod@xero.local|END|'
check "host list can be overridden"          's\n\n'               'SSH me@box|END|' \
      'TMUX_PICKER_SSH_HOSTS=(me@box)'
check "over ssh, s is refused, not run"      's\n\n'               'END|' \
      'SSH_CONNECTION="192.168.1.10 50000 192.168.1.20 22"'
check "over ssh, a number still attaches"    '1\n'                 'TMUX attach -t =work|' \
      'SSH_CONNECTION="192.168.1.10 50000 192.168.1.20 22"'

# The listing itself: a real tmux, so the -F output format is the one this
# machine's tmux actually prints (3.4 turns a tab separator into '_').
if command -v tmux >/dev/null; then
  sock="pickertest-$$"
  tmux -L "$sock" -f /dev/null new-session -d -s alpha
  got=$(printf '\n' | env -u TERM_PROGRAM -u LC_TERMINAL -u LC_TMUX_PICKER PICKER_SOCK="$sock" zsh -f -c '
    tmux() { command tmux -L "$PICKER_SOCK" "$@"; }
    source "$0"; _tmux_session_picker' "$PICKER" 2>&1 \
    | sed "s/\x1b\[[0-9;]*m//g" | grep ' 1) ' || true)
  tmux -L "$sock" kill-server
  case $got in
    *'1) alpha'*' 1 win  detached  '*) ok "listing splits name, windows, state" ;;
    *) bad "listing splits name, windows, state (got '$got')" ;;
  esac
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
