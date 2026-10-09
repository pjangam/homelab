#!/usr/bin/env python3
"""Print what ntfy actually sent on a topic, from the ntfy container's message
cache - to check whether an alert fired, and when. Run on xero:

  tools/notify/ntfy_history.py                     # homelab-health, last 24h
  tools/notify/ntfy_history.py homelab-health 72   # topic, hours back

Copies cache.db out of the container (it has no sqlite3) into a temp file.
ntfy keeps messages for its cache duration only (12h by default), so older
alerts are gone from here; email has them.
"""
import datetime
import os
import sqlite3
import subprocess
import sys
import tempfile

topic = sys.argv[1] if len(sys.argv) > 1 else "homelab-health"
hours = float(sys.argv[2]) if len(sys.argv) > 2 else 24
since = datetime.datetime.now().timestamp() - hours * 3600

with tempfile.TemporaryDirectory() as tmp:
    db = os.path.join(tmp, "cache.db")
    subprocess.run(["docker", "cp", "ntfy:/var/cache/ntfy/cache.db", db], check=True,
                   stdout=subprocess.DEVNULL)
    rows = sqlite3.connect(db).execute(
        "select time, priority, title, message from messages"
        " where topic = ? and time > ? order by time", (topic, since)).fetchall()

if not rows:
    print(f"nothing on {topic} in the last {hours:g}h (or it has aged out of the cache)")
for t, prio, title, msg in rows:
    when = datetime.datetime.fromtimestamp(t).strftime("%m-%d %H:%M")
    print(f"{when}  p{prio}  {title}\n    {msg.replace(chr(10), ' ')[:300]}")
