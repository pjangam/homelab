#!/usr/bin/env bash
# Collapses the DNS recorder's snapshot log to its transitions: the moments the
# bad resolver pair appeared or went away, against the corporate tunnel coming
# up or going down. RUN THIS ON THE MAC (or point it at a copied log).
#
# Why this exists: `mac-dns-recorder.sh --timeline` prints one stanza per change
# and the log is ~90 stanzas of 170 lines. The question the 2026-09-23 write-up
# left open - "is it a connect or a disconnect that strands the servers" - is a
# question about two sections of each snapshot read together, which is exactly
# what no amount of scrolling gives you. Answered on the first run: every single
# appearance of the pair lines up with utun18 coming up or re-establishing, so
# it is written at CONNECT. Disconnect usually restores it.
#
#   summarize_dns_snapshots.sh              # transitions only (the useful view)
#   summarize_dns_snapshots.sh --all        # every snapshot, one line each
#   summarize_dns_snapshots.sh --all <log>  # a log copied off the Mac
set -u
mode=transitions
[ "${1:-}" = "--all" ] && { mode=all; shift; }
LOG="${1:-$HOME/Library/Logs/homelab/dns-recorder/snapshots.log}"
[ -f "$LOG" ] || { echo "no log at $LOG" >&2; exit 1; }

MODE="$mode" BAD="${BAD_SERVER:-192.169.0.2}" python3 - "$LOG" <<'PY'
import os, re, sys

bad = os.environ["BAD"]
everything = os.environ["MODE"] == "all"
blocks = re.split(r"^SNAPSHOT  ", open(sys.argv[1], errors="replace").read(), flags=re.M)[1:]

prev = None
for b in blocks:
    ts = b.split("\n")[0].strip()
    setup = re.search(r"^ *Setup \([^)]*\).*?DNS +(.*)$", b, re.M)
    is_bad = bool(setup and bad in setup.group(1))
    # The corporate tunnel is the one carrying a 172.27/16 address.
    t = re.findall(r"^  (utun\d+): (172\.27\.[\d.]+)", b, re.M)
    tun = f"{t[0][0]}/{t[0][1]}" if t else ""
    addr = re.search(r"^  address: +(.*)$", b, re.M)
    addr = addr.group(1).strip() if addr else "?"

    note = ""
    if prev:
        if not prev[0] and is_bad:
            note += "  <== BAD PAIR WRITTEN"
        elif prev[0] and not is_bad:
            note += "  <-- cleared"
        if prev[1] != tun:
            note += f"   [tunnel: {prev[1] or 'down'} -> {tun or 'down'}]"

    if everything or note or prev is None:
        print(f"{ts:<24} en0={addr:<15} tun={tun:<22} Setup={'BAD' if is_bad else '-':<4}{note}")
    prev = (is_bad, tun)
PY
