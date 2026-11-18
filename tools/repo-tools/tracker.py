#!/usr/bin/env python3
"""The project tracker: one file per project in tracker/, and the generated
PROJECTS.md index of them. See tracker/README.md for the format and rules.

  tracker.py index [--staged]   write PROJECTS.md from tracker/ (working tree,
                                or the staged files with --staged)
  tracker.py check-staged       pre-commit: the staged PROJECTS.md matches the
                                staged tracker files, and every open project
                                this commit changes has a Cost and an Effort
  tracker.py combined [--staged|--head]
                                print every project as one markdown file in the
                                old PROJECTS.md shape ("## Projects" + "### Title"
                                entries), for check_open_items.sh
  tracker.py path "<title>"     print the tracker file whose heading is <title>

Stdlib only, and nothing newer than python 3.8: the commit hook also runs on
the Mac, whose stock python3 is old and has no PyYAML.
"""
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TRACKER = "tracker"
INDEX = "PROJECTS.md"

META = re.compile(r"^\*\*(Status|Priority|Cost|Effort|Actual cost):\*\*\s*(.*?)\s*$")
OPEN = ("Active", "Parked", "Backlog")
STATUSES = [  # display order; emoji/labels match the projects-ui dashboard
    ("Active", "🟢 Active"),
    ("Parked", "🟡 Parked"),
    ("Backlog", "💡 Backlog ideas"),
    ("Closed", "⚪ Closed (not acting)"),
    ("Done", "✅ Done"),
]
# Rupee totals only where they mean something: most Backlog ideas stay ideas,
# so a backlog total would read as a debt it isn't (user, 2026-11-18).
TOTALLED = ("Active", "Parked")


def git(*args, **kw):
    return subprocess.run(["git", "-C", REPO] + list(args), check=True,
                          stdout=subprocess.PIPE, **kw).stdout.decode()


# --- reading -----------------------------------------------------------------

def tracker_paths(where):
    """Project files under tracker/ (not README.md), sorted by path."""
    if where == "worktree":
        d = os.path.join(REPO, TRACKER)
        names = sorted(os.listdir(d)) if os.path.isdir(d) else []
        paths = ["%s/%s" % (TRACKER, n) for n in names]
    else:
        tree = "HEAD" if where == "head" else None
        if tree:
            try:
                out = git("ls-tree", "--name-only", "HEAD", TRACKER + "/", stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                out = ""
        else:
            out = git("ls-files", "--", TRACKER + "/")
        paths = sorted(out.split())
    return [p for p in paths if p.endswith(".md") and os.path.basename(p) != "README.md"]


def read(path, where):
    if where == "worktree":
        with open(os.path.join(REPO, path), encoding="utf-8") as f:
            return f.read()
    rev = "HEAD:" if where == "head" else ":"
    return git("show", rev + path)


def parse(path, text):
    lines = text.split("\n")
    title = lines[0][2:].strip() if lines and lines[0].startswith("# ") else None
    meta = {}
    for line in lines[1:]:
        if not line.strip():
            if meta:
                break
            continue
        m = META.match(line)
        if not m:
            break
        meta.setdefault(m.group(1).lower(), m.group(2))
    return {
        "path": path,
        "slug": os.path.splitext(os.path.basename(path))[0],
        "title": title,
        "status": meta.get("status", "?"),
        "priority": meta.get("priority", ""),
        "cost": meta.get("cost", ""),
        "effort": meta.get("effort", ""),
        "actual": meta.get("actual cost", ""),
        "text": text,
    }


def load(where="worktree"):
    return [parse(p, read(p, where)) for p in tracker_paths(where)]


# --- the index ---------------------------------------------------------------

def rupees(text):
    """'₹1,500-2,500' -> (1500, 2500); '₹0' -> (0, 0); '?' or prose -> None."""
    m = re.match(r"^~?\s*(?:₹|Rs\.?\s*)?\s*([\d,]+)(?:\s*-\s*(?:₹|Rs\.?\s*)?([\d,]+))?", text or "")
    if not m:
        return None
    lo = int(m.group(1).replace(",", ""))
    hi = int(m.group(2).replace(",", "")) if m.group(2) else lo
    return lo, hi


def fmt_rupees(lo, hi):
    f = lambda n: "₹{:,}".format(n)
    return f(lo) if lo == hi else "%s-%s" % (f(lo), f(hi))


def cell(text):
    return (text or "").replace("|", "\\|") or "-"


def render(entries):
    out = [
        "# Projects",
        "",
        "**Generated from `tracker/` by `tools/repo-tools/tracker.py index` - do not edit by hand.** "
        "One file per project lives in [`tracker/`](tracker/); how they work is in "
        "[`tracker/README.md`](tracker/README.md). The dashboard: `https://xero.<tailnet>/projects`.",
        "",
    ]
    order = ["P1", "P2", "P3"]
    rank = lambda e: (order.index(e["priority"]) if e["priority"] in order else 9, e["title"].lower())
    known = [s for s, _ in STATUSES]
    groups = [(s, label) for s, label in STATUSES] + sorted(
        {(e["status"], "❔ " + e["status"]) for e in entries if e["status"] not in known})
    for status, label in groups:
        rows = sorted((e for e in entries if e["status"] == status), key=rank)
        if not rows:
            continue
        head = "## %s (%d)" % (label, len(rows))
        if status in TOTALLED:
            costs = [rupees(e["cost"]) for e in rows]
            known_costs = [c for c in costs if c]
            if known_costs:
                head += " · %s" % fmt_rupees(sum(c[0] for c in known_costs), sum(c[1] for c in known_costs))
            if len(known_costs) < len(rows):
                head += " %s %d unbudgeted" % ("+" if known_costs else "·", len(rows) - len(known_costs))
        elif status == "Backlog":
            unbudgeted = sum(1 for e in rows if not rupees(e["cost"]))
            if unbudgeted:
                head += " · %d unbudgeted" % unbudgeted
        out += [head, ""]
        if status in OPEN:
            out += ["| Project | Priority | Cost | Effort |", "|---|---|---|---|"]
            for e in rows:
                out.append("| [%s](%s) | %s | %s | %s |" % (
                    cell(e["title"]), e["path"], cell(e["priority"]), cell(e["cost"]), cell(e["effort"])))
        else:
            out += ["| Project | Actual cost |", "|---|---|"]
            for e in rows:
                out.append("| [%s](%s) | %s |" % (cell(e["title"]), e["path"], cell(e["actual"])))
        out.append("")
    return "\n".join(out)


# --- checks ------------------------------------------------------------------

def problems_in(entries):
    """Format problems every project file must not have, whatever changed."""
    found = []
    titles = {}
    for e in entries:
        if not e["title"]:
            found.append("%s: first line must be '# <title>'" % e["path"])
            continue
        if e["title"] in titles:
            found.append("%s: same title as %s" % (e["path"], titles[e["title"]]))
        titles[e["title"]] = e["path"]
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", e["slug"]):
            found.append("%s: file name must be lowercase-with-dashes.md" % e["path"])
    return found


def budget_problems(e):
    if e["status"] not in OPEN:
        return []
    missing = []
    if rupees(e["cost"]) is None:
        missing.append("**Cost:** ₹low-high")
    if not e["effort"] or e["effort"].strip() == "?":
        missing.append("**Effort:** e.g. ~2 evenings / ~3 weekends")
    if not missing:
        return []
    return ["%s (%s): open project with no budget - add %s under Status/Priority"
            % (e["path"], e["status"], " and ".join(missing))]


def check_staged():
    changed = git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", TRACKER + "/").split()
    deleted = git("diff", "--cached", "--name-only", "--diff-filter=D", "--", TRACKER + "/").split()
    index_changed = bool(git("diff", "--cached", "--name-only", "--", INDEX).strip())
    if not changed and not deleted and not index_changed:
        return 0
    entries = load("staged")
    problems = problems_in([e for e in entries if e["path"] in changed])
    if os.environ.get("TRACKER_BUDGET_CHECK", "1") != "0":
        for e in entries:
            if e["path"] in changed:
                problems += budget_problems(e)
    try:
        staged_index = git("show", ":" + INDEX)
    except subprocess.CalledProcessError:
        staged_index = ""
    if staged_index != render(entries):
        problems.append(
            "PROJECTS.md does not match the staged tracker/ files. Regenerate it and commit it "
            "with them:\n      tools/repo-tools/tracker.py index --staged && git add PROJECTS.md\n"
            "    (and add PROJECTS.md to a `git commit -- <paths>` list).")
    if problems:
        print("tracker: this commit breaks the tracker rules (tracker/README.md):")
        print("\n".join("  " + p for p in problems))
        print("  Bypass once with git commit --no-verify.")
        return 1
    return 0


# --- other commands ----------------------------------------------------------

def combined(where):
    parts = ["## Projects", ""]
    for p in tracker_paths(where):
        text = read(p, where)
        if text.startswith("# "):
            text = "##" + text  # "# Title" -> "### Title"
        parts.append(text.rstrip("\n") + "\n")
    return "\n".join(parts)


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "index":
        where = "staged" if "--staged" in argv else "worktree"
        text = render(load(where))
        with open(os.path.join(REPO, INDEX), "w", encoding="utf-8") as f:
            f.write(text)
        problems = problems_in(load(where))
        for p in problems:
            print("warning: " + p, file=sys.stderr)
        return 0
    if cmd == "check-staged":
        return check_staged()
    if cmd == "combined":
        where = "staged" if "--staged" in argv else "head" if "--head" in argv else "worktree"
        sys.stdout.write(combined(where))
        return 0
    if cmd == "path" and len(argv) == 2:
        for e in load("worktree"):
            if e["title"] == argv[1]:
                print(e["path"])
                return 0
        print("no tracker file titled %r" % argv[1], file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
