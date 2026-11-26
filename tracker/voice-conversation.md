# Small talk with the voice satellites, in English and Marathi (LLM-answered)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹0-500 (₹500 API credit shared with car-claude; then ~₹25-150/month)
**Effort:** ~5 evenings (14-18h)

#### Open items
- [ ] **Pramod:** buy Anthropic API credit - the same item as [car-claude](car-claude.md)'s first one, one purchase covers both (~₹500, auto-reload off)
- [ ] **Claude, once credit exists:** re-run the 3 Marathi text questions through `/api/conversation/process` against `conversation.claude_conversation`, time each, and log answers + seconds here
- [ ] **Claude:** build phase 0 (fixed sentences for "how are you" / sunrise / rain chance, English), no LLM needed
- [ ] **Claude:** test Marathi replies with Piper's `mr_IN` voice and HA's Google Translate TTS (both free); write the result here
- [ ] **Together, after the timings:** decide routing - a "conversation" wake word (needs a `wake-proxy` change) or LLM as fallback for unmatched speech
- [ ] **Claude, optional:** one trial of Gemini's free tier as a second agent in the same pipeline dropdown, same 3 questions, for comparison

**Why:** raised 2026-11-26: the user wants short conversations with the HA voice satellites - "how are you?", "when is sunrise today?", "what are the chances it rains today?" - and wants it to understand Marathi as well as English. Asked whether an LLM can run on xero; the answer led to a cloud model.
**State:** researched 2026-11-26. **Decision direction: Claude Haiku 5.5 via the Anthropic API** (user: "so best option is send to claude haiku"), pending API credit. The brain is already wired in HA (see below); the missing pieces are STT for free speech, routing, and Marathi TTS.

#### Already true
- **HA agent exists:** `projects/voice-assistant/setup_claude_pipeline.py` (for [car-claude](car-claude.md)) created the Anthropic integration, agent `conversation.claude_conversation` (claude-haiku-5-5, Assist API on so it sees exposed entities incl. sun/weather, web search on, max 2 uses), and a pipeline "Claude" that is **not** preferred. Its prompt is the car prompt ("usually while they are driving") - home use wants a second agent/subentry with a home prompt ("reply in the language you were asked in").
- **Tested 2026-11-26:** "कसा आहेस?", "आज सूर्योदय किती वाजता आहे?", "आज पाऊस पडण्याची शक्यता किती आहे?" via `/api/conversation/process` - all three failed with "credit balance is too low". Latency and Marathi quality not yet measured.
- **Replies already play on each room's speaker** (voice-reply bridge, since 2026-11-18), so the reply path needs no new hardware.
- **Paid rule:** on 2026-11-04 the user set "no paid options" for voice (STT). car-claude already pays per use; for this the user now leans to Haiku at ~₹25/month. Gemini's free tier is the one option that still fits the old rule.

#### Feasibility
**Yes - a known build.** HA's conversation-agent integrations (Anthropic, OpenAI, Google Generative AI, Ollama) plug an LLM into an Assist pipeline, with the Assist API letting it read and control exposed entities ([Anthropic integration](https://www.home-assistant.io/integrations/anthropic/), [Google Generative AI](https://www.home-assistant.io/integrations/google_generative_ai_conversation/), [OpenAI](https://www.home-assistant.io/integrations/openai_conversation/)). The brain is the easy part. **The hard part here is the ears:** the satellites use Speech-to-Phrase, which only hears trained sentences, so free-form questions never reach an LLM today.

#### Options compared
Per-question cost assumes **~4,000 tokens in** (HA sends the exposed entities + tool definitions) **+ ~100 out**, ~20 questions/day (600/month), ₹85/$ (estimate). "Latency" is the brain only, after STT (Speech-to-Phrase 2.2-2.5s measured 2026-11-15) and before TTS. Every latency below is an **estimate, not measured**.

| # | Option | ₹/month | Latency / question | Marathi | Effort | Notes |
|---|---|---|---|---|---|---|
| 1 | **Local LLM on xero** (Ollama/llama.cpp, Qwen2.5 1.5B/3B, Llama 3.2 3B, Gemma 3 1B/4B, Sarvam-1 2B) | ₹0 (+ electricity) | **30-90s** to first word (est.: 2-4k-token prompt on an N5105, no GPU) | Qwen/Llama weak; Gemma 3 4B / Sarvam-1 better but slower | 2 evenings | Already ruled out in [local-qwen-delegation](local-qwen-delegation.md) and [xero-spare-ram](xero-spare-ram.md). Heat to 90C and memory-pressure history; xero 16GB available today. Turning off the Assist API shrinks the prompt, but then it cannot see sun/weather |
| 2 | **Local LLM on a future GPU box** ([machine-upgrades](machine-upgrades.md) "Local LLM": RTX 3060 12GB, ~40-60 tok/s on 7-8B, OCuLink eGPU) | ₹0 running; hardware ₹18-25k (used 3060) + a new machine ₹45-70k | ~1-3s (est.) | 7-8B models: fair (Gemma/Sarvam family) | weekends, with the machine move | Only if the machine upgrade happens for other reasons; not worth buying for this |
| 3 | **AWS self-hosted GPU** (g4dn.xlarge, T4 16GB) | **~₹32,000** always on (730h x ~$0.53/h) | ~1-2s warm; **minutes** from a cold start | as the model run | 3-4 evenings + Terraform | $0.526/h on-demand, $0.24 spot ([Vantage](https://instances.vantage.sh/aws/ec2/g4dn.xlarge?region=ap-south-1), 2026-11-26; region of that figure not stated, Mumbai is usually a little higher). Starting per question costs minutes. **Rejected: 1,000x Haiku's cost** |
| 4 | **AWS Bedrock pay-per-token** (Gemma 3 4B, Ministral 8B, Claude etc.) | ~₹11 (Gemma 3 4B) - ₹38 (Ministral 8B) | ~1-2s (est.; Mumbai region) | Gemma 3 4B fair; Claude on Bedrock as Anthropic | 2-3 evenings | Mumbai prices ([Bedrock pricing](https://aws.amazon.com/bedrock/pricing/), 2026-11-26): Gemma 3 4B $0.05/$0.09 per M, Ministral 8B $0.18/$0.18. No official HA Bedrock agent (custom integration only, not checked); IAM via Terraform (memory: terraform-for-cloud). No real advantage over the direct APIs |
| 5 | **Claude Haiku 5.5, Anthropic API** - **user's pick** | **~₹23** without search; **+₹0.85 per web search** | ~1-2s (est.; US region from India) | **good** | 1-2 evenings (agent exists) | $0.10/$0.50 per M (Anthropic model table, cached 2026-11-03): ~$0.00045 = ~₹0.04/question. **Trap:** web search is billed per search ($10 per 1,000, ~₹0.85 each - from Anthropic's pricing, not re-fetched today); 5 searches a day adds ~₹130/month, so the home agent should answer sun/rain from HA entities and keep search for real world questions. Prompt caching (on) lowers input cost further |
| 6 | **No-LLM fixed sentences** (phase 0) | ₹0 | **instant** (<0.1s after STT) | via stt-fallback matcher against a list of known questions | **1 evening** | custom sentences + `intent_script` reading `sun.sun` and `weather.forecast_home` (`weather.get_forecasts`, daily precipitation probability) + a canned "how are you". Speech-to-Phrase hears them reliably. Worth doing whatever the LLM choice |
| 7 | **OpenAI API** (gpt-5-nano / gpt-4o-mini / gpt-5.4-mini) | ~₹12 (5-nano), ~₹34 (4o-mini), ~₹175 (5.4-mini) | ~1-2s (est.) | 5.4-mini good; nano unknown | 1-2 evenings | Official HA "OpenAI Conversation" integration, same shape as Anthropic's (Assist API sees sun/weather). Prices per M in/out ([OpenAI pricing](https://developers.openai.com/api/docs/pricing), 2026-11-26): 5-nano $0.05/$0.40, 4o-mini $0.15/$0.60, 5.4-mini $0.75/$4.50. **A ChatGPT Plus subscription does not include API use** - billed separately |
| 8 | **Google Gemini API** (Flash-Lite) - **zero-cost alternative worth one trial** | **₹0 on the free tier**; paid ~₹23 (2.5 Flash-Lite) - ~₹60 (3.1 Flash-Lite) | ~1-2s (est.) | **good** | 1-2 evenings | Official HA "Google Generative AI" integration. Free tier on every Flash/Flash-Lite model, rate-limited ([Gemini pricing](https://aistudio.google.com/docs/pricing), 2026-11-26); paid 2.5 Flash-Lite $0.10/$0.40, 3.1 Flash-Lite $0.25/$1.50. **Privacy trade-off:** on the free tier Google uses prompts to improve its products, and the prompts carry the home's entity states. 2.5 Flash is deprecated 2026-12-01 (routes to 3.5 Flash-Lite) - pick a current model. Only option that fits the 2026-11-04 "no paid" rule |
| 9 | **Perplexity Sonar API** | ~₹460 (est.) | ~2-4s (est.; searches every time) | fair (not tested) | 2 evenings, custom integration | ~$1/M tokens + ~$5 per 1,000 requests (third-party summaries of [Perplexity pricing](https://docs.perplexity.ai/getting-started/pricing); its own page did not show Sonar rates when fetched). **No official HA integration**: community `bieniu/ha-perplexity`, or Extended OpenAI Conversation (HACS) pointed at Perplexity; users report HTTP 400 in voice pipelines and **no function calling**, so it cannot read sun/weather or control anything ([HA forum](https://community.home-assistant.io/t/perplexity-as-an-extension-of-voice-assistant-capabilities/861687)). One unconfirmed source says the Sonar chat API retires 2026-09-27 for an "Agent API". Pro-subscription API credit not confirmed. **Weak fit** |

- **Switching is cheap:** a pipeline's conversation agent is a dropdown in HA (Settings -> Voice assistants), so Haiku and Gemini can sit side by side as two agents and be compared on the same questions in minutes.
- **Rejected, and why:** xero local (minute-long waits, heat and memory history), AWS GPU (₹32k/month or minutes of cold start), Bedrock (same price class as the direct APIs plus IAM/Terraform, no official HA agent), Perplexity (no tool calls, no official integration, ~20x the cost).

#### Design notes (pieces besides the brain)
- **STT - Marathi:** the `stt-fallback` container (`projects/voice-assistant/stt_fallback.py`) runs AI4Bharat IndicConformer (~0.7s p50 on xero) only when Speech-to-Phrase returns empty, and today trusts it only to name one of our songs; everything else is dropped. **Idea:** when the transcript is not a song, pass the Devanagari text to the LLM agent instead of dropping it. Needs a guard so false wakes and noise do not become paid questions (minimum length, a confidence floor).
- **STT - English free speech: the real gap.** Local Whisper timed 2026-11-04: base.en ~3s and mishears, small.en 10-15s accurate; Moonshine 0.3s but needs a Wyoming wrapper and is base.en-level accurate; cloud STT is paid. Untested idea: IndicConformer transcribes English speech into Devanagari phonetics, and an LLM may read that ("व्हॉट इज द वेदर") well enough - one cheap test once credit exists.
- **Routing - two candidates:**
  - **Dedicated "conversation" wake word** (e.g. Dumbledore -> LLM pipeline, Hey Jarvis -> commands). **Trap:** `wake_proxy.py` reports a Dumbledore detection back as `hey_jarvis`, so HA cannot tell them apart today; it would need the proxy to flag which word fired (or a second pipeline per satellite). Also: Dumbledore is only 2/6 on synthetic voices, real voice untested.
  - **LLM as fallback:** HA's `prefer_local_intents` is already on - local sentences first, unmatched text to the agent. Simple, but every misheard command becomes a paid (and maybe wrong) question.
- **Phase 0 first:** fixed sentences answer the three example questions instantly and free, in English, and in Marathi through the stt-fallback matcher with a list of known questions. If they cover most of what the user asks, the LLM becomes the long tail.
- **TTS for Marathi replies** - checked 2026-11-26:
  - **Piper has a Marathi voice:** `mr/mr_IN/google` exists in [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices/tree/main/mr/mr_IN) (quality levels not shown; local, free, the `piper` container already runs). First thing to try.
  - **HA's Google Translate TTS** (`tts.google_translate_en_com`, already used by `test_stt.sh` with `TTS_LANG=mr`) speaks Marathi, free, but cloud and unofficial.
  - **Google Cloud TTS:** Chirp 3 HD lists mr-IN ([Chirp 3 HD](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd)); Standard/WaveNet mr-IN voices not confirmed. Free tier **not verified** (pricing page did not render; from memory 4M chars/month Standard, 1M WaveNet) and it is a Google Cloud project with billing, separate from a Gemini API key even on the same Google account (not verified).
  - AI4Bharat Indic TTS: heavy on xero's CPU, skip unless the others sound bad.
  - Until one is chosen, the agent replies in English.
- **Never lie about state:** an LLM answering "is the fan on?" reads HA's entity state; if the entity is unavailable it must say so, not guess. Put that in the home prompt.
- **xero load:** options 5-9 add nothing on xero beyond an HTTPS call; option 1 would compete with Immich and the STT containers on 4 cores.

#### Parts
No parts. API credit is in [car-claude](car-claude.md)'s open items (one purchase for both).

#### Cost detail
- **Header total:** ₹500 one-time API credit (shared with car-claude; it is the same Anthropic account) then ~₹25/month at 20 questions/day without web search, up to ~₹150 with ~5 searches a day.
- **Cheaper variants:** phase 0 alone ₹0; Gemini free tier ₹0 (privacy trade-off); gpt-5-nano ~₹12 (Marathi unknown).
- **Not counted:** cloud STT (not planned) and Google Cloud TTS (free tier likely covers it, unverified).

#### Effort detail
| Phase | Hours | What |
|---|---|---|
| 0 | 3 | fixed sentences + intent_script for sun / rain chance / "how are you", English; Marathi question list in the matcher |
| 1 | 1 | after credit: time the 3 Marathi questions, check web-search usage in the replies; optional Gemini side-by-side |
| 2 | 2-3 | home agent (second subentry, home prompt, search limits), pipeline wiring |
| 3 | 4-6 | **routing + STT - the phase that will overrun:** non-song Marathi transcripts to the agent with false-wake guards, wake-proxy flag if a conversation wake word is chosen, English free-speech test |
| 4 | 2-3 | Marathi TTS: Piper `mr_IN` vs Google Translate by ear, wire the chosen one per reply language |

#### Log
- 2026-11-26: idea recorded from a conversation: options compared (local, GPU box, AWS GPU, Bedrock, Haiku, fixed sentences; then OpenAI, Gemini, Perplexity added at the user's question "we can also use other llms like chatgpt/gemini/perplexity right?"). User leans to Claude Haiku 5.5. The 3 Marathi test questions failed on "credit balance is too low". Found: Piper has a `mr_IN` voice; wake-proxy hides which wake word fired; web search is the main cost driver.
