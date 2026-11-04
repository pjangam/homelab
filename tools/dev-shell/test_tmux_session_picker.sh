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
# is zsh run before the picker is sourced. TERM_PROGRAM is unset so sourcing
# the file does not start the picker itself.
run() {
  printf '%b' "$1" | env -u TERM_PROGRAM zsh -f -c '
    eval "$1"
    tmux() { case $1 in ls) print "work\t2\tdetached\tThu Sep 10 13:03:01 2026" ;;
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
