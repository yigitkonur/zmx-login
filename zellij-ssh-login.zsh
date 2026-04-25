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

  # Portable file-mtime (GNU stat vs macOS BSD stat).
  # GNU first: on Linux `stat -f %m` misparses as filesystem-info mode (with
  # `%m` read as a FILE argument); the command exits non-zero AND emits
  # default filesystem info for the real file on stdout, so the || fallback
  # still runs but $(...) captures both outputs -> multi-line garbage.
  # `stat -c %Y` succeeds cleanly on Linux; BSD rejects `-c` and falls through.
  _zl_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || print -- 0
  }

  _zl_session_name_from_line() {
    local line="$1" parsed
    parsed=${line% \[Created *}
    [[ $parsed == "$line" ]] && parsed=${line%% *}
    print -r -- "$parsed"
  }

  _zl_valid_new_session_name() {
    [[ -n $1 ]] || return 1
    [[ $1 != . && $1 != .. ]] || return 1
    [[ $1 != */* ]] || return 1
    [[ $1 != *$'\n'* ]]
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

  # Live sessions, sorted desc by $CACHE_DIR/attached mtime, prefixed with a
  # status icon: ● for active sessions, ✗ for exited-but-resurrectable. We
  # parse `zellij list-sessions -n` (no-formatting form) because it contains
  # the EXITED marker; --short does not. The icon prefix is stripped by the
  # caller before the name goes back to zellij.
  # Keep the producer finite: fzf waits for EOF before accepting no-match Enter.
  _zl_list_sessions() {
    local tmp pid ticks max_ticks
    tmp="${TMPDIR:-/tmp}/zellij-login-sessions.$$.$RANDOM"
    : >| "$tmp" || return 0

    zellij list-sessions -n >| "$tmp" 2>/dev/null &
    pid=$!
    ticks=0
    max_ticks=20

    while kill -0 "$pid" 2>/dev/null; do
      if (( ticks >= max_ticks )); then
        kill "$pid" 2>/dev/null || true
        sleep 0.05
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f -- "$tmp"
        return 0
      fi
      sleep 0.05
      (( ticks += 1 ))
    done

    wait "$pid" 2>/dev/null || true
    [[ -r $tmp ]] && cat "$tmp"
    rm -f -- "$tmp"
  }

  _zl_sorted_sessions() {
    local line name ts icon
    _zl_list_sessions | while IFS= read -r line; do
      [[ -z $line ]] && continue
      name=$(_zl_session_name_from_line "$line")
      [[ -z $name ]] && continue
      if [[ $line == *EXITED* ]]; then
        icon='✗'
      else
        icon='●'
      fi
      if [[ -f "$CACHE_DIR/attached/$name" ]]; then
        ts=$(_zl_mtime "$CACHE_DIR/attached/$name")
      else
        ts=0
      fi
      printf '%s\t%s %s\n' "$ts" "$icon" "$name"
    done | sort -rn -k1,1 | cut -f2-
  }

  # Dir candidates for the new-session picker. Order matters — the first line
  # is where fzf's cursor lands, and users reported the old order felt like
  # "only the first root's subtree is there" because one root's 10k+ subdirs
  # flooded the list before any other root's depth-0 entry appeared.
  #
  # Now:
  #   1. $HOME first (so Enter-on-open lands you at ~, always).
  #   2. MRU entries that still exist on disk.
  #   3. Each configured root at depth 0 side-by-side, so the top of the list
  #      shows roots together instead of one root's subtree drowning the rest.
  #   4. Each root's immediate children (depth 1). Deeper paths are reachable
  #      via MRU (recent_dirs) if the user has picked them before, or via the
  #      ctrl-n "make subdir under highlighted" escape hatch in the picker.
  #      Cap chosen to keep the candidate list tractable: on a typical dev
  #      machine depth 5 is ~30k candidates and fzf fuzzy-ranks sub-sub-paths
  #      above actual project dirs for short queries.
  # awk '!seen[$0]++' downstream dedupes across all four sections.
  _zl_dir_candidates() {
    local r d
    print -- "$HOME"
    if [[ -f "$CACHE_DIR/recent_dirs" ]]; then
      while IFS= read -r d; do
        [[ -d $d ]] && print -- "$d"
      done < "$CACHE_DIR/recent_dirs"
    fi
    for r in "${roots[@]}"; do
      [[ -d $r ]] && print -- "$r"
    done
    for r in "${roots[@]}"; do
      find "$r" -mindepth 1 -maxdepth 1 \
        \( -name .git -o -name node_modules -o -name .cache -o -name Library \
           -o -name .Trash -o -name .cargo -o -name .rustup -o -name .npm \) -prune \
        -o -type d -print 2>/dev/null
    done
  }

  # Skip is the first (default-highlighted) item so that Enter on an empty
  # query lands you in a normal shell with no zellij involvement.
  # Preview pane (right side) renders session metadata — cwd, status,
  # created-ago, last-attached — via the installer-shipped helper script.
  # Destructive keys (ctrl-x / ctrl-k) are wired through the action helper
  # so they can be rerun and trigger a reload without shelling out to zsh.
  # Each helper is picked up at its default install prefix; if they're not
  # present (user installed with a custom --prefix) the picker still works
  # but the preview and key-bindings are silently absent.
  local _zl_datadir="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-login"
  local _zl_preview_script="$_zl_datadir/zellij-login-preview.sh"
  local _zl_action_script="$_zl_datadir/zellij-login-action.sh"
  # fzf passes these command strings to `sh -c`, so any shell metacharacter
  # in the path (most commonly a space in $HOME) has to be quoted for sh or
  # `sh /Users/John Doe/…` splits into `sh /Users/John` + bad argv.
  # ${(q)…} is zsh's built-in shell-quote; handles spaces, quotes, and $.
  local _zl_header="enter = pick/create · esc = skip"
  local _zl_preview_q=${(q)_zl_preview_script}
  local _zl_action_q=${(q)_zl_action_script}
  local -a _zl_binds _zl_preview_args
  if [[ -x $_zl_preview_script ]]; then
    # Only set --preview when we actually have a renderer — otherwise fzf
    # reserves an empty 40%-wide pane for a preview that never appears.
    _zl_preview_args=(
      "--preview=sh $_zl_preview_q {}"
      "--preview-window=right,40%,wrap"
    )
  fi
  if [[ -x $_zl_action_script ]]; then
    # +pos(2) after reload parks the cursor on the first real session (skip
    # is at 1, sessions start at 2, new-session is at the bottom). This
    # makes ctrl-x cascade: each keystroke kills what's at position 2, the
    # next session slides up, cursor stays on position 2 ready for the
    # next kill.
    _zl_binds=(
      "--bind=ctrl-x:execute-silent(sh $_zl_action_q kill {})+reload(sh $_zl_action_q list)+pos(2)"
      "--bind=ctrl-k:execute-silent(sh $_zl_action_q clean-dead)+reload(sh $_zl_action_q list)+pos(2)"
    )
    _zl_header="enter=pick/create · esc=skip · ctrl-x=kill/delete · ctrl-k=clean dead"
  fi
  # Order: skip first (so Enter-on-open is the safe default), sessions in
  # the middle (sorted by recency), new-session LAST — so after a kill
  # + reload the default cursor position never lands on "create new", which
  # would turn an accidental Enter into an unintended new-session flow.
  # --print-query makes fzf emit the current query on line 1 and any selected
  # item on line 2. That gives us "type-to-create": a query that matches no
  # session produces the query alone, which we take as the new session name
  # and dispatch straight to the dir picker — saving the user a redundant
  # "new session name:" prompt for a name they already typed.
  local raw fzf_rc
  if raw=$(
    { print -- "$SKIP_SESSION"; _zl_sorted_sessions; print -- "$NEW_SESSION"; } \
    | fzf --height=60% --reverse --prompt="zellij session > " --no-multi \
        --print-query \
        --header-first --header="$_zl_header" \
        "${_zl_preview_args[@]}" "${_zl_binds[@]}"
  ); then
    fzf_rc=0
  else
    fzf_rc=$?
  fi
  # fzf rc: 0 = selection, 1 = no-match + Enter (type-to-create),
  # 130 = Esc / Ctrl-C. --print-query emits the query on stdout regardless,
  # so without this rc check, Esc-after-typing would fall into the
  # type-to-create branch below and spawn an unintended session.
  (( fzf_rc == 130 )) && return 0
  (( fzf_rc == 0 || fzf_rc == 1 )) || return 0

  local -a picker_out=("${(@f)raw}")
  local query=${picker_out[1]:-} choice=${picker_out[2]:-}

  # Explicit skip sentinel (default-highlighted or fuzzy-matched via query).
  [[ $choice == "$SKIP_SESSION" ]] && return 0

  # Warp wraps the shell in a per-tab ZDOTDIR (warptmp.XXXXXX) whose .zshrc
  # chain-sources the real ~/.zshrc. Inside a multiplexer PTY that chain can
  # deadlock waiting on terminal-integration handshakes the multiplexer doesn't
  # pass through, leaving Warp stuck on "Starting shell...". Dropping the
  # override lets the zellij session source $HOME/.zshrc directly. No-op for
  # non-Warp users and for anyone with a deliberate XDG-style ZDOTDIR.
  [[ $ZDOTDIR == */warptmp.* ]] && unset ZDOTDIR

  if [[ -z $choice && -n $query ]]; then
    # Type-to-create: the query IS the new-session name. Skip the read prompt.
    name=$query
  elif [[ $choice == "$NEW_SESSION" ]]; then
    print -n "new session name: "
    read -r name || return 0
    [[ -z $name ]] && return 0
  else
    # Existing session selected; strip the status icon we added earlier.
    case $choice in
      "● "*) choice=${choice#"● "} ;;
      "✗ "*) choice=${choice#"✗ "} ;;
    esac
    _zl_record_attach "$choice"
    zellij attach -c -- "$choice"
    return 0
  fi

  if ! _zl_valid_new_session_name "$name"; then
    print -u2 "zellij-login: invalid session name: $name"
    return 0
  fi

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
  # --layout is a zellij-top-level flag, not an `attach` subcommand option —
  # it MUST come before `attach`, or zellij rejects the whole invocation.
  local -a zj_args
  zj_args=(zellij)
  [[ -r ${ZELLIJ_CONFIG_DIR:-$HOME/.config/zellij}/layouts/zellij-login.kdl ]] \
    && zj_args+=(--layout zellij-login)
  zj_args+=(attach -c -- "$name")
  "${zj_args[@]}"
}

_zellij_login_hook || true
unset -f _zellij_login_hook \
  _zl_mtime _zl_session_name_from_line _zl_valid_new_session_name \
  _zl_record_attach _zl_record_cwd _zl_record_recent_dir \
  _zl_list_sessions _zl_sorted_sessions _zl_dir_candidates \
  2>/dev/null || true
