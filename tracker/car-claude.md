# Hands-free Claude in the car (Siri -> HA Assist -> Claude)
**Status:** Active
**Priority:** P2
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** buy API credit (console -> Plans & Billing; auto-reload off makes it a hard cap)
- [ ] **Claude:** then re-run `setup_claude_pipeline.py` (`set -a; . ./.env.healthcheck; . ./.env.anthropic; set +a; projects/voice-assistant/setup_claude_pipeline.py`): home location for web search, the two test questions
- [ ] **Pramod:** build the Shortcut (README step 3)

**Why:** raised 2026-11-03: a fully hands-free voice conversation, mainly while driving. The Claude app's mic in a Claude Code session is dictation only (tap to send, replies are text), and iOS cannot read a reply aloud without a tap or gesture. Claude's own voice mode is hands-free but only in ordinary chats, and it knows nothing about the home.
**State:** HA side set up 2026-11-04 by `projects/voice-assistant/setup_claude_pipeline.py`: Anthropic integration (key in HA's `.storage`, copy in gitignored `.env.anthropic`), agent `conversation.claude_conversation` (claude-haiku-5-5, web search, car prompt), pipeline "Claude" (not preferred). Blocked: the API account has no credit, so every question returns "credit balance is too low".

#### How it works
"Hey Siri, ask home" runs an iPhone Shortcut, which works in CarPlay with no touch:
1. **Dictate Text** - Siri turns speech into text on the phone, so xero's Speech-to-Phrase (fixed home phrases only) is not involved.
2. **Home Assistant "Assist" action** (HA Companion app's Shortcuts action) sends the text to HA over Tailscale and returns the reply text.
3. **HA's Assist pipeline**: "Prefer handling commands locally" handles home commands itself (instant, free); anything else goes to Claude through HA's official **Anthropic** integration as the conversation agent. Claude sees only the entities exposed to Assist.
4. **Speak Text** - Siri reads the reply out through the car.
5. Optional: repeat (listen again) until "stop" or silence, so it feels like a conversation.

Everything is off-the-shelf: setup only, no code to maintain.

#### Build steps
1. Add the Anthropic integration in HA (Settings -> Devices & services) with the API key; pick a current Claude model. Instructions to the agent: replies are heard in a car, so one or two spoken sentences, no lists, no markdown.
2. Create a **second** Assist pipeline (e.g. "Claude") with that agent and prefer-local on. **Leave the existing "Home Assistant" pipeline and both satellites unchanged** (they use Speech-to-Phrase, which cannot take free speech; see "Local voice control (HA Assist)").
3. Build the Shortcut on the iPhone: Dictate Text -> Assist (pipeline "Claude") -> Speak Text; name it "Ask home". Test on the phone, then in the car.
4. Optional loop, and check whether the Assist action keeps a conversation id so Claude remembers the previous question within one drive.

#### Open questions
- Does the Companion app's Assist action let you pick the pipeline, and pass a conversation id? If not, make the Claude pipeline the preferred one, or call HA's `/api/conversation/process` with "Get Contents of URL" instead (needs a long-lived token stored in the Shortcut).
- Cost: pay per use on the API key; short spoken questions are cheap. Set a monthly spend limit on the Anthropic console.
- Not in scope: Claude Code tasks (repo edits, scripts) by voice - they need reading and approval, not for driving.

**Done when:** "Hey Siri, ask home, is the bedroom fan on?" and a general question both get a spoken answer in the car with no touch; `projects/voice-assistant/README.md` has a short section on the Claude pipeline and the Shortcut.

#### Log
- 2026-11-03: recorded. Considered and set aside: a Claude Code hook speaking replies on a satellite (home only, not the car); iOS Speak Screen (needs a gesture).
- 2026-11-03: wrote `setup_claude_pipeline.py` against HA 2026.10.4's Anthropic integration (config flow + conversation subentry reconfigure over the REST API, pipeline over websocket): model `claude-haiku-5-5` for speed, web search on (2 uses, home location), max 400 tokens, car prompt. The key is entered once and kept only in HA's `.storage`. Not run: no API key on xero yet. README section added. No new port or device, so endpoints.toml and hardware.md are unchanged.
- 2026-11-04: ran the script: integration, agent and pipeline created. Test questions failed with "credit balance is too low" (account has no credit; the key itself was accepted). Fixed two script bugs: the home-location option is named `user_location` (was silently dropped), and the test retries while HA reloads the integration ("invalid agent ID" for a few seconds).
