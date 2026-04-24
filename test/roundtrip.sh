#!/bin/sh
# Sandbox round-trip test: install → re-install (idempotent) → uninstall.
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
  export ZDOTDIR XDG_DATA_HOME
}

# --- 1. install ---
env_opts
sh "$ROOT/install.sh" --no-install-deps >/dev/null
grep -Fq '# zmx-login:hook {{{' "$tmp_home/.zshrc" \
  || fail "marker not added to .zshrc"
[ -f "$tmp_home/.local/share/zmx-login/zmx-ssh-login.zsh" ] \
  || fail "hook file not placed"
say "install: ok"

# --- 2. idempotency ---
sh "$ROOT/install.sh" --no-install-deps >/dev/null
count="$(grep -Fc '# zmx-login:hook {{{' "$tmp_home/.zshrc")"
[ "$count" = "1" ] || fail "marker duplicated ($count occurrences)"
say "idempotent: ok"

# --- 3. --no-wire ---
alt_prefix="$tmp_home/alt"
sh "$ROOT/install.sh" --no-wire --no-install-deps --prefix="$alt_prefix" >/dev/null
[ -f "$alt_prefix/zmx-ssh-login.zsh" ] || fail "--no-wire did not place file"
grep -Fq "$alt_prefix" "$tmp_home/.zshrc" && fail "--no-wire still wrote to .zshrc"
say "--no-wire: ok"

# --- 4. uninstall ---
sh "$ROOT/uninstall.sh" >/dev/null
[ ! -f "$tmp_home/.local/share/zmx-login/zmx-ssh-login.zsh" ] \
  || fail "hook file not removed"
now="$(cat "$tmp_home/.zshrc")"
[ "$original" = "$now" ] || {
  printf 'expected:\n%s\n---\ngot:\n%s\n' "$original" "$now" >&2
  fail ".zshrc not restored byte-for-byte"
}
say "uninstall: ok"

# --- 5. non-interactive sourcing is a silent no-op ---
# zsh -c runs a non-interactive shell, so the hook bails on the [[ -o interactive ]]
# guard. This verifies the hook doesn't error out in that path -- it does NOT exercise
# the ZMX_LOGIN_HOOK_DONE re-entry guard, which requires a live interactive tty to
# test and isn't feasible in CI.
zsh -c ". '$ROOT/zmx-ssh-login.zsh'" >/dev/null 2>&1 \
  || fail "hook errors when sourced in a non-interactive shell"
say "non-interactive-guard: ok"

say "all tests passed"
