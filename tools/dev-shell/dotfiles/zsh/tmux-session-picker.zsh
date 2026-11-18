# ---------------------------------------------------------------------------
# tmux session picker
#
# Runs when an interactive iTerm shell starts *outside* tmux - a local tab, or
# an ssh login from one (iTerm's LC_TERMINAL=iTerm2 rides along over ssh, since
# macOS ssh sends LC_* and sshd accepts it). Never attaches on its own -- it
# lists the running sessions and waits for a choice: a number to attach, "s"
# to ssh somewhere (the one time a tab skips tmux on purpose; not offered in a
# shell that itself arrived over ssh), "n" to create a session you name, or
# Enter/"!" to stay in a plain shell.
#
# Sourced from the very top of ~/.zshrc, above the powerlevel10k instant-prompt
# block (code that reads from the console has to live above it).
#
# Escape hatch: NO_TMUX=1
# ---------------------------------------------------------------------------

_tmux_unique_name() {
  local base=$1 name=$1 n=2
  while tmux has-session -t "=$name" 2>/dev/null; do
    name="$base-$n"; (( n++ ))
  done
  print -r -- "$name"
}

# Where to look for project directories when guessing a session's start dir.
: ${TMUX_PROJECT_ROOT:=$HOME/code}

# Offered by the picker's ssh option; "n" there takes any other user@host.
# wol is by IP: its name does not resolve from the Mac (known issue).
(( ${+TMUX_PICKER_SSH_HOSTS} )) || TMUX_PICKER_SSH_HOSTS=(pramod@xero.local pramod@192.168.1.124)

# Pick or type an ssh destination and connect. Not exec'd: when ssh ends -- or
# fails to connect -- the tab carries on into a plain local shell, so an error
# stays on screen instead of closing the tab.
_tmux_ssh() {
  local h choice i=0
  for h in $TMUX_PICKER_SSH_HOSTS; do
    (( i++ ))
    printf '     %s%d%s) %s\n' $'\e[32m' $i $'\e[0m' "$h"
  done
  printf '     %sn%s) new host\n' $'\e[32m' $'\e[0m'
  while true; do
    read -r "choice?  ssh to [1]: " || return 1
    choice=${choice:-1}
    case $choice in
      <1-99>)
        if (( choice <= $#TMUX_PICKER_SSH_HOSTS )); then
          ssh $TMUX_PICKER_SSH_HOSTS[choice]
          return
        fi
        print -P "  %F{red}no host $choice%f"
        ;;
      n|N)
        read -r "choice?  user@host: " || return 1
        [[ -z $choice ]] && continue
        ssh ${(z)choice}                          # extra words, e.g. -p 2222, pass through
        return
        ;;
      *)
        # a typed user@host works here too, without going through n
        ssh ${(z)choice}
        return
        ;;
    esac
  done
}

# Best guess at a start directory for a session called $1.
_tmux_guess_dir() {
  local hit
  hit=$(find "$TMUX_PROJECT_ROOT" -maxdepth 3 -type d \
          \( -name node_modules -o -name .git -o -name target \) -prune -o \
          -type d -name "$1" -print 2>/dev/null | head -1)
  if [[ -n $hit ]]; then
    print -r -- "$hit"
  elif [[ $PWD != $HOME ]]; then
    print -r -- "$PWD"
  else
    print -r -- "$TMUX_PROJECT_ROOT"
  fi
}

# Bring up zsh's completion system just for the directory prompt. Only called
# when a session is actually being created, so it costs nothing on the common
# attach / plain-shell paths (oh-my-zsh runs compinit again later either way).
_tmux_init_dir_completion() {
  (( $+functions[_tmuxdir_complete_setup_done] )) && return 0

  autoload -Uz compinit 2>/dev/null && compinit -C 2>/dev/null || return 1
  zle -C _tmuxdir_complete complete-word _generic 2>/dev/null || return 1
  zstyle ':completion:_tmuxdir_complete:*' completer _files
  zstyle ':completion:_tmuxdir_complete:*' file-patterns '*(-/):directories'
  zstyle ':completion:_tmuxdir_complete:*' squeeze-slashes true
  zstyle ':completion:_tmuxdir_complete:*' menu select

  # private keymap, so the global Tab binding is left alone
  bindkey -N tmuxdir emacs
  bindkey -M tmuxdir '^I' _tmuxdir_complete

  _tmuxdir_complete_setup_done() { : }
  return 0
}

# Read a directory into $_tmux_dir_reply, pre-filled with $1 and Tab-completable.
_tmux_read_dir() {
  _tmux_dir_reply=$1
  if _tmux_init_dir_completion; then
    vared -M tmuxdir -p "  start directory (Tab completes): " _tmux_dir_reply || return 1
    print
  else
    # completion unavailable for some reason -- fall back to a plain prompt
    read -r "_tmux_dir_reply?  start directory [${1/#$HOME/~}]: " || return 1
    _tmux_dir_reply=${_tmux_dir_reply:-$1}
  fi
}

_tmux_new_named_session() {
  local default name dir

  default=${PWD:t}
  [[ $PWD == $HOME ]] && default=main
  default=$(_tmux_unique_name "$default")

  while true; do
    read -r "name?  name for the new session [$default]: " || return 1
    name=${name:-$default}
    name=${name//[^a-zA-Z0-9_.-]/-}
    [[ -z $name ]] && continue
    if tmux has-session -t "=$name" 2>/dev/null; then
      print -P "  %F{red}'$name' already exists%f -- pick another name or attach to it instead."
      continue
    fi
    break
  done

  local _tmux_dir_reply
  local guess=$(_tmux_guess_dir "$name")
  while true; do
    _tmux_read_dir "$guess" || return 1
    dir=${~_tmux_dir_reply}                       # expand ~ and globs
    # a bare relative path is taken as relative to $TMUX_PROJECT_ROOT
    [[ $dir != /* && -d $TMUX_PROJECT_ROOT/$dir ]] && dir=$TMUX_PROJECT_ROOT/$dir
    if [[ ! -d $dir ]]; then
      print -P "  %F{red}no such directory:%f $dir"
      guess=$dir
      continue
    fi
    exec tmux new-session -s "$name" -c "$dir"
  done
}

_tmux_session_picker() {
  local -a rows sessions attached
  # ':' separates the fields, not a tab: tmux 3.4 (xero) prints a tab in -F
  # output as '_'. A session name cannot hold ':' (tmux swaps it for '_'), and
  # the timestamp, which does, is the last field and is joined back up below.
  rows=( ${(f)"$(tmux ls -F '#{session_name}:#{session_windows}:#{?session_attached,attached,detached}:#{t:session_activity}' 2>/dev/null)"} )

  print
  if (( $#rows )); then
    local row when i=0
    local -a f
    for row in $rows; do
      f=( ${(s.:.)row} )
      f[4]=${(j.:.)f[4,-1]}
      sessions+=( $f[1] )
      attached+=( $f[3] )
      when=${f[4][5,16]}          # "Thu Sep 10 13:03:01 2026" -> "Sep 10 13:03"
      (( i++ ))
      printf '   %s%2d%s) %-26s %s%s win  %-8s  %s%s\n' \
             $'\e[32m' $i $'\e[0m' "$f[1]" $'\e[90m' "$f[2]" "$f[3]" "$when" $'\e[0m'
    done
  else
    print -P "   %F{242}(no tmux sessions running)%f"
  fi
  # Already on the far end of an ssh login (xero, from the Mac): hopping on from
  # here is not wanted, so the menu has no ssh option.
  local offer_ssh=1
  [[ -n $SSH_CONNECTION ]] && offer_ssh=0
  if (( offer_ssh )); then
    printf '    %ss%s) ssh   ' $'\e[32m' $'\e[0m'
  else
    printf '    '
  fi
  printf '%sn%s) new session   %sEnter%s) plain shell, no tmux\n' \
         $'\e[32m' $'\e[0m' $'\e[32m' $'\e[0m'

  local choice target
  while true; do
    read -r "choice?  > " || return 0
    case $choice in
      ''|'!')      return 0 ;;
      s|S)         (( offer_ssh )) && { _tmux_ssh; return 0 }
                   print -P "  %F{red}?%f  no ssh from here -- number to attach, n for new, Enter for plain shell" ;;
      n|N)         _tmux_new_named_session; return 0 ;;
      <1-999>)
        if (( choice >= 1 && choice <= $#sessions )); then
          target=${sessions[choice]}
          # already open in another tab? give this one an independent view of the
          # same windows instead of mirroring it (tmux session groups)
          if [[ $attached[choice] == attached ]]; then
            print -P "  %F{242}'$target' is open in another tab -- attaching an independent view of it%f"
            exec tmux new-session -t "=$target"
          fi
          exec tmux attach -t "=$target"
        fi
        print -P "  %F{red}no session $choice%f"
        ;;
      *) local hint=" s for ssh,"; (( offer_ssh )) || hint=
         print -P "  %F{red}?%f  number to attach,$hint n for new, Enter for plain shell" ;;
    esac
  done
}

# TERM_PROGRAM is iTerm's own and does not cross ssh; LC_TERMINAL does.
# LC_TMUX_PICKER=1 opts any other client in - Termius sets it per host
# (Host > Environment Variables), and sshd's stock AcceptEnv LC_* lets it in.
if [[ -o interactive && -t 0 && -z $TMUX && -z $NO_TMUX \
      && ( $TERM_PROGRAM == "iTerm.app" || $LC_TERMINAL == "iTerm2" || $LC_TMUX_PICKER == 1 ) ]] \
   && (( $+commands[tmux] )); then
  _tmux_session_picker
fi
