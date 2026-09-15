#!/usr/bin/env bash
# For every file in scripts/, list everything that refers to it - inside the
# repo AND in the places that call scripts by absolute path from outside it:
# the live crontab, installed systemd units, Home Assistant's gitignored config,
# shell dotfiles, Claude Code hooks, and running processes.
#
# Written for the scripts/ reorganisation (2026-09-15) so that nothing called
# from cron or a service gets moved blind, and meant to be re-run after a move:
# any reference still pointing at the old path shows up here.
#
#   ./scripts/find_script_references.sh            # table for every script
#   ./scripts/find_script_references.sh wled.sh    # one script, full detail
#
# Known blind spots, printed at the end rather than silently skipped: root's
# crontab (needs sudo), and whatever runs on the Pi or the Mac. Those machines
# run their own deployed copies, so a move on xero breaks the deploy script's
# source path (which IS in the repo, and shows up here) but not the running
# service.
set -u
cd "$(dirname "$0")/.." || exit 1
repo="$PWD"

# Each source must come out as ONE line - label, tab, content with newlines
# flattened. The first version printed multi-line content, so only a file's
# first line carried its label and every later match was misfiled as a repo
# reference: installed systemd units running scripts/ showed as not live.
one() { printf '%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\n\t' '  ')"; }

external_sources() {
  one crontab "$(crontab -l 2>/dev/null)"
  for f in /etc/crontab /etc/cron.d/*; do [ -r "$f" ] && one "cron:$f" "$(cat "$f")"; done
  for f in "$HOME"/.config/systemd/user/*.service "$HOME"/.config/systemd/user/*.timer \
           /etc/systemd/system/*.service /etc/systemd/system/*.timer; do
    [ -r "$f" ] && grep -q "$repo" "$f" 2>/dev/null && one "unit:$f" "$(cat "$f")"
  done
  for f in "$HOME"/.zshrc "$HOME"/.profile "$HOME"/.bashrc "$HOME"/.zprofile "$HOME"/.claude/settings.json; do
    [ -r "$f" ] && one "home:$f" "$(cat "$f")"
  done
  one processes "$(ps -eo args 2>/dev/null | grep -F "$repo" | grep -v -E 'find_script_references|grep')"
}

ext="$(external_sources)"

# HA config is gitignored, so git grep never sees it. Skip the DB and logs.
ha_hits() {
  grep -rIl --exclude='*.db*' --exclude='*.log*' --exclude-dir='deps' --exclude-dir='tts' \
    -F "$1" HOMEASSISTANT_CONFIG 2>/dev/null | sed 's/^/HA:/'
}

scan_one() {
  local name="$1" stem="${1%.*}"
  local repo_hits ext_hits ha
  # Python modules are imported by stem, not by filename.
  repo_hits="$(git grep -l -F -e "$name" -- ':!scripts/find_script_references.sh' 2>/dev/null
               [ "${name##*.}" = py ] && git grep -l -E "import ${stem}\b|from ${stem} import" 2>/dev/null)"
  repo_hits="$(printf '%s\n' "$repo_hits" | grep -v "^scripts/$name$" | sort -u | grep -v '^$')"
  ext_hits="$(printf '%s\n' "$ext" | awk -F'\t' -v n="$name" 'index($0,n){print $1}' | sort -u)"
  ha="$(ha_hits "$name")"
  printf '%s\n%s\n%s\n' "$repo_hits" "$ext_hits" "$ha" | grep -v '^$'
}

if [ $# -gt 0 ]; then
  for n in "$@"; do echo "== $n"; scan_one "$n" | sed 's/^/  /'; done
  exit 0
fi

for f in scripts/*; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  hits="$(scan_one "$n")"
  # A hit from cron/ or systemd/ in the repo is live one hop removed: crontab
  # calls cron/*.sh, and those call scripts/ - so they count as live too.
  live_re='^(crontab|cron:|unit:|home:|processes|HA:|cron/|systemd/)'
  live="$(printf '%s\n' "$hits" | grep -E "$live_re" | tr '\n' ' ')"
  docs="$(printf '%s\n' "$hits" | grep -v -E "$live_re" | tr '\n' ' ')"
  printf '%s\n  LIVE: %s\n  REPO: %s\n' "$n" "${live:--}" "${docs:--}"
done

echo
echo "Not scanned: root's crontab (sudo), and the Pi/Mac, which run deployed copies."
