#!/usr/bin/env python3
"""Bring HA's Assist config to the state this project expects. Idempotent.

- Exposes to Assist only the entities voice should reach, and un-exposes the
  stale/unavailable Tinxy duplicates whose names clash with the live ones.
- Adds spoken aliases (union with any already set) and puts the live Tinxy
  boards in their rooms.
- Adds the Wyoming integration for speech-to-phrase (127.0.0.1:10300) and
  piper (127.0.0.1:10200) and makes them the speech-to-text and
  text-to-speech of the preferred Assist pipeline. TTS is required: the phone
  app's voice mode asks for a spoken reply, and a pipeline without TTS
  rejects the run before any audio is sent.

Run from the repo root:  set -a; . ./.env.healthcheck; set +a
                         projects/voice-assistant/setup_assist.py
then `docker restart speech-to-phrase` so it retrains on the new names.
"""
import json
import os
import urllib.request

from ha_ws import call, call_many

HA_HTTP = "http://localhost:8123"
WYOMING = {"speech_to_phrase": 10300, "piper": 10200, "openwakeword": 10400}  # all on 127.0.0.1
# Wake word for the ESP32 satellite (the phone app starts at speech-to-text and
# ignores it). Swap to the custom model's id once "Alejandro" is trained.
WAKE_WORD_ID = "hey_jarvis"

# entity_id -> extra spoken names. Every entity here is exposed to Assist.
EXPOSE = {
    "switch.bedroom_tubelight": ["bedroom light", "bedroom tube light", "tube light"],
    "switch.bedroom_led_bulb_2": ["bedroom bulb", "bedroom LED"],
    "switch.bedroom_balcony": ["balcony light"],
    "fan.bedroom_fan_2": ["bedroom fan", "fan"],
    "switch.living_room_tubelight": ["hall light", "living room light"],
    "switch.living_room_shelf_led": ["shelf light"],
    "fan.living_room_fan": ["hall fan"],
    "switch.white_noise": [],
    "climate.panasonic_ac_panasonic_ac": ["AC", "air conditioner"],
    "scene.ojaswi_sleeping": [],
    "scene.ojaswi_awake": [],
    "media_player.spotify_pramod": [],
    "todo.shopping_list": [],
}

# Unavailable or meaningless entities that were exposed and would put clashing
# names ("Bedroom Fan" vs the live "bedfan") into the recogniser.
UNEXPOSE = [
    "switch.bedroom_tube_light", "switch.bedroom_led_bulb", "switch.bedroom_balcony_lamp",
    "fan.bedroom_fan",
    "switch.masterbedroom_tubelight", "switch.masterbedroom_dimmable_light",
    "switch.masterbedroom_led_bulb", "fan.masterbedroom_fan",
    "switch.living_room_blank", "light.bulb", "light.bulb_wash_basin",
    "switch.dishwasher_power", "switch.dishwasher_child_lock",
    "switch.dishwasher_half_load", "switch.dishwasher_extra_dry",
    "scene.new_scene",
    "media_player.sonalis_macbook_pro_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",
    "media_player.iphone_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",
    "media_player.xero_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",
    "media_player.realme_x_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",
    "media_player.pramods_macbook_pro_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast",
]

# Live Tinxy boards (by one of their entities) -> area.
DEVICE_AREAS = {"switch.bedroom_tubelight": "bedroom", "switch.living_room_tubelight": "living_room"}
AREA_ALIASES = {"living_room": ["hall"]}


def http(method, path, body=None):
    req = urllib.request.Request(
        HA_HTTP + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {os.environ['HA_TOKEN']}",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def main():
    call_many([
        {"type": "homeassistant/expose_entity", "assistants": ["conversation"],
         "entity_ids": list(EXPOSE), "should_expose": True},
        {"type": "homeassistant/expose_entity", "assistants": ["conversation"],
         "entity_ids": UNEXPOSE, "should_expose": False},
    ])
    print(f"exposed {len(EXPOSE)}, un-exposed {len(UNEXPOSE)}")

    registry = {e["entity_id"]: e for e in call({"type": "config/entity_registry/list"})}
    updates = []
    for entity_id, aliases in EXPOSE.items():
        if not aliases:
            continue
        current = call({"type": "config/entity_registry/get", "entity_id": entity_id})["aliases"]
        # HA keeps a None in the list as the slot for the entity's own name.
        merged = current + [a for a in aliases if a not in current]
        if merged != current:
            updates.append({"type": "config/entity_registry/update",
                            "entity_id": entity_id, "aliases": merged})
    for entity_id, area in DEVICE_AREAS.items():
        updates.append({"type": "config/device_registry/update",
                        "device_id": registry[entity_id]["device_id"], "area_id": area})
    for area_id, aliases in AREA_ALIASES.items():
        updates.append({"type": "config/area_registry/update",
                        "area_id": area_id, "aliases": aliases})
    call_many(updates)
    print(f"applied {len(updates)} alias/area updates")

    titles = [e["title"].lower().replace("-", "_").replace(" ", "_")
              for e in http("GET", "/api/config/config_entries/entry?domain=wyoming")]
    for name, port in WYOMING.items():
        if any(t.startswith(name) for t in titles):
            print(f"wyoming {name}: already configured")
            continue
        flow = http("POST", "/api/config/config_entries/flow", {"handler": "wyoming"})
        result = http("POST", f"/api/config/config_entries/flow/{flow['flow_id']}",
                      {"host": "127.0.0.1", "port": port})
        print(f"wyoming {name}:", result.get("type"), result.get("title"), result.get("errors"))

    states = [s["entity_id"] for s in http("GET", "/api/states")]
    stt = [e for e in states if e.startswith("stt.") and "phrase" in e]
    tts = [e for e in states if e.startswith("tts.") and "piper" in e]
    wake = [e for e in states if e.startswith("wake_word.") and "openwakeword" in e]
    if not stt or not tts or not wake:
        raise SystemExit("stt/tts entity not there yet - rerun in a few seconds")
    pipelines = call({"type": "assist_pipeline/pipeline/list"})
    pipe = next(p for p in pipelines["pipelines"] if p["id"] == pipelines["preferred_pipeline"])
    fields = {k: pipe[k] for k in (
        "conversation_engine", "conversation_language", "language", "name",
        "tts_engine", "tts_language", "tts_voice", "wake_word_entity", "wake_word_id")}
    fields.update(stt_engine=stt[0], stt_language="en", prefer_local_intents=True,
                  tts_engine=tts[0], tts_language="en_US", tts_voice="en_US-lessac-medium",
                  wake_word_entity=wake[0], wake_word_id=WAKE_WORD_ID)
    call({"type": "assist_pipeline/pipeline/update", "pipeline_id": pipe["id"], **fields})
    print(f"pipeline '{pipe['name']}': stt={stt[0]} tts={tts[0]} wake={wake[0]}:{WAKE_WORD_ID}")


if __name__ == "__main__":
    main()
