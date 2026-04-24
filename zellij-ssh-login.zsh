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
  local CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-login"
  local choice name target picked key sub r ts
  local -a roots fzf_out

  # Portable file-mtime (macOS BSD stat vs GNU stat).
  _zl_mtime() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || print -- 0
  }

  # Touch $CACHE_DIR/attached/<name> so the next picker sorts it to the top.
  # Cheap: a single zero-byte file per session.
  _zl_record_attach() {
    mkdir -p -- "$CACHE_DIR/attached"
    : > "$CACHE_DIR/attached/$1"
  }

  # Record the starting directory of a new session so B1's preview pane (and
  # future duplicates) can show "where does this session live".
  _zl_record_cwd() {
    mkdir -p -- "$CACHE_DIR/cwds"
    print -- "$2" > "$CACHE_DIR/cwds/$1"
  }

  # Push $1 to the top of the MRU dir list, deduped, capped at 50.
  _zl_record_recent_dir() {
    mkdir -p -- "$CACHE_DIR"
    local file="$CACHE_DIR/recent_dirs" tmp="$CACHE_DIR/.recent_dirs.tmp"
    { print -- "$1"; [[ -f $file ]] && awk -v d="$1" '$0 != d' "$file"; } \
      | awk 'NF' | head -50 > "$tmp" && mv -- "$tmp" "$file"
  }

  # Live sessions from zellij, sorted descending by $CACHE_DIR/attached mtime
  # (sessions never attached-via-this-hook fall to mtime=0, keeping zellij's
  # own order for the tail). Stale cache entries for killed sessions are
  # ignored naturally — we only emit names zellij reports as live.
  _zl_sorted_sessions() {
    local live name ts
    live=$(zellij list-sessions --short 2>/dev/null)
    [[ -z $live ]] && return
    while IFS= read -r name; do
      [[ -z $name ]] && continue
      if [[ -f "$CACHE_DIR/attached/$name" ]]; then
        ts=$(_zl_mtime "$CACHE_DIR/attached/$name")
      else
        ts=0
      fi
      printf '%s\t%s\n' "$ts" "$name"
    done <<< "$live" | sort -rn -k1,1 | cut -f2-
  }

  # Dir candidates for the new-session picker: MRU entries first (existing
  # dirs only), then a bounded find over the configured roots with the same
  # skip patterns the previous `fzf --walker` used. awk dedupes.
  _zl_dir_candidates() {
    local r d
    if [[ -f "$CACHE_DIR/recent_dirs" ]]; then
      while IFS= read -r d; do
        [[ -d $d ]] && print -- "$d"
      done < "$CACHE_DIR/recent_dirs"
    fi
    for r in "${roots[@]}"; do
      find "$r" -maxdepth 5 \
        \( -name .git -o -name node_modules -o -name .cache -o -name Library \
           -o -name .Trash -o -name .cargo -o -name .rustup -o -name .npm \) -prune \
        -o -type d -print 2>/dev/null
    done
  }

  # Skip is the first (default-highlighted) item so that Enter on an empty
  # query lands you in a normal shell with no zellij involvement.
  choice=$(
    { print -- "$SKIP_SESSION"; print -- "$NEW_SESSION"; _zl_sorted_sessions; } \
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
    _zl_record_attach "$choice"
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

  fzf_out=("${(@f)$(
    _zl_dir_candidates | awk '!seen[$0]++' \
      | fzf --height=60% --reverse \
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
  _zl_record_recent_dir "$target"
  _zl_record_cwd "$name" "$target"
  _zl_record_attach "$name"

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
