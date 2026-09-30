#!/usr/bin/env python3
"""Check that terminal-overrides '*:smcup@:rmcup@' really stops tmux switching the
outer terminal to its alternate screen.

That switch is the whole reason the mouse-off setup in dotfiles/tmux/tmux.conf
can scroll at all: the alternate screen has no scrollback, so with the mouse
given back to iTerm the wheel would have nothing to scroll. Removing smcup/rmcup
makes tmux draw on the main screen, so lines scroll off into iTerm's real
scrollback.

Attaches a throwaway tmux server on its own socket to a pty and looks for the
alternate-screen sequence (ESC [ ? 1049 h) in what tmux writes, with and without
the override. Needs no tty of its own, which is why this is Python and not more
of test_tmux_copy_mode.sh.

    tools/dev-shell/test_tmux_altscreen.py
"""
import os, pty, select, subprocess, sys, time

SOCK = f"altscreen-test-{os.getpid()}"
ALT_ON = b"\x1b[?1049h"


def tmux(*args, check=True):
    return subprocess.run(["tmux", "-L", SOCK, *args],
                          capture_output=True, check=check)


def attach_and_capture(seconds=1.5):
    """Attach a client on a pty and return every byte tmux writes to it."""
    master, slave = pty.openpty()
    env = dict(os.environ, TERM="xterm-256color")
    env.pop("TMUX", None)  # or tmux refuses to nest
    p = subprocess.Popen(["tmux", "-L", SOCK, "attach-session", "-t", "0"],
                         stdin=slave, stdout=slave, stderr=slave,
                         env=env, close_fds=True, start_new_session=True)
    os.close(slave)
    out, deadline = b"", time.time() + seconds
    while time.time() < deadline:
        if select.select([master], [], [], 0.1)[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
    tmux("detach-client", "-s", "0", check=False)
    try:
        p.wait(timeout=3)
    except subprocess.TimeoutExpired:
        p.kill()
    os.close(master)
    return out


def main():
    if subprocess.run(["which", "tmux"], capture_output=True).returncode:
        print("tmux not installed"); return 2
    tmux("kill-server", check=False)
    tmux("-f", "/dev/null", "new-session", "-d", "-x", "80", "-y", "24", "sleep 60")
    time.sleep(0.5)

    passed = failed = 0

    def is_(label, got, want):
        nonlocal passed, failed
        if got == want:
            print(f"  ok   {label}"); passed += 1
        else:
            print(f"  FAIL {label} (want {want!r}, got {got!r})"); failed += 1

    try:
        print("== stock tmux switches to the alternate screen ==")
        out = attach_and_capture()
        is_("client got output at all", len(out) > 0, True)
        is_("alternate screen entered", ALT_ON in out, True)

        print("== with *:smcup@:rmcup@ it does not ==")
        tmux("set", "-ga", "terminal-overrides", ",*:smcup@:rmcup@")
        out = attach_and_capture()
        is_("client got output at all", len(out) > 0, True)
        is_("alternate screen NOT entered", ALT_ON in out, False)
    finally:
        tmux("kill-server", check=False)

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
