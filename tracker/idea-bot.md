# Discord idea bot: send ideas to idea-dump from the phone
**Status:** Active
**Priority:** P2
**Cost:** ₹0
**Effort:** ~1 evening (2-3h)

#### Open items
- [ ] **Pramod:** create the private `homelab` Discord server with an `#ideas` channel, and the bot app with Message Content Intent on (README steps 1-4)
- [ ] **Pramod:** write `~/.config/idea-bot/env` on xero with the token and the two IDs (README step 5; type the token yourself, not in a Claude session)
- [ ] **Together, once the env file exists:** install and enable the unit, post a first test idea, check the thread reply and the commit
- [ ] **Claude:** after the first real ideas, run the `architecture-review` agent on `projects/idea-bot`
- [ ] **Claude, after the first real run:** add `idea-bot` to the healthcheck's watched user units, and to the xero entry's Log line in `docs/hardware.md` as running (now: installed only)

**Why:** sending an idea today means logging in, starting Claude, resuming a session and only then typing it. An always-listening bot lets a one-liner or a link go straight to the `idea-dump` agent from the phone (user, 2026-11-27). This is the "capture from the phone" part that the OpenClaw review said to build separately ([`openclaw.md`](openclaw.md)).
**State:** built, not yet running: waiting on the Discord server, bot token and env file. Code and setup in [`projects/idea-bot/`](../projects/idea-bot/README.md).

#### Decisions
| Decision | Choice | Why |
|---|---|---|
| Channel | **Discord** | already used for software and coffee communities; free bot, no phone number; threads give each idea its own conversation |
| Rejected: Telegram | - | not used for anything else any more |
| Rejected: WhatsApp | - | needs Meta's business API and a second number, or unofficial libraries that risk a ban |
| Rejected: iMessage | - | needs an always-on Mac; the personal Mac is not, the work one is off-limits |
| Server | new private server `homelab`, channel `#ideas` | only the user is in it; room for `#alerts` later |
| Runner | `claude -p --agent idea-dump` on xero, Claude subscription login | same agent as in sessions; `--agent` makes the repo's tracker hook see `agent_type=idea-dump` (checked 2026-11-27) |
| Working tree | the shared `~/code/homelab` checkout, one run at a time, refuses if not on `main` | a separate clone would lose the gitignored `docs/hardware.md` and the memory folder the agent reads |
| Follow-ups | a reply in the thread resumes the same Claude session (`--resume`) | the agent can be told "it's the bedroom" and update the same file |
| Permissions | `dontAsk` + allowlist: tracker writes, git commit flow, web; no shell, no secrets | links are untrusted pages; see the README's permissions table |

#### Log
- 2026-11-27: built `projects/idea-bot` (bot, unit, README). Checked headless: `--agent idea-dump` passes the tracker hook; permission probe allowed tracker writes, `git add tracker/*` and commit, and refused `.env.mqtt`, `curl`, `rm`, writes to `projects/` and `git reset`. Also fixed `tools/repo-tools/tracker.py` missing its executable bit (agents had been falling back to `python3`), and the idea-dump agent's stale "xero is 8GB" line (32GB since 2026-10-08).
