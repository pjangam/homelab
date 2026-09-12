# ---------------------------------------------------------------------------
# Claude Code shell wrappers: never run it outside tmux without asking first.
#
# Installed to ~/.zsh/functions/claude-tmux.zsh by scripts/setup-tmux-shell.sh
# and sourced from ~/.zshrc. Edit the copy in the repo, then re-run the script -
# a hand-edit in $HOME is invisible to every other machine.
#
# Why: a long Claude run in a bare terminal tab dies with the tab (and with any
# ssh that carried it). Inside tmux it survives, and the session picker
# (tmux-session-picker.zsh) can get you back to it.
#
#   _tmux_or_ask <session> [VAR=VAL ...] -- <binary> [args...]
#
# Inside tmux  -> runs the command right here.
# Outside tmux -> prompts; y/Enter relaunches it in tmux (new window in an
#                 existing session of that name, else a fresh session),
#                 n runs it here anyway, q aborts.
# ---------------------------------------------------------------------------
_tmux_or_ask() {
  local sess=$1; shift
  local -a envs
  while [[ $# -gt 0 && $1 != "--" ]]; do envs+=(-e "$1"); shift; done
  shift  # drop the --

  if [[ -n $TMUX ]]; then
    "$@"
    return
  fi

  local ans
  print -u2 -P "%F{yellow}!%f ${1:t} is about to run outside tmux."
  read -k 1 "ans?  Run it in tmux session '${sess}' instead? [Y/n/q] "
  print -u2

  case $ans in
    n|N) "$@" ;;
    q|Q|$'\e') print -u2 "  aborted."; return 130 ;;
    *)
      if tmux has-session -t "=$sess" 2>/dev/null; then
        tmux new-window -t "=$sess" -c "$PWD" "${envs[@]}" "$@" && tmux attach -t "=$sess"
      else
        tmux new-session -s "$sess" -c "$PWD" "${envs[@]}" "$@"
      fi
      ;;
  esac
}

# ${commands[claude]} is the real binary, so this function can shadow its name
# without recursing into itself.
claude() {
  _tmux_or_ask "${PWD:t}" -- ${commands[claude]:-claude} "$@"
}

# Claude Code pointed at a local ollama instead of the API: no proxy, no
# telemetry, a small local model, and no MCP servers or write tools.
claude-local() {
  local -a llm_env=(
    HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy=
    NO_PROXY=127.0.0.1,localhost
    no_proxy=127.0.0.1,localhost
    ANTHROPIC_AUTH_TOKEN=ollama
    ANTHROPIC_API_KEY=
    ANTHROPIC_BASE_URL=http://127.0.0.1:11434
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
  )
  # exported for the "already in tmux" path; passed via -e for the relaunch path
  local kv; for kv in $llm_env; do export $kv; done

  _tmux_or_ask "${PWD:t}" $llm_env -- ${commands[claude]:-claude} \
    --model qwen2.5-coder:7b --tools "Read,Glob,Grep" \
    --strict-mcp-config --mcp-config '{"mcpServers":{}}' "$@"
}

# Mouse clicks in the Claude Code TUI steal iTerm's own selection/scroll
# behaviour; turning them off keeps copy-paste working the usual way.
export CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1
