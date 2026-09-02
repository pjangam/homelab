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
- `set-status.sh` is called by Claude Code hooks on every prompt/stop/end
  event. It reads the session ID from the hook's stdin JSON and POSTs the new
  state to the server. Failures are swallowed (`|| true` equivalent) so a
  network hiccup never blocks an actual Claude Code turn.
- The light is an **aggregate** across every session that has reported in and
  hasn't gone stale (30 min): red if any session needs input, green if any is
  active, gray otherwise. This intentionally doesn't distinguish which
  account a session belongs to - on both machines only one account is logged
  in at a time, so concurrent sessions are never split across accounts on the
  same host.
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
- `SessionEnd` → `clawlight/set-status.sh end`

(Set up via the `update-config` skill rather than hand-edited, to keep the
hooks JSON schema correct.)

## Setup on another machine (e.g. the MacBook)

1. Copy `clawlight/set-status.sh` to that machine (or `git clone`/`pull` this
   repo there) and make sure `jq` and `curl` are installed.
2. Set `CLAWLIGHT_SERVER_URL` in your shell profile to xero's tailnet URL
   (`xero.$TAILNET_SUFFIX` - see `TAILNET_SUFFIX` in `.env` / `Readme.md`):
   ```bash
   export CLAWLIGHT_SERVER_URL=https://xero.<your-tailnet-suffix>
   ```
3. Wire the same four hooks in that machine's global `~/.claude/settings.json`,
   pointing at the local copy of `set-status.sh`.

Both accounts on the MacBook share the same hook config (since only one is
logged in at a time), so no extra setup is needed per account.

## Viewing it

Open on whatever device you want the light on:

- Same tailnet: `https://xero.<your-tailnet-suffix>/clawlight/`
- LAN only: `http://<xero-LAN-IP>:8126/`

Click **Float** to pop it into Picture-in-Picture so it stays on top of other
windows (desktop) or floats over other apps (iOS Safari).

## Known limitations

- One global aggregate light, not per-session - if you want to know *which*
  session needs input, open the page (session list is in the JSON API and
  shown as a subtitle) rather than relying on the light alone.
- No auth beyond Tailscale/LAN reachability - matches the trust model already
  used by `projects-ui` and other services in this repo.
- If the server itself restarts, the light briefly reads as idle until each
  session's next hook event re-reports it.
