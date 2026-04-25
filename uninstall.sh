#!/bin/sh
# zellij-login uninstaller — POSIX sh.
set -eu

HOOK_NAME="zellij-ssh-login.zsh"
PREVIEW_NAME="zellij-login-preview.sh"
ACTION_NAME="zellij-login-action.sh"
DEFAULT_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-login"
MARK_OPEN="# zellij-login:hook {{{"
MARK_CLOSE="# zellij-login:hook }}}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

LAYOUT_NAME="zellij-login.kdl"
ZELLIJ_CONFIG_DIR_PATH="${ZELLIJ_CONFIG_DIR:-$HOME/.config/zellij}"
ZELLIJ_LAYOUT_DIR="$ZELLIJ_CONFIG_DIR_PATH/layouts"

# Managed config.kdl. Two signals prove ownership before we touch it:
#   - marker comment in the first 5 lines of the file
#   - sha256 sidecar matching the current file content
# If the user edited our managed config, we preserve their edits and
# rename the stashed backup to *.restored alongside.
CONFIG_NAME="config.kdl"
CONFIG_TARGET="$ZELLIJ_CONFIG_DIR_PATH/$CONFIG_NAME"
CONFIG_BACKUP="$CONFIG_TARGET.zellij-login.bak"
CONFIG_RESTORED_ALONGSIDE="$CONFIG_TARGET.zellij-login.restored"
CONFIG_MARKER="// managed-by: zellij-login"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zellij-login"
CONFIG_SHA_SIDECAR="$STATE_DIR/config.sha256"

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
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
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

# config.kdl decision tree:
#   - no marker in first 5 lines      → user took ownership; leave it alone.
#   - marker + sha matches sidecar    → pristine ours; remove + restore .bak.
#   - marker + sha differs (or sha    → user edited our managed file; keep
#     sidecar missing)                  their edits, rename .bak to .restored.
if [ -f "$CONFIG_TARGET" ] \
    && sed -n '1,5p' "$CONFIG_TARGET" 2>/dev/null | grep -Fq "$CONFIG_MARKER"; then
  sha_now=""
  sha_recorded=""
  sha_now="$(sha256_file "$CONFIG_TARGET" 2>/dev/null)"
  [ -f "$CONFIG_SHA_SIDECAR" ] && sha_recorded="$(cat "$CONFIG_SHA_SIDECAR" 2>/dev/null)"
  if [ -n "$sha_now" ] && [ -n "$sha_recorded" ] && [ "$sha_now" = "$sha_recorded" ]; then
    rm -f -- "$CONFIG_TARGET"
    info "removed $CONFIG_TARGET"
    if [ -f "$CONFIG_BACKUP" ]; then
      mv -- "$CONFIG_BACKUP" "$CONFIG_TARGET"
      info "restored $CONFIG_TARGET from backup"
    fi
  else
    info "preserved user-edited $CONFIG_TARGET"
    if [ -f "$CONFIG_BACKUP" ]; then
      mv -- "$CONFIG_BACKUP" "$CONFIG_RESTORED_ALONGSIDE"
      info "original config preserved at $CONFIG_RESTORED_ALONGSIDE"
    fi
  fi
fi
# Always clean up the sidecar and state dir — they're ours regardless of
# whether the managed config.kdl was present with our marker (user may have
# deleted config.kdl or stripped the marker to take ownership).
[ -f "$CONFIG_SHA_SIDECAR" ] && rm -f -- "$CONFIG_SHA_SIDECAR"
rmdir "$STATE_DIR" 2>/dev/null || true

# Cache dir is wholly ours (MRU dirs, attached timestamps, session cwds).
if [ -d "$CACHE_DIR" ]; then
  rm -rf -- "$CACHE_DIR"
  info "removed cache dir $CACHE_DIR"
fi

if [ -f "$ZSHRC" ] && grep -Fq "$MARK_OPEN" "$ZSHRC"; then
  tmp="$(mktemp)"
  trap 'rm -f -- "$tmp"' EXIT
  awk -v o="$MARK_OPEN" -v c="$MARK_CLOSE" '
    index($0, o) > 0 { inblock = 1; next }
    index($0, c) > 0 { inblock = 0; next }
    !inblock         { print }
  ' "$ZSHRC" > "$tmp"
  mv -- "$tmp" "$ZSHRC"
  info "stripped hook block from $ZSHRC"
fi

info "done."
