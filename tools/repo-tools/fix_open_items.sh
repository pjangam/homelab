#!/usr/bin/env bash
# Bring the tracker/ projects a commit changes into the "Open items come
# first" format, re-stage them, and let the commit carry on. Called by
# .githooks/pre-commit when `check_open_items.sh --staged` fails; the user
# asked (2026-11-04) for the hook to fix the format rather than reject.
#
#   1. A checklist that is present but not first is moved straight under the
#      header lines (Status/Priority/Cost/Effort) - mechanical, done here.
#   2. What needs judgment - turning an old **Next step:** into owner-led items,
#      an item with no owner, an Active project with no checklist - is handed
#      to a headless Claude (`claude -p`, Read/Edit only, on those files only).
#   3. The check runs again; only if it passes are the files re-staged.
#
# It refuses (exit 1, commit stops) rather than guess when:
#   - a tracker file in this commit has unstaged edits: re-staging would sweep
#     them in. Stage or stash them first.
#   - the claude CLI is missing, fails, or its result still breaks the rule.
# OPEN_ITEMS_AUTOFIX=0 skips the fixing and only reports (the old behaviour).
#
# Usage: tools/repo-tools/fix_open_items.sh   (normally only from the hook)
# Runs under macOS's bash 3.2 too (the Mac clone commits through this hook).

set -uo pipefail
REPO=$(git rev-parse --show-toplevel)
cd "$REPO"
CHECK=tools/repo-tools/check_open_items.sh
TRACKER_PY=tools/repo-tools/tracker.py

report=$("$CHECK" --staged) && exit 0
echo "$report"
if [ "${OPEN_ITEMS_AUTOFIX:-1}" = "0" ]; then
  exit 1
fi
# A `git commit -- <paths>` runs this hook on a temporary index
# (next-index-*.lock). Staging a fix into it commits the fix, but git then
# writes the pre-fix copy back to the real index, leaving a staged revert
# behind (found 2026-11-18). So in that mode the fix is made in the working
# tree only and the commit stops: running the same command again commits the
# fixed file, because a pathspec commit takes the working-tree copy.
case "$(basename "${GIT_INDEX_FILE:-index}")" in
  next-index*) PATHSPEC_COMMIT=1 ;;
  *) PATHSPEC_COMMIT=0 ;;
esac
restage() {
  if [ "$PATHSPEC_COMMIT" = 1 ]; then
    echo "open-items: fixed ${files% } in the working tree. This was a \`git commit -- <paths>\`,"
    echo "            so run the same commit command again to commit the fix."
    exit 1
  fi
  # shellcheck disable=SC2086
  git add $files
}

# The check only looks at the tracker files this commit changes, so those are
# the only ones the fix may touch.
files=$(git diff --cached --name-only --diff-filter=ACMR -- tracker/ | tr '\n' ' ')
# shellcheck disable=SC2086
if ! git diff --quiet -- $files; then
  echo "open-items: a tracker file in this commit has unstaged edits, so it can't be fixed and re-staged safely."
  echo "            Stage (git add) or stash them, then commit again."
  exit 1
fi

# --- 1. Mechanical: move a misplaced checklist to the top of its file -------
moved=$(echo "$report" | sed -n 's/^  [A-Za-z?]* *\(.*\): Open items is not the first section.*/\1/p')
if [ -n "$moved" ]; then
  while IFS= read -r title; do
    [ -z "$title" ] && continue
    f=$(python3 "$TRACKER_PY" path "$title") || exit 1
    F="$f" python3 - <<'PY'
import os, re
p = os.environ['F']
e = open(p).read()
# The heading plus its list lines (and their indented continuations) only -
# a paragraph after the list is body, not checklist.
m = re.search(r'^#### Open items[ \t]*\n(?:(?:- |[ \t]+\S).*\n|[ \t]*\n)*', e, re.M)
block = m.group(0).rstrip('\n') + '\n'
e = e[:m.start()] + e[m.end():]
meta = list(re.finditer(r'^\*\*(Status|Priority|Cost|Effort|Actual cost):\*\*.*\n', e, re.M))
at = meta[-1].end() if meta else e.index('\n') + 1
e = e[:at] + '\n' + block + e[at:]
e = re.sub(r'\n{3,}', '\n\n', e)
open(p, 'w').write(e)
print('open-items: moved the checklist to the top of ' + p)
PY
  done <<< "$moved"
  restage   # in a pathspec commit this stops here; the re-run gets checked
  report=$("$CHECK" --staged) && { echo "open-items: fixed, re-staged $files"; exit 0; }
fi

# --- 2. Judgment: a headless Claude converts what is left --------------------
CLAUDE_BIN=$(command -v claude || echo "$HOME/.local/bin/claude")
if [ ! -x "$CLAUDE_BIN" ]; then
  echo "open-items: no claude CLI to convert these projects; fix them by hand (see tracker/README.md)."
  exit 1
fi
echo "open-items: asking claude to convert the projects above (about a minute)..."
before_claude=$(git diff --name-only | sort)
# Not `prompt=$(cat <<EOF ...)`: bash 3.2, which is what macOS ships and so
# what this hook runs under on the Mac, mis-parses an apostrophe inside a
# heredoc inside $( ). That was enough to make the whole script a syntax error
# there while parsing fine on xero's bash 5, so the auto-fix was silently dead
# on the Mac (found 2026-11-08). `read -d ""` needs no command substitution,
# so it parses on both.
IFS= read -r -d '' prompt <<EOF || true
Edit only these files in the current directory: $files - and in them only the projects named below, only these problems:

$report

Each file is one project: "# Title", then header lines (**Status:**, **Priority:**, **Cost:**, **Effort:**). The rule (tracker/README.md): every open project leads with a "#### Open items" checklist straight under those header lines, before **Why:**. One short line per item, each led by its owner in bold - "- [ ] **Pramod:** ...", "- [ ] **Together:** ..." (or "**Together, <when>:**"), "- [ ] **Claude:** ..." - Pramod is the user (buying, soldering, mounting, deciding, anything on his phone or hands), Claude is what a session can do alone, Together is work done in a session with him. An old "**Next step:**" paragraph or list is replaced by the checklist: split it into items and delete the Next step; detail that does not fit a one-line item goes into State or a short named "####" subsection, constraints that are not tasks go into State - lose nothing. For an Active project with no checklist and no Next step, derive the items from its State.

Do not touch the Log or any other file. Do not run git or any other command. When done, reply with one line per file saying what you changed.
EOF
if ! timeout 300 "$CLAUDE_BIN" -p "$prompt" --allowedTools "Read,Edit" --permission-mode acceptEdits </dev/null; then
  echo "open-items: claude failed or timed out; the files are left as they were staged. Fix by hand."
  # shellcheck disable=SC2086
  git checkout -- $files 2>/dev/null
  exit 1
fi

# Only those files may have changed. Other sessions' unstaged work in the
# shared tree was there before claude ran, so compare against that snapshot.
others=$(comm -13 <(echo "$before_claude") <(git diff --name-only | sort) \
  | grep -vxF -f <(echo "$files" | tr ' ' '\n' | grep .) || true)
if [ -n "$others" ]; then
  echo "open-items: claude touched other files ($others) - stopping; check them by hand."
  exit 1
fi
restage
if report=$("$CHECK" --staged); then
  echo "open-items: fixed and re-staged $files - look at what it changed with git show after the commit."
  exit 0
fi
echo "$report"
echo "open-items: still breaks the rule after the automatic fix; staged version kept, fix the rest by hand."
exit 1
