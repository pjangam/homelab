#!/usr/bin/env bash
# Tests for scripts/setup-tmux-shell.sh. Runs the installer against throwaway
# copies of ~/.zshrc etc. under a temp dir (ZSHRC/TMUX_CONF/FUNC_DIR
# overrides), so it never touches the real ones.
#
#   scripts/test_setup_tmux_shell.sh
set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/scripts/setup-tmux-shell.sh"
pass=0; fail=0

ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = 0 ]; then ok "$1"; else bad "$1"; fi; }

# check_count <label> <file> <pattern> <expected>
check_count() {
  local got; got=$(grep -c -- "$3" "$2" 2>/dev/null || true)
  if [ "$got" = "$4" ]; then ok "$1"; else bad "$1 (found $got, want $4)"; fi
}

run() {  # run the installer against a sandbox root
  ZSHRC="$1/zshrc" TMUX_CONF="$1/tmux.conf" FUNC_DIR="$1/functions" \
    "$INSTALL" "${2:-}" > "$1/out" 2>&1
}

SANDBOX=$(mktemp -d); trap 'rm -rf "$SANDBOX"' EXIT

echo "== fresh machine (no zshrc, no tmux.conf) =="
A="$SANDBOX/fresh"; mkdir -p "$A"
run "$A"; check "installer exits 0" $?
check "picker installed"  $([ -f "$A/functions/tmux-session-picker.zsh" ]; echo $?)
check "wrappers installed" $([ -f "$A/functions/claude-tmux.zsh" ]; echo $?)
check_count "picker sourced once" "$A/zshrc" 'source ~/.zsh/functions/tmux-session-picker.zsh' 1
check_count "wrappers sourced once" "$A/zshrc" 'source ~/.zsh/functions/claude-tmux.zsh' 1
check "picker block is first line" $([ "$(head -1 "$A/zshrc")" = '# >>> homelab tmux-shell: session picker >>>' ]; echo $?)
check_count "tmux binds installed" "$A/tmux.conf" 'pane_current_path' 3
check "zshrc is valid zsh" $(zsh -n "$A/zshrc"; echo $?)

echo "== idempotent re-run =="
before=$(cat "$A/zshrc"); beforet=$(cat "$A/tmux.conf")
run "$A"; check "second run exits 0" $?
check "zshrc unchanged"     $([ "$before" = "$(cat "$A/zshrc")" ]; echo $?)
check "tmux.conf unchanged" $([ "$beforet" = "$(cat "$A/tmux.conf")" ]; echo $?)
check "reports 'unchanged'" $(grep -q 'unchanged:' "$A/out"; echo $?)
check "made no backup files" $([ -z "$(ls "$A"/zshrc.bak.* 2>/dev/null)" ]; echo $?)

echo "== migrates the hand-edited original out of zshrc =="
B="$SANDBOX/legacy"; mkdir -p "$B"
cat > "$B/zshrc" <<'LEOF'
# Offer a tmux session menu when an interactive iTerm shell starts outside tmux.
# Must stay ABOVE the p10k instant-prompt block -- it reads from the console.
[[ -r ~/.zsh/functions/tmux-session-picker.zsh ]] && source ~/.zsh/functions/tmux-session-picker.zsh

export KEEP_ME=1
alias gs="git status"

# ---------------------------------------------------------------------------
# Never let Claude Code run outside tmux without asking first.
# ---------------------------------------------------------------------------
_tmux_or_ask() {
  local sess=$1; shift
  print "legacy"
}

claude() {
  _tmux_or_ask "${PWD:t}" -- ${commands[claude]:-claude} "$@"
}

claude-local() {
  local -a llm_env=( ANTHROPIC_BASE_URL=http://127.0.0.1:11434 )
  _tmux_or_ask "${PWD:t}" $llm_env -- ${commands[claude]:-claude} "$@"
}

# git branch switch that carries skip-worktree changes across
export KEEP_ME_TOO=1
export CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1
LEOF
printf 'bind c new-window -c "#{pane_current_path}"\n' > "$B/tmux.conf"
run "$B"; check "installer exits 0" $?
check_count "legacy _tmux_or_ask gone"  "$B/zshrc" '^_tmux_or_ask() {' 0
check_count "legacy claude() gone"      "$B/zshrc" '^claude() {' 0
check_count "legacy claude-local() gone" "$B/zshrc" '^claude-local() {' 0
check_count "legacy mouse export gone"  "$B/zshrc" 'CLAUDE_CODE_DISABLE_MOUSE_CLICKS' 0
check_count "picker sourced once"       "$B/zshrc" 'tmux-session-picker.zsh' 1
check_count "unrelated line kept"       "$B/zshrc" '^export KEEP_ME=1$' 1
check_count "line after the block kept" "$B/zshrc" '^export KEEP_ME_TOO=1$' 1
check_count "unrelated comment kept"    "$B/zshrc" 'git branch switch that carries' 1
check_count "alias kept"                "$B/zshrc" '^alias gs=' 1
check_count "tmux binds not duplicated" "$B/tmux.conf" 'bind c ' 1
check "backed the original up" $([ -n "$(ls "$B"/zshrc.bak.* 2>/dev/null)" ]; echo $?)
check "zshrc is valid zsh" $(zsh -n "$B/zshrc"; echo $?)
again=$(cat "$B/zshrc"); run "$B"
check "re-run is a no-op" $([ "$again" = "$(cat "$B/zshrc")" ]; echo $?)

echo "== refuses to cut a legacy block it can't find the end of =="
C="$SANDBOX/broken"; mkdir -p "$C"
cat > "$C/zshrc" <<'CEOF'
# ---------------------------------------------------------------------------
# Never let Claude Code run outside tmux without asking first.
# ---------------------------------------------------------------------------
_tmux_or_ask() {
  print "legacy"
}
export KEEP_ME=1
CEOF
run "$C"; check "installer still exits 0" $?
check "warns about it" $(grep -q 'leaving it alone' "$C/out"; echo $?)
check_count "legacy left in place" "$C/zshrc" '^_tmux_or_ask() {' 1
check_count "unrelated line kept"  "$C/zshrc" '^export KEEP_ME=1$' 1

echo "== takes over blocks installed by install-tmux-claude.sh =="
E="$SANDBOX/foreign"; mkdir -p "$E/functions"
cat > "$E/zshrc" <<'EEOF'
# >>> tmux-session-picker (managed by install-tmux-claude.sh) >>>
# Offer a tmux session menu when an interactive iTerm shell starts outside tmux.
# Must stay ABOVE the p10k instant-prompt block -- it reads from the console.
[[ -r ~/.zsh/functions/tmux-session-picker.zsh ]] && source ~/.zsh/functions/tmux-session-picker.zsh
# <<< tmux-session-picker <<<

export KEEP_ME=1
export CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1

# >>> claude-tmux-guard (managed by install-tmux-claude.sh) >>>
[[ -r ~/.zsh/functions/claude-tmux-guard.zsh ]] && source ~/.zsh/functions/claude-tmux-guard.zsh
# <<< claude-tmux-guard <<<
EEOF
cat > "$E/tmux.conf" <<'EEOF'
# New panes and windows open in the directory the current pane is in.
bind c   new-window      -c "#{pane_current_path}"

# >>> pane-path inheritance (managed by install-tmux-claude.sh) >>>
bind c   new-window      -c "#{pane_current_path}"
# <<< pane-path inheritance <<<
EEOF
printf 'print orphan\n' > "$E/functions/claude-tmux-guard.zsh"
run "$E"; check "installer exits 0" $?
check_count "their markers gone"       "$E/zshrc" 'install-tmux-claude.sh' 0
check_count "their guard unsourced"    "$E/zshrc" 'claude-tmux-guard' 0
check "orphan guard file removed"      $([ ! -f "$E/functions/claude-tmux-guard.zsh" ]; echo $?)
check_count "picker sourced once"      "$E/zshrc" 'tmux-session-picker.zsh' 1
check_count "wrappers sourced once"    "$E/zshrc" 'claude-tmux.zsh' 1
check_count "mouse export not duplicated" "$E/zshrc" 'CLAUDE_CODE_DISABLE_MOUSE_CLICKS' 0
check_count "unrelated line kept"      "$E/zshrc" '^export KEEP_ME=1$' 1
check_count "their tmux markers gone"  "$E/tmux.conf" 'install-tmux-claude.sh' 0
check_count "tmux bind not duplicated" "$E/tmux.conf" 'bind c ' 1
check "zshrc is valid zsh" $(zsh -n "$E/zshrc"; echo $?)
again=$(cat "$E/zshrc"); run "$E"
check "re-run is a no-op" $([ "$again" = "$(cat "$E/zshrc")" ]; echo $?)

echo "== --dry-run writes nothing =="
D="$SANDBOX/dry"; mkdir -p "$D"; printf 'export KEEP_ME=1\n' > "$D/zshrc"
run "$D" --dry-run; check "exits 0" $?
check "zshrc untouched"        $([ "$(cat "$D/zshrc")" = 'export KEEP_ME=1' ]; echo $?)
check "no functions installed" $([ ! -d "$D/functions" ]; echo $?)
check "no tmux.conf created"   $([ ! -f "$D/tmux.conf" ]; echo $?)
check "says what it would do"  $(grep -q 'would write' "$D/out"; echo $?)

echo "== refuses to write a zshrc that would not parse =="
F="$SANDBOX/broken-zsh"; mkdir -p "$F"
printf 'if [ -z "$FOO" ]; then\n  echo unterminated\n' > "$F/zshrc"
before=$(cat "$F/zshrc")
run "$F"; check "exits nonzero" $([ $? -ne 0 ]; echo $?)
check "said it refused"   $(grep -q 'refusing to write' "$F/out"; echo $?)
check "zshrc untouched"   $([ "$before" = "$(cat "$F/zshrc")" ]; echo $?)
check "no rollback needed" $([ -z "$(ls "$F"/zshrc.bak.* 2>/dev/null)" ]; echo $?)

echo "== --bundle makes a single file that installs with no repo around =="
G="$SANDBOX/standalone"; mkdir -p "$G/bin"
"$INSTALL" --bundle "$G/bin/install.sh" > "$G/bundle-out" 2>&1
check "bundle written"        $([ -x "$G/bin/install.sh" ]; echo $?)
check "no dotfiles/ near it"  $([ ! -d "$G/dotfiles" ]; echo $?)
ZSHRC="$G/zshrc" TMUX_CONF="$G/tmux.conf" FUNC_DIR="$G/functions" \
  "$G/bin/install.sh" > "$G/out" 2>&1
check "standalone install exits 0" $?
check "picker matches the repo copy" \
  $(diff <(tail -n +1 "$G/functions/tmux-session-picker.zsh") \
         <(cat "$REPO/dotfiles/zsh/tmux-session-picker.zsh") >/dev/null; echo $?)
check "wrappers match the repo copy" \
  $(diff "$G/functions/claude-tmux.zsh" "$REPO/dotfiles/zsh/claude-tmux.zsh" >/dev/null; echo $?)
check_count "tmux binds installed" "$G/tmux.conf" 'pane_current_path' 3
check "zshrc is valid zsh" $(zsh -n "$G/zshrc"; echo $?)
again=$(cat "$G/zshrc"); ZSHRC="$G/zshrc" TMUX_CONF="$G/tmux.conf" FUNC_DIR="$G/functions" "$G/bin/install.sh" >/dev/null 2>&1
check "re-run is a no-op" $([ "$again" = "$(cat "$G/zshrc")" ]; echo $?)
check "refuses to bundle a bundle" \
  $("$G/bin/install.sh" --bundle "$G/again.sh" >/dev/null 2>&1; [ $? -ne 0 ]; echo $?)

echo "== shipped function files are valid zsh =="
check "tmux-session-picker.zsh" $(zsh -n "$REPO/dotfiles/zsh/tmux-session-picker.zsh"; echo $?)
check "claude-tmux.zsh"         $(zsh -n "$REPO/dotfiles/zsh/claude-tmux.zsh"; echo $?)

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
