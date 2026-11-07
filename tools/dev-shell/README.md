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
  plain shell. `s` lists `pramod@xero.local` and `pramod@192.168.1.124` (wol,
  by IP because its name does not resolve from the Mac), plus `n) new host`
  (see "Adding an ssh host" below). Enter takes the first, a number picks one, `n` asks for
  a `user@host`, and extra words like `-p 2222` pass through. ssh is the one time a tab skips
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

## Adding an ssh host

The `s` menu's list is the `TMUX_PICKER_SSH_HOSTS` array. For a one-off
connection, `n) new host` is enough; add a host to the list when you will be
going there regularly.

**For every machine** (the usual case): edit the default near the top of
`dotfiles/zsh/tmux-session-picker.zsh`, then re-run the installer on each Mac.

```zsh
(( ${+TMUX_PICKER_SSH_HOSTS} )) || TMUX_PICKER_SSH_HOSTS=(pramod@xero.local pramod@192.168.1.124 pramod@newbox.local)
```

Order matters: the first entry is what Enter picks. Each entry is one ssh
destination, `user@host` or `user@ip`, handed to ssh as a single argument,
so it cannot carry options like `-p` - for a non-standard port,
add a `Host` block to `~/.ssh/config` and list its alias instead. Use an IP
for a host whose name does not resolve from the Mac (wol). Then:

```sh
tools/dev-shell/test_tmux_session_picker.sh   # update the expected hosts if you reordered
tools/dev-shell/setup-tmux-shell.sh
```

and commit. New tabs pick it up; already-open ones do not.

**For this machine only**: set the whole list in `~/.zshenv`, which zsh reads
before `~/.zshrc`. The picker only fills in its default when the array is not
already set, so this replaces the list rather than adding to it - repeat the
hosts you want to keep:

```zsh
TMUX_PICKER_SSH_HOSTS=(pramod@xero.local pramod@192.168.1.124 me@work-box)
```

Not `~/.zshrc`: the picker is sourced from its very first lines, before
anything you could put there, and the block it sits in is rewritten by the
installer.

Not built yet (deferred 2026-11-04): adding a host from inside the menu, e.g.
offering to save what was typed at `n) new host`.

## Tests and probes

| Script | What it checks |
|---|---|
| `test_setup_tmux_shell.sh` | the installer, against throwaway `$HOME` files |
| `test_tmux_session_picker.sh` | what each picker answer does, with `tmux` and `ssh` stubbed |
| `test_tmux_copy_mode.sh` | the copy-mode binds in a running tmux server |
| `test_tmux_altscreen.py` | whether dropping smcup/rmcup keeps tmux off the alternate screen |
| `probe_tmux_scrollback.py` | why iTerm's own scrollback cannot replace tmux's (DECSTBM scroll region) |
| `check_zsh_autocomplete.sh` | whether zsh-autocomplete is live, not merely brew-installed |
| `probe_zsh_autocomplete_menu.sh` | what zsh-autocomplete actually draws at a live prompt |

`qwen_delegate_repl.py` lives here too but is unrelated: see its own
`PROJECTS.md` entry.

## zsh-autocomplete

Installed with `brew install zsh-autocomplete` (Intel prefix,
`/usr/local/share/zsh-autocomplete`), **not** as an oh-my-zsh plugin. The
`source` line is a plain hand-edit in `~/.zshrc`, outside the managed blocks.

- **The trap: brew only puts the files on disk.** Nothing sources them. It is
  not in `$ZSH/plugins`, so listing it in `plugins=()` does nothing either, and
  brew's caveat about adding the `source` line is easy to miss. It sat
  installed and completely inert from 2026-09-19 to 2026-11-08 for that reason
  alone - no error, no warning, just no completions.
- **It must be sourced after `source $ZSH/oh-my-zsh.sh`.** Its own README says
  "near the top, before any `compdef`", but that assumes no oh-my-zsh: OMZ runs
  `compinit` unconditionally and binds keys, so sourcing Autocomplete first
  lets OMZ clobber its widgets.
- **That order costs nothing at startup** (measured: ~1.15s either way, which
  is nvm plus oh-my-zsh). Autocomplete detects OMZ's already-built
  `$ZSH_COMPDUMP`, reuses it instead of running a second `compinit`, and writes
  OMZ's metadata lines back so OMZ does not delete the dump next time.
- **`zsh-syntax-highlighting` has to come first**, which it does - it loads
  from `plugins=()` above the `source` line.
- **Check it with `check_zsh_autocomplete.sh`:** the install, the `source`
  line, the order against oh-my-zsh, and the live widget count.
- **"I opened a new tab and still see nothing" is usually not the plugin.** The
  picker gives an already-open session a grouped session (`new-session -t`),
  and a session group **shares its windows** - so the new tab is another view
  of the same pane, running the same process that started before you edited
  `~/.zshrc`. `tmux list-panes -a -F '#{session_name} #{pane_pid}'` showing one
  `pane_pid` under two session names is the tell. Run `exec zsh` in the pane,
  or take `n) new session` / plain Enter in the picker.
- **It is not `zsh-autosuggestions`.** Autocomplete draws a menu *below* the
  prompt; autosuggestions ghosts the rest of the line in grey, accepted with
  `->`. Wanting the second and installing the first looks exactly like "it
  doesn't work". Only Autocomplete is installed here.
- **See what it actually draws with `probe_zsh_autocomplete_menu.sh`**, e.g.
  `probe_zsh_autocomplete_menu.sh 'cd co' ~`. It drives a real interactive zsh
  in a throwaway tmux server (socket `-L acprobe`, so the real sessions are
  untouched) and prints the screen.
- **A widget check needs a pty**, which the script sets up with a throwaway
  `ZDOTDIR` chaining the real `~/.zshrc`. Autocomplete installs its ZLE widgets
  from a `precmd` hook, so `zsh -i -c ...` has no line editor, no prompt and no
  `precmd`, and reports zero widgets even when the setup is perfect.

## Known loose ends

- `clawlight/claude-tmux-name.zsh` defines its own `claude()` (names the
  Claude session after the tmux session). It is not sourced on the MacBook. If
  it ever is, whichever file is sourced last wins, so merge the two first.
- `~/code/personal/scripts/install-tmux-claude.sh` is the superseded untracked
  installer and still exists. Safe to delete; this installer strips its blocks.
