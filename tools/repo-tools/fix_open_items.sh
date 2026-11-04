#!/usr/bin/env bash
# Bring the PROJECTS.md entries a commit changes into the "Open items come
# first" format, re-stage the file, and let the commit carry on. Called by
# .githooks/pre-commit when `check_open_items.sh --staged` fails; the user
# asked (2026-11-04) for the hook to fix the format rather than reject.
#
#   1. A checklist that is present but not first is moved straight under
#      Status/Priority - mechanical, done here.
#   2. What needs judgment - turning an old **Next step:** into owner-led items,
#      an item with no owner, an Active entry with no checklist - is handed to
#      a headless Claude (`claude -p`, Read/Edit only, on PROJECTS.md only).
#   3. The check runs again; only if it passes is PROJECTS.md re-staged.
#
# It refuses (exit 1, commit stops) rather than guess when:
#   - PROJECTS.md has unstaged edits: re-staging would sweep them into this
#     commit. Stage or stash them first.
#   - the claude CLI is missing, fails, or its result still breaks the rule.
# OPEN_ITEMS_AUTOFIX=0 skips the fixing and only reports (the old behaviour).
#
# Usage: tools/repo-tools/fix_open_items.sh   (normally only from the hook)

set -uo pipefail
REPO=$(git rev-parse --show-toplevel)
cd "$REPO"
CHECK=tools/repo-tools/check_open_items.sh

report=$("$CHECK" --staged) && exit 0
echo "$report"
if [ "${OPEN_ITEMS_AUTOFIX:-1}" = "0" ]; then
  exit 1
fi
if ! git diff --quiet -- PROJECTS.md; then
  echo "open-items: PROJECTS.md has unstaged edits, so it can't be fixed and re-staged safely."
  echo "            Stage (git add PROJECTS.md) or stash them, then commit again."
  exit 1
fi
cp PROJECTS.md "$(git rev-parse --git-dir)/PROJECTS.md.before-open-items-fix"

# --- 1. Mechanical: move a misplaced checklist to the top of its entry -------
titles=$(echo "$report" | sed -n 's/^  [A-Za-z?]* *\(.*\): Open items is not the first section.*/\1/p')
if [ -n "$titles" ]; then
  TITLES="$titles" python3 - <<'EOF'
import os, re
p = 'PROJECTS.md'
s = open(p).read()
for title in filter(None, os.environ['TITLES'].split('\n')):
    start = s.index('### ' + title + '\n')
    end = s.find('\n### ', start + 4)
    e = s[start:end] if end != -1 else s[start:]
    # The heading plus its list lines (and their indented continuations) only -
    # a paragraph after the list is body, not checklist.
    m = re.search(r'^#### Open items[ \t]*\n(?:(?:- |[ \t]+\S).*\n|[ \t]*\n)*', e, re.M)
    block = m.group(0).rstrip('\n') + '\n'
    e = e[:m.start()] + e[m.end():]
    meta = list(re.finditer(r'^\*\*(Status|Priority):\*\*.*\n', e, re.M))
    at = meta[-1].end() if meta else e.index('\n') + 1
    e = e[:at] + '\n' + block + e[at:]
    e = re.sub(r'\n{3,}', '\n\n', e)
    s = s[:start] + e + (s[end:] if end != -1 else '')
    print(f'open-items: moved the checklist to the top of "{title}"')
open(p, 'w').write(s)
EOF
  git add PROJECTS.md
  report=$("$CHECK" --staged) && { echo "open-items: fixed, PROJECTS.md re-staged."; exit 0; }
fi

# --- 2. Judgment: a headless Claude converts what is left --------------------
CLAUDE_BIN=$(command -v claude || echo "$HOME/.local/bin/claude")
if [ ! -x "$CLAUDE_BIN" ]; then
  echo "open-items: no claude CLI to convert these entries; fix them by hand (see the PROJECTS.md intro)."
  exit 1
fi
echo "open-items: asking claude to convert the entries above (about a minute)..."
prompt=$(cat <<EOF
Edit PROJECTS.md in the current directory. Only these problems, only in the entries named, nothing else in the file:

$report

The rule (from the file's intro): every open entry leads with a "#### Open items" checklist straight under its **Status:**/**Priority:** lines, before **Why:**. One short line per item, each led by its owner in bold - "- [ ] **Pramod:** ...", "- [ ] **Together:** ..." (or "**Together, <when>:**"), "- [ ] **Claude:** ..." - Pramod is the user (buying, soldering, mounting, deciding, anything on his phone or hands), Claude is what a session can do alone, Together is work done in a session with him. An old "**Next step:**" paragraph or list is replaced by the checklist: split it into items and delete the Next step; detail that does not fit a one-line item goes into State or a short named "####" subsection, constraints that are not tasks go into State - lose nothing. For an Active entry with no checklist and no Next step, derive the items from its State.

Do not touch any other entry, the Log, or any other file. Do not run git or any other command. When done, reply with one line per entry saying what you changed.
EOF
)
if ! timeout 300 "$CLAUDE_BIN" -p "$prompt" --allowedTools "Read,Edit" --permission-mode acceptEdits </dev/null; then
  echo "open-items: claude failed or timed out; PROJECTS.md left as it was staged. Fix by hand."
  git checkout -- PROJECTS.md 2>/dev/null
  exit 1
fi

# Only PROJECTS.md may have changed.
others=$(git diff --name-only | grep -vx PROJECTS.md)
if [ -n "$others" ]; then
  echo "open-items: claude touched other files ($others) - stopping; check them by hand."
  exit 1
fi
git add PROJECTS.md
if report=$("$CHECK" --staged); then
  echo "open-items: fixed and re-staged. The diff against what you staged:"
  git diff --no-index --stat "$(git rev-parse --git-dir)/PROJECTS.md.before-open-items-fix" PROJECTS.md | tail -1
  exit 0
fi
echo "$report"
echo "open-items: still breaks the rule after the automatic fix; staged version kept, fix the rest by hand."
exit 1
