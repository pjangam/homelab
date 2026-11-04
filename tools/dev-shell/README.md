# tools/dev-shell/

The Mac shell setup: every new iTerm tab offers a tmux session, Claude Code
asks before running outside tmux, and inside tmux the wheel scrolls while a
drag is still a normal iTerm selection. Background and history are in the
`PROJECTS.md` entry "Claude Code and new iTerm tabs always land inside tmux".

## Who owns what

Edit the repo copy, then re-run `setup-tmux-shell.sh`. The installed copies in
`$HOME` are overwritten on every run, and a hand-edit there is invisible to
every other machine.

| What | Repo file | Installed to | Read by |
|---|---|---|---|
| Session picker on a new iTerm tab | `dotfiles/zsh/tmux-session-picker.zsh` | `~/.zsh/functions/tmux-session-picker.zsh` | zsh, via the top managed block in `~/.zshrc` |
| `claude` / `claude-local` wrappers, `CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1` | `dotfiles/zsh/claude-tmux.zsh` | `~/.zsh/functions/claude-tmux.zsh` | zsh, via the bottom managed block in `~/.zshrc` |
| The two `source` lines | written by `setup-tmux-shell.sh` | `~/.zshrc`, between `# >>> homelab tmux-shell: ... >>>` markers | zsh at startup |
| Pane/window directory, mouse, copy-mode binds, OSC 52, tab title | `dotfiles/tmux/tmux.conf` | `~/.tmux.conf`, between `# >>> homelab tmux-shell >>>` markers | the tmux server (the installer runs `tmux source-file`) |
| Wheel to tmux, clicks and drags to iTerm | not in the repo | iTerm profile, see below | iTerm |

So `~/.zshrc` holds only two `source` lines. Anything outside the managed
blocks in `~/.zshrc` and `~/.tmux.conf` is left alone.

## Installing

```sh
tools/dev-shell/setup-tmux-shell.sh --dry-run
tools/dev-shell/setup-tmux-shell.sh
```

Re-running is the update path. On a Mac with no clone of the repo,
`setup-tmux-shell.sh --bundle /tmp/install-tmux-shell.sh` writes one
self-contained file with the dotfiles baked in; copy it over and run it.

Then set these by hand in iTerm. The script cannot, and without them the
mouse setup in `tmux.conf` does not work:

- **Profiles > Terminal**: mouse reporting ON, report wheel events ON,
  report clicks & drags OFF.
- **General > Selection**: "Applications in terminal may access clipboard" ON
  (lets a tmux copy-mode copy reach the system clipboard over OSC 52).

## What it does

- **Session picker.** Runs only for an interactive iTerm shell outside tmux.
  It never attaches on its own: a number attaches, `s` connects over ssh, `n`
  creates a named session with a Tab-completed start directory, Enter gives a
  plain shell. `s` lists `pramod@xero.local` and `pramod@wol` (override with a
  `TMUX_PICKER_SSH_HOSTS=(...)` array set before the picker is sourced); Enter
  takes the first, a number picks one, anything else is typed as `user@host`
  and extra words like `-p 2222` pass through. ssh is the one time a tab skips
  tmux on purpose. When it ends, or fails to connect, the tab carries on as a
  plain local shell, so the error stays visible. A
  session already open in another tab gets an independent view (a tmux
  session group) instead of a mirror. Its `source` line must stay above
  powerlevel10k's instant-prompt block, because it reads from the console.
- **Claude wrappers.** Outside tmux, `claude` asks first: Enter relaunches it in
  a tmux session named after the directory, `n` runs it here anyway, `q`
  aborts.
- **Mouse.** tmux has mouse on, because that is the only way the wheel reaches
  it. iTerm only selects natively when it keeps the clicks, and the profile
  setting above splits them: tmux gets the wheel, iTerm keeps clicks and
  drags. The full reasoning is the comment in `dotfiles/tmux/tmux.conf`. The
  cost: no click-to-focus a pane or drag-to-resize, and a selection runs across
  side-by-side panes (prefix `z` to zoom one first). Prefix `g` turns tmux's
  mouse on and off.
- **Copy-and-stay.** If iTerm does report drags (another profile), a drag,
  double- or triple-click copies and keeps the scroll position instead of
  jumping to the bottom.
- **Tab title** is the tmux session (group) name.

Escape hatches: `NO_TMUX=1` skips the picker; `n` at the claude prompt runs it
outside tmux.

## Tests and probes

| Script | What it checks |
|---|---|
| `test_setup_tmux_shell.sh` | the installer, against throwaway `$HOME` files |
| `test_tmux_session_picker.sh` | what each picker answer does, with `tmux` and `ssh` stubbed |
| `test_tmux_copy_mode.sh` | the copy-mode binds in a running tmux server |
| `test_tmux_altscreen.py` | whether dropping smcup/rmcup keeps tmux off the alternate screen |
| `probe_tmux_scrollback.py` | why iTerm's own scrollback cannot replace tmux's (DECSTBM scroll region) |

`qwen_delegate_repl.py` lives here too but is unrelated: see its own
`PROJECTS.md` entry.

## Known loose ends

- `clawlight/claude-tmux-name.zsh` defines its own `claude()` (names the
  Claude session after the tmux session). It is not sourced on the MacBook. If
  it ever is, whichever file is sourced last wins, so merge the two first.
- `~/code/personal/scripts/install-tmux-claude.sh` is the superseded untracked
  installer and still exists. Safe to delete; this installer strips its blocks.
