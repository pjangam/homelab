#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["paho-mqtt"]
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
import re
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

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

# --- MQTT state publishing (for the physical GPIO light on the Pi) ---------
# The web page reads state over SSE, but a hardware light wants the opposite
# contract: it must be correct the moment it powers on, not once something
# next happens. clawlight only emits on hook events, so a subscriber starting
# cold during an idle stretch would know nothing for as long as the idle lasts.
# A retained MQTT topic solves exactly that - the broker replays the current
# state to any subscriber the instant it connects.
#
# An LWT on the availability topic covers the other half: if this server dies,
# the broker publishes `offline` for us, so the light can show "I don't know"
# instead of confidently displaying a colour that stopped being true.
#
# Credentials come from .env.mqtt via the systemd unit's EnvironmentFile.
# Unset password = publishing silently disabled, matching the ntfy contract
# above (correct on any machine that isn't xero).
MQTT_HOST = os.environ.get("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USERNAME = os.environ.get("MQTT_USERNAME", "")
MQTT_PASSWORD = os.environ.get("MQTT_PASSWORD", "")
MQTT_STATE_TOPIC = os.environ.get("MQTT_STATE_TOPIC", "clawlight/state")
MQTT_AVAILABILITY_TOPIC = os.environ.get("MQTT_AVAILABILITY_TOPIC", "clawlight/availability")

mqtt_client = None
# Set to None to force a republish - used on (re)connect so a broker that lost
# its retained store gets repopulated rather than staying blank until the next
# state change, which during a quiet stretch could be hours away.
last_published: str | None = None


# --- jump-to-console (focus) -----------------------------------------------
# Clicking a session on the light should take you to the terminal that needs
# you. This server deliberately does NOT run tmux itself, not even for sessions
# on its own host: it can only reach xero's tmux, never the MacBook's, so doing
# it here would mean two implementations of the same thing. Instead every host
# runs focus-agent.sh, which holds open an SSE connection to
# /api/focus-stream?host=<its own host> and executes the tmux commands locally.
# The server just routes, and one code path serves both machines.
#
# A request is held for at most this long. If the agent on that host is down,
# a click does nothing rather than queueing up a jump that yanks you somewhere
# unexpected minutes later. Acting on a stale request is worse than dropping
# it: the terminal moves at a moment you have no reason to expect it to.
FOCUS_REQUEST_TTL_SECONDS = 15

# A pane id is always %<digits>; a socket is always an absolute path. Both
# arrive over the network from another machine and end up as arguments to
# `tmux`, so they are validated on the way in and never trusted from the wire.
PANE_RE = re.compile(r"^%\d+$")

# host -> {tmux_socket, tmux_pane, ts}. Only the newest request per host is
# kept: focusing is a "take me there now" action, so a backlog of them is
# never what you want.
pending_focus: dict[str, dict] = {}

# host -> number of focus agents currently holding the SSE stream open. Used
# to refuse a jump outright when nothing is listening, rather than accepting
# it and letting the page flash success at a click that cannot possibly work.
# A control that lies about having worked is worse than one that says it
# didn't - you stop trusting the honest cases too.
focus_listeners: dict[str, int] = {}


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


def valid_tmux(tmux_socket: str, tmux_pane: str) -> bool:
    """Are these usable as `tmux -S <socket> ... -t <pane>` arguments?

    Both come off the wire from another machine, so anything not matching the
    shapes tmux actually produces is dropped rather than passed to the agent.
    """
    return bool(
        PANE_RE.match(tmux_pane)
        and tmux_socket.startswith("/")
        and "\n" not in tmux_socket
        and "\x00" not in tmux_socket
        and len(tmux_socket) < 256
    )


def report(session_id: str, host: str, state: str, cwd: str = "",
           tmux_socket: str = "", tmux_pane: str = ""):
    with lock:
        prune_locked()
        if state == "end":
            sessions.pop(session_id, None)
            maybe_notify_locked()
            return

        entry = sessions.get(session_id)
        if entry is None:
            entry = {"foreground": "active", "background": 0, "host": host, "cwd": "",
                     "tmux_socket": "", "tmux_pane": "", "ts": 0.0}
            sessions[session_id] = entry

        entry["host"] = host
        entry["ts"] = time.time()
        if cwd:  # not every hook event necessarily carries cwd - don't clobber a known value with blank
            entry["cwd"] = cwd
        # Same rule as cwd, plus: a session outside tmux reports these blank
        # forever, which is exactly how it ends up shown as unreachable.
        if valid_tmux(tmux_socket, tmux_pane):
            entry["tmux_socket"] = tmux_socket
            entry["tmux_pane"] = tmux_pane

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
            {
                "id": sid,
                "host": s["host"],
                "state": st,
                "label": label_for(s, sid),
                # False for a session started outside tmux - the page shows it
                # as unreachable rather than offering a jump that can't work.
                "reachable": bool(s.get("tmux_pane")),
            }
            for (sid, s), st in zip(items, states)
        ],
    }


def request_focus(session_id: str) -> tuple[bool, str]:
    """Queue a jump-to-console request for whichever host owns this session.

    Returns (ok, reason). The work itself happens on that host's focus agent -
    see the FOCUS_REQUEST_TTL_SECONDS comment for why this doesn't block on it.
    """
    with lock:
        prune_locked()
        entry = sessions.get(session_id)
        if entry is None:
            return False, "no such session"
        if not entry.get("tmux_pane"):
            return False, "session is not running under tmux"
        if not focus_listeners.get(entry["host"]):
            return False, f"no focus agent running on {entry['host']}"
        pending_focus[entry["host"]] = {
            "tmux_socket": entry["tmux_socket"],
            "tmux_pane": entry["tmux_pane"],
            "ts": time.time(),
        }
    return True, "queued"


def take_focus(host: str) -> dict | None:
    """Pop this host's pending focus request, if there is a fresh one."""
    with lock:
        req = pending_focus.pop(host, None)
    if req is None or time.time() - req["ts"] > FOCUS_REQUEST_TTL_SECONDS:
        return None
    return {"tmux_socket": req["tmux_socket"], "tmux_pane": req["tmux_pane"]}


def start_mqtt():
    """Connect to Mosquitto in the background. Never fatal - the web UI is the
    primary interface and must keep working with the broker down."""
    global mqtt_client
    if not MQTT_PASSWORD:
        print("MQTT publishing disabled (no MQTT_PASSWORD set)")
        return

    import paho.mqtt.client as mqtt

    def on_connect(client, userdata, flags, reason_code, properties):
        global last_published
        print(f"mqtt connected: {reason_code}")
        client.publish(MQTT_AVAILABILITY_TOPIC, "online", retain=True)
        last_published = None  # force a republish of the current state

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="clawlight-server")
    client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    client.will_set(MQTT_AVAILABILITY_TOPIC, "offline", retain=True)
    client.on_connect = on_connect
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=30)
    client.loop_start()  # background thread - a hook POST must never wait on the broker
    mqtt_client = client


def publish_state_loop():
    """Publish the aggregate whenever it changes.

    Polls snapshot() rather than hooking report(), because the aggregate can
    also change with no report at all - a force-closed terminal's session only
    disappears when prune_locked() ages it out. Polling catches both causes
    through one code path, and keeps MQTT work off the request threads.
    """
    global last_published
    while True:
        try:
            state = snapshot()["state"]
            if state != last_published and mqtt_client is not None:
                mqtt_client.publish(MQTT_STATE_TOPIC, state, retain=True)
                last_published = state
        except OSError as exc:
            print(f"mqtt publish failed: {exc}")  # transient; the loop retries
        time.sleep(1)


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
        elif path == "/api/focus-stream":
            host = parse_qs(urlparse(self.path).query).get("host", [""])[0]
            if not host:
                self.send_error(400)
                return
            self._stream_focus(host)
        else:
            self._send_static(path)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path == f"{PREFIX}/api/focus":
            self._handle_focus()
            return
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
            tmux_socket = str(data.get("tmux_socket", ""))
            tmux_pane = str(data.get("tmux_pane", ""))
        except (KeyError, ValueError, json.JSONDecodeError):
            self.send_error(400)
            return

        if state != "end" and state not in FOREGROUND_STATES and state not in BACKGROUND_STATES:
            self.send_error(400)
            return

        report(session_id, host, state, cwd, tmux_socket, tmux_pane)
        self._send_json({"ok": True})

    def _handle_focus(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
            session_id = str(data["session_id"])
        except (KeyError, ValueError, json.JSONDecodeError):
            self.send_error(400)
            return
        ok, reason = request_focus(session_id)
        self._send_json({"ok": ok, "reason": reason})

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


    def _stream_focus(self, host: str):
        """SSE of focus requests for one host, consumed by its focus-agent.sh.

        Polled rather than event-driven: one small loop is easier to reason
        about than waking condition variables from request threads, and the
        cost is a quarter-second of latency on a human keypress.
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        with lock:
            focus_listeners[host] = focus_listeners.get(host, 0) + 1

        last_keepalive = time.time()
        try:
            while True:
                req = take_focus(host)
                if req is not None:
                    self.wfile.write(f"data: {json.dumps(req)}\n\n".encode())
                    self.wfile.flush()
                    last_keepalive = time.time()
                elif time.time() - last_keepalive > 10:
                    # Also how the agent notices a dead connection: this is a
                    # steady ~1.3 bytes/sec, and the agent's curl aborts below
                    # 1 byte/sec, so a silently dropped link reconnects instead
                    # of sitting there looking connected forever.
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
                    last_keepalive = time.time()
                time.sleep(0.25)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with lock:
                focus_listeners[host] = max(0, focus_listeners.get(host, 0) - 1)
                if not focus_listeners[host]:
                    del focus_listeners[host]
                    # Whatever was queued for this host can no longer be
                    # delivered, and holding it would mean the next agent to
                    # connect gets yanked somewhere the user asked for long ago.
                    pending_focus.pop(host, None)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    start_mqtt()
    threading.Thread(target=publish_state_loop, daemon=True).start()
    print(f"clawlight server on {HOST}:{PORT}{PREFIX}")
    server.serve_forever()
