# Clawlight: a bootstrap script for a machine that has no hooks yet
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Claude:** write `clawlight/setup-clawlight-hooks.sh`, driven by the same ten-event list the README documents
- [ ] **Pramod:** run it on the personal MacBook as its first real test

**Why:** `clawlight/setup-mac-focus-agent.sh` assumes the ten Claude Code hooks already exist - it reads `CLAWLIGHT_SERVER_URL` and `CLAWLIGHT_HOST_NAME` back out of them and only rewrites their paths, and it exits with *"are the clawlight hooks set up on this machine?"* if `~/.claude/settings.json` has none. So the one step that is still by hand is the first one, and it is the fiddliest: ten hooks, each with two env vars embedded in the command, each mapped to the right state.
**State:** idea only. `clawlight/README.md` step 3 documents the wiring, so this is writing down what the README already tells a human to do by hand.

#### What it would do
- **Write the ten hooks** into the global `~/.claude/settings.json` - `UserPromptSubmit`/`PostToolUse` -> active, `Stop` -> waiting, `Notification`/`PermissionRequest` -> **input_needed** (the mapping that is easiest to get wrong), `SessionEnd` -> end, and the four subagent/task events -> task_start/task_end.
- **Embed both env vars in every command.** Hook commands do not source a shell profile, so `CLAWLIGHT_SERVER_URL` and `CLAWLIGHT_HOST_NAME` go inline or the hook silently reports nowhere.
- **Back up `settings.json` first and be re-runnable,** matching the existing script: rewriting a hook that is already correct should change nothing, and it must merge into whatever hooks are already configured rather than replacing the file.
- **Then hand off** to `setup-mac-focus-agent.sh`, which already covers the clone paths, the terminal detection and the launchd agent - or simply tell the user to run it next.
- **Work on Linux too.** xero's own hooks were wired by hand as well; the same script should serve any new machine, with the focus-agent half staying Mac-only.

#### Verification
Verify it the way the existing tooling does: `clawlight/diagnose-mac-focus.sh` already walks the Mac path step by step, and the server shows whether a host is reporting - a bootstrap that claims success while nothing appears on the page is the failure worth designing against.

#### Log
- 2026-09-19: noted, when the personal MacBook turned out to have no clawlight at all.
