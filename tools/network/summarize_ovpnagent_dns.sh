#!/usr/bin/env bash
# Every DNS write OpenVPN Connect's agent has made, and whether it restored it.
# RUN THIS ON THE MAC.
#
# /var/log/ovpnagent.log is the confession. For each dynamic-store dictionary
# ovpnagent touches it prints:
#
#   *** DSDict Setup:/Network/Service/<Wi-Fi uuid>/DNS
#   ORIG { ... }              <- what was there
#   MODIFIED { ... }          <- what it put there
#
# so a block whose MODIFIED holds 192.168.0.2 + 192.169.0.2 is a write, and one
# whose ORIG holds them and MODIFIED is empty is the restore. The bug is a write
# with no restore: measured 2026-09-30 over five months, 447 writes against 442
# restores - five net strandings, which matches the six occurrences on record.
#
# The discriminator is how the session ended. A clean disconnect logs the
# restore, a dscacheutil flush and a killall -HUP mDNSResponder. A session whose
# last line is "Process N has exited, destroy tun" skips all three: 32 of 48
# such exits had no restore near them.
#
#   summarize_ovpnagent_dns.sh              # write/restore history + verdict
#   summarize_ovpnagent_dns.sh --tail 20    # just the last 20 events
set -u
LOG="${OVPNAGENT_LOG:-/var/log/ovpnagent.log}"
BAD="${BAD_SERVER:-192.169.0.2}"   # the typo'd one; unique enough to key on
tail_n=0
[ "${1:-}" = "--tail" ] && tail_n="${2:-20}"

[ -r "$LOG" ] || { echo "cannot read $LOG (try sudo)" >&2; exit 1; }

BAD="$BAD" TAILN="$tail_n" python3 - "$LOG" <<'PY'
import os, re, sys

bad = os.environ["BAD"]
tail_n = int(os.environ["TAILN"])
events, ts, buf, cap = [], None, [], False

for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"^(\w{3} \w{3} +\d+ \d\d:\d\d:\d\d)\.\d+ (\d{4})", line)
    if m:
        ts = f"{m.group(1)} {m.group(2)}"
    if line.startswith("*** DSDict Setup:") and "/DNS" in line:
        cap, buf = True, []
        continue
    if cap:
        buf.append(line.rstrip())
        txt = "\n".join(buf)
        if "MODIFIED" in txt and line.strip() == "}" and len(buf) > 4:
            orig, mod = txt.split("MODIFIED", 1)[0], txt.split("MODIFIED", 1)[1]
            if bad in mod and bad not in orig:
                events.append((ts, "WROTE the bad pair"))
            elif bad in orig and bad not in mod:
                events.append((ts, "restored (emptied)"))
            else:
                events.append((ts, "touched Setup:/DNS (neither)"))
            cap, buf = False, []
    if "has exited, destroy tun" in line:
        events.append((ts, "TUNNEL PROCESS EXITED - restore is skipped on this path"))

shown = events[-tail_n:] if tail_n else events
for t, k in shown:
    print(f"  {t}   {k}")

wrote = sum(1 for _, k in events if k.startswith("WROTE"))
rest = sum(1 for _, k in events if k.startswith("restored"))
exits = sum(1 for _, k in events if k.startswith("TUNNEL"))
print()
print(f"  writes:            {wrote}")
print(f"  restores:          {rest}")
print(f"  net strandings:    {wrote - rest}")
print(f"  abnormal exits:    {exits}  ('has exited, destroy tun')")
if events:
    print(f"  last event:        {events[-1][0]}  -  {events[-1][1]}")
if events and events[-1][1].startswith(("WROTE", "TUNNEL")):
    print()
    print("  => the log ends on a write or an abnormal exit, so the bad pair was")
    print("     most likely left behind. Confirm live with:")
    print("       scutil <<< \"list\" | grep 'Setup:.*/DNS'")
PY
