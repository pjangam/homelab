# Claude Code and new iTerm tabs always land inside tmux
**Status:** Done

**Why:** A long Claude Code run in a bare terminal tab dies with the tab (and with any ssh carrying it), and there was no way back to a session you'd lost track of.
**Outcome:** shipped 2026-09-12 - `tools/dev-shell/setup-tmux-shell.sh`, installing a session picker, tab-completing start directories, `claude` / `claude-local` wrappers and tmux binds from `tools/dev-shell/dotfiles/`. Applied to the MacBook and verified. Run it on any new machine after `new_machine_setup.sh`. Who owns what, the later mouse/copy work and the iTerm settings the script can't set: `tools/dev-shell/README.md`.
- Left for the user (Pramod, optional cleanup): delete the superseded untracked `~/code/personal/scripts/install-tmux-claude.sh` on the MacBook (see "Two installers briefly existed" below).

#### What shipped
`tools/dev-shell/setup-tmux-shell.sh`, installing three things from `tools/dev-shell/dotfiles/`:
- **A session picker** (`tools/dev-shell/dotfiles/zsh/tmux-session-picker.zsh`) on every interactive iTerm shell that starts outside tmux. It deliberately **never auto-attaches** - an earlier version did, and silently dropping a new tab into whatever session happened to be first was worse than no tmux at all. It lists the running sessions (window count, attached/detached, last activity) and waits: a number attaches, `n` creates one you name, Enter gives a plain shell. Picking a session that's already open in another tab attaches an *independent view* of it (a tmux session group) rather than mirroring the other tab's window.
- **Tab-completing start directories.** Typing an exact project path by hand was the friction that nearly sank the whole thing. The new-session prompt pre-fills a guess (found by name under `$TMUX_PROJECT_ROOT`, default `~/code`) and completes with Tab, via a private `tmuxdir` keymap and a `_tmuxdir_complete` widget so the global Tab binding is untouched. Completion is only initialised on the create-a-session path, so the common attach/plain-shell paths pay nothing.
- **`claude` / `claude-local` wrappers** (`tools/dev-shell/dotfiles/zsh/claude-tmux.zsh`) that prompt before running outside tmux: Enter relaunches in a tmux window named after the current directory, `n` runs it here anyway, `q` aborts. `claude-local` (Claude Code against a local ollama) passes its env through `tmux -e` on the relaunch path, since the new session doesn't inherit the caller's exports.
- Plus `~/.tmux.conf` binds so new panes and windows open in the current pane's directory, which tmux hasn't done by default since 1.9.

#### Installing it on another Mac
`git clone git@github.com:pjangam/homelab.git && homelab/tools/dev-shell/setup-tmux-shell.sh`. For a machine that shouldn't have the repo, `tools/dev-shell/setup-tmux-shell.sh --bundle /tmp/install-tmux-shell.sh` emits **one self-contained file** with the three dotfiles appended to it as a payload (read back past an `exit 0`, so bash never parses them) - scp that over and run it. The bundle is generated from `tools/dev-shell/dotfiles/`, never hand-maintained, so it can't drift from the repo copy.

#### Notes worth keeping
- The picker's source line **has to sit above powerlevel10k's instant-prompt block** - anything that reads from the console does - so the installer maintains two separate managed blocks in `~/.zshrc` rather than appending one.
- Re-running is the update path: managed blocks are replaced, anything outside them is left alone, and the hand-edited original is migrated out of `~/.zshrc` so the two copies can't drift. It refuses to write a `~/.zshrc` that fails `zsh -n`, restoring the backup instead - a broken one is a broken login shell.
- **Two installers briefly existed for this.** A resumed session wrote a self-contained `~/code/personal/scripts/install-tmux-claude.sh` and applied it to the live dotfiles while this repo-tracked version was being built. This one now strips that one's managed blocks and its `claude-tmux-guard.zsh` on every run, so the machine converges on the repo copy no matter which ran last. The untracked script is superseded; delete it.
- Escape hatches: `NO_TMUX=1` skips the picker entirely, and answering `n` runs Claude outside tmux anyway.

#### Verification
`tools/dev-shell/test_setup_tmux_shell.sh` - 63 checks against throwaway `$HOME` files (fresh machine, migration, foreign-installer takeover, idempotent re-run, `--dry-run`, refusing a `~/.zshrc` that wouldn't parse, and a bundle installing with no repo anywhere near it). Applied to the MacBook and confirmed stable across repeated runs.

#### Log
- 2026-09-10/11: built by hand in a `~/code/personal/scripts` session.
- 2026-09-12: packaged into this repo so a second machine (or a reinstalled one) gets the same shell without reconstructing it from memory; shipped and verified.
- 2026-11-04: picker gained `s) ssh` (pramod@xero.local, wol by IP since `wol` does not resolve from the Mac, or `n) new host`), since ssh is the only time a tab skips tmux. `s` used to be an unlisted alias for plain shell. `tools/dev-shell/test_tmux_session_picker.sh` covers the menu.
- 2026-11-18: picker installed on xero too (`setup-tmux-shell.sh --picker-only`: picker only, no claude wrapper, `~/.tmux.conf` untouched). Fires on an ssh login from iTerm via `LC_TERMINAL=iTerm2` (TERM_PROGRAM does not cross ssh). No `s) ssh` option in a shell that arrived over ssh. Fixed the listing on tmux 3.4, which prints a tab in `-F` output as `_`: fields now split on `:`.
- 2026-11-18: `LC_TMUX_PICKER=1` opts any other ssh client in (Termius sets it per host; sshd's `AcceptEnv LC_*` passes it). Keep it off the Termius host whose startup command is clawlight's `phone-attach.sh`.
- 2026-11-18: iOS Termius did not send the variable (login env had no `LC_TMUX_PICKER`). Added `tpick` (picker on demand) for Termius's startup snippet instead.
- 2026-11-18: startup snippets are paid in Termius, so dropped the client-side route: `--picker-only` now sets `TMUX_PICKER_ON_SSH=1`, and xero shows the picker on every interactive ssh login. `LC_TMUX_PICKER` removed; `tpick` kept for re-opening the menu.
