#!/usr/bin/env python3
"""Split PROJECTS.md into one file per ### entry, join it back, and check that
a rewrite of the entries kept their facts.

Written for the 2026-10-14 restructure into fixed fields + Log; kept because
the same split/rewrite/join/check loop works for any whole-file pass.

  projects_md_chunks.py split <PROJECTS.md> <dir>   # dir/000_head.md, 001.md ...
  projects_md_chunks.py join  <dir> <out.md>
  projects_md_chunks.py check <old_dir> <new_dir>   # per chunk: facts that vanished

"check" is a loss detector, not a proof: it lists every inline-code span,
URL, date and number of the old chunk that the new one no longer contains.
Prose that was reworded passes; a dropped command, address or figure does not.
"""
import re
import sys
from pathlib import Path


def split(src, out):
    text = Path(src).read_text()
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    # Entries start at "### " lines outside fenced code (the intro has an
    # example entry inside a fence).
    lines = text.splitlines(keepends=True)
    starts, fence = [], False
    seen_projects = False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fence = not fence
        if fence:
            continue
        if line.startswith("## Projects"):
            seen_projects = True
        if seen_projects and line.startswith("### "):
            starts.append(i)
    bounds = [0] + starts + [len(lines)]
    for n, (a, b) in enumerate(zip(bounds, bounds[1:])):
        name = "000_head.md" if n == 0 else f"{n:03d}.md"
        (out / name).write_text("".join(lines[a:b]))
    print(f"{len(starts)} entries -> {out}")


def join(src, out):
    parts = sorted(Path(src).glob("*.md"))
    chunks = []
    for p in parts:
        t = p.read_text().rstrip("\n") + "\n"
        chunks.append(t)
    Path(out).write_text("\n".join(chunks))
    print(f"{len(parts)} chunks -> {out}")


FACT = re.compile(
    r"`[^`\n]+`"                      # inline code
    r"|https?://[^\s)>\]]+"           # URLs
    r"|\b\d{4}-\d{2}-\d{2}\b"         # dates
    r"|\b\d+(?:[.,]\d+)*\b"           # numbers
)


def facts(text):
    found = set(FACT.findall(text))
    return {f for f in found if not re.fullmatch(r"\d", f)}


def check(old_dir, new_dir):
    bad = 0
    for old in sorted(Path(old_dir).glob("*.md")):
        new = Path(new_dir) / old.name
        if not new.exists():
            print(f"{old.name}: MISSING")
            bad += 1
            continue
        nt = new.read_text()
        lost = sorted(f for f in facts(old.read_text()) if f not in nt)
        if lost:
            bad += 1
            print(f"{old.name}: {', '.join(lost)}")
    print(f"{bad} chunk(s) with lost facts")
    return 1 if bad else 0


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    sys.exit({"split": split, "join": join, "check": check}[cmd](*args) or 0)
