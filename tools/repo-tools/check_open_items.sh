#!/usr/bin/env bash
# List tracker/ projects that break the "Open items come first" rule (see
# tracker/README.md and CLAUDE.md):
#
#   - an Active project with no `#### Open items` checklist
#   - a project whose checklist is not the first thing after its header lines
#     (Status / Priority / Cost / Effort / Actual cost)
#   - a project that still carries an old `**Next step:**` paragraph
#   - an item with no owner (`**Pramod:**` / `**Together:**` / `**Claude:**`)
#   - a Done or Closed project that still has open items
#
# The dashboard (projects-ui) gathers every open project's checklist into one
# panel, so a project that breaks the rule is quietly missing from it.
#
# Usage: tools/repo-tools/check_open_items.sh [--staged]
#   Default: every tracker/ file in the working tree.
#   --staged: only the projects the commit changes (staged against HEAD), and
#   there an old Next step is an error too. This is what .githooks/pre-commit
#   runs (via fix_open_items.sh), so the format holds for every commit without
#   the untouched rest blocking anything.
# Both read tracker/ through `tracker.py combined`, which joins the files back
# into the old one-file shape ("### Title" entries) this check was written for.
# Exit:  0 nothing to report, 1 something to report.

set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO"
TRACKER_PY="$REPO/tools/repo-tools/tracker.py"

NEW=$(mktemp); OLD=$(mktemp); trap 'rm -f "$NEW" "$OLD"' EXIT
if [ "${1:-}" = "--staged" ]; then
  git diff --cached --quiet -- tracker/ && exit 0   # no tracker file in this commit
  python3 "$TRACKER_PY" combined --staged > "$NEW"
  python3 "$TRACKER_PY" combined --head > "$OLD"
  set -- "$NEW" "$OLD"
else
  python3 "$TRACKER_PY" combined > "$NEW"
  set -- "$NEW"
fi

python3 - "$@" <<'EOF'
import re, sys

def split_entries(text):
    out = {}
    for e in re.split(r'^### ', text.split('\n## ', 1)[-1], flags=re.M)[1:]:
        title, _, body = e.partition('\n')
        out[title] = body
    return out

text = open(sys.argv[1]).read()
staged = len(sys.argv) > 2
current = split_entries(text)
if staged:
    before = split_entries(open(sys.argv[2]).read())
    touched = {t for t, b in current.items() if before.get(t) != b}
entries = [f'{t}\n{b}' for t, b in current.items() if not staged or t in touched]
OWNERS = {'pramod', 'together', 'claude'}
problems, to_convert = [], []

for entry in entries:
    title, _, body = entry.partition('\n')
    status = re.search(r'^\*\*Status:\*\*\s*(\w+)', body, re.M)
    status = status.group(1) if status else '?'
    lines = [l for l in body.split('\n')]
    # First non-blank line after the Status/Priority lines.
    rest = [l for l in lines if not re.match(r'^\*\*(Status|Priority|Cost|Effort|Actual cost):\*\*', l)]
    first = next((l for l in rest if l.strip()), '')
    has_items = re.search(r'^#### Open items\s*$', body, re.M)
    items = []
    if has_items:
        block = body[has_items.end():]
        block = re.split(r'^#{1,4} ', block, maxsplit=1, flags=re.M)[0]
        items = [l for l in block.split('\n') if re.match(r'^- \[[ xX]\]', l)]
    open_items = [l for l in items if l.startswith('- [ ]')]
    has_next = re.search(r'^\*\*Next step:\*\*', body, re.M)

    def report(msg):
        problems.append(f'{status:8} {title}: {msg}')

    if status in ('Done', 'Closed'):
        if open_items:
            report(f'{len(open_items)} open item(s) on a {status} entry')
        continue
    if has_items and first.strip() != '#### Open items':
        report('Open items is not the first section after Status/Priority')
    if has_items and has_next:
        report('has both Open items and an old Next step - fold it in')
    for l in items:
        m = re.match(r'^- \[[ xX]\]\s*\*\*([^*:,]+)', l)
        if not m or m.group(1).strip().lower() not in OWNERS:
            report(f'item without a Pramod/Together/Claude owner: {l[:70]}')
    if status == 'Active' and not has_items:
        if has_next:
            to_convert.append(f'{status:8} {title}')
        else:
            report('Active with no Open items')
    elif status in ('Parked', 'Backlog') and has_next and not has_items:
        to_convert.append(f'{status:8} {title}')

if staged:
    problems += [f'{p}: still has a **Next step:** - convert it to #### Open items' for p in to_convert]
    to_convert = []
    if problems:
        print('tracker: a project this commit changes breaks the Open items rule')
        print('(see tracker/README.md / CLAUDE.md; bypass once with git commit --no-verify):')
if problems:
    if not staged: print('Breaks the Open items rule:')
    print('\n'.join('  ' + p for p in problems))
if to_convert:
    print(f'Still on the old Next step format ({len(to_convert)}) - convert when touched:')
    print('\n'.join('  ' + p for p in to_convert))
sys.exit(1 if problems or to_convert else 0)
EOF
