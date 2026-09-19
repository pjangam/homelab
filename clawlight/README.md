# Clawlight (software-only)

A color-coded status light for Claude Code sessions - green while Claude is
working, red when it needs your input, amber when a session's turn ended but
its own background shells are still running, gray when nothing's running. This is a
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
- **Background shells** (Bash `run_in_background`, Monitor) fire no hook at
  all when they start or finish, so the counter above can't see them. Instead
  `set-status.sh` checks the process table when `Stop` fires: every shell
  Claude Code runs a command in is a direct child of the `claude` process
  sourcing a `~/.claude/shell-snapshots/` file, and no foreground command can
  still be running at `Stop`, so any such child left is a background one. Then
  it reports `shells` instead of `waiting` - **amber**, never a push. Claude is
  re-invoked when the shell finishes, and that turn's own `Stop` re-checks.
  Two edges: a turn you interrupt (Esc) with a shell still running shows amber
  though it is waiting on you, and between a shell finishing and Claude's
  reply it can read amber for a few seconds. The Pi LED shows `shells` as
  green (amber there already means idle/unknown).
- The light is an **aggregate** across every session that has reported in and
  hasn't gone stale (30 min): red if any session needs input, green if any is
  active, amber if any is only waiting on its own shells, gray otherwise. This intentionally doesn't distinguish which
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

(Written by `setup-clawlight-hooks.sh` - see "Setup on another machine", it
works here too and defaults to the local server - rather than hand-edited, so
the JSON schema stays correct and no event ends up sending the wrong state.
Hooks are read when a session starts, so changes generally take effect on the
*next* new session rather than the one that made them.)

## Setup on another machine (e.g. the MacBook)

1. `git clone` this repo on that machine and make sure `jq` and `curl` are
   installed. A clone, not copies: `git pull` is then the whole deploy, where
   scp'd copies made "committed on xero" and "running on the Mac" two
   different things (three debugging rounds went on stale copies, 2026-09-09).
2. Wire the ten hooks into that machine's global `~/.claude/settings.json`,
   from the clone, with the name you want this machine to show up as:
   ```bash
   bash ~/code/homelab/clawlight/setup-clawlight-hooks.sh --host mbp19 --dry-run
   bash ~/code/homelab/clawlight/setup-clawlight-hooks.sh --host mbp19 \
        --server https://xero.<your-tailnet-suffix>
   ```
   It writes all ten with the right state per event, embedding
   `CLAWLIGHT_SERVER_URL` and `CLAWLIGHT_HOST_NAME` in each command - hook
   commands don't source your shell profile, so exporting them in a profile is
   not enough. It backs `settings.json` up, leaves any non-clawlight hooks
   alone, and is re-runnable: it strips the old set-status.sh hooks before
   writing, so a second run re-points paths rather than duplicating hooks.
   `--server` defaults to whatever the existing hooks already use, so a re-run
   to rename the host needs only `--host`.

   **It checks the server is reachable before writing, and afterwards proves
   the report actually arrived** rather than saying "done". Both matter
   because every failure on this path is silent by design - `set-status.sh`
   swallows errors so a network hiccup can't break a Claude Code turn, so a
   wrong URL looks exactly like nothing happening. The same goes for the state
   per event: `Notification`/`PermissionRequest` → `input_needed`, not
   `waiting`. Getting that one wrong leaves the light working perfectly while
   the machine never sends a push, ever (hand-wired wrong on the MacBook,
   found 2026-09-10 - which is why this is a script now and not a list to copy
   by hand).

3. Pick a host label that says which machine it is. The light shows
   `host/label` per session and the PiP bar renders it as small rotated text,
   so short and distinct beats descriptive: `xero`, `mac` (the M2), `mbp19`
   (the 2019 Intel 16", onboarded 2026-09-19). `--host` defaults to
   `hostname`, which on a Mac is a DHCP-style
   `Pramods-MacBook-Pro.local` - worth overriding.

4. Install the focus agent, so the light can jump you to a console on this
   machine (see "Jumping to the console that needs you"). Run this **on the
   Mac**, from the clone, and **after step 2** - it reads the hooks step 2
   wrote rather than taking the server and host again, and refuses to run if
   they aren't there. It re-points every clawlight hook at the clone's
   `set-status.sh` (backing up `settings.json` first, and warning about any
   event whose hook is missing or sends the wrong state), detects the
   terminal's AppleScript name, then writes and loads the launchd plist for the
   clone's `focus-agent.sh`:
   ```bash
   bash ~/code/homelab/clawlight/setup-mac-focus-agent.sh --dry-run   # show what it would do
   bash ~/code/homelab/clawlight/setup-mac-focus-agent.sh
   ```
   Updating afterwards is `git pull`. `set-status.sh` changes apply on the
   next hook event; `focus-agent.sh` is long-running, so also
   `launchctl kickstart -k gui/$(id -u)/dev.clawlight.focus-agent`. Re-run
   the setup script only if `clawlight/` moves within the repo, since the
   hooks and plist hold its path.
   It reads `CLAWLIGHT_SERVER_URL`/`CLAWLIGHT_HOST_NAME` back out of the hook
   commands rather than taking them again, so the agent can't end up
   disagreeing with what the hooks report - the failure mode where clicks
   route to a host nobody is listening for. `clawlight/launchd/` holds the
   plist template if you'd rather do it by hand.

Both accounts on the MacBook share the same hook config (since only one is
logged in at a time), so no extra setup is needed per account.

## Physical LED (wol-sender Pi)

A red/green bi-colour LED on the Pi's GPIO shows the same aggregate state as the web page,
without needing a browser tab open. It works here only because that Pi happens
to sit next to the desk - anywhere else this would need the ESP32 version
parked in `PROJECTS.md`.

```sh
scripts/clawlight/deploy_clawlight_led_pi.sh --dry-run   # --no-gpio, foreground, no LED needed
scripts/clawlight/deploy_clawlight_led_pi.sh             # install + enable clawlight-led.service
```

**State reaches the Pi over MQTT, not the SSE endpoint the web page uses.** A
hardware light has the opposite requirement to a web page: it has to be right
the moment it powers on, and clawlight only emits on hook events - so a
subscriber starting cold during a quiet stretch would sit wrong for as long as
the quiet lasted. `server.py` publishes the aggregate to `clawlight/state`
**retained**, so the broker replays it to the Pi the instant it connects.
Verified: the LED is correct within a second of process start.

Colours: green active (and `shells` - see "How it works"), red waiting, dim steady amber idle (dim rather than off,
so "nothing running" is distinguishable from "unplugged"), **amber pulse when
the state is unknown**. The LED has no blue die, so amber is red and green mixed;
the idle shade is the pulse's own amber held steady at low brightness, and only
the pulse ever moves.

That last one is the design's whole point. `server.py` sets an MQTT last-will
on `clawlight/availability`, so if it dies the broker announces `offline` on
its behalf and the light stops claiming to know anything. A light that keeps
showing a stale colour is worse than no light - see the 2026-09-07 MirAIe
outage, where something that looked healthy while reporting nothing went
unnoticed for 29 hours. Both paths are tested: killing `clawlight-server`
turns the LED amber within a second, and restarting it restores the real
colour.

Wiring diagram: `clawlight/led_wiring.html` (published at
https://claude.ai/artifact/UDgsMP8uYK5FkHFydLMwP9). Pin choice is in
`docs/gpio_pinout.md`. Set `COMMON_ANODE = True` in
`scripts/clawlight/clawlight-led.py` if the LED reads inverted (bright when idle).
`scripts/clawlight/test_clawlight_led.py` checks the pin output on gpiozero mock
pins, no Pi or LED needed.

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

Tested by `scripts/clawlight/test_clawlight_focus.py` (routing, staleness, and rejection
of tmux coordinates that arrive malformed over the wire) and
`scripts/clawlight/test_clawlight_focus_e2e.sh`, which runs a throwaway tmux server with
a real attached client against the live server and checks the client actually
moves.

## Jumping to a console from the iPhone

On an iPhone or iPad, tapping a session opens it in Termius instead of moving a
desk terminal. The phone can't run a focus agent, and a desk-style jump from it
would move the Mac's terminal while you're looking at the phone.

**The target goes through the server, because Termius links can't carry a
command** (checked 2026-09-17: a link can open a host, nothing more). So:

1. The tap posts `/clawlight/api/phone-jump`, which records "the phone wants
   pane X" for that session's host.
2. The page opens that host's link from `CLAWLIGHT_PHONE_OPEN_URLS`, if one is
   set. Otherwise it tells you to open the host in Termius yourself.
3. The saved Termius host's startup command, `phone-attach.sh`, claims the
   request (`/clawlight/api/phone-claim`) and attaches to that pane.

**Setup, once per host** (xero and the Mac):

- In Termius, save a host for the machine and set its startup command to the
  script's path in that machine's checkout, e.g.
  `~/code/homelab/clawlight/phone-attach.sh`. It needs
  `CLAWLIGHT_SERVER_URL` and `CLAWLIGHT_HOST_NAME` from your shell profile, the
  same as `set-status.sh`. The Mac also needs Remote Login on.
- Optional, on xero: in `.env.clawlight` (gitignored), set
  `CLAWLIGHT_PHONE_OPEN_URLS=xero=<link>,mac=<link>` and restart
  `clawlight-server`. Whether an `ssh://` link opens the *saved* host (with its
  startup command) or a bare connection is untested. A Shortcut wrapping
  Termius's "Connect to a host" action, opened with
  `shortcuts://run-shortcut?name=<name>`, is the other candidate.

What to expect:

- **Only a request up to 60s old is used**, and only once. A plain Termius
  connect later says "no jump requested" and leaves you at the shell.
- **The phone gets its own grouped session** (`phone-<pid>`). It shares the
  windows, so switching to the tapped window doesn't switch the desk terminal.
  It is removed when the phone detaches.
- **Two things still change on the desk.** The tapped pane becomes the active
  pane of its window for every client. With `window-size latest`, the window
  shrinks to the phone's size until the desk terminal is used again.
- **The page can't confirm the attach.** "Opening Termius" means only that the
  request was recorded.

Tested by `scripts/clawlight/test_clawlight_phone_jump.py` (routing, claim-once
and expiry) and `scripts/clawlight/test_clawlight_phone_jump_e2e.sh`, which runs
`phone-attach.sh` in a pty against the live server and a throwaway tmux server.

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

Tested by `scripts/clawlight/test_clawlight_notify.py`, and end to end against the live
server and topic by `scripts/clawlight/verify_clawlight_notify.sh` (which does buzz the
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
worth emptying occasionally. `scripts/clawlight/test_clawlight_ignore.sh` exercises this
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
- **Listed doesn't mean alive.** `SessionEnd` only fires on a clean exit, so a
  session whose terminal is closed or whose pane is killed (`tmux
  kill-session`, SIGHUP) never reports `end` and stays listed until the 30
  minute staleness prune. It shows in whatever state it last reported -
  usually `waiting` - so the light can sit red for a session that no longer
  exists. Observed 2026-09-10 while testing on the Mac.
