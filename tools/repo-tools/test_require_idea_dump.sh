#!/bin/bash
# Tests for require_idea_dump.py (the PreToolUse hook that routes new idea
# entries to the idea-dump agent). Run from anywhere:
#   tools/repo-tools/test_require_idea_dump.sh
cd "$(dirname "$0")/../.." || exit 1
H=tools/repo-tools/require_idea_dump.py
P="$PWD/PROJECTS.md"
fail=0
check() { # name, expect (deny|allow), json
  out=$(printf '%s' "$3" | python3 "$H")
  got=allow; grep -q '"deny"' <<<"$out" && got=deny
  if [ "$got" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (got $got)"; fail=1; fi
}
NEW='\n### Some idea\n**Status:** Backlog\n**Priority:** P3\n'
check "Edit adds backlog entry (main)" deny \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P\",\"old_string\":\"x\",\"new_string\":\"x$NEW\"}}"
check "Edit adds backlog entry (idea-dump agent)" allow \
  "{\"agent_type\":\"idea-dump\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P\",\"old_string\":\"x\",\"new_string\":\"x$NEW\"}}"
check "Edit adds backlog entry (other subagent)" deny \
  "{\"agent_type\":\"general-purpose\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P\",\"old_string\":\"x\",\"new_string\":\"x$NEW\"}}"
check "Edit adds Done entry" allow \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P\",\"old_string\":\"x\",\"new_string\":\"x\\n### Built it\\n**Status:** Done\\n\"}}"
check "Edit changes a Status line only" allow \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$P\",\"old_string\":\"**Status:** Active\",\"new_string\":\"**Status:** Parked\"}}"
check "Edit to another file" allow \
  "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PWD/README.md\",\"old_string\":\"x\",\"new_string\":\"x$NEW\"}}"
check "Bash heredoc append (main)" deny \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat >> PROJECTS.md <<'EOF'$NEW EOF\"}}"
check "Bash log-line edit" allow \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"python3 - <<'EOF'\\ns=open('PROJECTS.md').read()\\ni=s.index('### Spotify by voice')\\nEOF\"}}"
check "Bash unrelated" allow '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
exit $fail
