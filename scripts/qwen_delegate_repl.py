#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["anthropic", "requests"]
# ///
"""Minimal REPL: chat with a cloud Claude model, which can delegate trivial
subtasks to a local Qwen model running in Ollama.

Meant to run on a machine actually suited to local inference (e.g. a Mac
with Apple Silicon) - NOT the homelab server (Celeron N5105, no GPU,
already running production services with a history of memory-pressure
lockups; too weak and too risky to share resources with).

Setup on the target machine:
  1. Install Ollama: https://ollama.com/download
  2. Pull a small model:  ollama pull qwen2.5:1.5b
  3. export ANTHROPIC_API_KEY=...  (or `ant auth login` if you have the CLI)
  4. uv run scripts/qwen_delegate_repl.py

Type 'exit' or Ctrl-C to quit.
"""
import sys

import anthropic
import requests
from anthropic import beta_tool

OLLAMA_URL = "http://localhost:11434/api/generate"
QWEN_MODEL = "qwen2.5:1.5b"
ORCHESTRATOR_MODEL = "claude-opus-5"  # swap to claude-sonnet-5 / claude-haiku-4-5 if cost-conscious


@beta_tool
def delegate_to_local_model(task: str) -> str:
    """Delegate a simple, low-stakes subtask to a fast local model (Qwen via Ollama).

    Use this for trivial work: formatting, simple summarization, boilerplate
    text, basic classification, quick lookups from context you already have.
    Do NOT use it for anything requiring careful reasoning, code correctness,
    multi-step logic, or where getting it wrong matters - handle those
    yourself instead.

    Args:
        task: The specific, self-contained subtask to hand off. Include
            all context the local model needs - it has no memory of this
            conversation.
    """
    print(f"\n  [-> delegating to {QWEN_MODEL}: {task[:80]}{'...' if len(task) > 80 else ''}]")
    try:
        resp = requests.post(
            OLLAMA_URL,
            json={"model": QWEN_MODEL, "prompt": task, "stream": False},
            timeout=60,
        )
        resp.raise_for_status()
        result = resp.json()["response"]
        print(f"  [<- {QWEN_MODEL} replied: {result[:80]}{'...' if len(result) > 80 else ''}]\n")
        return result
    except requests.exceptions.RequestException as exc:
        print(f"  [!! local model call failed: {exc}]\n")
        return f"Error: local model unavailable ({exc}). Handle this yourself instead."


def main() -> None:
    client = anthropic.Anthropic()
    messages: list[dict] = []

    print(f"Chatting with {ORCHESTRATOR_MODEL} (delegates trivial work to {QWEN_MODEL} locally).")
    print("Type 'exit' to quit.\n")

    while True:
        try:
            user_input = input("you> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit"):
            break

        messages.append({"role": "user", "content": user_input})

        runner = client.beta.messages.tool_runner(
            model=ORCHESTRATOR_MODEL,
            max_tokens=4096,
            tools=[delegate_to_local_model],
            messages=messages,
        )

        final_text = ""
        for message in runner:
            messages.append({"role": "assistant", "content": message.content})
            tool_response = runner.generate_tool_call_response()
            if tool_response is not None:
                messages.append(tool_response)
            if message.stop_reason == "end_turn":
                final_text = "".join(
                    block.text for block in message.content if block.type == "text"
                )

        print(f"claude> {final_text}\n")


if __name__ == "__main__":
    try:
        main()
    except anthropic.AuthenticationError:
        print("No valid Anthropic credentials found. Set ANTHROPIC_API_KEY or run `ant auth login`.")
        sys.exit(1)
