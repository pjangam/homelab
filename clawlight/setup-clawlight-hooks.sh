#!/usr/bin/env bash
# Wires this machine's Claude Code hooks into clawlight. RUN THIS ON THE
# MACHINE BEING ONBOARDED, from inside the clone:
#
#   git clone git@github.com:pjangam/homelab.git ~/code/homelab
#   bash ~/code/homelab/clawlight/setup-clawlight-hooks.sh --dry-run
#   bash ~/code/homelab/clawlight/setup-clawlight-hooks.sh --host mbp19
#
# This is the step that was missing. `setup-mac-focus-agent.sh` *reads* the
# clawlight hooks - it dies with "wire them first" if they are not there, and
# it reads CLAWLIGHT_SERVER_URL back out of them rather than taking it as an
# argument. So on a machine clawlight has never seen, this runs first and that
# one second. The README described the ten hooks in prose and left them to be
# hand-wired, which is how a machine ends up with nine of them, or with
# Notification->waiting (the light still works; the machine just never sends a
# push, silently, forever - see README, "Setup on another machine" step 3).
#
# Works on macOS and Linux: it only touches ~/.claude/settings.json. The
# focus agent (jump-to-console) is a separate, optional step per platform.
#
# Re-runnable. It strips every existing set-status.sh hook before adding the
# ten back, so running it again after moving the clone or renaming the host
# fixes the paths rather than duplicating the hooks.
set -u

CLAWLIGHT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_STATUS="$CLAWLIGHT_DIR/set-status.sh"
SETTINGS="$HOME/.claude/settings.json"

# Every event clawlight depends on, and the state it must send. Keep this in
# step with the list in README.md and with the check in setup-mac-focus-agent.sh.
HOOK_MAP='{
  "UserPromptSubmit": "active",
  "Stop":             "waiting",
  "Notification":     "input_needed",
  "PermissionRequest":"input_needed",
  "PostToolUse":      "active",
  "SessionEnd":       "end",
  "SubagentStart":    "task_start",
  "SubagentStop":     "task_end",
  "TaskCreated":      "task_start",
  "TaskCompleted":    "task_end"
}'

dry_run=0
server_url="${CLAWLIGHT_SERVER_URL:-}"
host_name="${CLAWLIGHT_HOST_NAME:-}"

usage() {
  cat >&2 <<USAGE
usage: setup-clawlight-hooks.sh [--host NAME] [--server URL] [--dry-run]

  --host NAME    what this machine calls itself on the light (default: reuse
                 the existing hooks', else \$CLAWLIGHT_HOST_NAME, else hostname)
  --server URL   clawlight server (default: reuse the existing hooks', else
                 \$CLAWLIGHT_SERVER_URL, else http://localhost:8126)
  --dry-run      print what would change, touch nothing
USAGE
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --host)    host_name="${2:?--host needs a name}"; shift ;;
    --server)  server_url="${2:?--server needs a URL}"; shift ;;
    --host=*)   host_name="${1#*=}" ;;
    --server=*) server_url="${1#*=}" ;;
    -h|--help) usage ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
  shift
done

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

command -v jq >/dev/null   || die "jq not installed (brew install jq / apt install jq) - set-status.sh needs it too"
command -v curl >/dev/null || die "curl not installed - set-status.sh needs it"
[ -f "$SET_STATUS" ] || die "no set-status.sh next to this script ($CLAWLIGHT_DIR)"
git -C "$CLAWLIGHT_DIR" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$CLAWLIGHT_DIR is not inside a git clone - run this from the clone, not scp'd copies (README: three debugging rounds went on stale copies)"

# A hook command has no shell profile, so the env has to be embedded in the
# command itself. Values are read back out of the existing hooks the same way
# setup-mac-focus-agent.sh does it, so a re-run keeps what is already there.
existing_cmds=""
[ -f "$SETTINGS" ] && existing_cmds="$(jq -r '.hooks | .. | .command? // empty' "$SETTINGS" 2>/dev/null | grep set-status.sh || true)"
[ -n "$server_url" ] || server_url="$(printf '%s\n' "$existing_cmds" | grep -o 'CLAWLIGHT_SERVER_URL=[^ ]*' | head -1 | cut -d= -f2-)"
[ -n "$host_name" ]  || host_name="$(printf '%s\n' "$existing_cmds" | grep -o 'CLAWLIGHT_HOST_NAME=[^ ]*'  | head -1 | cut -d= -f2-)"
[ -n "$server_url" ] || server_url="http://localhost:8126"
[ -n "$host_name" ]  || host_name="$(hostname)"

# The label is a JSON string in a shell command line in a JSON file, and it is
# also what focus/phone-jump route on. Keep it to something that survives all
# three unquoted rather than discovering it half-works later.
case "$host_name" in
  *[!A-Za-z0-9_.-]* | "") die "host name '$host_name' must be letters, digits, dot, dash or underscore - it goes in a hook command line unquoted" ;;
esac

say "clone:        $CLAWLIGHT_DIR"
say "server:       $server_url"
say "host label:   $host_name"
say "settings:     $SETTINGS"
say

# --- is the server actually there? ------------------------------------------
# Checked before writing anything: hooks that point at an unreachable server
# fail silently by design (set-status.sh swallows errors so a network hiccup
# never breaks a turn), so a typo here would show up as "the light just never
# mentions this machine" and nothing else.
if curl -fsS -m 5 "$server_url/clawlight/api/status" >/dev/null 2>&1; then
  say "server is reachable"
else
  die "cannot reach $server_url/clawlight/api/status
       On a machine that is not xero this is usually Tailscale being down, or
       the wrong tailnet suffix. Fix that first - hooks pointing at an
       unreachable server fail silently and look like nothing happened."
fi

# --- build the ten hooks ------------------------------------------------------
env_prefix="CLAWLIGHT_SERVER_URL=$server_url CLAWLIGHT_HOST_NAME=$host_name "
new_hooks="$(jq -n --arg prefix "$env_prefix" --arg script "$SET_STATUS" --argjson map "$HOOK_MAP" '
  $map | to_entries | map({
    key: .key,
    value: [ (if .key == "PostToolUse" then {matcher: "*"} else {} end)
             + {hooks: [{type: "command", command: ($prefix + $script + " " + .value)}]} ]
  }) | from_entries')" || die "could not build the hooks JSON"

old_json='{}'
[ -f "$SETTINGS" ] && { old_json="$(jq . "$SETTINGS")" || die "$SETTINGS is not valid JSON - fix or move it first"; }

# Strip any existing set-status.sh hooks (so a re-run re-points rather than
# duplicates), leave every other hook on those events alone, then append ours.
new_json="$(printf '%s' "$old_json" | jq --argjson new "$new_hooks" '
  .hooks = ((.hooks // {})
    | with_entries(.value |= ( map(.hooks |= map(select((.command // "") | test("set-status\\.sh") | not)))
                             | map(select((.hooks // []) | length > 0)) ))
    | with_entries(select((.value | length) > 0)))
  | .hooks = reduce ($new | to_entries[]) as $e (.hooks; .[$e.key] = ((.[$e.key] // []) + $e.value))
')" || die "could not rewrite the hooks (jq 1.6+ needed)"

removed="$(printf '%s\n' "$existing_cmds" | grep -c . || true)"
say "clawlight hooks already present: ${removed:-0}   ->   writing 10"
say
say "each hook will run:"
say "  $env_prefix$SET_STATUS <state>"
say "events: $(printf '%s' "$HOOK_MAP" | jq -r 'to_entries | map("\(.key)->\(.value)") | join(", ")')"

if [ "$dry_run" = 1 ]; then
  say
  say "--- settings.json would become: ---"
  printf '%s\n' "$new_json" | jq '.hooks'
  say
  say "dry run - nothing changed"
  exit 0
fi

# --- write it ------------------------------------------------------------------
mkdir -p "$(dirname "$SETTINGS")"
if [ -f "$SETTINGS" ]; then
  backup="$SETTINGS.bak-clawlight-$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$backup"
  say
  say "backup:       $backup"
fi
printf '%s\n' "$new_json" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
jq -e . "$SETTINGS" >/dev/null || die "wrote invalid JSON to $SETTINGS - restore from the backup above"
chmod +x "$SET_STATUS"

# --- prove it, rather than claiming it ------------------------------------------
# Hooks only load when a session starts, so this session cannot demonstrate
# them. Run set-status.sh by hand with the same env and the same stdin shape
# Claude Code uses, and check the machine actually appears on the light.
say
say "testing the report path end to end..."
test_id="clawlight-setup-$$"
printf '{"session_id":"%s","cwd":"%s"}' "$test_id" "$CLAWLIGHT_DIR" \
  | CLAWLIGHT_SERVER_URL="$server_url" CLAWLIGHT_HOST_NAME="$host_name" bash "$SET_STATUS" active

# The status API calls the session id `id`, not `session_id` (the field name
# the report is POSTed under) - matching on the wrong one reads as "the report
# never arrived" when it arrived perfectly.
seen="$(curl -fsS -m 5 "$server_url/clawlight/api/status" \
        | jq -r --arg id "$test_id" '.sessions[]? | select(.id == $id) | .host' 2>/dev/null)"

# Clear the test session either way - a stray `active` would hold the light
# green for the server's 30-minute staleness window.
printf '{"session_id":"%s"}' "$test_id" \
  | CLAWLIGHT_SERVER_URL="$server_url" CLAWLIGHT_HOST_NAME="$host_name" bash "$SET_STATUS" end

[ "$seen" = "$host_name" ] \
  || die "the report did not arrive (server saw '${seen:-nothing}', expected '$host_name').
       Hooks are written, but something between here and $server_url is dropping it."
say "  the server saw host='$host_name' - this machine is now known to clawlight"

say
say "Done. Hooks load when a session STARTS, so this one still has the old"
say "config - open a new Claude Code session for the light to follow it."
say "Check with:  curl -s $server_url/clawlight/api/status | jq '.sessions'"
case "$(uname)" in
  Darwin) say
          say "Optional next: jump-to-console from the light, on this Mac -"
          say "  bash $CLAWLIGHT_DIR/setup-mac-focus-agent.sh" ;;
esac
