#!/usr/bin/env python3
"""Set up the "Claude" Assist pipeline for hands-free questions in the car. Idempotent.

1. Adds HA's Anthropic integration if it is missing. The API key is read from
   ANTHROPIC_API_KEY, or asked for (hidden input). HA keeps it in its own
   .storage, so it is never written to the repo or to an env file.
2. Sets up the integration's conversation agent: car instructions (one or two
   spoken sentences), the Assist API (so Claude can see and control the
   entities exposed to Assist), the model (CLAUDE_MODEL, default
   claude-haiku-5-5: fastest to answer), short replies, and web search.
3. Creates or updates a second Assist pipeline named "Claude" that uses that
   agent with "prefer handling commands locally" on. Leaves the preferred
   "Home Assistant" pipeline and the satellites alone.
4. Asks one home question and one general question through the new pipeline
   and prints the replies.

Run from the repo root:  set -a; . ./.env.healthcheck; set +a
                         projects/voice-assistant/setup_claude_pipeline.py
"""
import getpass
import json
import os
import time
import urllib.error
import urllib.request

from ha_ws import call

HA_HTTP = "http://localhost:8123"
PIPELINE_NAME = "Claude"
MODEL = os.environ.get("CLAUDE_MODEL", "claude-haiku-5-5")
PROMPT = """You are a voice assistant for Home Assistant.
Answer questions about the world truthfully.
Your replies are read aloud to the user, usually while they are driving.
Answer in one or two short spoken sentences. No lists, no markdown, no emoji,
no URLs. Say numbers, times and units the way a person would say them.
If a question needs a long answer, give the gist and offer to say more.
"""
# Options per step of the conversation subentry flow. Only the keys the step's
# form actually offers are sent (the model step's fields depend on the model).
INIT = {"prompt": PROMPT, "llm_hass_api": ["assist"], "recommended": False}
ADDITIONAL = {"chat_model": MODEL, "prompt_caching": "prompt"}
MODEL_STEP = {
    "max_tokens": 400,
    "thinking_effort": "low",
    "web_search": True,
    "web_search_max_uses": 2,
    "user_location": True,  # HA asks Claude once for the city/region of zone.home
    "web_fetch": False,
    "code_execution": False,
    "tool_search": False,
}


def http(method, path, body=None):
    req = urllib.request.Request(
        HA_HTTP + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {os.environ['HA_TOKEN']}",
                 "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path}: {e.code} {e.read().decode()}")


def offered(step, wanted):
    keys = {f["name"] for f in step.get("data_schema", [])}
    return {k: v for k, v in wanted.items() if k in keys}


def anthropic_entry():
    entries = http("GET", "/api/config/config_entries/entry?domain=anthropic")
    if entries:
        return entries[0]
    key = os.environ.get("ANTHROPIC_API_KEY") or getpass.getpass("Anthropic API key: ")
    flow = http("POST", "/api/config/config_entries/flow", {"handler": "anthropic"})
    res = http("POST", f"/api/config/config_entries/flow/{flow['flow_id']}", {"api_key": key.strip()})
    if res["type"] != "create_entry":
        raise SystemExit(f"adding the Anthropic integration failed: {res.get('errors') or res}")
    print("added the Anthropic integration")
    return res["result"]


def configure_agent(entry):
    sub = next(s for s in call({"type": "config_entries/subentries/list", "entry_id": entry["entry_id"]})
               if s["subentry_type"] == "conversation")
    step = http("POST", "/api/config/config_entries/subentries/flow",
                {"handler": [entry["entry_id"], "conversation"], "subentry_id": sub["subentry_id"]})
    for wanted in (INIT, ADDITIONAL, MODEL_STEP):
        if step["type"] != "form":
            break
        step = http("POST", f"/api/config/config_entries/subentries/flow/{step['flow_id']}",
                    offered(step, wanted))
        if step.get("errors"):
            raise SystemExit(f"step {step['step_id']} rejected: {step['errors']}")
    if step["type"] != "abort" or step.get("reason") != "reconfigure_successful":
        raise SystemExit(f"configuring the agent did not finish: {step}")
    print(f"agent '{sub['title']}': model={MODEL}, web search on, car prompt")
    ents = call({"type": "config/entity_registry/list"})
    return next(e["entity_id"] for e in ents
                if e["config_entry_id"] == entry["entry_id"]
                and e.get("config_subentry_id") == sub["subentry_id"]
                and e["entity_id"].startswith("conversation."))


def ensure_pipeline(agent):
    pipelines = call({"type": "assist_pipeline/pipeline/list"})
    preferred = next(p for p in pipelines["pipelines"] if p["id"] == pipelines["preferred_pipeline"])
    fields = {
        "name": PIPELINE_NAME,
        "language": "en",
        "conversation_engine": agent,
        "conversation_language": "en",
        "prefer_local_intents": True,
        # Text in, text out from the Shortcut; TTS is set anyway so the
        # phone app's voice mode can use this pipeline too (see README Gotchas).
        "stt_engine": None, "stt_language": None,
        "tts_engine": preferred["tts_engine"], "tts_language": preferred["tts_language"],
        "tts_voice": preferred["tts_voice"],
        "wake_word_entity": None, "wake_word_id": None,
    }
    existing = next((p for p in pipelines["pipelines"] if p["name"] == PIPELINE_NAME), None)
    if existing:
        call({"type": "assist_pipeline/pipeline/update", "pipeline_id": existing["id"], **fields})
        pid = existing["id"]
    else:
        pid = call({"type": "assist_pipeline/pipeline/create", **fields})["id"]
    print(f"pipeline '{PIPELINE_NAME}' ({pid}): agent={agent}, prefer local on; "
          f"preferred pipeline is still '{preferred['name']}'")
    return pid


def ask(agent, text):
    # Right after the reconfigure HA reloads the integration, and for a few
    # seconds the agent id is "invalid"; wait it out.
    for _ in range(10):
        try:
            res = http("POST", "/api/conversation/process", {"text": text, "agent_id": agent, "language": "en"})
            break
        except SystemExit as e:
            if "invalid agent ID" not in str(e):
                raise
            time.sleep(2)
    else:
        raise SystemExit(f"agent {agent} never became available")
    speech = res["response"].get("speech", {}).get("plain", {}).get("speech", "")
    print(f"  Q: {text}\n  A: {speech}")


if __name__ == "__main__":
    entry = anthropic_entry()
    agent = configure_agent(entry)
    ensure_pipeline(agent)
    print("test (straight to the agent, as the Shortcut's fallback would):")
    ask(agent, "Is the bedroom fan on?")
    ask(agent, "How far is the Moon from the Earth?")
