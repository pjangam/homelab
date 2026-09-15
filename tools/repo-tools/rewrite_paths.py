#!/usr/bin/env python3
"""Rewrite repo paths across every tracked text file, for a directory move.

    tools/repo-tools/rewrite_paths.py OLD=NEW [OLD=NEW ...]            # dry run
    tools/repo-tools/rewrite_paths.py --apply OLD=NEW [OLD=NEW ...]

Written for the 2026-09-15 split of the repo root into projects/, services/,
tools/ and docs/, where every move needs the same careful search-and-replace.

A path only matches as a path, not as the tail of a longer word: it must not
follow a letter, digit, '.', '-' or '_'. It MAY follow '/', so absolute and
variable-prefixed forms move too ($REPO/scripts/x, /home/.../scripts/x), with
two exceptions that must never change:
  - `.config/systemd/user/...` is the INSTALLED unit path, not the repo's copy;
  - anything already under a new home (projects/, tools/, services/, docs/),
    so running the same map twice is a no-op.

Moving the files, and fixing paths built at runtime (`dirname "$0"`/..,
__file__), stays a manual step - depth changes are not a text substitution.
"""
import re
import subprocess
import sys

NEW_HOMES = ("projects/", "tools/", "services/", "docs/")
SKIP_SUFFIXES = (".png", ".jpg", ".ico", "package-lock.json", ".jsonl")


def pattern(old):
    # Paths ending in a filename must not match a longer name (x.sh.bak), but a
    # sentence-ending period after one is still a match.
    tail = r"(?![\w-]|\.\w)" if not old.endswith("/") else ""
    return re.compile(r"(?<![\w.-])" + re.escape(old) + tail)


def keep(text, start):
    before = text[max(0, start - 40):start]
    if before.endswith(".config/"):
        return True
    return any(before.endswith(h) or before.endswith("/" + h) for h in NEW_HOMES)


def main(argv):
    apply = "--apply" in argv
    pairs = [a.split("=", 1) for a in argv if a != "--apply"]
    if not pairs or any(len(p) != 2 for p in pairs):
        sys.exit(__doc__)
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split("\n")
    total = 0
    for path in filter(None, files):
        if path.endswith(SKIP_SUFFIXES) or path == "scripts/repo-tools/rewrite_paths.py" or path.endswith("rewrite_paths.py"):
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        new, hits = text, 0
        for old, repl in pairs:
            def sub(m):
                nonlocal hits
                if keep(m.string, m.start()):
                    return m.group(0)
                hits += 1
                return repl
            new = pattern(old).sub(sub, new)
        if hits:
            total += hits
            print(f"{hits:4d}  {path}")
            if apply:
                open(path, "w", encoding="utf-8").write(new)
    print(f"{total} replacement(s){'' if apply else ' (dry run - pass --apply to write)'}")


if __name__ == "__main__":
    main(sys.argv[1:])
