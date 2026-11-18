# Local Qwen (Ollama) delegation experiment
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** on the Mac, install Ollama and `ollama pull qwen2.5:1.5b`, set `ANTHROPIC_API_KEY`
- [ ] **Pramod:** run `uv run tools/dev-shell/qwen_delegate_repl.py` (or `pip install anthropic requests` and drop the `uv run --script` shebang) and report what breaks

**Why:** wanted to test routing trivial subagent tasks to a locally-hosted model (Qwen via Ollama) instead of Anthropic's cloud models, to see if cost/latency can be saved on simple work while keeping a cloud Claude model for anything nontrivial. Manual/semi-automatic invocation is an explicitly acceptable bar for a first pass, full auto-detection would be a bonus.
**State:** researched thoroughly; `tools/dev-shell/qwen_delegate_repl.py` written and committed, syntax-checked only - **not yet run**, since it needs to execute on the Mac (target machine is a Mac M2, not the homelab server), which I (Claude, running via SSH on the homelab server) have no access to. It runs on the Mac, so the user runs and debugs it there.

#### Research findings
- **Key finding:** Claude Code (CLI or the Agent SDK library, which is Claude Code packaged as a library) validates model names against an Anthropic-only allowlist - there is no way, via `ANTHROPIC_BASE_URL`, agent-definition frontmatter, or any env var, to point the main session or a subagent at Ollama or any local model. That rules out the originally-envisioned approach entirely.
- **The viable path is different:** a **standalone script** using the Anthropic SDK's Tool Runner (`client.beta.messages.tool_runner`, not Claude Code at all), where Ollama/Qwen is wrapped as a *custom tool* (e.g. `delegate_to_local_model`) that a cloud Claude model can choose to call based on the tool's description - this gives genuine LLM-driven auto-routing (Claude itself judges what's trivial), which is actually closer to the original ask than manual routing.
- **Tradeoff:** this is a bare API loop, not a Claude Code replacement - no built-in file/bash tools, no session persistence, none of Claude Code's actual UX beyond what we hand-built (a minimal REPL).
- **Claude Agent SDK ruled out** (would've been a closer-to-Claude-Code chat experience) - it's the same harness under the hood and almost certainly has the same Anthropic-only model restriction, so it wouldn't solve the actual goal even though it looks closer to "chat normally."

#### Target machine
**Target machine changed to a Mac M2, not the homelab server.** This box (Celeron N5105, no GPU, ~5GB actually free, already running 7+ production containers with a history of memory-pressure lockups) is a poor fit for local inference even at small model sizes - too weak to be useful and too risky to share resources with. The Mac M2 has real unified memory and Metal acceleration Ollama uses natively, and nothing production running on it. Chose `qwen2.5:1.5b` as the model size for that machine.

#### The script
`tools/dev-shell/qwen_delegate_repl.py` is a REPL loop (`while True: input() -> tool_runner turn -> print reply`) that persists conversation history across turns, defines `delegate_to_local_model` as a custom tool wrapping Ollama's local HTTP API, and prints `[-> delegating to qwen2.5:1.5b: ...]` / `[<- ... replied: ...]` markers so delegation is visible live. Orchestrator defaults to `claude-opus-5` (swappable to sonnet/haiku for cost).

#### Log
- 2026-10-26: moved to Backlog by the user.
