_zellij_login_hook() {
  [[ -o interactive ]]                            || return 0
  [[ -n $SSH_TTY ]]                               || return 0
  [[ -z $ZELLIJ ]]                                || return 0
  [[ -z $ZELLIJ_LOGIN_SKIP ]]                     || return 0
  [[ -z $VSCODE_IPC_HOOK_CLI ]]                   || return 0
  [[ -z $CURSOR_SESSION_ID ]]                     || return 0
  [[ $TERM_PROGRAM != vscode ]]                   || return 0
  [[ $TERMINAL_EMULATOR != JetBrains-JediTerm ]]  || return 0
  [[ -z $ZELLIJ_LOGIN_HOOK_DONE ]]                || return 0
  export ZELLIJ_LOGIN_HOOK_DONE=1

  command -v zellij >/dev/null 2>&1 || { print -u2 "zellij-login: zellij not on PATH"; return 0; }
  command -v fzf    >/dev/null 2>&1 || { print -u2 "zellij-login: fzf not on PATH"; return 0; }

  local SKIP_SESSION="[ skip · plain shell ]"
  local NEW_SESSION="[+ new session ]"
  local choice name target picked key sub r
  local -a roots walker_args fzf_out

  # Skip is the first (default-highlighted) item so that Enter on an empty
  # query lands you in a normal shell with no zellij involvement.
  choice=$(
    { print -- "$SKIP_SESSION"; print -- "$NEW_SESSION"; zellij list-sessions --short 2>/dev/null; } \
    | fzf --height=40% --reverse --prompt="zellij session > " --no-multi \
        --header-first --header="enter = pick highlighted · esc = skip"
  )
  [[ -z $choice || $choice == "$SKIP_SESSION" ]] && return 0

  # Warp wraps the shell in a per-tab ZDOTDIR (warptmp.XXXXXX) whose .zshrc
  # chain-sources the real ~/.zshrc. Inside a multiplexer PTY that chain can
  # deadlock waiting on terminal-integration handshakes the multiplexer doesn't
  # pass through, leaving Warp stuck on "Starting shell...". Dropping the
  # override lets the zellij session source $HOME/.zshrc directly. No-op for
  # non-Warp users and for anyone with a deliberate XDG-style ZDOTDIR.
  [[ $ZDOTDIR == */warptmp.* ]] && unset ZDOTDIR

  if [[ $choice != "$NEW_SESSION" ]]; then
    zellij attach -c "$choice"
    return 0
  fi

  print -n "new session name: "
  read -r name || return 0
  [[ -z $name ]] && return 0

  if [[ -n $ZELLIJ_LOGIN_ROOTS ]]; then
    roots=(${(s.:.)ZELLIJ_LOGIN_ROOTS})
  else
    roots=()
    for r in "$HOME/research" "$HOME/dev" "$HOME/code" "$HOME/projects" "$HOME/Developer" "$HOME/src" "$HOME/work"; do
      [[ -d $r ]] && roots+=("$r")
    done
  fi
  (( ${#roots} )) || roots=("$HOME")

  walker_args=(--walker=dir --walker-skip=".git,node_modules,.cache,Library,.Trash,.cargo,.rustup,.npm")
  for r in "${roots[@]}"; do
    walker_args+=(--walker-root="$r")
  done

  fzf_out=("${(@f)$(
    fzf "${walker_args[@]}" \
        --height=60% --reverse \
        --prompt="dir for '$name' > " \
        --header="Enter=pick · Ctrl-N=subdir under highlighted · Esc=cancel" \
        --expect=ctrl-n
  )}")
  key=${fzf_out[1]}
  picked=${fzf_out[2]}
  [[ -z $picked ]] && return 0

  if [[ $key == ctrl-n ]]; then
    print -n "new subdir under $picked: "
    read -r sub || return 0
    [[ -z $sub ]] && return 0
    mkdir -p -- "$picked/$sub" || { print -u2 "zellij-login: mkdir failed"; return 0; }
    target="$picked/$sub"
  else
    target=$picked
  fi

  cd -- "$target" || return 0

  # Prefer our minimal "shell with persistence" layout if the installer placed
  # it. Falls back to the user's default_layout when the file isn't there
  # (e.g., they ran the installer with --no-zellij-config).
  local -a zj_args
  zj_args=(attach -c "$name")
  [[ -r ${ZELLIJ_CONFIG_DIR:-$HOME/.config/zellij}/layouts/zellij-login.kdl ]] \
    && zj_args+=(--layout zellij-login)
  zellij "${zj_args[@]}"
}

_zellij_login_hook
unset -f _zellij_login_hook
