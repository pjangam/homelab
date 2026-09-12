#!/usr/bin/env bash
# Install the tmux/Claude Code shell setup onto this machine. RUN IT ON A MAC
# (or any box you want the same shell on).
#
#   scripts/setup-tmux-shell.sh --dry-run
#   scripts/setup-tmux-shell.sh
#
# On a Mac that has no clone of this repo, make a standalone copy with the
# dotfiles baked into it and carry that one file over instead:
#
#   scripts/setup-tmux-shell.sh --bundle /tmp/install-tmux-shell.sh
#   scp /tmp/install-tmux-shell.sh othermac:  &&  ssh othermac ./install-tmux-shell.sh
#
# What it installs, all from dotfiles/ in this repo:
#
#   1. ~/.zsh/functions/tmux-session-picker.zsh - on a new iTerm tab outside
#      tmux, lists running sessions and waits for a choice (number to attach,
#      n to create one you name and give a start directory with Tab completion,
#      Enter for a plain shell). It never attaches on its own.
#   2. ~/.zsh/functions/claude-tmux.zsh - `claude` / `claude-local` wrappers
#      that refuse to start outside tmux without asking first.
#   3. Two source lines in ~/.zshrc, in marker-delimited managed blocks. The
#      picker's block goes at the very top, because it reads from the console
#      and so has to sit above powerlevel10k's instant-prompt block.
#   4. ~/.tmux.conf binds so new panes/windows open in the current pane's
#      directory (tmux >= 1.9 defaults to the session start dir instead).
#
# Re-running is the update path: managed blocks are replaced, anything you
# added outside them is left alone. It also migrates the original hand-edited
# version of all this out of ~/.zshrc and into the managed blocks, so the two
# copies can't drift.
#
# Overrides: ZSHRC, TMUX_CONF, FUNC_DIR.
set -euo pipefail

SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/dotfiles"
ZSHRC="${ZSHRC:-$HOME/.zshrc}"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
FUNC_DIR="${FUNC_DIR:-$HOME/.zsh/functions}"
STAMP="$(date +%Y%m%d-%H%M%S)"

PICKER_BEGIN='# >>> homelab tmux-shell: session picker >>>'
PICKER_END='# <<< homelab tmux-shell: session picker <<<'
CLAUDE_BEGIN='# >>> homelab tmux-shell: claude wrappers >>>'
CLAUDE_END='# <<< homelab tmux-shell: claude wrappers <<<'
TMUX_BEGIN='# >>> homelab tmux-shell >>>'
TMUX_END='# <<< homelab tmux-shell <<<'

dry_run=0
bundle_to=
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  --bundle)  bundle_to="${2:-./install-tmux-shell.sh}" ;;
  -h|--help) sed -n '2,36p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) printf 'error: unknown argument: %s (try --help)\n' "$1" >&2; exit 2 ;;
esac

# The three files this installs normally live in dotfiles/ next to the script.
# A bundle (--bundle) has them appended to itself instead, one payload section
# per file, so a single copied file is enough.
DOTFILES="zsh/tmux-session-picker.zsh zsh/claude-tmux.zsh tmux/tmux.conf"
bundled() { grep -q '^#__PAYLOAD__$' "$SELF"; }
dotfile() {  # $1 = path under dotfiles/
  if [ -f "$SRC/$1" ]; then
    cat "$SRC/$1"
  else
    awk -v want="$1" '
      /^#__FILE__ / { cur = $2; next }
      cur == want   { print }
    ' "$SELF"
  fi
}

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Write $2 to $1, or just report it under --dry-run. Diffs so a re-run that
# changes nothing says so out loud.
write_file() {
  local dest=$1 content=$2 check=${3:-}
  # $(...) strips trailing newlines from everything it captures, so normalise
  # here rather than at each call site: exactly one newline ends the file.
  while [ "${content: -1}" = $'\n' ]; do content="${content%$'\n'}"; done
  content="$content
"
  if [ -f "$dest" ] && printf '%s' "$content" | cmp -s - "$dest"; then
    say "  unchanged: $dest"
    return
  fi
  if [ "$dry_run" = 1 ]; then
    say "  would write: $dest"
    return
  fi
  # Check before writing, not after: a rollback needs a backup to roll back
  # to, and the file being written may be one we just created.
  if [ "$check" = zsh ] && command -v zsh >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp -t setup-tmux-shell)"
    printf '%s' "$content" > "$tmp"
    if ! zsh -n "$tmp" 2>&1; then
      rm -f "$tmp"
      die "refusing to write $dest - it would not parse as zsh (nothing was changed)"
    fi
    rm -f "$tmp"
  fi
  # An empty file we just created has nothing worth keeping a copy of.
  [ -s "$dest" ] && cp "$dest" "$dest.bak.$STAMP" && say "  backed up:  $dest.bak.$STAMP"
  mkdir -p "$(dirname "$dest")"
  printf '%s' "$content" > "$dest"
  say "  wrote:      $dest"
}

# Filter: drop a managed block, markers and all. Reads stdin so several can
# be chained - ours plus the ones install-tmux-claude.sh used.
strip_block() {
  awk -v b="$1" -v e="$2" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  '
}

# install-tmux-claude.sh (~/code/personal/scripts, untracked) installed this
# same setup under its own markers before this script existed. Strip those too,
# so whichever ran last, a run of this script leaves exactly one copy.
strip_foreign() {
  strip_block '# >>> tmux-session-picker (managed by install-tmux-claude.sh) >>>' \
              '# <<< tmux-session-picker <<<' \
  | strip_block '# >>> claude-tmux-guard (managed by install-tmux-claude.sh) >>>' \
                '# <<< claude-tmux-guard <<<' \
  | strip_block '# >>> pane-path inheritance (managed by install-tmux-claude.sh) >>>' \
                '# <<< pane-path inheritance <<<' \
  | { grep -v 'claude-tmux-guard\.zsh' || true; }
}

# Print stdin with the pre-script, hand-edited version of this setup removed:
# the two picker comment lines and its source line, the _tmux_or_ask banner
# through the end of claude-local(), and the mouse-clicks export. Everything
# here is now shipped from dotfiles/ instead.
strip_legacy() {
  awk '
    function flush(  i) { for (i = 1; i <= n; i++) print buf[i]; if (n) dropped = 0; n = 0 }
    {
      if (skip) {
        if ($0 ~ /^claude-local\(\) \{/) in_local = 1
        if (in_local && $0 ~ /^\}[[:space:]]*$/) { skip = 0; in_local = 0 }
        dropped = 1
        next
      }
      # A blank line left hanging where something was removed goes with it,
      # otherwise every run would leave one more behind.
      if (dropped && $0 ~ /^[[:space:]]*$/) next
      if (index($0, "Offer a tmux session menu when an interactive iTerm shell")) { dropped = 1; next }
      if (index($0, "Must stay ABOVE the p10k instant-prompt block")) { dropped = 1; next }
      if ($0 ~ /tmux-session-picker\.zsh/) { dropped = 1; next }
      if ($0 ~ /claude-tmux\.zsh/) { dropped = 1; next }
      if ($0 ~ /^export CLAUDE_CODE_DISABLE_MOUSE_CLICKS=/) { dropped = 1; next }
      # Buffer comment runs: a banner is only dropped once the run turns out to
      # introduce the legacy block.
      if ($0 ~ /^[[:space:]]*#/) {
        buf[++n] = $0
        if (index($0, "Never let Claude Code run outside tmux")) trigger = 1
        next
      }
      if (trigger) { n = 0; trigger = 0; skip = 1; dropped = 1; next }
      flush(); print; dropped = 0
    }
    END { flush() }
  '
}

# Is the legacy block safe to remove? Only if its end anchor is really there;
# without it strip_legacy would delete to EOF.
legacy_is_removable() {
  grep -q '^_tmux_or_ask() {' "$1" || return 0          # nothing to remove
  grep -q '^claude-local() {' "$1" && \
  awk '/^claude-local\(\) \{/ { f = 1; next } f && /^\}[[:space:]]*$/ { found = 1; exit } END { exit !found }' "$1"
}

if [ -n "$bundle_to" ]; then
  bundled && die "this is already a bundle - make one from the copy in the repo"
  [ -d "$SRC" ] || die "dotfiles/ not found next to this script (looked in $REPO)"
  {
    cat "$SELF"
    printf '#__PAYLOAD__\n'
    for f in $DOTFILES; do printf '#__FILE__ %s\n' "$f"; cat "$SRC/$f"; done
  } > "$bundle_to"
  chmod +x "$bundle_to"
  say "wrote $bundle_to - one self-contained file, copy it anywhere and run it."
  exit 0
fi

if [ ! -d "$SRC" ] && ! bundled; then
  die "no dotfiles/ next to this script and no bundled payload in it (looked in $REPO)"
fi
command -v tmux >/dev/null 2>&1 || warn "tmux is not installed - install it (brew install tmux) or none of this fires"
[ "${SHELL##*/}" = zsh ] || warn "your login shell is ${SHELL##*/}, not zsh - this only takes effect under zsh"

say "repo:      $REPO"
say "zshrc:     $ZSHRC"
say "tmux.conf: $TMUX_CONF"
say "functions: $FUNC_DIR"
[ "$dry_run" = 1 ] && say "(dry run - nothing will be written)"
say

say "1. shell functions"
write_file "$FUNC_DIR/tmux-session-picker.zsh" "$(dotfile zsh/tmux-session-picker.zsh)" zsh
write_file "$FUNC_DIR/claude-tmux.zsh"         "$(dotfile zsh/claude-tmux.zsh)" zsh

# Its guard file is now dead weight - claude-tmux.zsh replaces it, and its
# source line was just stripped above.
ORPHAN="$FUNC_DIR/claude-tmux-guard.zsh"
if [ -f "$ORPHAN" ]; then
  if [ "$dry_run" = 1 ]; then
    say "  would remove: $ORPHAN (superseded by claude-tmux.zsh)"
  else
    rm -f "$ORPHAN"
    say "  removed:    $ORPHAN (superseded by claude-tmux.zsh)"
  fi
fi

say
say "2. $ZSHRC"
[ -f "$ZSHRC" ] || { [ "$dry_run" = 1 ] || : > "$ZSHRC"; say "  creating a new $ZSHRC"; }

# sed drops leading blank lines: the block template supplies its own blank
# separator, and without this a re-run would grow one more every time.
body="$(strip_block "$PICKER_BEGIN" "$PICKER_END" < "$ZSHRC" \
        | strip_block "$CLAUDE_BEGIN" "$CLAUDE_END" \
        | strip_foreign \
        | sed '/./,$!d')"

if legacy_is_removable "$ZSHRC"; then
  body="$(printf '%s\n' "$body" | strip_legacy)"
else
  warn "found _tmux_or_ask() in $ZSHRC but not the end of claude-local() - leaving it alone."
  warn "delete it by hand, or the managed block below will just redefine it."
fi

zshrc_new="$PICKER_BEGIN
# Offer a tmux session menu when an interactive iTerm shell starts outside tmux.
# Must stay ABOVE the p10k instant-prompt block -- it reads from the console.
# Managed by scripts/setup-tmux-shell.sh in the homelab repo; edits here are lost.
[[ -r ~/.zsh/functions/tmux-session-picker.zsh ]] && source ~/.zsh/functions/tmux-session-picker.zsh
$PICKER_END

$body

$CLAUDE_BEGIN
# \`claude\` / \`claude-local\` wrappers that ask before running outside tmux.
# Managed by scripts/setup-tmux-shell.sh in the homelab repo; edits here are lost.
[[ -r ~/.zsh/functions/claude-tmux.zsh ]] && source ~/.zsh/functions/claude-tmux.zsh
$CLAUDE_END
"
write_file "$ZSHRC" "$zshrc_new" zsh

say
say "3. $TMUX_CONF"
tmux_body=""
[ -f "$TMUX_CONF" ] && tmux_body="$(strip_block "$TMUX_BEGIN" "$TMUX_END" < "$TMUX_CONF" | strip_foreign)"
# The pre-script ~/.tmux.conf was exactly these binds and nothing else; drop
# them so they don't end up duplicated above the managed block.
tmux_body="$(printf '%s\n' "$tmux_body" | awk '
  $0 ~ /^bind .*pane_current_path/ { next }
  index($0, "New panes and windows open in the directory the current pane is in") { next }
  index($0, "Since tmux 1.9 they default to the session") { next }
  { print }
')"
tmux_new="$(printf '%s\n' "$tmux_body" | sed '/./,$!d')
$TMUX_BEGIN
$(dotfile tmux/tmux.conf)
$TMUX_END
"
write_file "$TMUX_CONF" "$tmux_new"

say
if [ "$dry_run" = 1 ]; then
  say "dry run finished - re-run without --dry-run to apply."
  exit 0
fi

# Belt and braces: write_file already refused anything that failed this, but a
# broken ~/.zshrc is a broken login shell, so say it out loud.
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ZSHRC" && say "zsh -n $ZSHRC: OK"
fi

command -v tmux >/dev/null 2>&1 && tmux source-file "$TMUX_CONF" 2>/dev/null && say "reloaded $TMUX_CONF into the running tmux server"

say
say "done. Open a new iTerm tab to get the session picker."
say "Escape hatches: NO_TMUX=1 skips the picker; answering n to the claude"
say "prompt runs it outside tmux anyway."

# Nothing below this line is bash: a bundle appends its payload here, and this
# exit is what keeps the shell from ever reading it.
exit 0
