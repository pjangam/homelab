# Photo requests from a session to the phone, through the Discord idea-bot
**Status:** Backlog
**Priority:** P3
**Cost:** ₹0
**Effort:** ~1-2 evenings (4-7h)

#### Open items
- [ ] **Claude:** build it, after the idea-bot's architecture review and healthcheck items in [`idea-bot.md`](idea-bot.md); settle the open design questions below first
- [ ] **Together:** a first real photo request on an Active hardware project, end to end

**Why:** a session diagnosing something physical needs photos, and today the user has to send them into an interactive session by hand. The door-lock diagnosis ([`door-latch-repair.md`](door-latch-repair.md)) rested entirely on photos, and many Open items are physical jobs away from the desk. "Photos makes real usecase" (user, 2026-11-27).
**State:** idea only, design agreed in conversation 2026-11-27. Extends the running [`projects/idea-bot/`](../projects/idea-bot/README.md) (Discord bot on xero, `systemd --user` unit `idea-bot`). Nothing built.

#### Feasibility
- **Yes, everything needed is plain Discord bot API** that `bot.py` (`discord.py`) already uses or has one call away:
  - Posting into a channel and opening a thread: the bot already creates threads under `#ideas`.
  - Reading attachments: `bot.py`'s `message_text()` already sees `msg.attachments`; `Attachment.save(path)` downloads one ([discord.py docs](https://discordpy.readthedocs.io/en/stable/api.html#discord.Attachment.save)).
  - Buttons for unsolicited photos: `discord.ui.View` / `discord.ui.Button` ([discord.py interactions](https://discordpy.readthedocs.io/en/stable/interactions/api.html#discord.ui.Button)).
- **The bot already has Message Content Intent on**, which is also what lets it see attachments on your messages.
- **Nothing to buy**, nothing new to host, no inbound port.

#### How it would work
| Step | Who | What |
|---|---|---|
| 1. The session asks | Claude in a normal session | runs a helper on xero, e.g. `projects/idea-bot/ask_phone.py --project <slug> "<what to photograph>"` |
| 2. Request posted | helper / bot | a thread in a new channel (e.g. `#requests`) named `<slug>: <request>`; thread id -> project slug + request id recorded in the bot's state (`~/.local/state/idea-bot/`) |
| 3. Phone buzzes | Pramod | Discord notification; take the photos and **reply in that thread**. No typing |
| 4. Bot saves them | `bot.py` | downloads the attachments to a **gitignored, out-of-repo** folder, e.g. `~/homelab-photos/<slug>/<date>-<n>.jpg`; reacts on the message to confirm |
| 5. Session carries on | helper `--wait` | run in the background (or under Monitor) until the reply lands, then prints the file paths; the session Reads the images |
| 6. Thread stays | - | tied to the project, so later photos posted there land in the same folder |

- **Photos are never committed.** Decided for the door photos; same here.
- **Claude does not download anything.** `bot.py` saves the files; the session only runs the helper and Reads local files. No new agent tools, permissions stay as they are.
- **Unsolicited photos** (posted in `#requests` without a request, or anywhere the bot does not expect them): the bot replies with **buttons** for its 3 best-guess projects plus **"new idea"**. One tap, no typing, and never a silent wrong guess. This is what solves the short-title ambiguity: `smart-switch` vs `smart-switch-in-wall` ([`smart-switch.md`](smart-switch.md), [`smart-switch-in-wall.md`](smart-switch-in-wall.md)).
  - Best guess from the photo's caption (if any) against tracker titles and slugs, weighted to Active projects; no Claude run needed for the guess.
  - "New idea" hands the photo to the existing `#ideas` flow.

#### Rejected
| Option | Why not |
|---|---|
| One channel per project | overkill: dozens of channels, most empty, and new projects would need a channel each |
| Typing the project title with the photo | full titles are a mouthful to type on a phone |
| Typing a short title / guessing from it | ambiguous once projects split (`smart-switch` vs `smart-switch-in-wall`); a wrong guess files photos silently in the wrong place |
| Sending photos into an interactive Claude session (today) | needs logging in and resuming the session, the friction the idea-bot exists to remove |

#### Open design questions
| Question | Options | Leaning |
|---|---|---|
| How does the helper talk to the bot? | **A:** helper calls Discord's REST API itself with the same token (read from `~/.config/idea-bot/env` by the helper process, never shown to Claude) and writes the request to a state file the bot reads; **B:** bot listens on a local socket / HTTP on `127.0.0.1` | A needs no listener in the bot and works while the bot restarts; B keeps Discord access in one process. Decide in the build; if A, keep requests in their own file, not `threads.json`, so two writers never clash |
| Log a line in the tracker file when photos arrive? | bot appends a Log line vs not | probably not: a commit per photo is noise, and the bot would need write access to `tracker/` outside a Claude run. The session that uses the photos logs what they showed |
| Retention of `~/homelab-photos` | keep forever / prune when the project is Done / size cap | undecided; phone photos are a few MB each, so not urgent. Not backed up unless Immich or a backup picks the folder up - decide whether it should be |
| The asking session has ended | - | photos are still saved under the slug; the next session on that project checks `~/homelab-photos/<slug>/` (worth a line in the project's Open items when a request is outstanding) |
| Permissions | - | unchanged: no new agent tools, the download is done by `bot.py`, not by Claude |

#### Traps to design around
- **Attachment URLs are signed and expire** (Discord added expiry in 2023-24): download at receipt in `on_message`, never store the URL for later.
- **Messages sent while the bot is down are lost** (README trap): a reply posted during a restart needs re-posting. The bot could scan the request threads' recent history on startup to catch up.
- **Archived threads:** Discord auto-archives inactive threads; a reply in one un-archives it, but a bot posting a new request into an old project thread must handle the archived state.
- **One run at a time** applies to the Claude runs, not to saving photos: photo handling must not wait behind a 20-minute idea-dump run.
- **Upload size limits** on a free Discord account apply to the phone's send; ordinary phone photos are well under it.
- **Never lie about state:** `--wait` needs a timeout and must say "no reply yet" rather than exit quietly with nothing.

#### Readymade alternatives
| Option | Verdict |
|---|---|
| Share to Immich from the phone, session searches Immich | photos would land, but there is no "a session is waiting for this" link and no per-project folder; and it mixes repair photos into the family library |
| Upload via a share sheet to an SMB share / Tailscale Taildrop to xero | works, no notification to the phone that a photo is wanted, and nothing tells the session it arrived |
| Telegram / WhatsApp bot | rejected for the idea-bot already ([`idea-bot.md`](idea-bot.md) Decisions) |
- **The Discord bot wins** because it already runs, already reaches the phone with a notification, and threads give the request -> reply pairing for free.

#### Parts
- **Nothing to buy:** software only, on the running idea-bot (no parts block on purpose).

**Cost detail:** ₹0. Runs on xero inside the existing `idea-bot` unit; no new service, no subscription. Uses no Claude allowance unless "new idea" is tapped.

**Effort detail:** ~4-7h over 1-2 evenings.
| Phase | Hours |
|---|---|
| Decide transport (A vs B) and the request state file | 0.5h |
| `ask_phone.py`: post thread, record request, `--wait` with timeout, print paths | 1.5-2h |
| `bot.py`: route replies in `#requests` threads, save attachments, react | 1-1.5h |
| Unsolicited photos: best-guess ranking + buttons (persistent view across restarts) | 1-2h |
| README, diagrams (`message_routing.puml` gains a branch), first real request | 1h |
- **Will overrun:** the buttons. A `discord.ui.View` that must keep working after a bot restart needs fixed `custom_id`s and re-registration on startup; that is where the time goes, not the download code.

#### Possible later extensions (not part of this idea)
From the same conversation, 2026-11-27. Each would be its own tracker file if picked up.
| Idea | Notes |
|---|---|
| **Project updates from the phone** | "door latch: filed it, works now" -> tick the Open item, add a Log line. Same project-matching problem as photos; the buttons pattern would apply |
| **Shopping-list capture** | add a part to the shopping list from the phone; overlaps [`shopping-list-display.md`](shopping-list-display.md) |
| **Fill an Amazon/Robu cart from a project's parts list** | the bot builds the cart, the user pays. Real ordering only maybe later with a prepaid wallet: "I would still consider it with wallet. but not right now" (user). No full auto-ordering: there is no consumer ordering API, automating checkout is against the shops' terms, and payment needs OTP/UPI anyway |
| Rejected for Discord: **project execution** | needs broad tools while reading untrusted input; the idea-bot's tight allowlist exists precisely to avoid this |
| Rejected for Discord: **clawlight** | real-time and local; a cloud chat round trip is the wrong path |
| Rejected for Discord: **health alerts** | ntfy stays the alarm; Discord is not the place a failure must reach |

#### Log
- 2026-11-27: idea recorded from conversation. Transport, retention and tracker-logging left open (above). Sequenced after the idea-bot's architecture review and healthcheck item.
