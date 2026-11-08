#!/usr/bin/env bash
# Apply (or just check) the iTerm profile settings the tmux mouse setup needs.
#
# This closes the gap that setup-tmux-shell.sh leaves: that script installs
# tmux.conf and the zsh bits, but the mouse design in tmux.conf only works if
# iTerm is told to keep clicks and drags for itself. Until 2026-11-08 the README
# just said "set these by hand in iTerm. The script cannot", and on this MacBook
# they were never set - so a plain drag made no selection, while Option-drag
# (which forces iTerm to keep the drag) worked. That is the signature.
#
# Why these values -- the full reasoning is the comment at the top of
# dotfiles/tmux/tmux.conf. Short version: tmux needs the mouse or nothing
# scrolls, but iTerm only makes a Cmd-C-able selection when it keeps the drag.
# Reporting the wheel but not clicks and drags splits them: tmux gets the
# wheel, iTerm keeps selection.
#
#   Mouse Reporting                        true   wheel reaches tmux
#   Mouse Reporting allow clicks and drags false  iTerm keeps drags = selection
#                                                 (UI: "Don't report clicks and
#                                                 drags", Profiles > Terminal)
#   Allow Alternate Mouse Scroll           true   wheel still works with mouse off
#   AllowClipboardAccess (global)          true   OSC 52, so a tmux-side copy
#                                                 reaches the system clipboard
#
# Usage:
#   setup-iterm-mouse.sh            # check only, safe any time
#   setup-iterm-mouse.sh --apply    # write them (iTerm must be quit)
set -uo pipefail

plist=$HOME/Library/Preferences/com.googlecode.iterm2.plist
mode=check
[[ ${1:-} == --apply ]] && mode=apply
[[ ${1:-} == --check || -z ${1:-} ]] || [[ $mode == apply ]] || {
  echo "usage: $0 [--check|--apply]" >&2; exit 2; }

[[ -r $plist ]] || { echo "No iTerm prefs at $plist - is iTerm installed?" >&2; exit 1; }

# iTerm keeps prefs in memory and rewrites the plist when it quits, so editing
# the file underneath a running iTerm silently loses the change.
if [[ $mode == apply ]] && pgrep -xq iTerm2; then
  cat >&2 <<'EOF'
iTerm is running. It rewrites this plist when it quits, which would discard
anything written now. Either:
  * quit iTerm completely, re-run with --apply, then reopen it; or
  * set it in the UI (takes effect immediately, no restart):
      Settings > Profiles > Terminal > Mouse reporting
        [x] Don't report clicks and drags
    and repeat per profile you use.
EOF
  exit 1
fi

MODE=$mode PLIST=$plist python3 - <<'PY'
import os, plistlib, pathlib, sys

want = {
    "Mouse Reporting": True,
    "Mouse Reporting allow clicks and drags": False,
    "Allow Alternate Mouse Scroll": True,
}
mode = os.environ["MODE"]
p = pathlib.Path(os.environ["PLIST"])
d = plistlib.loads(p.read_bytes())
profiles = d.get("New Bookmarks", [])
default_guid = d.get("Default Bookmark Guid")
bad = changed = 0

for pr in profiles:
    tag = " (default)" if pr.get("Guid") == default_guid else ""
    print(f"profile {pr.get('Name','?')!r}{tag}")
    for k, v in want.items():
        cur = pr.get(k, "<absent, iTerm default>")
        ok = (cur is v)
        if not ok:
            bad += 1
            if mode == "apply":
                pr[k] = v
                changed += 1
        mark = "ok  " if ok else ("set " if mode == "apply" else "WRONG")
        print(f"  {mark} {k} = {cur}" + ("" if ok else f"   -> want {v}"))

clip = d.get("AllowClipboardAccess", "<absent>")
ok = clip in (True, 1)
if not ok:
    bad += 1
    if mode == "apply":
        d["AllowClipboardAccess"] = True
        changed += 1
print(f"global\n  {'ok  ' if ok else ('set ' if mode=='apply' else 'WRONG')} "
      f"AllowClipboardAccess = {clip}" + ("" if ok else "   -> want True"))

if mode == "apply" and changed:
    backup = p.with_suffix(p.suffix + ".bak-itermmouse")
    backup.write_bytes(p.read_bytes())
    p.write_bytes(plistlib.dumps(d))
    print(f"\nwrote {changed} change(s); backup at {backup}")
    sys.exit(0)

if mode == "apply":
    print("\nnothing to change")
    sys.exit(0)

sys.exit(1 if bad else 0)
PY
rc=$?

if [[ $mode == apply && $rc == 0 ]]; then
  # cfprefsd caches the old values and would hand them back to iTerm on launch.
  killall cfprefsd 2>/dev/null
  echo "flushed cfprefsd; reopen iTerm and a plain drag should select again"
elif [[ $mode == check && $rc != 0 ]]; then
  cat <<'EOF'

Fix with --apply (iTerm quit), or in the UI with iTerm running:
  Settings > Profiles > Terminal > Mouse reporting
    [x] Don't report clicks and drags

Signature of this being wrong: a plain drag selects nothing, but Option-drag
does - Option forces iTerm to keep the drag instead of reporting it to tmux.
EOF
fi
exit $rc
