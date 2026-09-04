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
import os
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "0.0.0.0"
PORT = 8126
PREFIX = "/clawlight"
WEB_DIR = Path(__file__).parent / "web"
STALE_AFTER_SECONDS = 30 * 60
FOREGROUND_STATES = {"active", "waiting"}
BACKGROUND_STATES = {"task_start", "task_end"}

# --- push notifications (self-hosted ntfy) -----------------------------------
# Published over loopback rather than the tailnet URL: no TLS dependency, the
# publish token never leaves the host, and it still works if the tailnet is
# having a moment. The token is write-only on this topic (see
# scripts/setup_ntfy_users.sh), so a leak cannot read notification history.
#
# Credentials come from .env.ntfy via the systemd unit's EnvironmentFile.
# Unset token = notifications silently disabled, which is the correct
# behaviour on any machine that isn't xero.
NTFY_URL = os.environ.get("NTFY_URL", "http://127.0.0.1:8127/clawlight")
NTFY_TOKEN = os.environ.get("NTFY_CLAWLIGHT_TOKEN", "")
# Where the notification should take you when tapped. Optional.
NTFY_CLICK_URL = os.environ.get("CLAWLIGHT_PUBLIC_URL", "")
# Don't re-alert for this long after alerting. A session that flaps
# waiting->active->waiting (e.g. several permission prompts in a row) is one
# interruption, not several - you are already looking at the screen by then.
NOTIFY_COOLDOWN_SECONDS = 60

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

# Aggregate state as of the last report, so notifications are EDGE-triggered on
# the transition into `waiting` rather than fired on every hook event while a
# session sits at a prompt. Guarded by `lock` along with `sessions`.
last_aggregate = "idle"
last_notify_ts = 0.0


def prune_locked():
    now = time.time()
    stale = [sid for sid, s in sessions.items() if now - s["ts"] > STALE_AFTER_SECONDS]
    for sid in stale:
        del sessions[sid]


def push_notification(labels: list[str]):
    """Best-effort ntfy push. Runs on its own thread; never raises into a hook."""
    body = ", ".join(labels) if labels else "a session"
    req = urllib.request.Request(
        NTFY_URL,
        data=body.encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {NTFY_TOKEN}",
            "Title": "Claude needs you",
            "Tags": "bell",
            "Priority": "4",
            **({"Click": NTFY_CLICK_URL} if NTFY_CLICK_URL else {}),
        },
    )
    try:
        urllib.request.urlopen(req, timeout=5).close()
    except (urllib.error.URLError, OSError):
        pass  # same contract as set-status.sh: a push must never break a turn


def aggregate_locked() -> tuple[str, list[str]]:
    """Aggregate state, plus labels of the sessions driving `waiting`.

    Caller must hold `lock`. Mirrors snapshot()'s precedence rules.
    """
    agg = "idle"
    waiting = []
    for sid, entry in sessions.items():
        st = effective_state(entry)
        if st == "waiting":
            waiting.append(f"{entry['host']}/{label_for(entry, sid)}")
            agg = "waiting"
        elif st == "active" and agg != "waiting":
            agg = "active"
    return agg, waiting


def maybe_notify_locked():
    """Fire a push if the aggregate just entered `waiting`. Caller holds `lock`."""
    global last_aggregate, last_notify_ts

    agg, waiting = aggregate_locked()
    previous, last_aggregate = last_aggregate, agg

    if not NTFY_TOKEN or agg != "waiting" or previous == "waiting":
        return
    now = time.time()
    if now - last_notify_ts < NOTIFY_COOLDOWN_SECONDS:
        return
    last_notify_ts = now
    threading.Thread(target=push_notification, args=(waiting,), daemon=True).start()


def report(session_id: str, host: str, state: str, cwd: str = ""):
    with lock:
        prune_locked()
        if state == "end":
            sessions.pop(session_id, None)
            maybe_notify_locked()
            return

        entry = sessions.get(session_id)
        if entry is None:
            entry = {"foreground": "active", "background": 0, "host": host, "cwd": "", "ts": 0.0}
            sessions[session_id] = entry

        entry["host"] = host
        entry["ts"] = time.time()
        if cwd:  # not every hook event necessarily carries cwd - don't clobber a known value with blank
            entry["cwd"] = cwd

        if state in FOREGROUND_STATES:
            entry["foreground"] = state
        elif state == "task_start":
            entry["background"] += 1
        elif state == "task_end":
            entry["background"] = max(0, entry["background"] - 1)

        maybe_notify_locked()


def effective_state(entry: dict) -> str:
    if entry["background"] > 0:
        return "active"
    return entry["foreground"]


def label_for(entry: dict, session_id: str) -> str:
    # Prefer the session's project directory (last path segment of cwd) to
    # identify which console this is - falls back to a short session id when
    # a hook event didn't carry cwd (e.g. it fired before the first one that does).
    if entry["cwd"]:
        return entry["cwd"].rstrip("/").rsplit("/", 1)[-1] or entry["cwd"]
    return session_id[:8]


def snapshot() -> dict:
    with lock:
        prune_locked()
        items = list(sessions.items())

    states = [effective_state(s) for _, s in items]

    if "waiting" in states:
        agg = "waiting"
    elif "active" in states:
        agg = "active"
    else:
        agg = "idle"

    return {
        "state": agg,
        "sessions": [
            {"host": s["host"], "state": st, "label": label_for(s, sid)}
            for (sid, s), st in zip(items, states)
        ],
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
            cwd = str(data.get("cwd", ""))
        except (KeyError, ValueError, json.JSONDecodeError):
            self.send_error(400)
            return

        if state != "end" and state not in FOREGROUND_STATES and state not in BACKGROUND_STATES:
            self.send_error(400)
            return

        report(session_id, host, state, cwd)
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
