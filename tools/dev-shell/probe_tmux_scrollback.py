#!/usr/bin/env python3
"""Does removing smcup/rmcup actually feed lines into the OUTER terminal's
scrollback? Attaches a throwaway tmux server to a pty, makes it print a lot of
numbered lines, and inspects the bytes tmux writes.

The thing that decides it is DECSTBM (CSI <top>;<bottom> r), a scroll region.
If tmux sets one - which it must, to scroll the area above a bottom status line
- then scrolled-off lines are discarded by the terminal rather than pushed into
scrollback, and the wheel has nothing to scroll no matter what smcup does.

    tools/dev-shell/probe_tmux_scrollback.py
"""
import os, pty, re, select, subprocess, sys, time

DECSTBM = re.compile(rb"\x1b\[(\d*);(\d*)r")
ALT_ON = b"\x1b[?1049h"


def run(sock, *args, check=False):
    return subprocess.run(["tmux", "-L", sock, *args], capture_output=True, check=check)


def probe(label, setup):
    sock = f"sbprobe-{os.getpid()}"
    run(sock, "kill-server")
    run(sock, "-f", "/dev/null", "new-session", "-d", "-x", "80", "-y", "24", "sleep 90")
    time.sleep(0.4)
    for opt in setup:
        run(sock, *opt)

    master, slave = pty.openpty()
    env = dict(os.environ, TERM="xterm-256color"); env.pop("TMUX", None)
    p = subprocess.Popen(["tmux", "-L", sock, "attach-session", "-t", "0"],
                         stdin=slave, stdout=slave, stderr=slave,
                         env=env, close_fds=True, start_new_session=True)
    os.close(slave)

    out = b""
    def drain(seconds):
        nonlocal out
        end = time.time() + seconds
        while time.time() < end:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    c = os.read(master, 1 << 16)
                except OSError:
                    return
                if not c:
                    return
                out += c

    drain(1.0)
    # Make the pane produce far more lines than the window is tall.
    run(sock, "respawn-pane", "-k", "-t", "0", "sh -c 'for i in $(seq 1 200); do echo LINE$i; done; sleep 60'")
    drain(2.0)

    run(sock, "detach-client", "-s", "0")
    try:
        p.wait(timeout=3)
    except subprocess.TimeoutExpired:
        p.kill()
    os.close(master)
    run(sock, "kill-server")

    regions = sorted(set(DECSTBM.findall(out)))
    print(f"  {label}")
    print(f"    bytes:                 {len(out)}")
    print(f"    alt screen entered:    {ALT_ON in out}")
    print(f"    scroll region set:     {bool(regions)}  {regions[:4] if regions else ''}")
    early = b"LINE3\n" in out or b"LINE3\r" in out
    late = b"LINE199" in out
    print(f"    early line reached pty: {early}    late line reached pty: {late}")
    return bool(regions)


def main():
    print("== stock (alt screen, status at bottom) ==")
    probe("stock", [])
    print("== smcup@ only, status still at bottom ==")
    r1 = probe("smcup@", [("set", "-ga", "terminal-overrides", ",*:smcup@:rmcup@")])
    print("== smcup@ AND status off ==")
    r2 = probe("smcup@ + status off", [("set", "-ga", "terminal-overrides", ",*:smcup@:rmcup@"),
                                       ("set", "-g", "status", "off")])
    print()
    print("scroll region still set with status at bottom:", r1)
    print("scroll region still set with status off:      ", r2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
