#!/bin/sh
# zmx-login installer — POSIX sh, macOS + Linux.
# Works standalone (git clone) and curl-piped.
#
# Local:   sh install.sh
# Remote:  curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/install.sh | sh
set -eu

REPO="yigitkonur/zmx-login"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

HOOK_NAME="zmx-ssh-login.zsh"
DEFAULT_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/zmx-login"
MARK_OPEN="# zmx-login:hook {{{"
MARK_CLOSE="# zmx-login:hook }}}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

wire=1
prefix="$DEFAULT_PREFIX"

usage() {
  cat <<EOF
Usage: sh install.sh [--no-wire] [--prefix=PATH]
   or: curl -fsSL ${RAW_URL}/install.sh | sh
   or: curl -fsSL ${RAW_URL}/install.sh | sh -s -- --no-wire

  --no-wire       install the hook file only; do not modify \$ZDOTDIR/.zshrc
  --prefix=PATH   install hook under PATH (default: $DEFAULT_PREFIX)
  -h, --help      show this help

Environment (read by the hook at runtime):
  ZMX_LOGIN_ROOTS   colon-separated directories for the dir picker
                    (default: \$HOME/{research,dev,code,projects,Developer,src,work})
  ZMX_LOGIN_SKIP    set to 1 to bypass the hook for a given session
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-wire)      wire=0 ;;
    --prefix=*)     prefix="${arg#--prefix=}" ;;
    -h|--help)      usage; exit 0 ;;
    *)              printf 'zmx-login: unknown argument: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

info() { printf 'zmx-login: %s\n' "$*"; }
warn() { printf 'zmx-login: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

command -v zsh >/dev/null 2>&1 || die "zsh is required"
command -v zmx >/dev/null 2>&1 || warn "zmx not on PATH — install from https://github.com/neurosnap/zmx before first SSH"
command -v fzf >/dev/null 2>&1 || warn "fzf not on PATH — install via your package manager before first SSH"

# Locate source hook: prefer local copy adjacent to this script, else fetch from GitHub.
src=""
cleanup=""
# shellcheck disable=SC1007  # intentional: unset CDPATH for this cd only
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || script_dir=""
if [ -n "$script_dir" ] && [ -f "$script_dir/$HOOK_NAME" ]; then
  src="$script_dir/$HOOK_NAME"
  info "installing from local clone ($script_dir)"
else
  command -v curl >/dev/null 2>&1 || die "neither $HOOK_NAME found locally nor curl available"
  src="$(mktemp "${TMPDIR:-/tmp}/zmx-login.XXXXXX")"
  cleanup="$src"
  trap 'rm -f -- "$cleanup"' EXIT
  info "downloading $HOOK_NAME from $RAW_URL"
  curl -fsSL "$RAW_URL/$HOOK_NAME" -o "$src" || die "download failed: $RAW_URL/$HOOK_NAME"
fi

mkdir -p -- "$prefix"
cp -- "$src" "$prefix/$HOOK_NAME"
info "installed hook at $prefix/$HOOK_NAME"

if [ "$wire" -eq 0 ]; then
  info "skipped .zshrc wiring (--no-wire). Source it manually:"
  printf '    source %s/%s\n' "$prefix" "$HOOK_NAME"
  exit 0
fi

[ -f "$ZSHRC" ] || : > "$ZSHRC"
if grep -Fq "$MARK_OPEN" "$ZSHRC" 2>/dev/null; then
  info "$ZSHRC already sources the hook"
else
  # Ensure file ends with a newline before appending.
  if [ -s "$ZSHRC" ] && [ "$(tail -c 1 "$ZSHRC" | wc -l | tr -d ' ')" = 0 ]; then
    printf '\n' >> "$ZSHRC"
  fi
  {
    printf '%s\n' "$MARK_OPEN"
    printf '[ -r "%s/%s" ] && source "%s/%s"\n' \
      "$prefix" "$HOOK_NAME" "$prefix" "$HOOK_NAME"
    printf '%s\n' "$MARK_CLOSE"
  } >> "$ZSHRC"
  info "wired hook into $ZSHRC"
fi

info "done. Open a new SSH session on this host to see the picker."
info "uninstall: curl -fsSL $RAW_URL/uninstall.sh | sh"
