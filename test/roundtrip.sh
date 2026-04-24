#!/bin/sh
# Sandbox round-trip test: install → re-install (idempotent) → uninstall,
# plus a legacy-zmx-login migration test.
# Uses a temp HOME so the real ~/.zshrc is never touched.
set -eu

# shellcheck disable=SC1007
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp_home="$(mktemp -d)"
trap 'rm -rf -- "$tmp_home"' EXIT

say() { printf '[test] %s\n' "$*"; }
fail() { printf '[test] FAIL: %s\n' "$*" >&2; exit 1; }

# Seed a pre-existing .zshrc with content we must preserve.
cat > "$tmp_home/.zshrc" <<'EOF'
# my dotfile
export FOO=bar
alias ll='ls -la'
EOF
original="$(cat "$tmp_home/.zshrc")"

env_opts() {
  ZDOTDIR="$tmp_home"
  XDG_DATA_HOME="$tmp_home/.local/share"
  ZELLIJ_CONFIG_DIR="$tmp_home/.config/zellij"
  export ZDOTDIR XDG_DATA_HOME ZELLIJ_CONFIG_DIR
}

# --- 1. install ---
env_opts
sh "$ROOT/install.sh" --no-install-deps >/dev/null
grep -Fq '# zellij-login:hook {{{' "$tmp_home/.zshrc" \
  || fail "marker not added to .zshrc"
[ -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "hook file not placed"
[ -f "$tmp_home/.config/zellij/layouts/zellij-login.kdl" ] \
  || fail "layout file not placed"
grep -Fq 'zellij:compact-bar' "$tmp_home/.config/zellij/layouts/zellij-login.kdl" \
  || fail "layout file content unexpected"
say "install: ok"

# --- 2. idempotency ---
sh "$ROOT/install.sh" --no-install-deps >/dev/null
count="$(grep -Fc '# zellij-login:hook {{{' "$tmp_home/.zshrc")"
[ "$count" = "1" ] || fail "marker duplicated ($count occurrences)"
say "idempotent: ok"

# --- 3. --no-wire ---
alt_prefix="$tmp_home/alt"
sh "$ROOT/install.sh" --no-wire --no-install-deps --prefix="$alt_prefix" >/dev/null
[ -f "$alt_prefix/zellij-ssh-login.zsh" ] || fail "--no-wire did not place file"
grep -Fq "$alt_prefix" "$tmp_home/.zshrc" && fail "--no-wire still wrote to .zshrc"
say "--no-wire: ok"

# --- 4. uninstall ---
sh "$ROOT/uninstall.sh" >/dev/null
[ ! -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "hook file not removed"
[ ! -f "$tmp_home/.config/zellij/layouts/zellij-login.kdl" ] \
  || fail "layout file not removed"
now="$(cat "$tmp_home/.zshrc")"
[ "$original" = "$now" ] || {
  printf 'expected:\n%s\n---\ngot:\n%s\n' "$original" "$now" >&2
  fail ".zshrc not restored byte-for-byte"
}
say "uninstall: ok"

# --- 5. non-interactive sourcing is a silent no-op ---
# zsh -c runs a non-interactive shell, so the hook bails on the [[ -o interactive ]]
# guard. This verifies the hook doesn't error out in that path -- it does NOT exercise
# the ZELLIJ_LOGIN_HOOK_DONE re-entry guard, which requires a live interactive tty to
# test and isn't feasible in CI.
zsh -c ". '$ROOT/zellij-ssh-login.zsh'" >/dev/null 2>&1 \
  || fail "hook errors when sourced in a non-interactive shell"
say "non-interactive-guard: ok"

# --- 6. legacy zmx-login migration ---
# Simulate a pre-existing zmx-login install (from the previous version of
# this project) and verify the new installer strips it cleanly.
rm -rf -- "$tmp_home/.local/share/zellij-login"
cat > "$tmp_home/.zshrc" <<'EOF'
# my dotfile
export FOO=bar
alias ll='ls -la'
# zmx-login:hook {{{
[ -r "$HOME/.local/share/zmx-login/zmx-ssh-login.zsh" ] && source "$HOME/.local/share/zmx-login/zmx-ssh-login.zsh"
# zmx-login:hook }}}
EOF
mkdir -p -- "$tmp_home/.local/share/zmx-login"
: > "$tmp_home/.local/share/zmx-login/zmx-ssh-login.zsh"

sh "$ROOT/install.sh" --no-install-deps >/dev/null

grep -Fq '# zmx-login:hook {{{' "$tmp_home/.zshrc" \
  && fail "legacy zmx-login block still present after migration"
[ ! -d "$tmp_home/.local/share/zmx-login" ] \
  || fail "legacy zmx-login directory still present after migration"
grep -Fq '# zellij-login:hook {{{' "$tmp_home/.zshrc" \
  || fail "new zellij-login block not added during migration"
[ -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "new hook file not placed during migration"
say "legacy-migration: ok"

# --- 7. --no-zellij-config ---
# The installer should place the hook but SKIP the layout.
rm -rf -- "$tmp_home/.local/share/zellij-login" "$tmp_home/.config/zellij"
cat > "$tmp_home/.zshrc" <<'EOF'
# my dotfile
EOF
sh "$ROOT/install.sh" --no-install-deps --no-zellij-config >/dev/null
[ -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "--no-zellij-config did not install hook"
[ ! -f "$tmp_home/.config/zellij/layouts/zellij-login.kdl" ] \
  || fail "--no-zellij-config still wrote the layout file"
say "--no-zellij-config: ok"

say "all tests passed"
