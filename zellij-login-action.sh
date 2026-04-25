#!/bin/sh
# zellij-login fzf action helper. Invoked by `fzf --bind` in the session
# picker. POSIX sh so startup is quick (bound keys fire per-keystroke).
#
# Subcommands:
#   kill <picker-line>   Context-aware: live session → kill-session.
#                        Exited session → delete-session --force (nuke
#                        the resurrectable state too). Refuses to act on
#                        sentinels. Cleans our own cache entries for the
#                        session after.
#   clean-dead           Iterates all EXITED sessions and force-deletes
#                        each. Refresh with one keystroke at 32+ sessions.
#   list                 Emit the sorted picker list (same format the
#                        hook produces at startup) for fzf `reload()`.

set -eu

action=${1:-}
case "$action" in
  kill|clean-dead|list) ;;
  *) printf 'zellij-login-action: unknown subcommand: %s\n' "$action" >&2; exit 2 ;;
esac

cache="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-login"

list_sessions() {
  tmp=$(mktemp "${TMPDIR:-/tmp}/zellij-login-sessions.XXXXXX") || return 0
  zellij list-sessions -n > "$tmp" 2>/dev/null &
  pid=$!
  ticks=0

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge 20 ]; then
      kill "$pid" 2>/dev/null || true
      sleep 0.05
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f -- "$tmp"
      return 0
    fi
    sleep 0.05
    ticks=$((ticks + 1))
  done

  wait "$pid" 2>/dev/null || true
  [ -r "$tmp" ] && cat "$tmp"
  rm -f -- "$tmp"
}

session_name_from_line() {
  line=$1
  name=${line% \[Created *}
  [ "$name" = "$line" ] && name=${line%% *}
  printf '%s\n' "$name"
}

session_line_for_name() {
  wanted=$1
  list_sessions | while IFS= read -r line; do
    name=$(session_name_from_line "$line")
    [ "$name" = "$wanted" ] || continue
    printf '%s\n' "$line"
    break
  done
}

# emit_sorted_list: same shape as the hook's _zl_sorted_sessions. Duplicated
# here (~15 lines) rather than fetched from the hook — this helper is reached
# through fzf --bind subshells that don't inherit the hook's locals.
#
# Order MUST match the hook's initial-list pipeline: skip first (safe default
# for Enter-after-reload), real sessions in the middle (sorted desc by last-
# attached mtime), new-session LAST (so accidental Enter after a kill can't
# trigger the create-new-session flow).
emit_sorted_list() {
  printf '%s\n' "[ skip · plain shell ]"
  list_sessions | while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=$(session_name_from_line "$line")
    [ -z "$name" ] && continue
    case "$line" in
      *EXITED*) icon='✗' ;;
      *)        icon='●' ;;
    esac
    if [ -f "$cache/attached/$name" ]; then
      # GNU stat first — see zellij-login-preview.sh for why the order matters.
      ts=$(stat -c %Y "$cache/attached/$name" 2>/dev/null \
           || stat -f %m "$cache/attached/$name" 2>/dev/null \
           || echo 0)
    else
      ts=0
    fi
    printf '%s\t%s %s\n' "$ts" "$icon" "$name"
  done | sort -rn -k1,1 | cut -f2-
  printf '%s\n' "[+ new session ]"
}

strip_icon() {
  case "$1" in
    "● "*) printf '%s' "${1#"● "}" ;;
    "✗ "*) printf '%s' "${1#"✗ "}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

is_sentinel() {
  case "$1" in
    "[ skip · plain shell ]"|"[+ new session ]"|"") return 0 ;;
    *) return 1 ;;
  esac
}

drop_cache() {
  # Best-effort — the session is going away either way.
  rm -f -- "$cache/attached/$1" "$cache/cwds/$1" 2>/dev/null || true
}

case "$action" in
  list)
    emit_sorted_list
    ;;

  kill)
    raw=${2:-}
    name=$(strip_icon "$raw")
    if is_sentinel "$name"; then exit 0; fi
    # Look up this session's current status; delete-force if exited,
    # plain-kill otherwise. Either way, clean our cache for it.
    status_line=$(session_line_for_name "$name")
    case "$status_line" in
      *EXITED*) zellij delete-session --force -- "$name" >/dev/null 2>&1 || true ;;
      *)        zellij kill-session -- "$name" >/dev/null 2>&1 || true ;;
    esac
    drop_cache "$name"
    ;;

  clean-dead)
    list_sessions | while IFS= read -r line; do
          case "$line" in *EXITED*) ;; *) continue ;; esac
          n=$(session_name_from_line "$line")
          [ -z "$n" ] && continue
          zellij delete-session --force -- "$n" >/dev/null 2>&1 || true
          drop_cache "$n"
        done
    ;;
esac
