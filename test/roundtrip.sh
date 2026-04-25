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
  XDG_CACHE_HOME="$tmp_home/.cache"
  ZELLIJ_CONFIG_DIR="$tmp_home/.config/zellij"
  export ZDOTDIR XDG_DATA_HOME XDG_CACHE_HOME ZELLIJ_CONFIG_DIR
}

# --- 1. install ---
env_opts
sh "$ROOT/install.sh" --no-install-deps >/dev/null
grep -Fq '# zellij-login:hook {{{' "$tmp_home/.zshrc" \
  || fail "marker not added to .zshrc"
[ -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "hook file not placed"
[ -f "$tmp_home/.local/share/zellij-login/zellij-login-preview.sh" ] \
  || fail "preview helper not placed"
[ -x "$tmp_home/.local/share/zellij-login/zellij-login-preview.sh" ] \
  || fail "preview helper not executable"
[ -f "$tmp_home/.local/share/zellij-login/zellij-login-action.sh" ] \
  || fail "action helper not placed"
[ -x "$tmp_home/.local/share/zellij-login/zellij-login-action.sh" ] \
  || fail "action helper not executable"
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
# Simulate cache accumulated by the hook so we can assert it's cleaned up.
mkdir -p -- "$tmp_home/.cache/zellij-login/attached"
: > "$tmp_home/.cache/zellij-login/attached/fake-session"
: > "$tmp_home/.cache/zellij-login/recent_dirs"
sh "$ROOT/uninstall.sh" >/dev/null
[ ! -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "hook file not removed"
[ ! -f "$tmp_home/.local/share/zellij-login/zellij-login-preview.sh" ] \
  || fail "preview helper not removed"
[ ! -f "$tmp_home/.local/share/zellij-login/zellij-login-action.sh" ] \
  || fail "action helper not removed"
[ ! -f "$tmp_home/.config/zellij/layouts/zellij-login.kdl" ] \
  || fail "layout file not removed"
[ ! -d "$tmp_home/.cache/zellij-login" ] \
  || fail "cache dir not removed"
now="$(cat "$tmp_home/.zshrc")"
[ "$original" = "$now" ] || {
  printf 'expected:\n%s\n---\ngot:\n%s\n' "$original" "$now" >&2
  fail ".zshrc not restored byte-for-byte"
}
say "uninstall: ok"

# --- 4b. uninstall restores a no-final-newline .zshrc byte-for-byte ---
env_opts
rm -rf -- "$tmp_home/.local/share/zellij-login" "$tmp_home/.config/zellij"
printf 'export FOO=no-final-newline' > "$tmp_home/.zshrc"
cp "$tmp_home/.zshrc" "$tmp_home/.zshrc.no-final.orig"
sh "$ROOT/install.sh" --no-install-deps >/dev/null
sh "$ROOT/uninstall.sh" >/dev/null
cmp -s "$tmp_home/.zshrc.no-final.orig" "$tmp_home/.zshrc" \
  || fail ".zshrc without final newline was not restored byte-for-byte"
say "uninstall-no-final-newline: ok"

# --- 4c. custom prefix is shell-quoted in the generated .zshrc source line ---
env_opts
rm -rf -- "$tmp_home/.local/share/zellij-login" "$tmp_home/.config/zellij"
cat > "$tmp_home/.zshrc" <<'EOF'
# my dotfile
EOF
weird_prefix="$tmp_home/prefix with spaces 'quote' dollar\$ back\\slash \"dbl\""
sh "$ROOT/install.sh" --no-install-deps --prefix="$weird_prefix" >/dev/null
[ -f "$weird_prefix/zellij-ssh-login.zsh" ] \
  || fail "weird --prefix did not place hook"
zsh -n "$tmp_home/.zshrc" >/dev/null 2>&1 \
  || fail "weird --prefix generated invalid zsh"
ZDOTDIR="$tmp_home" zsh -c ". \"$tmp_home/.zshrc\"" >/dev/null 2>&1 \
  || fail "weird --prefix source line did not source cleanly"
sh "$ROOT/uninstall.sh" --prefix="$weird_prefix" >/dev/null
say "prefix-shell-quote: ok"

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

# --- 8. curl-pipe does not false-detect CWD as a local clone ---
# When `curl | sh` runs, $0 is "sh" and `dirname -- "$0"` resolves to the
# user's CWD. If that CWD happens to contain an unrelated checkout of this
# repo, the old code path mis-detected it and installed from there instead
# of fetching from GitHub. Simulate by piping install.sh over stdin from a
# sandbox CWD that contains only a fake hook; a curl shim makes the download
# path deterministic (no network required). The installer must NOT take the
# local-clone branch.
env_opts
rm -rf -- "$tmp_home/.local/share/zellij-login" "$tmp_home/.config/zellij"
cat > "$tmp_home/.zshrc" <<'EOF'
# my dotfile
EOF
fake_clone="$tmp_home/fake-clone"
mkdir -p -- "$fake_clone"
printf '# fake hook -- must NOT be installed\n' > "$fake_clone/zellij-ssh-login.zsh"

mkdir -p -- "$tmp_home/bin"
cat > "$tmp_home/bin/curl" <<'EOF'
#!/bin/sh
echo "curl-shim: simulated network failure" >&2
exit 7
EOF
chmod +x "$tmp_home/bin/curl"

log="$tmp_home/curl-pipe.log"
(
  cd "$fake_clone" || exit 1
  PATH="$tmp_home/bin:$PATH" sh -s -- --no-install-deps < "$ROOT/install.sh"
) > "$log" 2>&1 || true

[ ! -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "curl-pipe: fake-clone hook installed -- detection misfired"
! grep -Fq "installing from local clone" "$log" \
  || { cat "$log" >&2; fail "curl-pipe: installer logged 'installing from local clone'"; }
grep -Fq "downloading" "$log" \
  || { cat "$log" >&2; fail "curl-pipe: download branch not reached"; }
say "curl-pipe-detection: ok"

say "all tests passed"
