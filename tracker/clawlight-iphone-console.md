# Clawlight jump-to-console from the iPhone (Termius -> ssh -> tmux attach)
**Status:** Active
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** in Termius, save the xero host with `~/code/homelab/clawlight/phone-attach.sh` as its startup command
- [ ] **Pramod:** tap a xero session on the clawlight page, connect by hand, then try the open links; report what fails

**Why:** clawlight's click-to-jump (see ✅ Done) only moves a terminal on a desk machine. From the phone, the red light says a session needs you, but you still have to open Termius, pick the right host, and find the right tmux session by hand. Nothing runs Claude on the iPhone itself. Every session is on xero or the MacBook inside tmux, so tapping the session on the page should open Termius, ssh to that host, and attach at that pane.
**State:** built on xero 2026-09-17, not yet tried from the phone. `clawlight/phone-attach.sh`, `/api/phone-jump` + `/api/phone-claim` in `server.py`, and an iOS-only tap path on the page. The unit and end-to-end tests pass (`scripts/clawlight/test_clawlight_phone_jump*`), and the server is restarted with it. The README's "Jumping to a console from the iPhone" section has the design and setup. What is left is below.

#### Left to do
- **Phone setup:** saved Termius hosts for xero and the Mac, with `phone-attach.sh` as the startup command. Then tap a session on the page and connect within a minute.
- **The open link is untested.** `CLAWLIGHT_PHONE_OPEN_URLS` in `.env.clawlight` is unset, so the page currently says "open <host> in Termius". Try an `ssh://` link (does it use the saved host's startup command?) and the Shortcuts "Connect to a host" action.
- **The Mac needs a `git pull`** in its clone for the script, and Remote Login on.

#### Design notes (as first written)
- **The server already knows where to go.** `set-status.sh` reports the host, `$TMUX`'s socket and `$TMUX_PANE` for every session, and sessions outside tmux are already marked unreachable.
- **So the phone needs no focus agent.** It is the one client that cannot run `focus-agent.sh`. Its version of a jump is just a link the page opens, not a routed request, and it takes a different path from the desk click. The page has to pick between the two, e.g. by detecting iOS or a "jump on this device" toggle, because the phone should not also move the Mac's terminal.

#### Things to settle (most likely to kill it first)
- **Can a Termius link run a command, or only open a host? Checked 2026-09-17: no documented way.** The iOS changelog mentions "Deep links handling" once (4.6.5, 2020), with no syntax. Neither the changelog nor the connection docs show a link that carries a command. What Termius does have is a fixed **startup command per saved host**, which is how people already run Claude from the phone (e.g. `tmux attach -t cc || tmux new -s cc`). It can't vary per tap. So the design is snippet-plus-lookup:
  1. One saved Termius host each for xero and the Mac, whose startup command runs a small script (e.g. `clawlight-attach`).
  2. A tap on the page records "phone wants pane X on host Y" on the server, then opens `ssh://` to that host.
  3. The script reads the newest request and runs `tmux -S <socket> new-session -t <session>`, then selects the pane. With no recent request, it attaches normally. Requests should expire like desk jumps do (15s), so a later plain connect doesn't land on an old pane.
- **Unchecked, could skip the lookup: Termius's Shortcuts action.** Shortcuts has a Termius "Connect to a host" action. The docs don't say whether it takes a command. If it does, the page could run a Shortcut (`shortcuts://run-shortcut?name=...&input=...`) that passes the pane directly. This can only be checked on the phone, by opening that action in Shortcuts.
- **Alternative app: Blink Shell** has `blinkshell://run?key=<URLKey>&cmd=<url-encoded command>`, which would make the jump a pure link. Not chosen: the scheme is poorly documented, Blink is a paid subscription, it means leaving Termius, and it's unclear whether the scheme still works after a 2025 security report on Blink's `ssh://` link handling (dgl.cx, "Blink and you'll miss it").
- **Attaching resizes the desk terminal.** With tmux's default `window-size latest`, the phone becomes the latest client and shrinks the window for everyone else attached. Selecting a window also changes it for every client on that session, so jumping on the phone would move the Mac's view too. A grouped session (`tmux new-session -t <target>`) gets its own current window and avoids the second problem. It is probably the right attach command anyway.
- **Use the reported socket.** The target command is `tmux -S <socket> ...`, not a bare `tmux attach`, or a session on a non-default socket is silently missed.
- **A non-interactive ssh command gets a thin PATH on the Mac.** Homebrew's tmux in `/opt/homebrew/bin` may not be found. It's the same trap as `lsof` under launchd (see the Done entry), so check it the way the ssh session sees it, not from an interactive shell.
- **Mac reachability from the phone:** needs Remote Login on and the Mac awake on the tailnet. xero is always reachable. A Mac that's asleep should show the same honest "can't jump" as a missing focus agent, not a Termius connection that hangs.

#### Log
- 2026-09-15: noted.
- 2026-09-17: checked Termius deep links (no documented way to carry a command); built on xero - `phone-attach.sh`, the phone API endpoints and the iOS tap path, tests passing, server restarted.
