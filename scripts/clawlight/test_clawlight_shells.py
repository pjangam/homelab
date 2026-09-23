#!/usr/bin/env python3
"""Tests set-status.sh's background-shell detection on a fake process tree.

`Stop` should report `shells` (amber) instead of `waiting` (red) when the claude
process still has a background shell running, and stay `waiting` otherwise. The
detection reads the process table, so this builds the same shape for real: a
process whose executable is named `claude`, a child whose command line sources a
shell snapshot, and the hook reached through `/bin/sh -c`. The report goes to a
throwaway local HTTP server, never the live clawlight server.

Run: python3 scripts/clawlight/test_clawlight_shells.py
"""
import json
import os
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SET_STATUS = Path(__file__).resolve().parent.parent.parent / "clawlight" / "set-status.sh"

reports: list[dict] = []


class Capture(BaseHTTPRequestHandler):
    def do_POST(self):
        reports.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Capture)
threading.Thread(target=server.serve_forever, daemon=True).start()

tmp = Path(tempfile.mkdtemp())
# comm is taken from the executable's file name, so a copy of bash named
# `claude` is what makes this ancestor look like Claude Code to `ps -o comm=`.
fake_claude = tmp / "claude"
shutil.copy("/bin/bash", fake_claude)
env = {
    **os.environ,
    "CLAWLIGHT_SERVER_URL": f"http://127.0.0.1:{server.server_port}",
    "CLAWLIGHT_IGNORE_DIR": str(tmp / "ignore"),
}
env.pop("CLAWLIGHT_BACKGROUND_SHELLS", None)
hook = f'printf %s "$PAYLOAD" | /bin/sh -c "{SET_STATUS} $STATE"'
background = '( exec -a "zsh -c source /h/.claude/shell-snapshots/snapshot-zsh-1.sh && eval sleep" sleep 30 ) & sleep 0.3; '

failures = 0


def run(desc, script, state, want, payload=None):
    global failures
    reports.clear()
    payload = json.dumps({"session_id": "t", **(payload or {})})
    subprocess.run([fake_claude, "-c", script + hook + "; kill $(jobs -p) 2>/dev/null; true"],
                   env={**env, "STATE": state, "PAYLOAD": payload}, timeout=30, check=False)
    got = reports[-1]["state"] if reports else None
    ok = got == want
    print(f"{'PASS' if ok else 'FAIL'}  {desc}")
    if not ok:
        print(f"      expected {want!r}, got {got!r}")
        failures += 1


run("Stop with no background shell is waiting", "", "waiting", "waiting")
run("Stop with a background shell running is shells", background, "waiting", "shells")
run("a real prompt stays input_needed even with a shell running", background, "input_needed", "input_needed")
run("an unrelated child process is not a shell", "sleep 30 & sleep 0.3; ", "waiting", "waiting")

# The idle nudge Claude Code sends ~60s after a turn ends. With the session's
# own shell still running it is not waiting on you, so it must not turn red.
IDLE = {"hook_event_name": "Notification", "notification_type": "idle_prompt",
        "message": "Claude is waiting for your input"}
IDLE_BY_MESSAGE = {"hook_event_name": "Notification", "message": "Claude is waiting for your input"}
PERMISSION = {"hook_event_name": "Notification", "notification_type": "permission_prompt",
              "message": "Claude needs your permission to use Bash"}
run("idle nudge with a background shell running is shells", background, "input_needed", "shells", IDLE)
run("idle nudge recognised by its message alone", background, "input_needed", "shells", IDLE_BY_MESSAGE)
run("idle nudge with no background shell stays input_needed", "", "input_needed", "input_needed", IDLE)
run("a permission Notification stays input_needed with a shell running", background, "input_needed", "input_needed", PERMISSION)
run("PermissionRequest stays input_needed with a shell running", background, "input_needed", "input_needed",
    {"hook_event_name": "PermissionRequest"})

shutil.rmtree(tmp)
print()
print(f"FAILURES: {failures}")
raise SystemExit(1 if failures else 0)
