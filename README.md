# zmx-login

a zsh hook. ssh into a box, get prompted for a [zmx](https://github.com/neurosnap/zmx) session — attach to one you already have, or spin up a new one in a directory you pick with fzf. sessions survive disconnect, cmd+q, flaky wifi, whatever. that's zmx doing the work; this just asks the right question at the right time.

mac + linux. zsh-only. no compile step. the hook is 77 lines, the installer is POSIX sh, there's nothing clever going on.

## install

one-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/install.sh | sh
```

or clone and run:

```sh
git clone https://github.com/yigitkonur/zmx-login.git
cd zmx-login && make install
```

both paths drop the hook at `~/.local/share/zmx-login/zmx-ssh-login.zsh` and append a tagged block to your `.zshrc` between `# zmx-login:hook {{{` and `# zmx-login:hook }}}`. re-running is a no-op — nothing gets duplicated and nothing outside the block gets touched.

open a new ssh session. you're done.

### requirements

- zsh 5+ as login shell
- `zmx` 0.5+ on PATH
- `fzf` 0.48+ on PATH

the installer **auto-installs `zmx` and `fzf` if they're missing** — via brew on mac, via `apt` / `dnf` / `pacman` on linux. it'll print exactly what it's doing. pass `--no-install-deps` if you'd rather handle the deps yourself. on mac without brew, or on unsupported distros, it falls back to printing the exact command to run.

if they go missing at runtime later (you uninstalled fzf, zmx binary walked away), the hook prints one stderr line and lands you in a normal shell. no silent breakage.

### flags

```
sh install.sh --no-wire           # place the file, don't touch .zshrc (source it yourself)
sh install.sh --no-install-deps   # don't try to auto-install zmx / fzf
sh install.sh --prefix=PATH       # install somewhere other than ~/.local/share/zmx-login
```

curl-piped with flags:

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/install.sh \
  | sh -s -- --no-wire
```

## uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/uninstall.sh | sh
```

or `make uninstall` from a clone.

strips the marked block from `.zshrc` byte-for-byte and deletes the hook file. your `.zshrc` ends up identical to before — the test suite proves this with a diff on every CI run.

## what you see

ssh in:

```
zmx session >
  [+ new session]
  main
  scratch
```

- enter on an existing name → attach. cwd + scrollback preserved.
- enter on `[+ new session]` → type a name → pick a directory → land inside, attached.
- ctrl-n in the dir picker → prompts for a subdir name, `mkdir -p`s it, selects it.
- esc anywhere → quits out to a plain shell. nothing mandatory.

to detach later, use zmx's detach key (`ctrl+\` by default — see `zmx --help`). session keeps running. next ssh, pick it from the list, pick up where you left off. you can cmd+q your terminal mid-session and the process survives. that's the whole point.

## config

set these before the sourced block in `.zshrc`, or (better) in `~/.zshenv`:

```sh
# custom directory roots for the new-session picker (colon-separated, like PATH)
export ZMX_LOGIN_ROOTS="$HOME/repos:$HOME/work/clients"
```

defaults to whichever of `~/research ~/dev ~/code ~/projects ~/Developer ~/src ~/work` exist. falls back to `~` if none of those are there.

bypass the hook for one session:

```sh
ZMX_LOGIN_SKIP=1 ssh host
```

## when the hook stays out of your way

bails silently on all of these, so scripted ssh, rsync, git, and IDE remote sessions never see it:

- non-interactive shell (ssh-with-command, scp, sftp, rsync, git-upload-pack — these don't even source `.zshrc`, but we guard anyway)
- `SSH_TTY` is unset
- already inside a zmx session (`ZMX_SESSION` set — prevents re-entry when zmx re-execs your shell)
- `VSCODE_IPC_HOOK_CLI`, `CURSOR_SESSION_ID`, `TERM_PROGRAM=vscode`, or `TERMINAL_EMULATOR=JetBrains-JediTerm` is set
- `ZMX_LOGIN_SKIP=1`
- `zmx` or `fzf` not on PATH (one stderr warning, then out of the way)

## stuck? check these first

quick sanity ladder — run from the box you're sshing *from*:

```sh
# 1. is your ssh actually interactive with a tty?
ssh -t host 'echo SSH_TTY=$SSH_TTY; echo interactive:$-'
# SSH_TTY should be /dev/ttys<n>, interactive should include 'i'

# 2. is the hook wired?
ssh host 'grep zmx-login ~/.zshrc'
# should print the marker block + source line

# 3. are the deps there?
ssh host 'command -v zmx fzf zsh'
# all three should print paths

# 4. one-liner diagnostic
ssh host 'grep -c zmx-login ~/.zshrc; ls -la ~/.local/share/zmx-login/ 2>&1'
# should print: 3 (lines matching marker), then the hook file
```

### common issues

**no picker shows up.**
one of the guards is firing. run diagnostic #1 above. if `SSH_TTY` is empty, force a tty with `ssh -t host`. if your shell isn't interactive, you're running `ssh host cmd` instead of a login session — that's working as intended, the hook's not supposed to fire there.

if the guards look fine but still nothing: `ZMX_LOGIN_SKIP=1 ssh host` then once inside run `source ~/.local/share/zmx-login/zmx-ssh-login.zsh` — you'll see any errors directly.

**picker fires on every new shell / tab inside the ssh session.**
shouldn't — `ZMX_LOGIN_HOOK_DONE` is exported after the first run. if you're seeing it, your shell inheritance is broken somehow (some multiplexers spawn fresh env shells). file an issue with your setup.

**directory picker is slow or full of junk.**
you've got huge trees under the default roots. the hook skips `.git node_modules .cache Library .Trash .cargo .rustup .npm` but if you've got other fat directories (monorepos, `go/pkg/mod`, `.pnpm-store`), tighten the roots:

```sh
export ZMX_LOGIN_ROOTS="$HOME/dev/active-project:$HOME/research"
```

**zmx is missing after install.**
the installer warns but doesn't hard-fail. `brew install neurosnap/tap/zmx` (mac) or a release binary from https://github.com/neurosnap/zmx/releases (linux). ssh back in.

**detaching from zmx drops me into a plain shell instead of closing ssh.**
that's on purpose. if the hook used `exec`, a zmx crash would log you out of ssh entirely. the compromise: after detach you land in the outer login shell — just type `exit` once to close ssh.

**i want to test changes without nuking my `.zshrc`.**
sandbox pattern:

```sh
tmp=$(mktemp -d)
ZDOTDIR=$tmp XDG_DATA_HOME=$tmp/.local/share sh install.sh
# poke around: cat $tmp/.zshrc, ls $tmp/.local/share/zmx-login/
ZDOTDIR=$tmp XDG_DATA_HOME=$tmp/.local/share sh uninstall.sh
rm -rf $tmp
```

**i want to see what's in my `.zshrc` without opening the file.**

```sh
ssh host 'awk "/zmx-login:hook \{\{\{/,/zmx-login:hook \}\}\}/" ~/.zshrc'
```

## how it works

one zsh file (`zmx-ssh-login.zsh`) sourced from `.zshrc`. runs once per login shell, guarded on a chain of `SSH_TTY` / interactive / IDE-remote / in-zmx / skip-flag checks — in that order, cheapest-and-most-likely-to-fail first. on pass: an fzf picker for the session (sessions stream in from `zmx list --short` while the picker is already rendering — no wait), then for new sessions an fzf `--walker=dir` picker for the directory with `ctrl-n` as "make subdir." then `zmx attach $name` in the chosen directory.

no `exec` — if zmx crashes or exits, the hook returns and you get a normal shell instead of getting logged out.

the installer and uninstaller are POSIX sh. they run under `dash`, pass `shellcheck --shell=sh`, and talk to each other through a pair of marker lines. the sandbox test (`test/roundtrip.sh`) verifies the install → re-install-is-idempotent → uninstall-restores-byte-for-byte contract on every CI run.

## dev

```sh
make check      # zsh -n, sh -n, shellcheck, sandbox round-trip test
make test       # alias for check
```

CI runs the same stack on every push — `.github/workflows/check.yml`. the sandbox test uses a throwaway `$HOME`, so it never touches your real dotfiles.

see `AGENTS.md` if you're an AI agent working on this repo.

## license

mit. see [LICENSE](LICENSE).
