#!/bin/sh
# zellij-login uninstaller — POSIX sh.
set -eu

HOOK_NAME="zellij-ssh-login.zsh"
PREVIEW_NAME="zellij-login-preview.sh"
ACTION_NAME="zellij-login-action.sh"
DEFAULT_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-login"
MARK_OPEN="# zellij-login:hook {{{"
MARK_CLOSE="# zellij-login:hook }}}"
MARK_NO_FINAL_NEWLINE="# zellij-login:original-no-final-newline"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

LAYOUT_NAME="zellij-login.kdl"
ZELLIJ_LAYOUT_DIR="${ZELLIJ_CONFIG_DIR:-$HOME/.config/zellij}/layouts"

# Hook-authored runtime state (MRU dirs, attach timestamps, session cwds).
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-login"

prefix="$DEFAULT_PREFIX"

for arg in "$@"; do
  case "$arg" in
    --prefix=*)   prefix="${arg#--prefix=}" ;;
    -h|--help)
      cat <<EOF
Usage: sh uninstall.sh [--prefix=PATH]

  --prefix=PATH   remove hook installed under PATH (default: $DEFAULT_PREFIX)
EOF
      exit 0 ;;
    *) printf 'zellij-login: unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

info() { printf 'zellij-login: %s\n' "$*"; }

trim_final_newline() {
  file=$1
  size=$(wc -c < "$file" | tr -d ' ')
  [ "$size" -gt 0 ] || return 0
  tmp_trim="$(mktemp)"
  dd if="$file" of="$tmp_trim" bs=1 count=$((size - 1)) 2>/dev/null \
    || { rm -f -- "$tmp_trim"; return 1; }
  mv -- "$tmp_trim" "$file"
}

if [ -f "$prefix/$HOOK_NAME" ]; then
  rm -f -- "$prefix/$HOOK_NAME"
  info "removed $prefix/$HOOK_NAME"
fi
if [ -f "$prefix/$PREVIEW_NAME" ]; then
  rm -f -- "$prefix/$PREVIEW_NAME"
  info "removed $prefix/$PREVIEW_NAME"
fi
if [ -f "$prefix/$ACTION_NAME" ]; then
  rm -f -- "$prefix/$ACTION_NAME"
  info "removed $prefix/$ACTION_NAME"
fi
rmdir "$prefix" 2>/dev/null || true

# The zellij-login layout is ours — take it with us. Leave other user layouts
# (and the layouts/ dir itself if non-empty) alone.
if [ -f "$ZELLIJ_LAYOUT_DIR/$LAYOUT_NAME" ]; then
  rm -f -- "$ZELLIJ_LAYOUT_DIR/$LAYOUT_NAME"
  info "removed $ZELLIJ_LAYOUT_DIR/$LAYOUT_NAME"
fi

# Cache dir is wholly ours (MRU dirs, attached timestamps, session cwds).
if [ -d "$CACHE_DIR" ]; then
  rm -rf -- "$CACHE_DIR"
  info "removed cache dir $CACHE_DIR"
fi

if [ -f "$ZSHRC" ] && grep -Fq "$MARK_OPEN" "$ZSHRC"; then
  had_no_final_newline=0
  grep -Fq "$MARK_NO_FINAL_NEWLINE" "$ZSHRC" && had_no_final_newline=1
  tmp="$(mktemp)"
  trap 'rm -f -- "$tmp"' EXIT
  awk -v o="$MARK_OPEN" -v c="$MARK_CLOSE" '
    index($0, o) > 0 { inblock = 1; next }
    index($0, c) > 0 { inblock = 0; next }
    !inblock         { print }
  ' "$ZSHRC" > "$tmp"
  [ "$had_no_final_newline" -eq 1 ] && trim_final_newline "$tmp"
  mv -- "$tmp" "$ZSHRC"
  info "stripped hook block from $ZSHRC"
fi

info "done."
