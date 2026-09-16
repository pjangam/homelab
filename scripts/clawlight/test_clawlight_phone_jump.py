#!/usr/bin/env python3
"""Tests clawlight's jump-to-console from the phone, server side.

The phone's jump is pulled, not pushed: the page records a request and the ssh
session's startup script (phone-attach.sh) claims it. Worth pinning down:

  (a) a session outside tmux is refused rather than recorded,
  (b) a request is claimed by the host that owns the pane, once, and by no
      other host,
  (c) an unclaimed request expires, so a plain Termius connect later on doesn't
      land in a pane asked for long ago, and
  (d) the per-host open URL comes back with the request, and a host without
      one still works.

Run: python3 scripts/clawlight/test_clawlight_phone_jump.py
"""
import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent

spec = importlib.util.spec_from_file_location("clawlight_server", REPO / "clawlight" / "server.py")
srv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(srv)

failures = 0


def check(desc, got, want):
    global failures
    ok = got == want
    print(f"{'PASS' if ok else 'FAIL'}  {desc}")
    if not ok:
        print(f"      expected {want!r}, got {got!r}")
        failures += 1


def reset():
    srv.sessions.clear()
    srv.phone_requests.clear()
    srv.PHONE_OPEN_URLS.clear()


SOCK = "/tmp/tmux-1000/default"

# --- (a) sessions outside tmux ----------------------------------------------
reset()
srv.report("s-bare", "xero", "waiting", "/home/pramod/code/homelab")
check("a session outside tmux is refused",
      srv.request_phone_jump("s-bare"),
      {"ok": False, "reason": "session is not running under tmux"})
check("...and records nothing", srv.phone_requests, {})
check("an unknown session is refused",
      srv.request_phone_jump("nope")["ok"], False)

# --- (b) claimed by the owning host, once -----------------------------------
reset()
srv.report("s-mac", "mac", "waiting", "/Users/p/code/x", SOCK, "%7")
check("a tmux session is accepted, naming its host",
      srv.request_phone_jump("s-mac"), {"ok": True, "host": "mac", "open_url": ""})
check("another host claims nothing", srv.claim_phone_jump("xero"), None)
check("the owning host gets the pane",
      srv.claim_phone_jump("mac"), {"tmux_socket": SOCK, "tmux_pane": "%7"})
check("...only once", srv.claim_phone_jump("mac"), None)

srv.report("s-mac2", "mac", "waiting", "/Users/p/code/y", SOCK, "%9")
srv.request_phone_jump("s-mac")
srv.request_phone_jump("s-mac2")
check("two taps: the newest wins",
      srv.claim_phone_jump("mac")["tmux_pane"], "%9")

# --- (c) expiry --------------------------------------------------------------
reset()
srv.report("s-xero", "xero", "waiting", "/home/pramod/code/homelab", SOCK, "%3")
srv.request_phone_jump("s-xero")
srv.phone_requests["xero"]["ts"] -= srv.PHONE_REQUEST_TTL_SECONDS + 1
check("a request older than the TTL is not handed out",
      srv.claim_phone_jump("xero"), None)

srv.request_phone_jump("s-xero")
srv.phone_requests["xero"]["ts"] -= srv.PHONE_REQUEST_TTL_SECONDS - 5
check("...but one just inside it is (an ssh connect takes a while)",
      srv.claim_phone_jump("xero") is not None, True)

# --- (d) open URLs -------------------------------------------------------------
check("open URLs parse from host=url pairs",
      srv.parse_open_urls(" xero=ssh://p@xero , mac=shortcuts://run-shortcut?name=mac&x=1,junk,=nohost"),
      {"xero": "ssh://p@xero", "mac": "shortcuts://run-shortcut?name=mac&x=1"})
check("empty config gives no URLs", srv.parse_open_urls(""), {})

reset()
srv.PHONE_OPEN_URLS.update({"xero": "ssh://p@xero"})
srv.report("s-xero", "xero", "waiting", "/home/pramod/code/homelab", SOCK, "%3")
check("the host's open URL comes back with the request",
      srv.request_phone_jump("s-xero")["open_url"], "ssh://p@xero")

print()
if failures:
    print(f"{failures} check(s) failed")
    raise SystemExit(1)
print("all checks passed")
