#!/bin/sh
# zellij-login installer — POSIX sh, macOS + Linux.
# Works standalone (git clone) and curl-piped.
#
# Local:   sh install.sh
# Remote:  curl -fsSL https://raw.githubusercontent.com/yigitkonur/zellij-login/main/install.sh | sh
set -eu

REPO="yigitkonur/zellij-login"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

HOOK_NAME="zellij-ssh-login.zsh"
PREVIEW_NAME="zellij-login-preview.sh"
ACTION_NAME="zellij-login-action.sh"
DEFAULT_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-login"
MARK_OPEN="# zellij-login:hook {{{"
MARK_CLOSE="# zellij-login:hook }}}"
MARK_NO_FINAL_NEWLINE="# zellij-login:original-no-final-newline"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

# Zellij layout we ship for the "shell with persistence, not a multiplexer"
# experience: one plain pane + a single-line compact-bar.
LAYOUT_REL_PATH="layouts/zellij-login.kdl"
LAYOUT_NAME="zellij-login.kdl"
ZELLIJ_LAYOUT_DIR="${ZELLIJ_CONFIG_DIR:-$HOME/.config/zellij}/layouts"

# Legacy-install constants so the new installer can migrate users who had
# the previous zmx-backed version of this project installed.
LEGACY_NAME="zmx-login"
LEGACY_PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/${LEGACY_NAME}"
LEGACY_MARK_OPEN="# ${LEGACY_NAME}:hook {{{"
LEGACY_MARK_CLOSE="# ${LEGACY_NAME}:hook }}}"

wire=1
install_deps=1
install_config=1
prefix="$DEFAULT_PREFIX"

usage() {
  cat <<EOF
Usage: sh install.sh [--no-wire] [--no-install-deps] [--no-zellij-config] [--prefix=PATH]
   or: curl -fsSL ${RAW_URL}/install.sh | sh
   or: curl -fsSL ${RAW_URL}/install.sh | sh -s -- --no-wire

  --no-wire            install the hook file only; do not modify \$ZDOTDIR/.zshrc
  --no-install-deps    do not attempt to auto-install missing zellij / fzf
  --no-zellij-config   do not install the "zellij-login" layout into
                       \$ZELLIJ_CONFIG_DIR/layouts; new sessions then use
                       whatever default_layout your zellij config selects
  --prefix=PATH        install hook under PATH (default: $DEFAULT_PREFIX)
  -h, --help           show this help

Environment (read by the hook at runtime):
  ZELLIJ_LOGIN_ROOTS   colon-separated directories for the dir picker
                       (default: \$HOME/{research,dev,code,projects,Developer,src,work})
  ZELLIJ_LOGIN_SKIP    set to 1 to bypass the hook for a given session

If a previous zmx-login install is detected (either the wired block in
\$ZSHRC or the hook directory $LEGACY_PREFIX), this installer will remove
it before wiring the new one.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-wire)           wire=0 ;;
    --no-install-deps)   install_deps=0 ;;
    --no-zellij-config)  install_config=0 ;;
    --prefix=*)          prefix="${arg#--prefix=}" ;;
    -h|--help)           usage; exit 0 ;;
    *)                   printf 'zellij-login: unknown argument: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

info() { printf 'zellij-login: %s\n' "$*"; }
warn() { printf 'zellij-login: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

quote_shell() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

# Resolve a relative --prefix to an absolute path. The source line we later
# append to $ZSHRC embeds $prefix verbatim; a relative value like `./foo`
# would be re-resolved against whatever PWD zsh has on next login, which is
# almost never the one the user ran the installer from.
case "$prefix" in
  /*) ;;
  *)
    prefix_orig=$prefix
    prefix_parent=$(dirname -- "$prefix")
    prefix_base=$(basename -- "$prefix")
    mkdir -p -- "$prefix_parent" 2>/dev/null || true
    # shellcheck disable=SC1007  # intentional: drop CDPATH for this cd only
    prefix_abs=$(CDPATH= cd -- "$prefix_parent" 2>/dev/null && pwd) \
      || die "could not resolve --prefix=$prefix_orig to an absolute path"
    prefix="$prefix_abs/$prefix_base"
    ;;
esac

# On mac, bootstrap Homebrew itself if it's missing — so the one-liner works
# end-to-end on a clean machine instead of stopping at "install brew first."
bootstrap_brew() {
  info "brew not found — bootstrapping Homebrew (may take a few minutes)"
  info "(you may be prompted for your sudo password by the Homebrew installer)"
  if ! (set +e; NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"); then
    warn "Homebrew bootstrap failed — install manually: https://brew.sh"
    return 1
  fi
  # The Homebrew installer prints the shellenv instructions but doesn't exec them
  # in this shell, so deps below still wouldn't find brew. Activate it here.
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew >/dev/null 2>&1
}

# Platform-specific install command + human hint for each dep.
# $cmd is empty when no automated path is available on this platform.
os="$(uname -s 2>/dev/null || echo unknown)"
case "$os" in
  Darwin)
    if ! command -v brew >/dev/null 2>&1 && [ "$install_deps" -eq 1 ]; then
      bootstrap_brew || true
    fi
    if command -v brew >/dev/null 2>&1; then
      zsh_cmd="brew install zsh"
      zellij_cmd="brew install zellij"
      fzf_cmd="brew install fzf"
    else
      zsh_cmd=""; zellij_cmd=""; fzf_cmd=""
    fi
    zsh_hint="brew install zsh  (install brew first: https://brew.sh)"
    zellij_hint="brew install zellij  (install brew first: https://brew.sh)"
    fzf_hint="brew install fzf  (install brew first: https://brew.sh)"
    ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      zsh_cmd="sudo apt-get update -qq && sudo apt-get install -y zsh"
      zellij_cmd="sudo apt-get update -qq && sudo apt-get install -y zellij"
      fzf_cmd="sudo apt-get update -qq && sudo apt-get install -y fzf"
    elif command -v dnf >/dev/null 2>&1; then
      zsh_cmd="sudo dnf install -y zsh"
      zellij_cmd="sudo dnf install -y zellij"
      fzf_cmd="sudo dnf install -y fzf"
    elif command -v pacman >/dev/null 2>&1; then
      zsh_cmd="sudo pacman -S --noconfirm zsh"
      zellij_cmd="sudo pacman -S --noconfirm zellij"
      fzf_cmd="sudo pacman -S --noconfirm fzf"
    else
      zsh_cmd=""; zellij_cmd=""; fzf_cmd=""
    fi
    zsh_hint="apt install zsh  (or your distro's package manager)"
    zellij_hint="apt install zellij  (or grab a release from https://github.com/zellij-org/zellij/releases)"
    fzf_hint="apt install fzf  (or your distro's package manager)"
    ;;
  *)
    zsh_cmd=""; zellij_cmd=""; fzf_cmd=""
    zsh_hint="see https://www.zsh.org/"
    zellij_hint="see https://zellij.dev/"
    fzf_hint="see https://github.com/junegunn/fzf"
    ;;
esac

# ensure_dep TOOL INSTALL_CMD HINT [required]
# Returns 0 if the tool is available after this call. Exits the installer if
# a required tool is unavailable and we couldn't install it.
ensure_dep() {
  tool=$1; cmd=$2; hint=$3; required=${4:-0}

  command -v "$tool" >/dev/null 2>&1 && return 0

  if [ "$install_deps" -eq 0 ] || [ -z "$cmd" ]; then
    if [ "$required" -eq 1 ]; then
      die "$tool is required — install: $hint"
    fi
    warn "$tool not on PATH — install: $hint"
    return 1
  fi

  info "$tool not on PATH — auto-installing: $cmd"
  info "(this may take up to a minute)"
  # Subshell with set +e so partial failures don't kill us before we can warn.
  if (set +e; eval "$cmd") && command -v "$tool" >/dev/null 2>&1; then
    info "$tool installed"
    return 0
  fi

  if [ "$required" -eq 1 ]; then
    die "auto-install of $tool failed — install manually: $hint"
  fi
  warn "auto-install of $tool failed — install manually: $hint"
  return 1
}

ensure_dep zsh    "$zsh_cmd"    "$zsh_hint"    1 || true
ensure_dep zellij "$zellij_cmd" "$zellij_hint" 0 || true
ensure_dep fzf    "$fzf_cmd"    "$fzf_hint"    0 || true

# Legacy zmx-login migration.
# Detect the old wired block and/or hook directory from the previous
# (zmx-based) version of this project. Strip the old block from $ZSHRC
# and remove the old install dir so the new install is the single source.
migrate_legacy() {
  did_anything=0
  if [ -f "$ZSHRC" ] && grep -Fq "$LEGACY_MARK_OPEN" "$ZSHRC"; then
    tmp="$(mktemp)"
    # Same awk strip the (old) uninstaller used — inlined so migration
    # doesn't depend on the legacy uninstaller being reachable.
    awk -v o="$LEGACY_MARK_OPEN" -v c="$LEGACY_MARK_CLOSE" '
      index($0, o) > 0 { inblock = 1; next }
      index($0, c) > 0 { inblock = 0; next }
      !inblock         { print }
    ' "$ZSHRC" > "$tmp"
    mv -- "$tmp" "$ZSHRC"
    info "removed legacy ${LEGACY_NAME} block from $ZSHRC"
    did_anything=1
  fi
  if [ -d "$LEGACY_PREFIX" ]; then
    rm -rf -- "$LEGACY_PREFIX"
    info "removed legacy ${LEGACY_NAME} directory at $LEGACY_PREFIX"
    did_anything=1
  fi
  if [ "$did_anything" -eq 1 ]; then
    info "migrated from ${LEGACY_NAME} — new zellij-login replaces it"
  fi
}
migrate_legacy

# Resolve hook, preview, and layout sources: prefer a local clone adjacent to
# this script; otherwise fetch each from GitHub raw into a single temp dir.
src=""
src_preview=""
src_action=""
src_layout=""
# Only probe for a local clone when $0 looks like a real install.sh file path.
# Under `curl | sh` the shell sees $0="sh" and `dirname -- "$0"` resolves to
# the user's CWD -- if that happens to contain an unrelated checkout of this
# repo, the old detection misfires and installs from there instead of fetching
# from GitHub. Gating on the basename is the cheapest reliable discriminator:
# legitimate invocations (sh install.sh, ./install.sh, /abs/install.sh) keep
# the local-clone path; curl-pipe and `cat install.sh | sh` fall through to
# the download branch as intended.
script_dir=""
case "$0" in
  */install.sh|install.sh)
    # shellcheck disable=SC1007  # intentional: unset CDPATH for this cd only
    script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || script_dir=""
    ;;
esac
if [ -n "$script_dir" ] && [ -f "$script_dir/$HOOK_NAME" ]; then
  src="$script_dir/$HOOK_NAME"
  [ -f "$script_dir/$PREVIEW_NAME" ] && src_preview="$script_dir/$PREVIEW_NAME"
  [ -f "$script_dir/$ACTION_NAME" ] && src_action="$script_dir/$ACTION_NAME"
  [ -f "$script_dir/$LAYOUT_REL_PATH" ] && src_layout="$script_dir/$LAYOUT_REL_PATH"
  info "installing from local clone ($script_dir)"
else
  command -v curl >/dev/null 2>&1 || die "neither $HOOK_NAME found locally nor curl available"
  _tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/zellij-login.XXXXXX")"
  trap 'rm -rf -- "$_tmpdir"' EXIT
  info "downloading $HOOK_NAME from $RAW_URL"
  curl -fsSL "$RAW_URL/$HOOK_NAME" -o "$_tmpdir/$HOOK_NAME" \
    || die "download failed: $RAW_URL/$HOOK_NAME"
  src="$_tmpdir/$HOOK_NAME"
  info "downloading $PREVIEW_NAME from $RAW_URL"
  if curl -fsSL "$RAW_URL/$PREVIEW_NAME" -o "$_tmpdir/$PREVIEW_NAME"; then
    src_preview="$_tmpdir/$PREVIEW_NAME"
  else
    warn "preview download failed — session picker will lack the preview pane"
  fi
  info "downloading $ACTION_NAME from $RAW_URL"
  if curl -fsSL "$RAW_URL/$ACTION_NAME" -o "$_tmpdir/$ACTION_NAME"; then
    src_action="$_tmpdir/$ACTION_NAME"
  else
    warn "action helper download failed — kill/clean keys in the picker will be inert"
  fi
  if [ "$install_config" -eq 1 ]; then
    info "downloading $LAYOUT_NAME from $RAW_URL"
    if curl -fsSL "$RAW_URL/$LAYOUT_REL_PATH" -o "$_tmpdir/$LAYOUT_NAME"; then
      src_layout="$_tmpdir/$LAYOUT_NAME"
    else
      warn "layout download failed — proceeding without zellij-login layout"
    fi
  fi
fi

mkdir -p -- "$prefix"
# Re-running the installer over an existing install upgrades it to whatever's
# in $src (the latest main on curl-pipe, or the clone's copy on a local install).
action="installed"
[ -f "$prefix/$HOOK_NAME" ] && action="upgraded"
cp -- "$src" "$prefix/$HOOK_NAME"
info "$action hook at $prefix/$HOOK_NAME"

# Ship the preview + action helpers alongside the hook. The hook references
# them by the default install prefix; a --prefix override makes both work only
# at the standard path (acceptable — they are cosmetic / convenience features).
if [ -n "$src_preview" ]; then
  cp -- "$src_preview" "$prefix/$PREVIEW_NAME"
  chmod +x "$prefix/$PREVIEW_NAME"
fi
if [ -n "$src_action" ]; then
  cp -- "$src_action" "$prefix/$ACTION_NAME"
  chmod +x "$prefix/$ACTION_NAME"
fi

# Install the zellij-login layout (single pane + compact-bar, no tab bar)
# unless the user opted out via --no-zellij-config. This is what makes new
# sessions feel like "shell with persistence" instead of a multiplexer.
if [ "$install_config" -eq 1 ] && [ -n "$src_layout" ]; then
  mkdir -p -- "$ZELLIJ_LAYOUT_DIR"
  layout_action="installed"
  [ -f "$ZELLIJ_LAYOUT_DIR/$LAYOUT_NAME" ] && layout_action="updated"
  cp -- "$src_layout" "$ZELLIJ_LAYOUT_DIR/$LAYOUT_NAME"
  info "$layout_action layout at $ZELLIJ_LAYOUT_DIR/$LAYOUT_NAME"
elif [ "$install_config" -eq 0 ]; then
  info "skipped zellij-login layout (--no-zellij-config)"
fi

if [ "$wire" -eq 0 ]; then
  info "skipped .zshrc wiring (--no-wire). Source it manually:"
  hook_path="$prefix/$HOOK_NAME"
  hook_path_q=$(quote_shell "$hook_path")
  printf '    source %s\n' "$hook_path_q"
  exit 0
fi

[ -f "$ZSHRC" ] || : > "$ZSHRC"
if grep -Fq "$MARK_OPEN" "$ZSHRC" 2>/dev/null; then
  info "$ZSHRC already sources the hook"
else
  added_separator=0
  # If $ZSHRC exists with content that doesn't end in a newline, add one
  # so our marker doesn't concatenate onto the last line.
  if [ -s "$ZSHRC" ] && [ -n "$(tail -c 1 "$ZSHRC")" ]; then
    printf '\n' >> "$ZSHRC"
    added_separator=1
  fi
  hook_path="$prefix/$HOOK_NAME"
  hook_path_q=$(quote_shell "$hook_path")
  {
    printf '%s\n' "$MARK_OPEN"
    [ "$added_separator" -eq 1 ] && printf '%s\n' "$MARK_NO_FINAL_NEWLINE"
    printf '[ -r %s ] && source %s\n' "$hook_path_q" "$hook_path_q"
    printf '%s\n' "$MARK_CLOSE"
  } >> "$ZSHRC"
  info "wired hook into $ZSHRC"
fi

info "done. Open a new SSH session on this host to see the picker."
info "uninstall: curl -fsSL $RAW_URL/uninstall.sh | sh"
