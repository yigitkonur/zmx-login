# AGENTS.md — zellij-login

Instructions for AI agents (Claude Code, Codex, Cursor, etc.) working in this repo. Read before editing.

## What this is

A ~500-line zsh hook project. On interactive SSH login, the hook sources from `.zshrc`, prompts the user for a [zellij](https://zellij.dev/) session via `fzf`, and either attaches to an existing one or creates a new one after picking a directory with an `fzf --walker=dir` picker. POSIX-sh installer and uninstaller wire it into `.zshrc` via a marker-delimited block. The installer also auto-migrates users upgrading from the previous (zmx-based) version of this project.

## Non-goals

- **Bash / fish compat for the hook.** zsh features are load-bearing: `${(@f)…}`, `(s.:.)`, `local -a`, `[[ -o interactive ]]`. Rewriting for portability is a regression.
- **Multi-multiplexer support.** Zellij only. If someone wants a tmux or zmx variant, it's a fork, not a flag.
- **Rewrite in Go / Rust / Python.** Adding a compile toolchain to install a shell fragment defeats the point.
- **Feature growth.** The hook does one thing: pick + attach. Configuration is env-var only (`ZELLIJ_LOGIN_ROOTS`, `ZELLIJ_LOGIN_SKIP`). Don't add CLI flags to the hook, YAML config, or session templates.
- **New dependencies.** Allowed: `zsh`, `zellij`, `fzf`, coreutils, `awk`. Not allowed: `gum`, `broot`, `yazi`, `jq`, anything else.

## Hard constraints

- **Hook** (`zellij-ssh-login.zsh`): zsh-only. Must pass `zsh -n`.
- **Installer / uninstaller / test** (`install.sh`, `uninstall.sh`, `test/roundtrip.sh`): POSIX `sh`. Must pass `sh -n` and `shellcheck --shell=sh`.
- **Behavior invariants** (verified by `test/roundtrip.sh`; breaking any of these is a regression):
  - Idempotent install — re-running produces exactly one marker block, never duplicates.
  - Byte-for-byte `.zshrc` restore on uninstall.
  - Silent bailout on non-interactive shells, IDE remote shells, already-in-zellij, missing deps.
  - Legacy `zmx-login` install is cleanly migrated (marker block stripped, old dir removed) when the new installer runs.
- **No changes to** `~/.ssh/*`, `/etc/ssh/sshd_config`, SSH `ForceCommand`, or `~/.ssh/rc`. The hook's only integration point is `.zshrc`.
- **Hot path discipline.** The hook runs on every interactive SSH login. Any work added before the short-circuit guards (interactive / `SSH_TTY` / `ZELLIJ` / IDE exclusions / skip flag) is a hot-path regression. Guards must be parameter expansions only — no subshells, no external commands — until we've confirmed the user wants the hook to fire.

## Before committing

```
make check
```

Runs `zsh -n`, `sh -n`, `shellcheck --shell=sh`, and the sandbox round-trip + migration tests. CI runs the identical stack on every push. If local fails, don't push.

## Testing locally

Never exercise `install.sh` against your real `.zshrc`. Use the sandbox pattern from `test/roundtrip.sh`:

```sh
tmp=$(mktemp -d)
ZDOTDIR=$tmp XDG_DATA_HOME=$tmp/.local/share sh install.sh --no-install-deps
# inspect / exercise
ZDOTDIR=$tmp XDG_DATA_HOME=$tmp/.local/share sh uninstall.sh
rm -rf $tmp
```

## Commit messages

Conventional Commits with a short, descriptive scope — `feat(hook): …`, `fix(installer): …`, `refactor(test): …`, `docs(readme): …`. Subject under 50 chars, imperative. No `WIP`, no `misc`, no `updates`. One commit, one purpose.

## File map

| Path | What |
| --- | --- |
| `zellij-ssh-login.zsh` | The hook. ~85 lines. |
| `install.sh` | POSIX-sh installer. Handles local-clone and curl-pipe installs, Homebrew bootstrap, dep auto-install, and zmx-login → zellij-login migration. |
| `uninstall.sh` | POSIX-sh uninstaller. Strips the marker block with awk. |
| `test/roundtrip.sh` | Sandbox install/idempotency/uninstall/migration test. |
| `Makefile` | `install` / `uninstall` / `check` / `test`. |
| `.github/workflows/check.yml` | CI runs `make check`-equivalent on every push. |
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
