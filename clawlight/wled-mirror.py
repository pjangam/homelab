#!/usr/bin/env python3
"""Mirror the clawlight aggregate colour onto the aarti-lights WLED strip.

Polls clawlight's /api/status on xero and, on every state change, sets the
whole strip to one solid colour matching web/index.html's COLORS map.

    systemctl --user start clawlight-wled-mirror.service   # see README.md

The unit conflicts with aarti-lights.service: while WLED is on, its realtime UDP stream
overrides anything set over the JSON API. Hand the strip back with
`systemctl --user start aarti-lights.service`.

CLAWLIGHT_URL and WLED_HOST override the defaults below.
"""
import json
import os
import time
import urllib.request

CLAWLIGHT_URL = os.environ.get("CLAWLIGHT_URL", "http://127.0.0.1:8126/clawlight/api/status")
WLED_HOST = os.environ.get("WLED_HOST", "192.168.1.125")
BRI = int(os.environ.get("WLED_BRI", "150"))

# Same colours as clawlight/web/index.html.
COLORS = {
    "active": [0x22, 0xC5, 0x5E],
    "waiting": [0xEF, 0x44, 0x44],
    "shells": [0xF5, 0x9E, 0x0B],
    "idle": [0x6B, 0x72, 0x80],
}


def get_state() -> str:
    with urllib.request.urlopen(CLAWLIGHT_URL, timeout=5) as r:
        state = json.load(r).get("state", "idle")
    return state if state in COLORS else "idle"


def set_wled(rgb):
    body = {"on": True, "bri": BRI, "transition": 5,
            "seg": [{"id": 0, "fx": 0, "pal": 0, "col": [rgb, [0, 0, 0], [0, 0, 0]], "on": True}]}
    req = urllib.request.Request(f"http://{WLED_HOST}/json/state", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    urllib.request.urlopen(req, timeout=5).read()


def main():
    last = None
    while True:
        try:
            state = get_state()
            if state != last:
                set_wled(COLORS[state])
                print(f"{time.strftime('%H:%M:%S')} {state} -> {COLORS[state]}", flush=True)
                last = state
        except Exception as exc:  # transient network errors; retry next tick
            print(f"error: {exc}", flush=True)
            last = None
        time.sleep(2)


if __name__ == "__main__":
    main()
