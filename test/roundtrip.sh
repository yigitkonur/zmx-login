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
  XDG_STATE_HOME="$tmp_home/.local/state"
  ZELLIJ_CONFIG_DIR="$tmp_home/.config/zellij"
  export ZDOTDIR XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME ZELLIJ_CONFIG_DIR
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

# Reset sandbox state before the config.kdl cases so each starts clean.
config_reset() {
  env_opts
  rm -rf -- \
    "$tmp_home/.local/share/zellij-login" \
    "$tmp_home/.config/zellij" \
    "$tmp_home/.local/state/zellij-login" \
    "$tmp_home/.cache/zellij-login"
  cat > "$tmp_home/.zshrc" <<'EOF'
# my dotfile
EOF
}

CONFIG_TARGET="$tmp_home/.config/zellij/config.kdl"
CONFIG_BACKUP="$CONFIG_TARGET.zellij-login.bak"
CONFIG_RESTORED="$CONFIG_TARGET.zellij-login.restored"
CONFIG_SIDECAR="$tmp_home/.local/state/zellij-login/config.sha256"

# --- 9. config-fresh-install ---
config_reset
sh "$ROOT/install.sh" --no-install-deps >/dev/null
[ -f "$CONFIG_TARGET" ] || fail "config.kdl not installed on fresh install"
sed -n '1,5p' "$CONFIG_TARGET" | grep -Fq '// managed-by: zellij-login' \
  || fail "marker not in first 5 lines of installed config.kdl"
[ -f "$CONFIG_SIDECAR" ] || fail "sha sidecar not recorded"
[ "$(cat "$CONFIG_SIDECAR")" = "$(shasum -a 256 "$CONFIG_TARGET" | awk '{print $1}')" ] \
  || fail "sidecar sha does not match config.kdl content"
[ ! -f "$CONFIG_BACKUP" ] || fail "fresh install created an unexpected .bak"
say "config-fresh-install: ok"

# --- 10. config-preserves-user ---
config_reset
mkdir -p -- "$tmp_home/.config/zellij"
printf 'theme "user-sentinel"\n' > "$CONFIG_TARGET"
user_before="$(cat "$CONFIG_TARGET")"
sh "$ROOT/install.sh" --no-install-deps >/dev/null
sed -n '1,5p' "$CONFIG_TARGET" | grep -Fq '// managed-by: zellij-login' \
  || fail "post-install config.kdl is not ours"
[ -f "$CONFIG_BACKUP" ] || fail "user config not backed up"
[ "$(cat "$CONFIG_BACKUP")" = "$user_before" ] \
  || fail ".bak does not match original user content byte-for-byte"
[ -f "$CONFIG_SIDECAR" ] || fail "sidecar not recorded after backup+install"
say "config-preserves-user: ok"

# --- 11. config-reinstall-idempotent (no double-backup, user edits to our managed file are restored) ---
# Starting from state after case 10.
printf '\n// stray user edit\n' >> "$CONFIG_TARGET"
bak_mtime_before="$(stat -f %m "$CONFIG_BACKUP" 2>/dev/null || stat -c %Y "$CONFIG_BACKUP")"
sh "$ROOT/install.sh" --no-install-deps >/dev/null
cmp -s "$CONFIG_TARGET" "$ROOT/zellij-login-config.kdl" \
  || fail "managed config.kdl not restored to pristine on reinstall"
bak_mtime_after="$(stat -f %m "$CONFIG_BACKUP" 2>/dev/null || stat -c %Y "$CONFIG_BACKUP")"
[ "$bak_mtime_before" = "$bak_mtime_after" ] \
  || fail ".bak was rewritten on reinstall (double-backup)"
[ "$(cat "$CONFIG_SIDECAR")" = "$(shasum -a 256 "$CONFIG_TARGET" | awk '{print $1}')" ] \
  || fail "sidecar not updated after reinstall"
say "config-reinstall-idempotent: ok"

# --- 12. config-uninstall-restores ---
# Still in state from case 11: user content preserved in .bak; ours in place.
sh "$ROOT/uninstall.sh" >/dev/null
[ "$(cat "$CONFIG_TARGET")" = "$user_before" ] \
  || fail "config.kdl not restored to user content on uninstall"
[ ! -f "$CONFIG_BACKUP" ] || fail ".bak still present after uninstall"
[ ! -f "$CONFIG_SIDECAR" ] || fail "sidecar not removed on uninstall"
[ ! -d "$tmp_home/.local/state/zellij-login" ] \
  || fail "state dir not cleaned up on uninstall"
say "config-uninstall-restores: ok"

# --- 13. config-uninstall-fresh (no prior user config) ---
config_reset
sh "$ROOT/install.sh" --no-install-deps >/dev/null
sh "$ROOT/uninstall.sh" >/dev/null
[ ! -f "$CONFIG_TARGET" ] || fail "config.kdl not removed on fresh-uninstall"
[ ! -f "$CONFIG_BACKUP" ] || fail "unexpected .bak after fresh-uninstall"
[ ! -f "$CONFIG_SIDECAR" ] || fail "sidecar not removed on fresh-uninstall"
[ ! -d "$tmp_home/.local/state/zellij-login" ] \
  || fail "state dir not cleaned up on fresh-uninstall"
say "config-uninstall-fresh: ok"

# --- 14. config-no-zellij-config-flag skips both layout and config.kdl ---
config_reset
sh "$ROOT/install.sh" --no-install-deps --no-zellij-config >/dev/null
[ -f "$tmp_home/.local/share/zellij-login/zellij-ssh-login.zsh" ] \
  || fail "--no-zellij-config did not install hook"
[ ! -f "$tmp_home/.config/zellij/layouts/zellij-login.kdl" ] \
  || fail "--no-zellij-config still wrote layout"
[ ! -f "$CONFIG_TARGET" ] || fail "--no-zellij-config still wrote config.kdl"
[ ! -f "$CONFIG_SIDECAR" ] || fail "--no-zellij-config still wrote sidecar"
say "config-no-zellij-config: ok"

# --- 15. config-user-took-ownership (marker stripped → uninstall leaves file alone) ---
config_reset
mkdir -p -- "$tmp_home/.config/zellij"
printf 'theme "pre-ownership"\n' > "$CONFIG_TARGET"
sh "$ROOT/install.sh" --no-install-deps >/dev/null
# User adopts the managed file by stripping our marker comment.
sed -i.tmp -e '/^\/\/ managed-by: zellij-login/d' "$CONFIG_TARGET"
rm -f -- "$CONFIG_TARGET.tmp"
owned_before="$(cat "$CONFIG_TARGET")"
bak_before="$(cat "$CONFIG_BACKUP")"
sh "$ROOT/uninstall.sh" >/dev/null
[ "$(cat "$CONFIG_TARGET")" = "$owned_before" ] \
  || fail "uninstall touched a user-owned config.kdl"
[ "$(cat "$CONFIG_BACKUP")" = "$bak_before" ] \
  || fail "uninstall touched the .bak when user had taken ownership"
say "config-user-took-ownership: ok"

# --- 16. config-user-edited-managed (marker kept, content changed → preserve edits, rename .bak) ---
config_reset
mkdir -p -- "$tmp_home/.config/zellij"
printf 'theme "pre-edit"\n' > "$CONFIG_TARGET"
pre_edit_user="$(cat "$CONFIG_TARGET")"
sh "$ROOT/install.sh" --no-install-deps >/dev/null
printf '\n// tweaked keybind\n' >> "$CONFIG_TARGET"
edited_managed="$(cat "$CONFIG_TARGET")"
sh "$ROOT/uninstall.sh" >/dev/null
[ "$(cat "$CONFIG_TARGET")" = "$edited_managed" ] \
  || fail "uninstall clobbered the user's edits to our managed config.kdl"
[ ! -f "$CONFIG_BACKUP" ] || fail ".bak should have been renamed to .restored"
[ -f "$CONFIG_RESTORED" ] || fail ".restored not created to preserve original"
[ "$(cat "$CONFIG_RESTORED")" = "$pre_edit_user" ] \
  || fail ".restored does not match the original user content"
[ ! -f "$CONFIG_SIDECAR" ] || fail "sidecar not removed after edited-managed uninstall"
say "config-user-edited-managed: ok"

# --- 17. config-bak-collision-refuses ---
config_reset
mkdir -p -- "$tmp_home/.config/zellij"
printf 'theme "live-user"\n' > "$CONFIG_TARGET"
printf 'theme "stale-bak"\n' > "$CONFIG_BACKUP"
live_before="$(cat "$CONFIG_TARGET")"
bak_before="$(cat "$CONFIG_BACKUP")"
set +e
sh "$ROOT/install.sh" --no-install-deps >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "installer did not exit non-zero on .bak collision"
[ "$(cat "$CONFIG_TARGET")" = "$live_before" ] \
  || fail "user config.kdl mutated during refused install"
[ "$(cat "$CONFIG_BACKUP")" = "$bak_before" ] \
  || fail "existing .bak mutated during refused install"
say "config-bak-collision-refuses: ok"

# --- 18. config-zellij-setup-check (conditional on zellij on PATH) ---
if command -v zellij >/dev/null 2>&1; then
  config_reset
  sh "$ROOT/install.sh" --no-install-deps >/dev/null
  zellij --config "$CONFIG_TARGET" setup --check >/dev/null 2>&1 \
    || fail "zellij rejects the shipped config.kdl"
  say "config-zellij-setup-check: ok"
else
  say "config-zellij-setup-check: skipped (zellij not on PATH)"
fi

say "all tests passed"
