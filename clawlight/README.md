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
  hiccup never blocks an actual Claude Code turn. It also honours a
  per-session ignore marker - see "Hiding a single session" below.
- Each session tracks three things: a **foreground** state (`active`/`waiting`,
  from `UserPromptSubmit`/`Stop`/`Notification`/`PermissionRequest`), a
  **needs-input** flag (set by `Notification`/`PermissionRequest` only, cleared
  by `active`, and the sole trigger for a push - see "Push notifications"), and
  a **background** task counter (from `SubagentStart`/`SubagentStop`/
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
systemctl --user enable --now clawlight-focus-agent.service
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
- `Notification` → `clawlight/set-status.sh input_needed`
- `PermissionRequest` → `clawlight/set-status.sh input_needed`
- `PostToolUse` → `clawlight/set-status.sh active`
- `SessionEnd` → `clawlight/set-status.sh end`
- `SubagentStart` → `clawlight/set-status.sh task_start`
- `SubagentStop` → `clawlight/set-status.sh task_end`
- `TaskCreated` → `clawlight/set-status.sh task_start`
- `TaskCompleted` → `clawlight/set-status.sh task_end`

`input_needed` is `waiting` plus "and it's a human it's waiting for" - same red
light, but the only state that can send a push.

`PostToolUse` exists specifically to close a gap: approving a permission
prompt (which set `input_needed` via `PermissionRequest`) has no dedicated
"resolved" hook, so nothing flipped the state back once Claude resumed - the
next tool call succeeding is the natural "I'm working again" signal instead.

(Set up via the `update-config` skill rather than hand-edited, to keep the
hooks JSON schema correct. Hooks are only loaded when a session starts, so
changes take effect on the *next* new session, never the one that made them -
`PostToolUse` is the one exception, since its own next firing is itself the
proof it works.)

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
3. Wire the same ten hooks in that machine's global `~/.claude/settings.json`,
   pointing at the local copy of `set-status.sh`. Hook commands don't source
   your shell profile, so embed both env vars directly in each command
   instead of relying on step 2's exports, e.g.:
   ```
   CLAWLIGHT_SERVER_URL=https://xero.<your-tailnet-suffix> CLAWLIGHT_HOST_NAME=mac /path/to/set-status.sh active
   ```
   The state argument for each event must match the list above - in
   particular `Notification`/`PermissionRequest` → `input_needed`, not
   `waiting`. That one is worth checking after any change here, because
   getting it wrong fails silently: the light still works, the machine just
   never sends a push (done on the MacBook 2026-09-10).

4. Install the focus agent, so the light can jump you to a console on this
   machine (see "Jumping to the console that needs you"). Run this **on the
   Mac** - it resolves the two values that can't be known from xero (where
   `set-status.sh` was copied to, and the terminal's AppleScript name), then
   writes and loads the launchd plist:
   ```bash
   scp pramod@xero.<tailnet>:/path/to/homelab/clawlight/setup-mac-focus-agent.sh /tmp/
   bash /tmp/setup-mac-focus-agent.sh --dry-run   # show what it would do
   bash /tmp/setup-mac-focus-agent.sh
   ```
   It reads `CLAWLIGHT_SERVER_URL`/`CLAWLIGHT_HOST_NAME` back out of the hook
   commands rather than taking them again, so the agent can't end up
   disagreeing with what the hooks report - the failure mode where clicks
   route to a host nobody is listening for. `clawlight/launchd/` holds the
   plist template if you'd rather do it by hand.

Both accounts on the MacBook share the same hook config (since only one is
logged in at a time), so no extra setup is needed per account.

## Physical LED (wol-sender Pi)

An RGB LED on the Pi's GPIO shows the same aggregate state as the web page,
without needing a browser tab open. It works here only because that Pi happens
to sit next to the desk - anywhere else this would need the ESP32 version
parked in `PROJECTS.md`.

```sh
scripts/deploy_clawlight_led_pi.sh --dry-run   # --no-gpio, foreground, no LED needed
scripts/deploy_clawlight_led_pi.sh             # install + enable clawlight-led.service
```

**State reaches the Pi over MQTT, not the SSE endpoint the web page uses.** A
hardware light has the opposite requirement to a web page: it has to be right
the moment it powers on, and clawlight only emits on hook events - so a
subscriber starting cold during a quiet stretch would sit wrong for as long as
the quiet lasted. `server.py` publishes the aggregate to `clawlight/state`
**retained**, so the broker replays it to the Pi the instant it connects.
Verified: the LED is correct within a second of process start.

Colours: green active, red waiting, dim white idle (dim rather than off, so
"nothing running" is distinguishable from "unplugged"), **amber pulse when the
state is unknown**.

That last one is the design's whole point. `server.py` sets an MQTT last-will
on `clawlight/availability`, so if it dies the broker announces `offline` on
its behalf and the light stops claiming to know anything. A light that keeps
showing a stale colour is worse than no light - see the 2026-09-07 MirAIe
outage, where something that looked healthy while reporting nothing went
unnoticed for 29 hours. Both paths are tested: killing `clawlight-server`
turns the LED amber within a second, and restarting it restores the real
colour.

Wiring and pin choice are in `gpio_pinout.md`. Set `COMMON_ANODE = True` in
`scripts/clawlight-led.py` if the LED reads inverted (bright when idle).

## Jumping to the console that needs you

Clicking a session on the page switches that machine's terminal to the tmux
pane it's running in - the light stops being only an indicator and becomes the
way you get there. (Borrowed from `clawlight-cli`'s jump-to-terminal; see
`PROJECTS.md` for why the rest of that tool still isn't a fit.)

**Sessions are addressed by tmux pane.** `set-status.sh` reports `$TMUX`'s
socket and `$TMUX_PANE` along with the state. A session started outside tmux
has neither, and the page shows it as **unreachable** rather than offering a
jump that would quietly do nothing.

**The server never runs tmux itself.** Each host runs `focus-agent.sh`, which
holds an SSE connection to `/clawlight/api/focus-stream?host=<its host>` and
runs the tmux commands locally. This is the whole reason the feature works on
both machines: xero's server can reach xero's tmux but never the MacBook's, so
executing server-side would have meant two implementations of the same thing -
one of them the one that actually matters, since most sessions are on the Mac.
Routing instead means one code path, tested once.

A few consequences worth knowing:

- **A click at a host whose agent isn't running is refused, not accepted.**
  The server counts live `/api/focus-stream` subscribers per host, so the page
  can say "no focus agent running on mac" instead of flashing success at a
  jump that could never happen. A control that lies about having worked is
  worse than one that says it didn't.
- **An accepted request still expires after 15s** if the agent disconnects
  before collecting it, and is dropped outright when that host's last agent
  goes away. Either way you never get yanked somewhere you asked for minutes
  ago - the "never act on stale state" rule again.
- **Only the newest request per host is kept.** Clicking twice takes you to
  the second one, not through the first.
- **`CLAWLIGHT_HOST_NAME` must match what `set-status.sh` reports** on that
  machine. If they disagree, requests route to a host nobody is listening for
  and clicks silently do nothing.
- **On macOS, set `CLAWLIGHT_FOCUS_APP`** to the terminal app you run tmux in.
  Switching the tmux window is useless if the terminal is still behind the
  browser. For iTerm the agent goes further and selects the *tab* that owns
  the tmux client's tty - activating the app alone leaves it on whatever tab
  you were last on, which looks like the jump went to the wrong place.
- **A session reached over ssh needs both machines, and gets them.** Clicking
  a xero session that you are viewing through an ssh tab on the Mac is two
  jobs: xero switches its tmux, and the Mac surfaces the tab holding that ssh
  session. Neither agent can see into the other's world, and the tmux client's
  tty on xero is a pty there, not a local tab - so the link between them is
  the ssh connection's **source port**, which exactly one process on exactly
  one machine owns.

  After handling the tmux half, the agent reads `SSH_CONNECTION` out of the
  tmux client's environment and announces it. The server broadcasts that to
  every other host rather than addressing it, because the announcing host
  knows the connection but not which clawlight host label sits at the far end;
  each agent runs one `lsof` for that port and only the real owner finds
  anything. That agent then resolves the owning process to a tty - stepping
  through a local tmux pane first if the ssh is itself running inside tmux -
  and selects the terminal tab for it.

  Needs `lsof` on the far machine, and only announces from Linux (it reads
  `/proc/<pid>/environ`); a macOS client is local and already handled
  directly.
- **You can't click the PiP window** - it's a video frame, not a page. Jumping
  happens from the actual page, which is also where an ntfy notification's
  click-through lands you, so "phone buzzes → tap → jump" is one path.

Tested by `scripts/test_clawlight_focus.py` (routing, staleness, and rejection
of tmux coordinates that arrive malformed over the wire) and
`scripts/test_clawlight_focus_e2e.sh`, which runs a throwaway tmux server with
a real attached client against the live server and checks the client actually
moves.

## Push notifications

The server pushes to a self-hosted ntfy topic ("Claude needs you") when a
session is stuck on you. Two rules keep it a signal rather than a buzz per
message:

- **Only `input_needed` counts, never `Stop`.** `Stop` fires at the end of
  every message, so notifying on it means a notification per message. A push
  needs the session to be red *and* to have said it's waiting on a human -
  i.e. a permission prompt, or Claude Code's own "waiting for your input"
  notification after you leave a prompt unanswered.
- **It waits `NOTIFY_DELAY_SECONDS` (20s), then re-checks.** The light
  flickers red more often than you'd expect - a background shell finishing, a
  permission you answer as it appears - and anything that resolves inside the
  delay never sends. `NOTIFY_COOLDOWN_SECONDS` (60s) then keeps a run of
  prompts from becoming a run of notifications: by the second one you're
  already looking at the screen.

Notifications are edge-triggered per session, so a second console asking while
the first is still unanswered gets its own push (subject to the cooldown), and
a session sitting at a prompt never re-fires. A session whose light is green
because background work is still running doesn't push until that work ends and
the light actually goes red.

No `NTFY_CLAWLIGHT_TOKEN` in the environment = pushes silently disabled, which
is the right behaviour anywhere but xero.

Tested by `scripts/test_clawlight_notify.py`, and end to end against the live
server and topic by `scripts/verify_clawlight_notify.sh` (which does buzz the
phone once).

## Hiding a single session

To keep one session off the light without dropping the hooks for every other
session on that machine, create a marker file named after its session id:

```sh
mkdir -p ~/.claude/clawlight-ignore
touch ~/.claude/clawlight-ignore/<session_id>
```

Delete the marker to unhide it. `CLAWLIGHT_IGNORE_DIR` overrides the location.

An ignored session reports `end` instead of its real state rather than just
going quiet. Going quiet would leave whatever it last reported sitting on the
light until the server's 30-minute staleness prune, so hiding a session that
was `waiting` would keep the light red for half an hour; reporting `end`
removes it on its very next hook event.

The marker is keyed by session id, so it only ever applies to one session and
is dead weight once that session is gone - `~/.claude/clawlight-ignore` is
worth emptying occasionally. `scripts/test_clawlight_ignore.sh` exercises this
against the running server using a throwaway session id.

## Viewing it

Open on whatever device you want the light on:

- Same tailnet: `https://xero.<your-tailnet-suffix>/clawlight/`
- LAN only: `http://<xero-LAN-IP>:8126/`

Click **Float** to pop it into Picture-in-Picture so it stays on top of other
windows (desktop) or floats over other apps (iOS Safari).

## Known limitations

- One global aggregate light, not per-session - though it does show *which*
  session is driving the current color, and clicking it jumps you there (see
  "Jumping to the console that needs you").
- A session started outside tmux can't be jumped to. It still shows on the
  light, marked unreachable.
- No auth beyond Tailscale/LAN reachability - matches the trust model already
  used by `projects-ui` and other services in this repo.
- If the server itself restarts, the light briefly reads as idle until each
  session's next hook event re-reports it.
