# OpenClaw (self-hosted always-on AI agent) - considered, probably never
**Status:** Parked
**Priority:** P3
**Cost:** ₹0
**Effort:** ~1 evening (3-4h) for a read-only trial

#### Open items
- [ ] **Pramod:** decide whether it is ever worth reopening - only if you want something that messages you first (follow-up reminders, email/PR triage) and scheduled Claude + ntfy cannot do it

**Why:** looked at 2026-11-26 as a possible "always-on Claude" you chat with from the phone. The user's verdict at the end of that conversation: *"record this as an idea for later. based on this discussion this is never going to be needed"*. Parked because nearly everything it does is already covered here, not because something blocks it.
**State:** researched and decided against, 2026-11-26. Nothing installed. A trial sketch is kept below only so a reopening does not start from zero.

#### What it is
| | |
|---|---|
| **Project** | OpenClaw, open source (MIT), self-hosted; formerly Clawdbot / Moltbot. About a year old as of 2026-11 |
| **Who runs it** | a nonprofit foundation, since its creator joined OpenAI |
| **Shape** | an always-on gateway daemon you chat with through messaging apps; memory is files on disk |
| **Triggers** | heartbeat, cron, webhooks, Gmail hooks - so it can message you first |
| **Skills** | the ClawHub marketplace |
| **Links** | [docs.openclaw.ai](https://docs.openclaw.ai), [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw), [Docker install](https://docs.openclaw.ai/install/docker) |

#### What was concluded (2026-11-26)
- **Not "a long-running session with huge context".** Same model, same context window; sessions still compact or reset. Its memory is files, the same idea as the Claude Code memory folder and `CLAUDE.md` already in use.
- **Phone capture is already solved.** Termius plus Claude Code Remote Control does it; the only friction is starting a session. If that is ever worth fixing, do it separately, not with OpenClaw:
  - one long-lived tmux session with Remote Control on, or
  - an iOS Shortcut / tiny bot that posts to an inbox file on xero.
- **Already covered, and better:**

| Need | What does it today |
|---|---|
| Homelab ops | Claude Code sessions on xero, this repo |
| Voice | HA satellites; LLM small talk planned in [voice-conversation](voice-conversation.md) |
| Scheduled checks | cron / systemd timers + ntfy |
| Device control | Home Assistant |
| Phone access to sessions | Termius + Remote Control; [clawlight-iphone-console](clawlight-iphone-console.md) |

- **The only two things it adds:**
  1. **Messaging you first** - follow-up reminders, a judgment-based morning brief.
  2. **Watching email and personal GitHub PR comments with judgment**, all in one feed.
- **Cheaper route for those two:** a scheduled Claude task + the Gmail connector + ntfy gets about 70% of it with no new service on xero. Try that first if the itch appears.
- **Work repos and work email are out of scope.** The employer M1 Mac runs only clawlight; employer data must not go through a personal agent on xero.

#### Security - the rules any watcher must follow
- **Email and PR comments are untrusted input** (prompt injection). Any watcher is **notify-only**:
  - read-only Gmail / GitHub access; no send, no reply
  - no shell, no homelab access
  - its only output is a message to the user
- **Never combine** untrusted input + private data + an outbound channel in one agent.
- **No ClawHub skills.** Early-2026 reports of malicious skills and of exposed OpenClaw instances.
- **Blast radius on xero is high:** Vaultwarden, the backups, `BACKUP_PASSPHRASE` and the docker socket all live there.

#### Trial sketch (only if reopened; not a build plan)
- **Home:** `services/openclaw/` (off-the-shelf software), its own compose file, README with the folder.
- **Image:** `ghcr.io/openclaw/openclaw` (set `OPENCLAW_IMAGE`; the setup script otherwise builds `openclaw:local`).
- **Network:** Gateway + Control UI on port 18789, bound to **localhost** on xero; reached over the tailnet through a Caddy HTTPS block (single-file mount, so `docker restart caddy` after the edit).
- **Trap - bind:** the Docker setup defaults the gateway bind to `lan` (`OPENCLAW_GATEWAY_BIND`, `gateway.bind`). Override it to loopback.
- **State:** its own directory (`OPENCLAW_CONFIG_DIR` -> `/home/node/.openclaw`, workspace, auth secret dir). No repo mount, no docker socket, no shared `.env`.
- **Tools:** `agents.defaults.sandbox` mode `non-main`, `workspaceAccess: none`; deny `exec` in tool policy; then run `openclaw security audit`.
- **Trap - sandbox needs docker:** sandboxing is off by default and its default backend drives the `docker` CLI, which would need the docker socket the rule above forbids. With no socket, the `exec` deny and no workspace are the real fence; check what `non-main` does without a backend before relying on it.
- **Model:** the user's **Claude login** via the bundled claude-cli backend, not an API key. The user runs it (interactive):
  ```bash
  openclaw-cli models auth login --provider anthropic --method cli --set-default
  ```
- **Trap - heartbeat cost:** the heartbeat spends subscription usage around the clock. Decide whether to enable it at all.
- **Channel:** web UI first; maybe **Discord** later (user's preference), locked to the user's ID with `dmPolicy` / `allowFrom` or pairing.
- **Bookkeeping if built:** `projects/endpoints/endpoints.toml` entry, `docs/hardware.md` (new container on xero).
- **RAM:** xero has 32GB (Crucial, since 2026-10) but runs a lot; measure the gateway's idle RSS on day one.

#### Rejected
| Option | Why not |
|---|---|
| OpenClaw as the phone-capture tool | already done with Termius + Remote Control; a new service for start-up friction is overkill |
| OpenClaw for ops / voice / checks / devices | Claude Code, HA, cron + ntfy already do these better |
| ClawHub skills | malicious-skill reports, early 2026 |
| Any watcher that can reply, run shell or touch the homelab | untrusted input + private data + outbound channel |
| Work email / work repos | employer data stays off personal infrastructure |
| API-key model | user prefers the Claude subscription login |

**What would reopen it:** wanting something that messages you first (follow-up reminders, email/PR triage) **and** finding the scheduled-Claude-task + ntfy route is not enough.

#### Cost and effort detail
- **Cost ₹0:** runs on xero, model through the existing Claude subscription. The hidden cost is subscription usage if the heartbeat is on, and xero RAM.
- **Effort ~1 evening (3-4h)** for a read-only trial:
  - 1h: compose file, localhost bind, Caddy block
  - 1h: sandbox / tool policy, `security audit`, Claude login (user)
  - 1-2h: web UI trial, decide keep or delete - the overrun is the hardening, not the install

#### Log
- 2026-11-26: researched in conversation; concluded it adds only "messages you first" and judged email/PR triage; parked, probably never.
