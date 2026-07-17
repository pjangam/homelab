#!/usr/bin/env python3
"""Tiny HTTP API to toggle white-noise.service for Home Assistant."""
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

UID = os.getuid()
USER_ENV = {
    "XDG_RUNTIME_DIR": f"/run/user/{UID}",
    "DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{UID}/bus",
}


def systemctl(action):
    subprocess.run(
        ["systemctl", "--user", action, "white-noise"],
        env={**os.environ, **USER_ENV},
        check=False,
    )


def is_active():
    r = subprocess.run(
        ["systemctl", "--user", "is-active", "white-noise"],
        env={**os.environ, **USER_ENV},
        capture_output=True,
        text=True,
    )
    return r.stdout.strip() == "active"


class Handler(BaseHTTPRequestHandler):
    def send_json(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/white-noise/status":
            self.send_json(200, {"state": "active" if is_active() else "inactive"})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/white-noise/on":
            systemctl("start")
            self.send_json(200, {"state": "active"})
        elif self.path == "/white-noise/off":
            systemctl("stop")
            self.send_json(200, {"state": "inactive"})
        else:
            self.send_json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 8765), Handler)
    print("white-noise-api listening on :8765")
    server.serve_forever()
