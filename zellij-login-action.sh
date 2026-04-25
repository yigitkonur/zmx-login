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
  zellij list-sessions -n 2>/dev/null | while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=${line%% *}
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

# After kill / clean-dead, rewrite the hook's list-sessions snapshot so any
# preview render fired by fzf's `reload()` sees the new state. Atomic via
# temp-then-rename; concurrent writers can't corrupt the destination.
refresh_list_cache() {
  mkdir -p -- "$cache"
  rlc_tmp="$cache/.sessions.tmp.$$"
  zellij list-sessions -n 2>/dev/null > "$rlc_tmp" || true
  mv -- "$rlc_tmp" "$cache/.sessions.txt" 2>/dev/null \
    || rm -f -- "$rlc_tmp" 2>/dev/null
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
    status_line=$(zellij list-sessions -n 2>/dev/null \
      | awk -v n="$name" '$1 == n { print; exit }')
    case "$status_line" in
      *EXITED*) zellij delete-session --force -- "$name" >/dev/null 2>&1 || true ;;
      *)        zellij kill-session -- "$name" >/dev/null 2>&1 || true ;;
    esac
    drop_cache "$name"
    refresh_list_cache
    ;;

  clean-dead)
    zellij list-sessions -n 2>/dev/null | awk '/EXITED/ { print $1 }' \
      | while IFS= read -r n; do
          [ -z "$n" ] && continue
          zellij delete-session --force -- "$n" >/dev/null 2>&1 || true
          drop_cache "$n"
        done
    refresh_list_cache
    ;;
esac
