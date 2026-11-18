#!/bin/bash
# Tests for require_idea_dump.py (the PreToolUse hook that routes new idea
# files in tracker/ to the idea-dump agent). Run from anywhere:
#   tools/repo-tools/test_require_idea_dump.sh
cd "$(dirname "$0")/../.." || exit 1
H=tools/repo-tools/require_idea_dump.py
NEWF="$PWD/tracker/some-new-idea-that-does-not-exist.md"
OLDF="$PWD/tracker/$(ls tracker | grep -v README.md | head -1)"
fail=0
check() { # name, expect (deny|allow), json
  out=$(printf '%s' "$3" | python3 "$H")
  got=allow; grep -q '"deny"' <<<"$out" && got=deny
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got $got)"; fail=1; fi
}
IDEA='# Some idea\n**Status:** Backlog\n**Priority:** P3\n'
check "Write new backlog file (main)" deny \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$NEWF\",\"content\":\"$IDEA\"}}"
check "Write new backlog file (idea-dump agent)" allow \
  "{\"agent_type\":\"idea-dump\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$NEWF\",\"content\":\"$IDEA\"}}"
check "Write new backlog file (other subagent)" deny \
  "{\"agent_type\":\"general-purpose\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$NEWF\",\"content\":\"$IDEA\"}}"
check "Write new Done file" allow \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$NEWF\",\"content\":\"# Built it\\n**Status:** Done\\n\"}}"
check "Write over an existing tracker file" allow \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$OLDF\",\"content\":\"$IDEA\"}}"
check "Edit a Status line" allow \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$OLDF\",\"old_string\":\"**Status:** Active\",\"new_string\":\"**Status:** Backlog\"}}"
check "Write elsewhere" allow \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PWD/notes.md\",\"content\":\"$IDEA\"}}"
check "Bash heredoc into tracker (main)" deny \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat > tracker/x.md <<'EOF'\\n$IDEA EOF\"}}"
check "Bash status edit in tracker" allow \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i 's/Status:** Active/Status:** Backlog/' tracker/x.md\"}}"
check "Bash unrelated" allow '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
exit $fail
