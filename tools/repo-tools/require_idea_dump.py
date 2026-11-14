#!/usr/bin/env python3
"""Claude Code PreToolUse hook: new idea entries in PROJECTS.md go through the
idea-dump agent (.claude/agents/idea-dump.md), not the main session.

Denies an Edit, Write or Bash call that adds a new `### ` entry with
`**Status:** Backlog` or `Parked` to PROJECTS.md, unless the call comes from
the idea-dump agent itself (hook input carries `agent_type` for subagent calls,
checked 2026-11-14). The deny reason tells the session to delegate, so the
agent gets used without anyone remembering to ask for it.

Allowed: edits to existing entries, and new Active/Done entries for work done
in the session (a record of what was built is not an idea to research).

Wired in .claude/settings.json. Test: tools/repo-tools/test_require_idea_dump.sh
"""
import json
import re
import sys
from pathlib import Path

ENTRY = re.compile(r"(?m)^### \S")
IDEA_STATUS = re.compile(r"\*\*Status:\*\*\s*(Backlog|Parked)")
ALLOWED_AGENTS = {"idea-dump"}


def count_entries(text):
    return len(ENTRY.findall(text or ""))


def adds_idea_entry(tool, inp):
    if tool == "Edit":
        if not inp.get("file_path", "").endswith("PROJECTS.md"):
            return False
        new, old = inp.get("new_string", ""), inp.get("old_string", "")
        return count_entries(new) > count_entries(old) and bool(IDEA_STATUS.search(new))
    if tool == "Write":
        path = inp.get("file_path", "")
        if not path.endswith("PROJECTS.md"):
            return False
        content = inp.get("content", "")
        try:
            before = Path(path).read_text()
        except OSError:
            before = ""
        return count_entries(content) > count_entries(before) and bool(IDEA_STATUS.search(content))
    if tool == "Bash":
        cmd = inp.get("command", "")
        # heredoc / python appends: a new heading at line start plus an idea status
        return "PROJECTS.md" in cmd and count_entries(cmd) > 0 and bool(IDEA_STATUS.search(cmd))
    return False


def main():
    data = json.load(sys.stdin)
    if data.get("agent_type") in ALLOWED_AGENTS:
        return
    if not adds_idea_entry(data.get("tool_name"), data.get("tool_input") or {}):
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "New Backlog/Parked entries in PROJECTS.md are written by the idea-dump agent "
            "(CLAUDE.md, user 2026-11-14). Call the Agent tool with subagent_type "
            "\"idea-dump\": give it the idea in the user's words plus everything decided "
            "in this conversation (choices, prices, parts, what the user will do). It "
            "researches, writes the entry with a ```parts block and Open items, and "
            "commits. Edits to existing entries are not affected."),
    }}))


if __name__ == "__main__":
    main()
