#!/bin/sh
# Runtime argv assertions for the zellij-login hook. Exercises hook paths
# test/roundtrip.sh can't reach -- lines 12+ require an interactive shell,
# and roundtrip.sh only sources in `zsh -c` (non-interactive) so the hook
# bails at the first guard. This test drives the hook with `zsh -i` inside
# a sandbox HOME, replaces `zellij` and `fzf` with PATH shims that capture
# argv, and asserts on the exact argv the hook would have passed to zellij.
set -eu

# shellcheck disable=SC1007
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

say()  { printf '[runtime] %s\n' "$*"; }
dump() { [ -s "$RUN_LOG" ] && { printf '[runtime] RUN_LOG:\n' >&2; cat "$RUN_LOG" >&2; }; }
fail() { printf '[runtime] FAIL: %s\n' "$*" >&2; dump; exit 1; }

# PATH shims. `zellij list-sessions -n` emits a scenario-controlled file;
# every other `zellij` call appends its space-joined argv to RUN_LOG. `fzf`
# drains stdin and prints the pre-canned output for its Nth invocation from
# FZF_OUTPUTS_DIR/N -- a simple scheme that matches the hook's 1-or-2 fzf
# calls per run (session picker; optionally dir picker with --expect=ctrl-n).
mkdir -p "$tmp/bin"
cat > "$tmp/bin/zellij" <<'EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "list-sessions" ]; then
  [ -f "${MOCK_SESSIONS:-/nonexistent}" ] && cat "$MOCK_SESSIONS" || true
  exit 0
fi
{ printf 'zellij'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "${RUN_LOG:?}"
EOF
chmod +x "$tmp/bin/zellij"

# fzf shim: capture stdin to FZF_STDIN_DIR/<idx> (so depth-cap tests can
# inspect the candidate list the hook piped in), then emit pre-canned
# output from FZF_OUTPUTS_DIR/<idx>.
cat > "$tmp/bin/fzf" <<'EOF'
#!/bin/sh
set -eu
idx=$(cat "${FZF_IDX_FILE:?}" 2>/dev/null || printf 0)
idx=$((idx + 1))
printf '%s' "$idx" > "$FZF_IDX_FILE"
stdin_log="${FZF_STDIN_DIR:?}/$idx"
cat > "$stdin_log"
out="${FZF_OUTPUTS_DIR:?}/$idx"
[ -f "$out" ] && cat "$out" || true
EOF
chmod +x "$tmp/bin/fzf"

# Sandbox HOME so `zsh -i` doesn't touch the real .zshrc.
mkdir -p "$tmp/home/.config/zellij/layouts" \
         "$tmp/home/.local/share"           \
         "$tmp/home/.cache"
cp "$ROOT/layouts/zellij-login.kdl" "$tmp/home/.config/zellij/layouts/"

HOME="$tmp/home";                      export HOME
ZDOTDIR="$HOME";                       export ZDOTDIR
XDG_DATA_HOME="$HOME/.local/share";    export XDG_DATA_HOME
XDG_CACHE_HOME="$HOME/.cache";         export XDG_CACHE_HOME
XDG_CONFIG_HOME="$HOME/.config";       export XDG_CONFIG_HOME
ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"; export ZELLIJ_CONFIG_DIR
PATH="$tmp/bin:$PATH";                 export PATH
SSH_TTY=/dev/ttyp0;                    export SSH_TTY

# Clear guards that would short-circuit the hook.
unset ZELLIJ VSCODE_IPC_HOOK_CLI CURSOR_SESSION_ID TERM_PROGRAM \
      TERMINAL_EMULATOR ZELLIJ_LOGIN_HOOK_DONE ZELLIJ_LOGIN_SKIP \
      2>/dev/null || true

RUN_LOG="$tmp/run.log";                export RUN_LOG
FZF_IDX_FILE="$tmp/fzf.idx";           export FZF_IDX_FILE
FZF_OUTPUTS_DIR="$tmp/fzf.out";        export FZF_OUTPUTS_DIR
FZF_STDIN_DIR="$tmp/fzf.stdin";        export FZF_STDIN_DIR

reset() {
  rm -f "$RUN_LOG" "$FZF_IDX_FILE"
  rm -rf "$FZF_OUTPUTS_DIR" "$FZF_STDIN_DIR"
  mkdir -p "$FZF_OUTPUTS_DIR" "$FZF_STDIN_DIR"
  : > "$RUN_LOG"
}

# Runs the hook once in a fresh interactive zsh. $1 is stdin (for `read`
# prompts in the new-session flow). zsh -i keeps [[ -o interactive ]] true;
# there's no .zshrc in the sandbox HOME, so nothing else runs.
run_hook() {
  printf '%s' "$1" | zsh -i -c ". \"$ROOT/zellij-ssh-login.zsh\"" \
    >/dev/null 2>&1 || true
}

# NOTE on fzf output shape: the session picker runs with --print-query, so
# fzf emits the current query on line 1 and the selection (if any) on
# line 2. Canned outputs below follow that shape: empty first line when
# the user didn't type a query; query-only (no second line) when the
# query matched no candidate (scenario 7 "type-to-create").

# --- 1. attach existing session (layout flag does NOT apply here) ---
reset
printf 'existing-session [Created 1h 23m ago]\n' > "$tmp/sessions"
MOCK_SESSIONS="$tmp/sessions"; export MOCK_SESSIONS
printf '\n%s\n' '● existing-session' > "$FZF_OUTPUTS_DIR/1"
run_hook ''
grep -Fxq 'zellij attach -c -- existing-session' "$RUN_LOG" \
  || fail "attach-existing: expected 'zellij attach -c -- existing-session'"
say "attach-existing: ok"

# --- 2. new session with the zellij-login layout installed ---
reset
: > "$tmp/sessions"
printf '\n%s\n' '[+ new session ]' > "$FZF_OUTPUTS_DIR/1"
printf '\n%s\n' "$HOME" > "$FZF_OUTPUTS_DIR/2"
run_hook 'newsess
'
grep -Fxq 'zellij --layout zellij-login attach -c -- newsess' "$RUN_LOG" \
  || fail "new-with-layout: expected 'zellij --layout zellij-login attach -c -- newsess'"
say "new-with-layout: ok"

# --- 3. new session when the layout file is absent (e.g. --no-zellij-config) ---
reset
rm -f "$ZELLIJ_CONFIG_DIR/layouts/zellij-login.kdl"
: > "$tmp/sessions"
printf '\n%s\n' '[+ new session ]' > "$FZF_OUTPUTS_DIR/1"
printf '\n%s\n' "$HOME" > "$FZF_OUTPUTS_DIR/2"
run_hook 'nosess
'
grep -Fxq 'zellij attach -c -- nosess' "$RUN_LOG" \
  || fail "new-without-layout: expected 'zellij attach -c -- nosess'"
! grep -Fq -- '--layout' "$RUN_LOG" \
  || fail "new-without-layout: --layout should NOT appear when layout file is missing"
cp "$ROOT/layouts/zellij-login.kdl" "$ZELLIJ_CONFIG_DIR/layouts/"
say "new-without-layout: ok"

# --- 4. dash-prefixed session name: -- separator must survive intact ---
reset
: > "$tmp/sessions"
printf '\n%s\n' '[+ new session ]' > "$FZF_OUTPUTS_DIR/1"
printf '\n%s\n' "$HOME" > "$FZF_OUTPUTS_DIR/2"
run_hook '-xy
'
grep -Fxq 'zellij --layout zellij-login attach -c -- -xy' "$RUN_LOG" \
  || fail "dash-name: '-- -xy' separator missing -- name would be parsed as flags"
say "dash-name: ok"

# --- 5. ZELLIJ_LOGIN_SKIP=1 must short-circuit before touching zellij ---
reset
export ZELLIJ_LOGIN_SKIP=1
run_hook ''
unset ZELLIJ_LOGIN_SKIP
[ ! -s "$RUN_LOG" ] || fail "skip: zellij should not be called"
say "skip: ok"

# --- 6. already inside a zellij session must short-circuit ---
reset
export ZELLIJ=1
run_hook ''
unset ZELLIJ
[ ! -s "$RUN_LOG" ] || fail "in-zellij: zellij should not be called"
say "in-zellij: ok"

# --- 7. type-to-create: query matches no session, becomes the new name ---
# The session-picker fzf emits `typedname\n` (query only, no selection) to
# simulate "user typed a name that matches nothing, pressed Enter". Hook
# should skip the `read -r name` prompt and use the query as $name. The
# dir picker (2nd fzf call) returns $HOME as before.
reset
: > "$tmp/sessions"
printf '%s\n' 'typedname' > "$FZF_OUTPUTS_DIR/1"
printf '\n%s\n' "$HOME" > "$FZF_OUTPUTS_DIR/2"
run_hook ''
grep -Fxq 'zellij --layout zellij-login attach -c -- typedname' "$RUN_LOG" \
  || fail "type-to-create: expected 'zellij --layout zellij-login attach -c -- typedname'"
say "type-to-create: ok"

# --- 8. dir-depth-cap: new-session dir picker stops at depth 1 ---
# Seed a root with a depth-2+ tree and assert that only depth-0 + depth-1
# dirs reach the fzf stdin. Prevents regression to the old maxdepth-5 list
# that drowned top-level projects under fuzzy-ranked sub-sub-paths.
reset
: > "$tmp/sessions"
mkdir -p -- "$HOME/proj-a/subdir-1/leaf" "$HOME/proj-b"
ZELLIJ_LOGIN_ROOTS="$HOME"; export ZELLIJ_LOGIN_ROOTS
printf '\n%s\n' '[+ new session ]' > "$FZF_OUTPUTS_DIR/1"
printf '\n%s\n' "$HOME" > "$FZF_OUTPUTS_DIR/2"
run_hook 'depthsess
'
unset ZELLIJ_LOGIN_ROOTS
grep -Fxq "$HOME/proj-a" "$FZF_STDIN_DIR/2" \
  || fail "dir-depth-cap: expected top-level '$HOME/proj-a' in dir-picker stdin"
grep -Fxq "$HOME/proj-b" "$FZF_STDIN_DIR/2" \
  || fail "dir-depth-cap: expected top-level '$HOME/proj-b' in dir-picker stdin"
! grep -Fxq "$HOME/proj-a/subdir-1" "$FZF_STDIN_DIR/2" \
  || fail "dir-depth-cap: depth-2 '$HOME/proj-a/subdir-1' leaked past maxdepth cap"
! grep -Fxq "$HOME/proj-a/subdir-1/leaf" "$FZF_STDIN_DIR/2" \
  || fail "dir-depth-cap: depth-3 '$HOME/proj-a/subdir-1/leaf' leaked past maxdepth cap"
rm -rf -- "$HOME/proj-a" "$HOME/proj-b"
say "dir-depth-cap: ok"

say "all runtime tests passed"
