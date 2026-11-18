#!/usr/bin/env python3
"""Claude Code PreToolUse hook: new idea files in tracker/ are written by the
idea-dump agent (.claude/agents/idea-dump.md), not the main session.

Denies a Write that creates a new tracker/<slug>.md with `**Status:** Backlog`
or `Parked`, or a Bash call that writes such a file into tracker/, unless the
call comes from the idea-dump agent itself (hook input carries `agent_type`
for subagent calls, checked 2026-11-14). The deny reason tells the session to
delegate, so the agent gets used without anyone remembering to ask for it.

Allowed: edits to existing tracker files (a status change included), and new
Active/Done files for work done in the session (a record of what was built is
not an idea to research).

Wired in .claude/settings.json. Test: tools/repo-tools/test_require_idea_dump.sh
"""
import json
import os
import re
import sys

IDEA_STATUS = re.compile(r"\*\*Status:\*\*\s*(Backlog|Parked)")
TRACKER_FILE = re.compile(r"(?:^|/)tracker/[^/\s'\"]+\.md$")
ALLOWED_AGENTS = {"idea-dump"}


def adds_idea_file(tool, inp):
    if tool == "Write":
        path = inp.get("file_path", "")
        if not TRACKER_FILE.search(path) or path.endswith("/README.md"):
            return False
        return not os.path.exists(path) and bool(IDEA_STATUS.search(inp.get("content", "")))
    if tool == "Bash":
        cmd = inp.get("command", "")
        # heredoc / cp / python writes into tracker/ carrying an idea status
        return "tracker/" in cmd and bool(re.search(r"(?m)^# \S", cmd)) and bool(IDEA_STATUS.search(cmd))
    return False


def main():
    data = json.load(sys.stdin)
    if data.get("agent_type") in ALLOWED_AGENTS:
        return
    if not adds_idea_file(data.get("tool_name"), data.get("tool_input") or {}):
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "New Backlog/Parked projects in tracker/ are written by the idea-dump agent "
            "(CLAUDE.md, user 2026-11-14). Call the Agent tool with subagent_type "
            "\"idea-dump\": give it the idea in the user's words plus everything decided "
            "in this conversation (choices, prices, parts, what the user will do). It "
            "researches, writes tracker/<slug>.md with a budget, a ```parts block and "
            "Open items, regenerates PROJECTS.md and commits. Edits to existing tracker "
            "files are not affected."),
    }}))


if __name__ == "__main__":
    main()
