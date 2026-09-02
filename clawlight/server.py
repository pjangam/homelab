#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Serves the clawlight status page and status API under /clawlight/*.

Sessions POST their state here (see set-status.sh, called from Claude Code hooks)
rather than each host writing a local file - this lets sessions on multiple
machines (xero, the MacBook) all contribute to one aggregate light. State lives
in memory only; a server restart just waits for the next hook event per session
to repopulate, which is fine since UserPromptSubmit/Stop fire constantly.
"""
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "0.0.0.0"
PORT = 8126
PREFIX = "/clawlight"
WEB_DIR = Path(__file__).parent / "web"
STALE_AFTER_SECONDS = 30 * 60
FOREGROUND_STATES = {"active", "waiting"}
BACKGROUND_STATES = {"task_start", "task_end"}

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
}

lock = threading.Lock()
# session_id -> {foreground: active|waiting, background: int, host, ts}
#
# `foreground` tracks the main turn (UserPromptSubmit/Stop/Notification).
# `background` counts running subagents/forked tasks (SubagentStart+TaskCreated
# increment, SubagentStop+TaskCompleted decrement) - these run independently of
# the main turn (e.g. a forked background agent), so Stop firing while one is
# still working must not read as "waiting", or the light lies about needing
# your input when Claude is still actually working.
sessions: dict[str, dict] = {}


def prune_locked():
    now = time.time()
    stale = [sid for sid, s in sessions.items() if now - s["ts"] > STALE_AFTER_SECONDS]
    for sid in stale:
        del sessions[sid]


def report(session_id: str, host: str, state: str):
    with lock:
        prune_locked()
        if state == "end":
            sessions.pop(session_id, None)
            return

        entry = sessions.get(session_id)
        if entry is None:
            entry = {"foreground": "active", "background": 0, "host": host, "ts": 0.0}
            sessions[session_id] = entry

        entry["host"] = host
        entry["ts"] = time.time()

        if state in FOREGROUND_STATES:
            entry["foreground"] = state
        elif state == "task_start":
            entry["background"] += 1
        elif state == "task_end":
            entry["background"] = max(0, entry["background"] - 1)


def effective_state(entry: dict) -> str:
    if entry["background"] > 0:
        return "active"
    return entry["foreground"]


def snapshot() -> dict:
    with lock:
        prune_locked()
        items = list(sessions.values())

    states = [effective_state(s) for s in items]

    if "waiting" in states:
        agg = "waiting"
    elif "active" in states:
        agg = "active"
    else:
        agg = "idle"

    return {
        "state": agg,
        "sessions": [{"host": s["host"], "state": st} for s, st in zip(items, states)],
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # keep the systemd journal quiet; status is low-value log noise

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if not path.startswith(PREFIX):
            self.send_error(404)
            return
        path = path[len(PREFIX):] or "/"

        if path == "/api/status":
            self._send_json(snapshot())
        elif path == "/api/events":
            self._stream_events()
        else:
            self._send_static(path)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path != f"{PREFIX}/api/report":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
            session_id = str(data["session_id"])
            host = str(data.get("host", "unknown"))
            state = str(data["state"])
        except (KeyError, ValueError, json.JSONDecodeError):
            self.send_error(400)
            return

        if state != "end" and state not in FOREGROUND_STATES and state not in BACKGROUND_STATES:
            self.send_error(400)
            return

        report(session_id, host, state)
        self._send_json({"ok": True})

    def _send_json(self, data: dict):
        body = json.dumps(data).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_static(self, path: str):
        if path == "/":
            path = "/index.html"
        file_path = (WEB_DIR / path.lstrip("/")).resolve()
        if WEB_DIR not in file_path.parents or not file_path.is_file():
            self.send_error(404)
            return
        body = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", MIME_TYPES.get(file_path.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _stream_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        last_sent = None
        last_keepalive = time.time()
        try:
            while True:
                payload = json.dumps(snapshot())
                if payload != last_sent:
                    self.wfile.write(f"data: {payload}\n\n".encode())
                    self.wfile.flush()
                    last_sent = payload
                    last_keepalive = time.time()
                elif time.time() - last_keepalive > 15:
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
                    last_keepalive = time.time()
                time.sleep(1)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"clawlight server on {HOST}:{PORT}{PREFIX}")
    server.serve_forever()
