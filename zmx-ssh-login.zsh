_zmx_login_hook() {
  [[ -o interactive ]]                            || return 0
  [[ -n $SSH_TTY ]]                               || return 0
  [[ -z $ZMX_SESSION ]]                           || return 0
  [[ -z $ZMX_LOGIN_SKIP ]]                        || return 0
  [[ -z $VSCODE_IPC_HOOK_CLI ]]                   || return 0
  [[ -z $CURSOR_SESSION_ID ]]                     || return 0
  [[ $TERM_PROGRAM != vscode ]]                   || return 0
  [[ $TERMINAL_EMULATOR != JetBrains-JediTerm ]]  || return 0
  [[ -z $ZMX_LOGIN_HOOK_DONE ]]                   || return 0
  export ZMX_LOGIN_HOOK_DONE=1

  command -v zmx >/dev/null 2>&1 || { print -u2 "zmx-login: zmx not on PATH"; return 0; }
  command -v fzf >/dev/null 2>&1 || { print -u2 "zmx-login: fzf not on PATH"; return 0; }

  local SKIP_SESSION="[ skip · plain shell ]"
  local NEW_SESSION="[+ new session ]"
  local choice name target picked key sub r
  local -a roots walker_args fzf_out

  # Skip is the first (default-highlighted) item so that Enter on an empty
  # query lands you in a normal shell with no zmx involvement.
  choice=$(
    { print -- "$SKIP_SESSION"; print -- "$NEW_SESSION"; zmx list --short 2>/dev/null; } \
    | fzf --height=40% --reverse --prompt="zmx session > " --no-multi \
        --header-first --header="enter = pick highlighted · esc = skip"
  )
  [[ -z $choice || $choice == "$SKIP_SESSION" ]] && return 0

  if [[ $choice != "$NEW_SESSION" ]]; then
    zmx attach "$choice"
    return 0
  fi

  print -n "new session name: "
  read -r name || return 0
  [[ -z $name ]] && return 0

  if [[ -n $ZMX_LOGIN_ROOTS ]]; then
    roots=(${(s.:.)ZMX_LOGIN_ROOTS})
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
    mkdir -p -- "$picked/$sub" || { print -u2 "zmx-login: mkdir failed"; return 0; }
    target="$picked/$sub"
  else
    target=$picked
  fi

  cd -- "$target" || return 0
  zmx attach "$name"
}

_zmx_login_hook
unset -f _zmx_login_hook
