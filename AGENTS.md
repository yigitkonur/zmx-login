# AGENTS.md — zellij-login

Instructions for AI agents (Claude Code, Codex, Cursor, etc.) working in this repo. Read before editing.

## What this is

A ~550-line zsh hook project. On interactive SSH login, the hook sources from `.zshrc`, prompts the user for a [zellij](https://zellij.dev/) session via `fzf`, and either attaches to an existing one or creates a new one after picking a directory with a `find`-backed `fzf` picker. POSIX-sh installer and uninstaller wire it into `.zshrc` via a marker-delimited block. The installer also ships a minimal zellij layout (`layouts/zellij-login.kdl`) — one plain pane + a one-line `zellij:compact-bar` status strip, no tab bar — and a curated `zellij-login-config.kdl` (frameless UI, mouse-on, Chrome/macOS-style Alt+letter keybinds) that full-replaces the user's `~/.config/zellij/config.kdl` with a byte-preserving backup. The installer auto-migrates users upgrading from the previous (zmx-based) version of this project.

## Non-goals

- **Bash / fish compat for the hook.** zsh features are load-bearing: `${(@f)…}`, `(s.:.)`, `local -a`, `[[ -o interactive ]]`. Rewriting for portability is a regression.
- **Multi-multiplexer support.** Zellij only. If someone wants a tmux or zmx variant, it's a fork, not a flag.
- **Rewrite in Go / Rust / Python.** Adding a compile toolchain to install a shell fragment defeats the point.
- **Feature growth.** The hook does one thing: pick + attach. Configuration is env-var only (`ZELLIJ_LOGIN_ROOTS`, `ZELLIJ_LOGIN_SKIP`). Don't add CLI flags to the hook, YAML config, or session templates.
- **New dependencies.** Allowed: `zsh`, `zellij`, `fzf`, coreutils, `awk`. Not allowed: `gum`, `broot`, `yazi`, `jq`, anything else.
- **Third-party zellij plugins in the default.** Stick to `zellij:*` built-ins. Third-party plugins require managing zellij's permission cache (`~/.cache/zellij/permissions.kdl`, format officially undocumented) and force a permission-prompt flow that's fragile on upgrades. If a specific third-party plugin becomes essential, cover it in docs as an opt-in, never in the default layout.
- **Merging into the user's `config.kdl`.** The installer full-replaces `config.kdl` with a byte-preserving backup — it does not append a marker-delimited block. Zellij does not merge duplicate top-level `keybinds`/`ui` blocks (last-write-wins on parse), so a safe append would require a KDL parser, outside POSIX-sh scope. Full-replace is the only mode.
- **Binding `Cmd` keys from our config.** macOS `Cmd` chords are consumed by the terminal emulator (Terminal.app, iTerm2, WezTerm, Ghostty, Alacritty, Kitty) before they reach zellij. We ship `Alt+letter` keybinds; users who want literal `Cmd+T/W/N` remap them in their terminal. README documents per-terminal recipes — the installer never touches terminal config.

## Hard constraints

- **Hook** (`zellij-ssh-login.zsh`): zsh-only. Must pass `zsh -n`.
- **Installer / uninstaller / test** (`install.sh`, `uninstall.sh`, `test/roundtrip.sh`): POSIX `sh`. Must pass `sh -n` and `shellcheck --shell=sh`.
- **Behavior invariants** (verified by `test/roundtrip.sh` and `test/runtime.sh`; breaking any of these is a regression):
  - Idempotent install — re-running produces exactly one marker block, never duplicates.
  - Byte-for-byte `.zshrc` restore on uninstall.
  - Silent bailout on non-interactive shells, IDE remote shells, already-in-zellij, missing deps.
  - Legacy `zmx-login` install is cleanly migrated (marker block stripped, old dir removed) when the new installer runs.
  - `--no-zellij-config` skips **both** the layout install **and** the `config.kdl` override (no backup, no sidecar, no state dir created); the hook still works, falling back to the user's own zellij config.
  - Uninstaller removes `zellij-login.kdl` from `$ZELLIJ_CONFIG_DIR/layouts/` and leaves other layouts alone.
  - **`config.kdl` ownership contract.** Two signals — the `// managed-by: zellij-login` marker within the first 5 lines AND a matching sha256 at `$XDG_STATE_HOME/zellij-login/config.sha256` — are required before the uninstaller removes `config.kdl`. Marker absent → user took ownership → do nothing. Marker + sha match → our pristine file → remove and restore `.bak`. Marker + sha mismatch → user edited our managed file → preserve their edits, rename `.bak` → `.zellij-login.restored` alongside.
  - **At-most-one `.bak`.** If a user-owned `config.kdl` exists AND `.bak` already exists, the installer refuses-on-collision (exits non-zero with a clear `zellij-login:` error), leaving both files byte-unchanged. It never silently overwrites a prior backup.
  - **Byte-for-byte backup.** When the installer backs up a user's `config.kdl`, the `.bak` matches the original byte-for-byte. Re-running the installer on our managed file does not touch `.bak` (no double-backup, asserted via mtime).
  - **Shipped `config.kdl` parses with zellij.** `test/roundtrip.sh` runs `zellij --config $CONFIG_TARGET setup --check` after a fresh install (conditional on zellij on PATH) — protects against an edit introducing an invalid option name.
  - **Zellij argv contract** (asserted by `test/runtime.sh`): attach-existing runs `zellij attach -c -- <name>`; new-with-layout runs `zellij --layout zellij-login attach -c -- <name>`; new-without-layout (layout file absent) runs `zellij attach -c -- <name>` with no `--layout`. `--layout` is a zellij top-level flag and must come *before* `attach`; the `--` separator is required because user-typed names can start with `-`. The new-session `<name>` may originate from the `[+ new session ]` + `read -r name` flow *or* from the `--print-query` "type-to-create" flow (query that matched no existing session); argv shape is identical in both cases.
- **No changes to** `~/.ssh/*`, `/etc/ssh/sshd_config`, SSH `ForceCommand`, or `~/.ssh/rc`. The hook's only integration point is `.zshrc`.
- **Hot path discipline.** The hook runs on every interactive SSH login. Any work added before the short-circuit guards (interactive / `SSH_TTY` / `ZELLIJ` / IDE exclusions / skip flag) is a hot-path regression. Guards must be parameter expansions only — no subshells, no external commands — until we've confirmed the user wants the hook to fire.
- **Undocumented fzf action in use.** The session picker binds `pos(N)` after `reload()` (hook lines ~145-147) so `ctrl-x` / `ctrl-k` cascade-kill keeps the cursor on the first real session. `pos(N)` works in fzf 0.48+ but is not listed in `fzf --help` or the man page. If you bump the fzf floor or replace the cascade-kill flow, re-verify the binding still produces the right cursor position — there's no documented equivalent (`first` lands on the skip sentinel, breaking the cascade).
- **fzf `--print-query` rc discipline.** The session picker uses `--print-query`, which emits the current query on stdout on *every* exit — including Esc (rc=130) and no-match-Enter (rc=1). The dispatch captures `fzf_rc=$?` immediately after the command substitution and bails on 130; without that check, Esc-after-typing falls into the type-to-create branch and spawns an unintended session. When refactoring the dispatch, keep the rc capture on the line directly following `$(…)` (any intervening command clobbers `$?`). Asserted by `test/runtime.sh` scenario 9 `esc-with-query`.
- **`local` discipline inside `_zellij_login_hook`.** Every variable assigned inside the function must be declared `local`. Zsh bare assignments go global and persist in the user's interactive shell after `return`, so a missed `local` silently leaks state on every SSH login (no warning, no error). Declare upfront — e.g. `local raw fzf_rc` before the fzf command substitution — rather than relying on catching it in review.

## Before committing

```
make check
```

Runs `zsh -n`, `sh -n`, `shellcheck --shell=sh`, and the sandbox round-trip + migration tests.

No remote CI. Enforcement is client-side: run `make hooks` once in your clone and `make check` then runs automatically on every `git push` (via `.githooks/pre-push`). A failing check aborts the push. Bypass with `git push --no-verify` only if you know exactly what you're skipping.

## Testing locally

Never exercise `install.sh` against your real `.zshrc` or `~/.config/zellij/config.kdl`. Use the sandbox pattern from `test/roundtrip.sh`:

```sh
tmp=$(mktemp -d)
export ZDOTDIR=$tmp \
       XDG_DATA_HOME=$tmp/.local/share \
       XDG_CACHE_HOME=$tmp/.cache \
       XDG_STATE_HOME=$tmp/.local/state \
       ZELLIJ_CONFIG_DIR=$tmp/.config/zellij
sh install.sh --no-install-deps
# inspect / exercise
sh uninstall.sh
rm -rf $tmp
```

`XDG_STATE_HOME` matters now — the config.kdl sha sidecar lands under `$XDG_STATE_HOME/zellij-login/`; without overriding it, the sandbox would write into your real `~/.local/state`.

## Commit messages

Conventional Commits with a short, descriptive scope — `feat(hook): …`, `fix(installer): …`, `refactor(test): …`, `docs(readme): …`. Subject under 50 chars, imperative. No `WIP`, no `misc`, no `updates`. One commit, one purpose.

## File map

| Path | What |
| --- | --- |
| `zellij-ssh-login.zsh` | The hook. Session picker + new-session flow. |
| `zellij-login-preview.sh` | POSIX-sh fzf preview renderer (session metadata). Installed alongside the hook. |
| `zellij-login-action.sh` | POSIX-sh fzf `--bind` target for destructive keys (kill / clean-dead) and for `reload()` list generation. Installed alongside the hook. |
| `layouts/zellij-login.kdl` | Single-pane + one-line `zellij:compact-bar` layout. Shipped into `$ZELLIJ_CONFIG_DIR/layouts/` by the installer. |
| `zellij-login-config.kdl` | Curated zellij config.kdl. First line is `// managed-by: zellij-login` (the ownership marker). Full-replaces `$ZELLIJ_CONFIG_DIR/config.kdl` with the user's prior content preserved at `config.kdl.zellij-login.bak`. |
| `install.sh` | POSIX-sh installer. Handles local-clone and curl-pipe installs, Homebrew bootstrap, dep auto-install, layout + config.kdl + helper placement, marker+sha ownership recording, and zmx-login → zellij-login migration. |
| `uninstall.sh` | POSIX-sh uninstaller. Strips the marker block with awk; removes the helpers, layout, cache dir, and — when the marker+sha match — the managed config.kdl (restoring `.bak`). If the user edited our managed config.kdl, preserves their edits and renames `.bak` → `.zellij-login.restored`. |
| `$XDG_STATE_HOME/zellij-login/config.sha256` | Sidecar written by the installer: sha256 of the shipped config.kdl at install time. Compared on uninstall to detect user edits to the managed file. Not a repo file — created at install time on the user's machine. |
| `test/roundtrip.sh` | Sandbox install/idempotency/uninstall/migration/layout/--no-zellij-config/curl-pipe-detection + ten config.kdl cases (fresh, preserve-user, reinstall-idempotent, uninstall-restores, uninstall-fresh, --no-zellij-config, user-took-ownership, user-edited-managed, bak-collision-refuses, zellij-setup-check). Eighteen cases total. Also asserts helpers and cache dir lifecycle. |
| `test/runtime.sh` | PATH-shim runtime test (nine cases). Drives the hook under `zsh -i` in a sandbox HOME with fake `zellij` + `fzf` binaries; asserts exact argv shape for attach/create/skip/type-to-create/Esc-with-query/depth-cap flows. The fzf shim supports `FZF_OUTPUTS_DIR/<idx>`, `FZF_STDIN_DIR/<idx>`, and `FZF_RC_DIR/<idx>` for per-call output / stdin capture / exit-code simulation. |
| `Makefile` | `install` / `uninstall` / `check` / `test` / `hooks`. |
| `.githooks/pre-push` | Runs `make check` before every `git push`. Enable via `make hooks`. |
| `README.md` | User-facing docs. Casual tone on purpose (dropped-session-friendly). |
| `AGENTS.md` | This file. |
| `CLAUDE.md` | Points at `AGENTS.md`. |
| `LICENSE` | MIT. |

## Style notes

- README tone is deliberately casual / lowercase — don't "professionalize" it without asking; the style is a product decision.
- Comments in code: only non-obvious WHY. No narration, no history. If a comment explains what the code does, delete it.
- Error messages from shell scripts: prefix with `zellij-login:`. Stderr for warnings and errors, stdout for progress.

## If you break the test

The round-trip test is the contract. If a change makes it fail, either fix the change or adjust the test — but don't commit with it failing, and don't commit with a test weakened to hide the regression. If the test is wrong, say so in the commit message and explain why.

## History note

This project was formerly `zmx-login` (backed by [zmx](https://github.com/neurosnap/zmx)). It moved to zellij because zellij is in homebrew-core (no custom tap), has broader Linux packaging, and matches the author's day-to-day workflow. The GitHub repo was renamed; GitHub's URL redirects mean legacy one-liners keep working indefinitely. The installer's legacy-migration block (`migrate_legacy` in `install.sh`) handles users upgrading in-place.
