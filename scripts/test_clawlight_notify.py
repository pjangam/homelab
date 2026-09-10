#!/usr/bin/env python3
"""Tests clawlight's ntfy notification rules.

Three failure modes worth guarding against, all invisible in normal use until
they matter: (a) a notification flood - firing on every message, or on every
hook event while a session sits at a prompt; (b) a buzz for something that
resolved itself inside the delay; (c) a silent miss, where a session genuinely
stuck on you never alerts.

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

# Hold the delayed pushes instead of running them on a timer, so a test decides
# when "the delay is up" and assertions stay deterministic.
pending: list = []
srv.schedule = lambda delay, fn: pending.append(fn)


def delay_elapses():
    due, pending[:] = list(pending), []
    for fn in due:
        fn()


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
    pending.clear()
    srv.sessions.clear()
    srv.last_needing = set()
    srv.last_notify_ts = 0.0


HOMELAB = "/home/pramod/code/homelab"

# 1. the end of an ordinary turn is not a notification. `Stop` fires after every
#    message; a push per message is exactly the noise this test exists to catch.
reset()
srv.report("s1", "xero", "active", HOMELAB)
srv.report("s1", "xero", "waiting", HOMELAB)
delay_elapses()
check("end of a normal turn does not notify", len(fired), 0)

# 2. a session actually blocked on you notifies - but only once the delay is up
reset()
srv.report("s1", "xero", "active", HOMELAB)
srv.report("s1", "xero", "input_needed", HOMELAB)
check("nothing is sent before the delay is up", len(fired), 0)
delay_elapses()
check("a session waiting on input notifies once", fired, [["xero/homelab"]])

# 3. staying at the prompt must not re-fire (the flood case)
srv.report("s1", "xero", "input_needed", HOMELAB)
srv.report("s1", "xero", "input_needed", HOMELAB)
delay_elapses()
check("repeated input_needed reports do not re-notify", len(fired), 1)

# 4. answered inside the delay window = never sent
reset()
srv.report("s1", "xero", "input_needed", HOMELAB)
srv.report("s1", "xero", "active", HOMELAB)  # permission granted, work resumed
delay_elapses()
check("a prompt answered within the delay never notifies", len(fired), 0)

# 5. the light is what gets notified about: a prompt raised while background
#    work still runs (light green) waits until the light actually goes red
reset()
srv.report("s2", "xero", "active", HOMELAB)
srv.report("s2", "xero", "task_start")
srv.report("s2", "xero", "input_needed", HOMELAB)
delay_elapses()
check("input needed while a background task runs does not notify", len(fired), 0)
srv.report("s2", "xero", "task_end")
delay_elapses()
check("notifies once the background task finishes", fired, [["xero/homelab"]])

# 6. flapping back to needing input inside the cooldown stays quiet
srv.report("s2", "xero", "active", HOMELAB)
srv.report("s2", "xero", "input_needed", HOMELAB)
delay_elapses()
check("asking again within the cooldown is suppressed", len(fired), 1)

# 7. the same transition after the cooldown does fire
srv.last_notify_ts -= srv.NOTIFY_COOLDOWN_SECONDS + 1
srv.report("s2", "xero", "active", HOMELAB)
srv.report("s2", "xero", "input_needed", HOMELAB)
delay_elapses()
check("asking again after the cooldown notifies", len(fired), 2)

# 8. a second console asking while the first is still unanswered
reset()
srv.report("a", "xero", "input_needed", HOMELAB)
delay_elapses()
check("first session notifies", fired[0], ["xero/homelab"])
srv.last_notify_ts -= srv.NOTIFY_COOLDOWN_SECONDS + 1  # past the shared cooldown
srv.report("b", "mac", "input_needed", "/home/pramod/code/other")
delay_elapses()
check("a second session asking notifies for itself only", fired[1], ["mac/other"])

# 9. a session that ends before the delay is up says nothing
reset()
srv.report("s4", "xero", "input_needed", HOMELAB)
srv.report("s4", "xero", "end")
delay_elapses()
check("a session that ends within the delay never notifies", len(fired), 0)

# 10. no token configured = notifications disabled entirely
reset()
srv.NTFY_TOKEN = ""
srv.report("s3", "xero", "input_needed", HOMELAB)
delay_elapses()
check("no token means no notification", len(fired), 0)
srv.NTFY_TOKEN = "tk_test"

print()
print("FAILURES:", failures)
sys.exit(1 if failures else 0)
