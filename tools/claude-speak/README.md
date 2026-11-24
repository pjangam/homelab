# tools/claude-speak/

Reads every Claude Code reply aloud on a Mac, using a `Stop` hook and macOS `say`.
Code blocks, tables and markdown symbols are stripped, identifiers are split
into words (`ItineraryItemDetailResponse`, `snake_case`), common acronyms are
spelled out (`XML`, `ID`); the whole reply is
read (no length cap); a new reply stops the one still being read, and so does
sending a message.

## What runs where

| What | Repo file | Installed to |
|---|---|---|
| The reader | `speak-reply.sh` | `~/.claude/hooks/speak-reply.sh`, run by a `Stop` entry in `~/.claude/settings.json` |
| The stopper (`killall say`) | `speak-stop.sh` | `~/.claude/hooks/speak-stop.sh`, run by a `UserPromptSubmit` entry, and by the hotkey below |
| On/off switch + voice | - | `~/.claude/speak` (exists = on; optional first line = `say` options) |

- **Host:** any Mac running Claude Code. Installed on the MacBook 2026-11-20.
- **Edit the repo copy**, then re-run `install.sh`. The installed copy is overwritten on every run.
- **No state or secrets.** Each reply goes through a temp file that is deleted after it is spoken.

## Installing

```sh
tools/claude-speak/install.sh --on        # install and turn speech on
tools/claude-speak/install.sh             # install/update, leave on/off as it is
tools/claude-speak/install.sh --uninstall # remove both hooks, their settings entries and the switch
```

- Needs `jq` (`brew install jq`).
- Idempotent: the settings entry is added only if missing, other hooks are untouched, the old settings are kept as `settings.json.bak-speak`.
- Restart running Claude Code sessions after the first install.
- It checks that the voice actually produces audio and warns if not (see traps).

## Using it

| Action | Command |
|---|---|
| Turn on | `touch ~/.claude/speak` |
| Turn off | `rm ~/.claude/speak` |
| Change voice/speed | `echo "-v Daniel -r 230" > ~/.claude/speak` |
| List voices | `say -v '?'` |
| Stop the current reply | send any message, the hotkey below, or `killall say` |

### Stop hotkey

Ctrl+C cannot do it: Claude Code owns that key and hooks never see keypresses.
Set up by hand, once per Mac, as an **iTerm key binding** (works whenever iTerm
is the front app):

1. iTerm > Settings > Keys > **Key Bindings** > **+**
2. Keyboard Shortcut: `Ctrl+Cmd+S`
3. Action: **Run Coprocess**, command `killall say`

Not used, and why (2026-11-20):

| Option | Why not |
|---|---|
| macOS Shortcuts hotkey | The shortcut ran fine (`shortcuts run "stop saying from shell"` stopped speech) but its keyboard trigger never fired, with `Ctrl+Opt+S` or `Ctrl+Opt+Cmd+S`. |
| Alfred hotkey | Workflows need the Powerpack. |
| Hammerspoon (works in every app) | Offered, not chosen: another app to install. The fallback if an all-apps hotkey is ever wanted. |

## Traps

| Symptom | Cause | Fix |
|---|---|---|
| Hook fires, nothing heard, a system beep plays fine | The **system default voice** renders silence (`say -o x.aiff hi` gives a ~4 KB file; a working voice gives 80 KB+). Hit on the MacBook 2026-11-20. `say` still exits 0. | The hook names a voice (`-v Samantha`) instead of using the default. Fix the default in System Settings > Accessibility > Spoken Content. |
| Hook fires, `say &` never speaks | Claude Code kills the hook's process group when the hook exits, taking a backgrounded `say` with it. | `speak-reply.sh` forks `say` into a new session with perl's `POSIX::setsid` (macOS has no `setsid` binary). Do not "simplify" it back to `say &`. |
| Nothing at all, remotely | The hook speaks on the machine Claude Code runs on, not on the phone/browser driving it via Remote Control. | Be at the Mac. |
| `ItineraryItemDetailResponse` read as one long word | `say` does not split PascalCase/camelCase, and underscores used to be deleted, gluing snake_case together. | A second `sed` inserts spaces at case changes and turns `_` into a space (2026-11-24). Side effect: `OAuth` -> "O Auth", `iPhone` -> "i Phone". |
| `XML`, `Id` read as words ("zml", "id") | `say` pronounces some acronyms as words. | A list in `speak-reply.sh` (`any=` / `upper=`) is spelled letter by letter: `XML` -> "X M L", `getUserById` -> "get User By I D". Short ones that are also words (`ha`, `os`, `pr`) only when uppercase. Add to the list when another one is misread (2026-11-24). |
| Every session talks | The switch is global. | `rm ~/.claude/speak`. |
| Typing in any session cuts off another session's reply | The stopper kills every `say` on the Mac, not only this session's. | By design: simpler than tracking which session spoke. |

To debug, add `echo "$(date) fired" >> ~/.claude/hooks/speak-reply.log` near the
top of the installed hook, then remove it afterward.
