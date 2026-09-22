# Name each Claude Code session after the tmux session it runs in, so /resume,
# the clawlight page and the Pi's clock all say `clock` rather than guessing
# from the directory. Source it from ~/.zshrc (bash works too):
#
#   source ~/code/homelab/clawlight/claude-tmux-name.zsh
#
# Claude Code has no hook or setting for the session name - `claude -n` at
# launch is the only way in (checked 2.1.278) - hence a wrapper function.
# A grouped session's own name carries a `-N` suffix, so the group name wins.
#
# Left alone: outside tmux, an explicit -n/--name, a resume (-c/-r keeps the
# name the session already has), and subcommands/--help/--version, which
# don't take -n.
claude() {
  local arg
  if [ -n "${TMUX:-}" ] && { [ $# -eq 0 ] || [ "${1#-}" != "$1" ]; }; then
    for arg in "$@"; do
      case "$arg" in
        -n | --name | --name=* | -c | --continue | -r | --resume | --resume=* \
          | -h | --help | -v | --version) command claude "$@"; return ;;
      esac
    done
    local name
    name="$(tmux display-message -p '#{?session_group,#{session_group},#{session_name}}' 2>/dev/null)"
    if [ -n "$name" ]; then
      command claude -n "$name" "$@"
      return
    fi
  fi
  command claude "$@"
}
