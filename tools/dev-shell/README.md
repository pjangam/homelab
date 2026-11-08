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
| Wheel to tmux, clicks and drags to iTerm | `setup-iterm-mouse.sh` | iTerm profile (`com.googlecode.iterm2.plist`) | iTerm |

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

Then the iTerm profile settings, without which the mouse setup in `tmux.conf`
does not work. `setup-tmux-shell.sh` does **not** touch these - they live in
iTerm's own prefs, not a dotfile:

```sh
tools/dev-shell/setup-iterm-mouse.sh            # check, safe any time
tools/dev-shell/setup-iterm-mouse.sh --apply    # write them (iTerm must be quit)
```

It wants mouse reporting ON, alternate mouse scroll ON, clicks and drags **not**
reported, and the global "Applications in terminal may access clipboard" ON (the
last one lets a tmux copy-mode copy reach the system clipboard over OSC 52).
With iTerm running, set it in the UI instead - it applies immediately:
**Settings > Profiles > Terminal > Mouse reporting > [x] Don't report clicks and
drags**, once per profile you actually use.

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
| `check_zsh_prompt_plugins.sh` | whether autosuggestions is live and loading before syntax-highlighting |
| `probe_zsh_prompt.sh` | what the prompt plugins actually draw at a live prompt |

`qwen_delegate_repl.py` lives here too but is unrelated: see its own
`PROJECTS.md` entry.

## Prompt plugins

Two plugins get confused for each other constantly. What is set up here:

| Plugin | What you see | State |
|---|---|---|
| `zsh-autosuggestions` | the rest of the line in **grey ghost text**, accepted with `->` | in use, brew 0.7.1, loaded from `plugins=()` |
| `zsh-autocomplete` | a **menu below the prompt** listing matches | brew 26.08.04 on disk, deliberately **not** sourced |
| `zsh-syntax-highlighting` | the typed line coloured as you go | in use, oh-my-zsh custom clone, **must load last** |

Chosen 2026-11-08: autosuggestions only. Autocomplete is left installed but
dormant, so re-enabling it is one `source` line - see the history below before
you do.

- **Load order is the whole trick.** `zsh-syntax-highlighting` has to come
  **last**. On zsh newer than 5.8 it installs a `zle-line-pre-redraw` hook and
  its README requires it to register "after anything else that adds hooks that
  modify the command-line buffer"; autosuggestions' own source says
  "highlighting breaks if our widgets are wrapped by zsh-syntax-highlighting
  widgets". Both must therefore load before it.
- **So autosuggestions goes in `plugins=()`, not in a `source` line.** z-sy-h
  loads from `plugins=()` inside `source $ZSH/oh-my-zsh.sh`, so any `source`
  line after that - which is exactly what brew's caveat tells you to add - is
  already too late. Listing it in `plugins=()` above z-sy-h is the only spot
  that gets the order right.
- **That needs a shim**, at
  `$ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh`.
  brew ships only `share/zsh-autosuggestions/zsh-autosuggestions.zsh`, with no
  `.plugin.zsh`, so oh-my-zsh's `is_plugin()` cannot find it. The shim is one
  `source` line pointing at brew's copy, which keeps brew as the updater. Do
  not copy the plugin into it.
- **brew only puts files on disk - nothing sources them.** Neither plugin is in
  `$ZSH/plugins`, so naming it in `plugins=()` without the shim does nothing,
  and there is no error when nothing loads it. `zsh-autocomplete` sat installed
  and completely inert from 2026-09-19 to 2026-11-08 for that reason alone.
- **"I opened a new tab and still see nothing" is usually not the plugin.** The
  picker gives an already-open session a grouped session (`new-session -t`),
  and a session group **shares its windows** - so the new tab is another view
  of the same pane, running the same process that started before you edited
  `~/.zshrc`. `tmux list-panes -a -F '#{session_name} #{pane_pid}'` showing one
  `pane_pid` under two session names is the tell. Run `exec zsh` in the pane,
  or take `n) new session` / plain Enter in the picker.
- **A plain screen capture cannot tell a suggestion from real text.** Grey
  ghost text and an accepted suggestion read identically in
  `tmux capture-pane -p`. Use `-e`: the suggestion is `SGR 90`
  (`^[[90mde/home_tools`), and after `->` that span is gone.
- **Autocomplete, if you ever re-enable it,** needs its `source` line **after**
  `source $ZSH/oh-my-zsh.sh`, not "near the top" as its README says - that
  advice assumes no oh-my-zsh, which runs `compinit` unconditionally and binds
  keys, so sourcing Autocomplete first lets OMZ clobber its widgets. Sourcing
  it after costs nothing measurable (~1.15s either way, which is nvm plus
  oh-my-zsh): it detects OMZ's already-built `$ZSH_COMPDUMP`, reuses it instead
  of running a second `compinit`, and writes OMZ's metadata lines back so OMZ
  does not delete the dump next time.

### Checking it

```sh
tools/dev-shell/check_zsh_prompt_plugins.sh          # setup, order, and a live pty check
tools/dev-shell/probe_zsh_prompt.sh 'cd co' ~ -e     # what the screen actually shows
```

Both need a pty, which they set up themselves in a throwaway tmux server
(socket `-L zpluginscheck` / `-L acprobe`, so the real sessions are untouched).
`zsh -i -c ...` proves nothing: the widgets bind from a `precmd` hook, so with
no line editor and no prompt there is no `precmd` and the count is always zero.

## When text selection stops working

Hit on this MacBook 2026-11-08: a plain drag selected nothing in iTerm, though
the same setup worked on the work MacBook.

- **The tell is Option-drag.** If a plain drag selects nothing but **Option**-drag
  does, the iTerm side is wrong, not tmux. Option forces iTerm to keep the drag
  for itself instead of reporting it, which is precisely what the profile
  setting is supposed to do all the time.
- **Cause:** `Mouse Reporting allow clicks and drags` absent from the profile,
  so at iTerm's default of *reporting* them. tmux has `mouse on` (it must, or
  nothing scrolls), so tmux received the drag and iTerm had no selection for
  Cmd-C to copy.
- **Not a tmux problem.** `tmux show -g mouse` / `set-clipboard` and
  `~/.tmux.conf` were all correct and identical to the repo copy. Check
  `setup-iterm-mouse.sh` before touching tmux.
- **It is per profile.** Both profiles here needed it; a new tab on the other
  profile would have behaved differently. The script reports every profile.
- **The settings are Mac-only.** Copying `tmux.conf` to `xero` carries none of
  this - there is no iTerm there. A remote tmux over ssh is still governed by
  the local iTerm profile, which is why the fix covers ssh too.

## Known loose ends

- `clawlight/claude-tmux-name.zsh` defines its own `claude()` (names the
  Claude session after the tmux session). It is not sourced on the MacBook. If
  it ever is, whichever file is sourced last wins, so merge the two first.
- `~/code/personal/scripts/install-tmux-claude.sh` is the superseded untracked
  installer and still exists. Safe to delete; this installer strips its blocks.
