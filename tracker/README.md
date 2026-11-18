# tracker/

One file per homelab project, of every status: ideas, active work, parked, done and closed. Replaced the single ever-growing `PROJECTS.md` on 2026-11-18 (see [`tracker-split.md`](tracker-split.md)).

| What | Where |
|---|---|
| A project's state, plan, research, parts, Log | `tracker/<slug>.md` - this folder |
| The one-line-per-project list | [`PROJECTS.md`](../PROJECTS.md) - **generated**, never edit by hand |
| The dashboard | `projects-ui`, `https://xero.<tailnet>/projects` - reads this folder live |
| Code a project builds | `projects/<name>/`, linked from the tracker file |
| History before the split | `git log $(git log --diff-filter=A --format=%h -- tracker/README.md)^ -- PROJECTS.md` - `git log --follow` does not cross a file split |

## Rules

- **The file never moves.** Picking a project, parking it or finishing it is a one-line edit to its `**Status:**`. Links stay valid.
- **Most ideas stay Backlog for ever, and that is fine.** A Backlog file is a researched, budgeted idea, not a debt.
- **New idea files are written by the `idea-dump` agent** (`.claude/agents/idea-dump.md`). A main-session Write of a new Backlog/Parked file is denied by `tools/repo-tools/require_idea_dump.py`.
- **After changing a file, regenerate the index and commit it with the file:**
  ```bash
  tools/repo-tools/tracker.py index
  git commit -- tracker/<slug>.md PROJECTS.md
  ```
  The pre-commit hook only **checks** that `PROJECTS.md` matches the staged files; it never writes it.
- **`PROJECTS.md` merge conflict** (two clones changed tracker files): never hand-merge it. Run `tools/repo-tools/tracker.py index`, `git add PROJECTS.md`, continue.
- **Docs style:** tables and bullets, not paragraphs (CLAUDE.md).

## File shape

```
# Some project
**Status:** Active
**Priority:** P2
**Cost:** ₹1,500-2,500
**Effort:** ~2 weekends

#### Open items
- [ ] **Pramod:** something the user does by hand (buy, solder, mount, decide)
- [ ] **Together, 2026-11-04 21:00:** something done in a session with the user
- [ ] **Claude:** something a session can do on its own

**Why:** the motivation, one short paragraph.
**State:** where it stands today (open projects).
**Outcome:** what shipped or was decided, and when (Done/Closed - replaces Open items and State).

#### Design / Options / Wiring / Parts / ...
Reference detail that is not history, as named `####` subsections.

#### Log
- 2026-10-08: dated updates, oldest first.
```

- **File name:** short `lowercase-with-dashes.md`, matching `projects/<name>` when there is code. Not the title: titles carry state and change.
- **First line** is `# Title`, then the header lines, one per line, no blank line between them.
- **Subsections are `####`.** Never `##` or `###` in a file: the dashboard joins the files back into one document for its parser.

### Header lines

| Line | Values | On |
|---|---|---|
| `**Status:**` | `Active` · `Parked` (revisit when it becomes a real problem) · `Backlog` (idea, not started) · `Closed` (understood, decided not to act) · `Done` | every file |
| `**Priority:**` | `P1` (most urgent) · `P2` · `P3` | Active, Parked, Backlog |
| `**Cost:**` | rupees, `₹1,500-2,500` or `₹0`; `?` = not estimated yet | Active, Parked, Backlog |
| `**Effort:**` | evenings or weekends, `~2 evenings` / `~3 weekends (20h)`; `?` = not estimated | Active, Parked, Backlog |
| `**Actual cost:**` | rupees spent | Done (optional) |

- **Budget is required on open projects.** The commit hook rejects an open file the commit changes unless both Cost and Effort are real estimates. Files migrated with `?` get one the next time they are touched.
- **Index totals:** rupees are totalled for Active and Parked only. Backlog shows a count: a total of ideas that mostly never happen would read as a debt.

### Open items

- **Every Active file, and any Parked/Backlog file with a concrete next action,** opens with `#### Open items` straight under the header lines.
- **One short line per item, led by its owner:** `**Pramod:**`, `**Together:**` or `**Claude:**`, optionally with a when after a comma.
- **Done item:** delete it and add a Log bullet; don't leave it ticked. **New task:** add it.
- **Enforced at commit time:** `tools/repo-tools/fix_open_items.sh` moves a misplaced checklist, or has a headless `claude -p` convert what needs judgment. In a `git commit -- <paths>` it fixes the working tree and stops; run the same commit again.
- **The dashboard gathers every open item into one panel by owner**, so an item outside the checklist is effectively forgotten.

### Parts lists

A project that needs things bought carries a fenced ` ```parts ` block, one line per item - never a markdown table:

```
qty | item | est | note
1 | INMP441 I2S mic | 150-300 | digital I2S, NOT analog MAX4466
```

- **`est`** is rupees for the whole quantity, `400` or `150-300`; blank if unknown.
- **Prices assume a local electronics shop.** Something that genuinely has to be ordered online says so in its note.
- **Alternatives:** a `# Option 1 - ...` line starts an option; the dashboard gives each its own shopping-list checkbox. Rows above the first `#` line go with whichever option is picked.

## Tools

| Tool | What |
|---|---|
| `tools/repo-tools/tracker.py` | `index` writes `PROJECTS.md`; `check-staged` is the hook's check; `combined` joins the files for the checkers; `path "<title>"` finds a file |
| `tools/repo-tools/check_open_items.sh` | lists files breaking the Open items rule (`--staged`: only this commit's) |
| `tools/repo-tools/fix_open_items.sh` | pre-commit auto-fix of the above |
| `tools/repo-tools/require_idea_dump.py` | routes new idea files to the `idea-dump` agent |
