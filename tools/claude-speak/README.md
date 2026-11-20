# tools/claude-speak/

Reads every Claude Code reply aloud on a Mac, using a `Stop` hook and macOS `say`.
Code blocks, tables and markdown symbols are stripped; the whole reply is
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
A global shortcut via the macOS **Shortcuts** app instead (one-time, by hand,
per Mac - `install.sh` cannot create it):

1. Shortcuts > **+** > add the **Run Shell Script** action, script: `~/.claude/hooks/speak-stop.sh`
2. Name it "Stop Speaking"; in its details (the **i** panel) > **Add Keyboard Shortcut**, e.g. `Ctrl+Opt+S`
3. The first press may ask to allow running scripts: allow it.

Not set up as an Alfred hotkey because Alfred workflows need the Powerpack.

## Traps

| Symptom | Cause | Fix |
|---|---|---|
| Hook fires, nothing heard, a system beep plays fine | The **system default voice** renders silence (`say -o x.aiff hi` gives a ~4 KB file; a working voice gives 80 KB+). Hit on the MacBook 2026-11-20. `say` still exits 0. | The hook names a voice (`-v Samantha`) instead of using the default. Fix the default in System Settings > Accessibility > Spoken Content. |
| Hook fires, `say &` never speaks | Claude Code kills the hook's process group when the hook exits, taking a backgrounded `say` with it. | `speak-reply.sh` forks `say` into a new session with perl's `POSIX::setsid` (macOS has no `setsid` binary). Do not "simplify" it back to `say &`. |
| Nothing at all, remotely | The hook speaks on the machine Claude Code runs on, not on the phone/browser driving it via Remote Control. | Be at the Mac. |
| Every session talks | The switch is global. | `rm ~/.claude/speak`. |
| Typing in any session cuts off another session's reply | The stopper kills every `say` on the Mac, not only this session's. | By design: simpler than tracking which session spoke. |

To debug, add `echo "$(date) fired" >> ~/.claude/hooks/speak-reply.log` near the
top of the installed hook, then remove it afterward.
