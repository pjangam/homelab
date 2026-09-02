# Clawlight (software-only)

A color-coded status light for Claude Code sessions - green while Claude is
working, red when it needs your input, gray when nothing's running. This is a
software stand-in for the parked "Claw Light" hardware idea in `PROJECTS.md`
(a physical ESP32 desk light) - no hardware here, just a web page you keep
floating on top of everything else via the browser's native Picture-in-Picture.

## How it works

- `server.py` runs on `xero` (port 8126, reverse-proxied by Caddy under
  `/clawlight`). It holds an in-memory registry of active sessions and serves
  the status page + a JSON/SSE API. State is **not** persisted to disk - a
  server restart just waits for the next hook event per session to repopulate.
- `set-status.sh` is called by Claude Code hooks on every relevant event. It
  reads the session ID (and cwd, for labeling) from the hook's stdin JSON and
  POSTs the new state to the server. Failures are swallowed so a network
  hiccup never blocks an actual Claude Code turn.
- Each session tracks two things: a **foreground** state (`active`/`waiting`,
  from `UserPromptSubmit`/`Stop`/`Notification`/`PermissionRequest`) and a
  **background** task counter (from `SubagentStart`/`SubagentStop`/
  `TaskCreated`/`TaskCompleted`). A session reads as `active` if either the
  foreground turn is active OR any background task is still running - so a
  forked/background agent still working doesn't make the light lie about
  needing your input just because the main turn ended.
- The light is an **aggregate** across every session that has reported in and
  hasn't gone stale (30 min): red if any session needs input, green if any is
  active, gray otherwise. This intentionally doesn't distinguish which
  account a session belongs to - on both machines only one account is logged
  in at a time, so concurrent sessions are never split across accounts on the
  same host.
- Each session is labeled by its cwd's last path segment (e.g. `homelab`),
  falling back to a short session id if cwd wasn't available yet. The page
  shows `host/label: state` per session, and the PiP bar renders the
  identifiers of whichever session(s) are driving the current color as small
  rotated text, so you can tell *which* console needs you, not just that one
  does.
- `web/index.html` shows the light and a "Float" button. Float draws the
  current color onto a canvas, turns it into a stream
  (`canvas.captureStream()`), and requests native video Picture-in-Picture on
  it - this works the same way on desktop Safari/Chrome and iOS Safari, where
  PiP genuinely floats over other apps/the home screen (unlike a normal
  browser tab).

## Setup on xero (the server)

```bash
systemctl --user daemon-reload
systemctl --user enable --now clawlight-server.service
```

Then reload Caddy so `/clawlight` is proxied:

```bash
docker compose restart caddy
```

Hooks are wired in the **global** `~/.claude/settings.json` (not a
project-local one) so the light reflects whichever Claude Code session is
running, in whichever repo:

- `UserPromptSubmit` → `clawlight/set-status.sh active`
- `Stop` → `clawlight/set-status.sh waiting`
- `Notification` → `clawlight/set-status.sh waiting`
- `PermissionRequest` → `clawlight/set-status.sh waiting`
- `SessionEnd` → `clawlight/set-status.sh end`
- `SubagentStart` → `clawlight/set-status.sh task_start`
- `SubagentStop` → `clawlight/set-status.sh task_end`
- `TaskCreated` → `clawlight/set-status.sh task_start`
- `TaskCompleted` → `clawlight/set-status.sh task_end`

(Set up via the `update-config` skill rather than hand-edited, to keep the
hooks JSON schema correct. Hooks are only loaded when a session starts, so
changes take effect on the *next* new session, never the one that made them.)

## Setup on another machine (e.g. the MacBook)

1. Copy `clawlight/set-status.sh` to that machine (or `git clone`/`pull` this
   repo there) and make sure `jq` and `curl` are installed.
2. Set `CLAWLIGHT_SERVER_URL` (xero's tailnet URL) and, if `hostname` reports
   something unhelpful on that machine (e.g. a DHCP-style name), a friendly
   `CLAWLIGHT_HOST_NAME` too:
   ```bash
   export CLAWLIGHT_SERVER_URL=https://xero.<your-tailnet-suffix>
   export CLAWLIGHT_HOST_NAME=mac
   ```
3. Wire the same nine hooks in that machine's global `~/.claude/settings.json`,
   pointing at the local copy of `set-status.sh`. Hook commands don't source
   your shell profile, so embed both env vars directly in each command
   instead of relying on step 2's exports, e.g.:
   ```
   CLAWLIGHT_SERVER_URL=https://xero.<your-tailnet-suffix> CLAWLIGHT_HOST_NAME=mac /path/to/set-status.sh active
   ```

Both accounts on the MacBook share the same hook config (since only one is
logged in at a time), so no extra setup is needed per account.

## Viewing it

Open on whatever device you want the light on:

- Same tailnet: `https://xero.<your-tailnet-suffix>/clawlight/`
- LAN only: `http://<xero-LAN-IP>:8126/`

Click **Float** to pop it into Picture-in-Picture so it stays on top of other
windows (desktop) or floats over other apps (iOS Safari).

## Known limitations

- One global aggregate light, not per-session - it does show *which* session
  is driving the current color (see above), but there's no way to jump
  straight to that terminal/window from the light itself.
- No auth beyond Tailscale/LAN reachability - matches the trust model already
  used by `projects-ui` and other services in this repo.
- If the server itself restarts, the light briefly reads as idle until each
  session's next hook event re-reports it.
