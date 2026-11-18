#!/usr/bin/env python3
"""Run sentences through HA's conversation agent as if a satellite heard them.

THE COMMANDS REALLY RUN (music starts, white noise stops) - this is not a
parse check; for that use the debug call in README. The room comes from the
satellite's device, the same way voice commands get it.

    set -a; . ../../.env.healthcheck; set +a      # HA_TOKEN (don't name a zsh var `path`)
    say.py bedroom "resume the music" "next song"
    say.py living_room "play faint"
    say.py phone "pause the music"                 # no satellite: no room
"""
import sys

import ha_ws

DEVICES = {
    "bedroom": "f201def98beb10329a75b755eccf06a6",      # Voice Satellite
    "living_room": "081d56f0816eaa3a2c13c881fd1d3684",  # Voice Living Room
    "phone": None,
}

room, sentences = sys.argv[1], sys.argv[2:]
for text in sentences:
    msg = {"type": "conversation/process", "text": text, "language": "en"}
    if DEVICES[room]:
        msg["device_id"] = DEVICES[room]
    r = ha_ws.call(msg)
    speech = r["response"].get("speech", {}).get("plain", {}).get("speech", "")
    print(f"{room:11} {text!r:32} -> {speech!r}")
