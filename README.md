# zellij-login

a zsh hook. ssh into a box, get prompted for a [zellij](https://zellij.dev/) session — attach to one you already have, or spin up a new one in a directory you pick with fzf. sessions survive disconnect, cmd+q, flaky wifi, whatever. that's zellij doing the work; this just asks the right question at the right time.

mac + linux. zsh-only. no compile step. the hook is ~85 lines, the installer is POSIX sh, there's nothing clever going on.

## coming from zmx-login?

this project used to be `zmx-login`. the same one-liner upgrades you in place — on first run after the switch, the installer detects the old `zmx-login` block in your `.zshrc` and the `~/.local/share/zmx-login/` dir, strips them, then installs the zellij-backed version. nothing to do manually. GitHub redirects keep the old URLs working if you bookmarked them.

## install

one-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zellij-login/main/install.sh | sh
```

or clone and run:

```sh
git clone https://github.com/yigitkonur/zellij-login.git
cd zellij-login && make install
```

both paths drop the hook at `~/.local/share/zellij-login/zellij-ssh-login.zsh` and append a tagged block to your `.zshrc` between `# zellij-login:hook {{{` and `# zellij-login:hook }}}`. re-running is a no-op — nothing gets duplicated and nothing outside the block gets touched.

open a new ssh session. you're done.

### requirements

- zsh 5+ as login shell
- `zellij` on PATH
- `fzf` 0.48+ on PATH (for `--walker=dir`)

the installer **bootstraps everything it needs if it's missing** — on mac it installs Homebrew (if absent) then `brew install`s `zellij` and `fzf`; on linux it `apt install`s (or `dnf` / `pacman`) zellij, fzf, and zsh. it prints exactly what it's doing and may prompt for your sudo password once for the Homebrew bootstrap. pass `--no-install-deps` if you'd rather handle all of that yourself — the hook still installs, and you get copy-pasteable warnings with the exact commands to run.

missing any of the three at runtime (not at install)? the hook prints one stderr line and lands you in a normal shell. no silent breakage.

### flags

```
sh install.sh --no-wire             # place the file, don't touch .zshrc (source it yourself)
sh install.sh --no-install-deps     # don't try to auto-install zellij / fzf
sh install.sh --no-zellij-config    # skip installing the "zellij-login" layout
sh install.sh --prefix=PATH         # install somewhere other than ~/.local/share/zellij-login
```

curl-piped with flags:

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zellij-login/main/install.sh \
  | sh -s -- --no-wire
```

## upgrade

same one-liner as install. re-running fetches the latest hook from `main` and overwrites your local copy. the installer detects the existing file and logs `upgraded hook at …` instead of `installed`. the wired block in `.zshrc` is already correct, so it's left alone.

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zellij-login/main/install.sh | sh
```

if you pinned to a non-default prefix earlier, re-run with the same `--prefix=…` so you don't end up with two installs.

## uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zellij-login/main/uninstall.sh | sh
```

or `make uninstall` from a clone.

strips the marked block from `.zshrc` byte-for-byte and deletes the hook file. your `.zshrc` ends up identical to before — the test suite proves this with a diff on every CI run.

## what you see

ssh in:

```
enter = pick highlighted · esc = skip
zellij session >
  [ skip · plain shell ]      ← highlighted by default
  [+ new session ]
  main
  scratch
```

- **enter immediately (don't type anything)** → skip. plain shell, no zellij, no persistence. this is the default so you can bypass the picker with one keystroke.
- type a session name (or arrow down) → enter → attach. cwd + scrollback preserved.
- pick `[+ new session ]` → type a name → pick a directory → land inside, attached.
- ctrl-n in the dir picker → prompts for a subdir name, `mkdir -p`s it, selects it.
- esc anywhere → also skips, plain shell.

### inside the session

new sessions use a minimal layout this installer ships: **one plain pane and a one-line status bar at the bottom** (session name + current mode). no tab bar, no stacked status rows, no nagging — it feels like a regular terminal with persistence, not a tmux clone.

you don't need to learn splits, tabs, or pane-navigation keybinds. mouse works (click to focus, scroll to scroll back, select to copy). if you ever want the richer UI:

- **ctrl+o** → opens the zellij session manager (attach / detach / rename / kill / resurrect)
- **ctrl+o d** → detach; session keeps running. next ssh, pick it from the picker, pick up where you left off.
- **ctrl+o w** → web sharing, if you need it

you can cmd+q your terminal mid-session and the process survives. that's the whole point.

## config

set these before the sourced block in `.zshrc`, or (better) in `~/.zshenv`:

```sh
# custom directory roots for the new-session picker (colon-separated, like PATH)
export ZELLIJ_LOGIN_ROOTS="$HOME/repos:$HOME/work/clients"
```

defaults to whichever of `~/research ~/dev ~/code ~/projects ~/Developer ~/src ~/work` exist. falls back to `~` if none of those are there.

bypass the hook for one session:

```sh
ZELLIJ_LOGIN_SKIP=1 ssh host
```

### optional: tighten zellij's UI further

the layout this installer ships covers the "shell with persistence" feel out of the box. if you want to go further — mute the startup tips and release-notes popups, hide the session name inside pane frames, etc. — add this to your `~/.config/zellij/config.kdl`:

```kdl
show_startup_tips false
show_release_notes false

ui {
    pane_frames {
        hide_session_name true
    }
}
```

these are user-level config choices, so the installer doesn't touch `config.kdl` — copy what you want.

## when the hook stays out of your way

bails silently on all of these, so scripted ssh, rsync, git, and IDE remote sessions never see it:

- non-interactive shell (ssh-with-command, scp, sftp, rsync, git-upload-pack — these don't even source `.zshrc`, but we guard anyway)
- `SSH_TTY` is unset
- already inside a zellij session (`$ZELLIJ` set — prevents re-entry when zellij re-execs your shell)
- `VSCODE_IPC_HOOK_CLI`, `CURSOR_SESSION_ID`, `TERM_PROGRAM=vscode`, or `TERMINAL_EMULATOR=JetBrains-JediTerm` is set
- `ZELLIJ_LOGIN_SKIP=1`
- `zellij` or `fzf` not on PATH (one stderr warning, then out of the way)

## stuck? check these first

quick sanity ladder — run from the box you're sshing *from*:

```sh
# 1. is your ssh actually interactive with a tty?
ssh -t host 'echo SSH_TTY=$SSH_TTY; echo interactive:$-'
# SSH_TTY should be /dev/ttys<n>, interactive should include 'i'

# 2. is the hook wired?
ssh host 'grep zellij-login ~/.zshrc'
# should print the marker block + source line

# 3. are the deps there?
ssh host 'command -v zellij fzf zsh'
# all three should print paths

# 4. one-liner diagnostic
ssh host 'grep -c zellij-login ~/.zshrc; ls -la ~/.local/share/zellij-login/ 2>&1'
# should print: 3 (lines matching marker), then the hook file
```

### common issues

**no picker shows up.**
one of the guards is firing. run diagnostic #1 above. if `SSH_TTY` is empty, force a tty with `ssh -t host`. if your shell isn't interactive, you're running `ssh host cmd` instead of a login session — that's working as intended, the hook's not supposed to fire there.

if the guards look fine but still nothing: `ZELLIJ_LOGIN_SKIP=1 ssh host` then once inside run `source ~/.local/share/zellij-login/zellij-ssh-login.zsh` — you'll see any errors directly.

**picker fires on every new shell / tab inside the zellij session.**
shouldn't — `ZELLIJ_LOGIN_HOOK_DONE` is exported after the first run, and `$ZELLIJ` is set inside a zellij session (the primary guard). if you're seeing it, your shell inheritance is broken somehow. file an issue with your setup.

**directory picker is slow or full of junk.**
you've got huge trees under the default roots. the hook skips `.git node_modules .cache Library .Trash .cargo .rustup .npm` but if you've got other fat directories (monorepos, `go/pkg/mod`, `.pnpm-store`), tighten the roots:

```sh
export ZELLIJ_LOGIN_ROOTS="$HOME/dev/active-project:$HOME/research"
```

**zellij attach stalls on Warp with "Starting shell..."**
should be fixed — the hook unsets Warp's per-tab `ZDOTDIR` (a `warptmp.XXXXXX` wrapper) right before `zellij attach`. if you still see this on the latest version, file an issue with `printenv | grep -E '^(ZDOTDIR|WARP)='` output from a stuck SSH session.

**zellij is missing after install.**
the installer warns but doesn't hard-fail. `brew install zellij` (mac) or `apt install zellij` (recent ubuntu/debian) or a release binary from https://github.com/zellij-org/zellij/releases (older distros). ssh back in.

**detaching from zellij drops me into a plain shell instead of closing ssh.**
that's on purpose. if the hook used `exec`, a zellij crash would log you out of ssh entirely. the compromise: after detach you land in the outer login shell — just type `exit` once to close ssh.

**i want to test changes without nuking my `.zshrc`.**
sandbox pattern:

```sh
tmp=$(mktemp -d)
ZDOTDIR=$tmp XDG_DATA_HOME=$tmp/.local/share sh install.sh --no-install-deps
# poke around: cat $tmp/.zshrc, ls $tmp/.local/share/zellij-login/
ZDOTDIR=$tmp XDG_DATA_HOME=$tmp/.local/share sh uninstall.sh
rm -rf $tmp
```

**i want to see what's in my `.zshrc` without opening the file.**

```sh
ssh host 'awk "/zellij-login:hook \{\{\{/,/zellij-login:hook \}\}\}/" ~/.zshrc'
```

## how it works

one zsh file (`zellij-ssh-login.zsh`) sourced from `.zshrc`. runs once per login shell, guarded on a chain of `SSH_TTY` / interactive / IDE-remote / in-zellij / skip-flag checks — in that order, cheapest-and-most-likely-to-fail first. on pass: an fzf picker for the session (sessions stream in from `zellij list-sessions --short` while the picker is already rendering — no wait), then for new sessions an fzf `--walker=dir` picker for the directory with `ctrl-n` as "make subdir." then `zellij attach -c $name` in the chosen directory.

no `exec` — if zellij crashes or exits, the hook returns and you get a normal shell instead of getting logged out.

the installer and uninstaller are POSIX sh. they run under `dash`, pass `shellcheck --shell=sh`, and talk to each other through a pair of marker lines. the installer also detects any previous zmx-login install and migrates it — same one-liner, no manual steps. the sandbox test (`test/roundtrip.sh`) verifies the install → re-install-is-idempotent → uninstall-restores-byte-for-byte → legacy-migration contract on every CI run.

## dev

```sh
make check      # zsh -n, sh -n, shellcheck, sandbox round-trip + migration test
make test       # alias for check
```

CI runs the same stack on every push — `.github/workflows/check.yml`. the sandbox test uses a throwaway `$HOME`, so it never touches your real dotfiles.

see `AGENTS.md` if you're an AI agent working on this repo.

## license

mit. see [LICENSE](LICENSE).
