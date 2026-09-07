#!/usr/bin/env bash
# Exercises the per-session ignore marker in clawlight/set-status.sh against the
# running clawlight server. Uses a throwaway session id so it never touches a
# real session's state, and cleans up after itself.
#
# Usage: scripts/test_clawlight_ignore.sh
set -u

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
set_status="$repo_dir/clawlight/set-status.sh"
server_url="${CLAWLIGHT_SERVER_URL:-http://localhost:8126}"
ignore_dir="$(mktemp -d)"
sid="test-ignore-$$"
fails=0

export CLAWLIGHT_IGNORE_DIR="$ignore_dir"

cleanup() {
  printf '{"session_id":"%s"}' "$sid" | "$set_status" end >/dev/null 2>&1
  rm -rf "$ignore_dir"
}
trap cleanup EXIT

report() { printf '{"session_id":"%s","cwd":"/tmp/%s"}' "$sid" "$1" | "$set_status" "$2"; }
listed() { curl -fsS -m 5 "$server_url/clawlight/api/status" | grep -q "\"label\": \"$1\""; }

check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected $3, got $2)"
    fails=$((fails + 1))
  fi
}

# 1. Normal path: an unignored session shows up on the light.
report "notignored" active
listed "notignored" && r=present || r=absent
check "unignored session is reported" "$r" present

# 2. Marker present: the session is actively removed, not merely left stale.
touch "$ignore_dir/$sid"
report "notignored" active
listed "notignored" && r=present || r=absent
check "ignored session is removed from the light" "$r" absent

# 3. Marker still present: staying ignored is a no-op, not an error.
report "notignored" waiting
listed "notignored" && r=present || r=absent
check "ignored session stays removed on later events" "$r" absent

# 4. Marker removed: the session comes back.
rm "$ignore_dir/$sid"
report "notignored" active
listed "notignored" && r=present || r=absent
check "unignoring restores the session" "$r" present

# 5. A session id that would escape the ignore dir is not treated as ignored,
#    and must not stop the script reporting normally.
mkdir -p "$ignore_dir/nested"
evil="../nested"
touch "$ignore_dir/nested"
printf '{"session_id":"%s","cwd":"/tmp/traversal"}' "$evil" | "$set_status" active
listed "traversal" && r=present || r=absent
check "path-traversal session id is not silently ignored" "$r" present
printf '{"session_id":"%s"}' "$evil" | "$set_status" end >/dev/null 2>&1

echo
if [ "$fails" -eq 0 ]; then
  echo "all checks passed"
else
  echo "$fails check(s) failed"
fi
exit "$fails"
