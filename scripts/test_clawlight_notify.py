#!/usr/bin/env python3
"""Tests clawlight's edge-triggered ntfy notification logic.

The failure modes worth guarding against are (a) a notification flood - firing
on every hook event while a session sits at a prompt - and (b) a silent miss,
where a genuine new prompt never alerts. Both are invisible in normal use until
they matter, hence this test.

Run: python3 scripts/test_clawlight_notify.py
"""
import importlib.util
import os
import sys
from pathlib import Path

os.environ["NTFY_CLAWLIGHT_TOKEN"] = "tk_test"  # must be set before import
REPO = Path(__file__).resolve().parent.parent

spec = importlib.util.spec_from_file_location("clawlight_server", REPO / "clawlight" / "server.py")
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

fired: list[list[str]] = []
srv.push_notification = lambda labels: fired.append(labels)
# Run the notifier inline instead of on a thread so assertions are deterministic.
srv.threading.Thread = lambda target, args, daemon: type(
    "T", (), {"start": lambda self: target(*args)}
)()

failures = 0


def check(desc, got, want):
    global failures
    ok = got == want
    print(f"{'PASS' if ok else 'FAIL'}  {desc}")
    if not ok:
        print(f"      expected {want!r}, got {got!r}")
        failures += 1


def reset():
    fired.clear()
    srv.sessions.clear()
    srv.last_aggregate = "idle"
    srv.last_notify_ts = 0.0


# 1. idle -> active -> waiting fires exactly once, naming the session
reset()
srv.report("s1", "xero", "active", "/home/pramod/code/homelab")
check("active report does not notify", len(fired), 0)
srv.report("s1", "xero", "waiting", "/home/pramod/code/homelab")
check("transition into waiting notifies once", fired, [["xero/homelab"]])

# 2. staying in waiting must not re-fire (the flood case)
srv.report("s1", "xero", "waiting", "/home/pramod/code/homelab")
srv.report("s1", "xero", "waiting", "/home/pramod/code/homelab")
check("repeated waiting reports do not re-notify", len(fired), 1)

# 3. flapping back to waiting inside the cooldown stays quiet
srv.report("s1", "xero", "active", "/home/pramod/code/homelab")
srv.report("s1", "xero", "waiting", "/home/pramod/code/homelab")
check("re-entering waiting within cooldown is suppressed", len(fired), 1)

# 4. same transition after the cooldown does fire
srv.last_notify_ts -= srv.NOTIFY_COOLDOWN_SECONDS + 1
srv.report("s1", "xero", "active", "/home/pramod/code/homelab")
srv.report("s1", "xero", "waiting", "/home/pramod/code/homelab")
check("re-entering waiting after cooldown notifies", len(fired), 2)

# 5. a running background task must NOT read as waiting (the existing
#    foreground/background rule must still hold for notifications too)
reset()
srv.report("s2", "xero", "active", "/home/pramod/code/homelab")
srv.report("s2", "xero", "task_start")
srv.report("s2", "xero", "waiting", "/home/pramod/code/homelab")
check("waiting while a background task runs does not notify", len(fired), 0)
srv.report("s2", "xero", "task_end")
check("notifies once the background task finishes", len(fired), 1)

# 6. multiple waiting sessions are named together
reset()
srv.report("a", "xero", "waiting", "/home/pramod/code/homelab")
srv.report("b", "mac", "waiting", "/home/pramod/code/other")
check("first waiting session notifies", fired[0], ["xero/homelab"])
check("second session does not re-notify (already waiting)", len(fired), 1)

# 7. no token configured = notifications disabled entirely
reset()
srv.NTFY_TOKEN = ""
srv.report("s3", "xero", "waiting", "/home/pramod/code/homelab")
check("no token means no notification", len(fired), 0)
srv.NTFY_TOKEN = "tk_test"

print()
print("FAILURES:", failures)
sys.exit(1 if failures else 0)
