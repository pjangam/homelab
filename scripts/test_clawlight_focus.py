#!/usr/bin/env python3
"""Tests clawlight's jump-to-console routing.

The routing is the part that fails silently. A click either reaches the agent
on the right host or it doesn't, and when it doesn't, the light looks exactly
the same as when it worked - so the cases worth pinning down are:

  (a) a session outside tmux is reported unreachable rather than offering a
      jump that quietly does nothing,
  (b) a request goes to the host that owns the pane and to no other host,
  (c) a request that nobody collected in time expires instead of yanking the
      terminal somewhere minutes later - and a click at a host whose agent
      isn't running is refused outright rather than flashing success, and
  (d) tmux coordinates arriving over the network are validated before they
      ever become `tmux` arguments.

Run: python3 scripts/test_clawlight_focus.py
"""
import importlib.util
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

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


def reset(*listening_hosts):
    srv.sessions.clear()
    srv.pending_focus.clear()
    srv.focus_listeners.clear()
    srv.last_aggregate = "idle"
    # Stand in for the focus agents that would be holding /api/focus-stream
    # open on each of those hosts.
    for host in listening_hosts:
        srv.focus_listeners[host] = 1


def session_by_label(label):
    for s in srv.snapshot()["sessions"]:
        if s["label"] == label:
            return s
    return None


# --- (a) reachability -------------------------------------------------------
reset("xero")
srv.report("s-tmux", "xero", "waiting", "/home/pramod/code/homelab", "/tmp/tmux-1000/default", "%3")
srv.report("s-bare", "xero", "waiting", "/home/pramod/code/other")

check("tmux session is reachable", session_by_label("homelab")["reachable"], True)
check("non-tmux session is unreachable", session_by_label("other")["reachable"], False)
check("snapshot exposes the session id needed to address a jump",
      session_by_label("homelab")["id"], "s-tmux")

ok, reason = srv.request_focus("s-bare")
check("focusing a non-tmux session is refused", (ok, reason), (False, "session is not running under tmux"))
check("...and queues nothing", srv.pending_focus, {})

ok, reason = srv.request_focus("s-gone")
check("focusing an unknown session is refused", (ok, reason), (False, "no such session"))

# --- (b) routing to the owning host ----------------------------------------
reset("xero", "mac")
srv.report("s-xero", "xero", "waiting", "/home/pramod/code/homelab", "/tmp/tmux-1000/default", "%3")
srv.report("s-mac", "mac", "waiting", "/Users/pramod/code/aws", "/private/tmp/tmux-501/default", "%7")

check("queueing succeeds for a tmux session", srv.request_focus("s-mac"), (True, "queued"))
check("the request lands on the owning host only", sorted(srv.pending_focus), ["mac"])
check("the other host collects nothing", srv.take_focus("xero"), None)
check("the owning host collects the right pane",
      srv.take_focus("mac"),
      {"kind": "tmux", "tmux_socket": "/private/tmp/tmux-501/default", "tmux_pane": "%7"})
check("a collected request is not delivered twice", srv.take_focus("mac"), None)

# Only the newest matters: clicking twice should take you to the second one,
# not queue a jump you have to sit through before the one you meant.
srv.request_focus("s-xero")
srv.report("s-xero2", "xero", "waiting", "/home/pramod/code/second", "/tmp/tmux-1000/default", "%9")
srv.request_focus("s-xero2")
check("a newer request replaces the older one for that host",
      srv.take_focus("xero"),
      {"kind": "tmux", "tmux_socket": "/tmp/tmux-1000/default", "tmux_pane": "%9"})

# --- (c) staleness ----------------------------------------------------------
reset("xero")
srv.report("s-xero", "xero", "waiting", "/home/pramod/code/homelab", "/tmp/tmux-1000/default", "%3")
srv.request_focus("s-xero")
srv.pending_focus["xero"]["ts"] -= srv.FOCUS_REQUEST_TTL_SECONDS + 1
check("a request nobody collected in time expires", srv.take_focus("xero"), None)
check("...and is dropped, not left pending", srv.pending_focus, {})

reset("xero")
srv.report("s-mac", "mac", "waiting", "/Users/pramod/code/aws", "/private/tmp/tmux-501/default", "%7")
check("a jump to a host with no focus agent is refused",
      srv.request_focus("s-mac"), (False, "no focus agent running on mac"))
check("...and queues nothing for it", srv.pending_focus, {})

# The agent going away has to drop the queue too, or the next one to connect
# gets yanked somewhere the user asked for long ago.
reset("xero")
srv.report("s-xero", "xero", "waiting", "/home/pramod/code/homelab", "/tmp/tmux-1000/default", "%3")
srv.request_focus("s-xero")
srv.focus_listeners.clear()
srv.pending_focus.clear()  # what _stream_focus's finally: block does on disconnect
check("a request is dropped when its agent disconnects", srv.take_focus("xero"), None)

# --- (e) the ssh hand-off to the host holding the terminal tab --------------
# A session reached over ssh needs two machines: one switches tmux, the other
# surfaces the tab. The announcing host knows the connection but not which
# clawlight host sits at the far end, so the request is broadcast and only the
# machine owning that source port acts on it.
reset("xero", "mac", "other")
check("a raise goes to every host except the announcer",
      srv.request_raise_ssh(63170, "192.168.1.123:22", "xero"), 2)
check("...and reaches them", sorted(srv.pending_focus), ["mac", "other"])
check("...carrying the connection, tagged as a raise",
      srv.take_focus("mac"),
      {"kind": "raise_ssh", "source_port": 63170, "peer": "192.168.1.123:22"})
check("the announcer is not asked to raise anything", srv.take_focus("xero"), None)

reset("xero")
check("a raise with nobody else listening reaches no one",
      srv.request_raise_ssh(63170, "192.168.1.123:22", "xero"), 0)

# A tmux jump must stay distinguishable from a raise, or the agent runs the
# wrong half on the wrong machine.
reset("xero")
srv.report("s-x", "xero", "waiting", "/home/pramod/code/homelab", "/tmp/tmux-1000/default", "%3")
srv.request_focus("s-x")
check("a tmux jump is tagged as such", srv.take_focus("xero")["kind"], "tmux")

# peer becomes an lsof match string on whichever machine picks it up.
peers = [
    ("192.168.1.123:22", True, "ipv4 host:port"),
    ("100.70.215.25:22", True, "tailscale address"),
    ("fe80::1:22", True, "ipv6-ish"),
    ("192.168.1.123", False, "no port"),
    ("192.168.1.123:22; id", False, "command injection"),
    ("$(id):22", False, "substitution"),
    ("", False, "empty"),
]
for peer, want, desc in peers:
    check(f"peer validation: {desc}", bool(srv.SSH_PEER_RE.match(peer)), want)

# --- (d) validation of wire-supplied tmux coordinates -----------------------
cases = [
    ("/tmp/tmux-1000/default", "%0", True, "well-formed"),
    ("/tmp/tmux-1000/default", "%12", True, "multi-digit pane"),
    ("/tmp/tmux-1000/default", "", False, "empty pane (session not in tmux)"),
    ("", "%0", False, "empty socket"),
    ("/tmp/sock", "0", False, "pane id missing its % sigil"),
    ("/tmp/sock", "%0; rm -rf ~", False, "command injection in pane"),
    ("/tmp/sock", "$(id)", False, "substitution in pane"),
    ("relative/sock", "%0", False, "non-absolute socket"),
    ("-S", "%0", False, "socket that could read as a tmux flag"),
    ("/tmp/a\nb", "%0", False, "newline in socket"),
    ("/" + "x" * 300, "%0", False, "absurdly long socket"),
]
for sock, pane, want, desc in cases:
    check(f"validation: {desc}", srv.valid_tmux(sock, pane), want)

# A rejected pair must not be stored at all - otherwise it would still be
# offered as reachable and handed to the agent later.
reset("xero")
srv.report("s-bad", "xero", "waiting", "/home/pramod/code/homelab", "/tmp/sock", "%0; rm -rf ~")
check("a rejected pane is not stored", session_by_label("homelab")["reachable"], False)

# A hook event without cwd/tmux must not wipe coordinates a previous one set.
reset("xero")
srv.report("s-x", "xero", "active", "/home/pramod/code/homelab", "/tmp/tmux-1000/default", "%3")
srv.report("s-x", "xero", "waiting")
check("a later hook event without tmux info keeps the known pane",
      srv.take_focus("xero") if srv.request_focus("s-x")[0] else None,
      {"kind": "tmux", "tmux_socket": "/tmp/tmux-1000/default", "tmux_pane": "%3"})

print()
if failures:
    print(f"{failures} check(s) failed")
    raise SystemExit(1)
print("all checks passed")
