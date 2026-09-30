#!/usr/bin/env python3
"""One-off (2026-09-30): turn PROJECTS.md's "## <status>" sections into a
"**Status:**" line under each project, with every project in one flat
"## Projects" list. Kept for the record; running it twice is a no-op."""
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "PROJECTS.md"
STATUS = {"Active": "Active", "Parked": "Parked", "Backlog ideas": "Backlog",
          "Closed (not acting)": "Closed", "Done": "Done"}

lines = open(PATH).read().split("\n")
out, status, fence, skipping_intro, placed = [], None, False, False, False
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith("```"):
        fence = not fence
    heading = re.match(r"^## \S+ (.+)$", line) if not fence else None
    if heading and heading.group(1) in STATUS:
        status = STATUS[heading.group(1)]
        # Drop the heading and the "---" rule before it (plus blanks).
        while out and out[-1].strip() in ("", "---"):
            out.pop()
        out.append("")
        if not placed:
            out += ["---", "", "## Projects"]
            placed = True
        out.append("")
        skipping_intro = True  # a section's own intro paragraph (Closed has one)
        i += 1
        continue
    if skipping_intro and not fence:
        if line.startswith("### "):
            skipping_intro = False
        else:
            i += 1
            continue
    out.append(line)
    if line.startswith("### ") and status and not fence:
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if not nxt.startswith("**Status:**"):
            out.append(f"**Status:** {status}")
            if nxt.strip() and not nxt.startswith("**Priority:**"):
                out.append("")  # body started straight under the heading
    i += 1

open(PATH, "w").write("\n".join(out))
