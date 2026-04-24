# zmx-login

A zsh hook that prompts you for a [zmx](https://github.com/neurosnap/zmx) session on interactive SSH login, then attaches to an existing session or creates a new one rooted in a directory you pick with fzf.

- **Persistent** — sessions survive disconnect / Cmd-Q / network drops (that's zmx; this just wires it into login).
- **Safe for scripted SSH** — `scp`, `sftp`, `rsync`, `ssh host cmd`, git-over-ssh, VS Code / Cursor Remote, JetBrains Gateway all bypass the hook.
- **One zsh file + one POSIX-sh installer**. macOS and Linux. No compilation.

## Install

One-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/install.sh | sh
```

Or clone and run:

```sh
git clone https://github.com/yigitkonur/zmx-login.git
cd zmx-login && make install
```

The installer places the hook at `${XDG_DATA_HOME:-~/.local/share}/zmx-login/zmx-ssh-login.zsh` and appends a marked block to `~/.zshrc` between `# zmx-login:hook {{{` and `# zmx-login:hook }}}`. Idempotent.

### Requirements

- zsh 5+ as your login shell
- [zmx](https://github.com/neurosnap/zmx) 0.5+ on `PATH`
- [fzf](https://github.com/junegunn/fzf) 0.48+ on `PATH` (for `--walker=dir`)

Install on macOS:

```sh
brew install zsh fzf
brew install neurosnap/tap/zmx
```

Install on Debian/Ubuntu:

```sh
sudo apt install zsh fzf
# zmx: see https://github.com/neurosnap/zmx/releases for a prebuilt binary
```

### Installer options

```
sh install.sh --no-wire         # install the file only; source it yourself
sh install.sh --prefix=/opt/…   # custom install prefix
```

Curl-piped with args:

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/install.sh \
  | sh -s -- --no-wire
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/yigitkonur/zmx-login/main/uninstall.sh | sh
# or from a clone:
make uninstall
```

Removes the hook file and strips the marked block from `~/.zshrc` — leaving the rest untouched.

## Usage

SSH in:

```
zmx session >
  [+ new session]
  main
  scratch
```

- Pick an existing session → attach. Your cwd and scrollback are preserved by zmx.
- Pick `[+ new session]` → type a name → pick a directory from your project roots → `cd` there → attach.
- In the directory picker, `Ctrl-N` prompts for a subdir name and creates it under the highlighted path.
- Esc at any prompt drops you into a plain shell — nothing is mandatory.

## Configuration

Set these in `~/.zshenv` or above the sourced block in `~/.zshrc`:

| Variable | Effect |
| --- | --- |
| `ZMX_LOGIN_ROOTS` | Colon-separated directories for the picker. Default: whichever of `~/research ~/dev ~/code ~/projects ~/Developer ~/src ~/work` exist, fallback to `~`. |
| `ZMX_LOGIN_SKIP` | Set to `1` to bypass the hook for this session (`ZMX_LOGIN_SKIP=1 ssh host`). |

Example:

```sh
export ZMX_LOGIN_ROOTS="$HOME/repos:$HOME/work/clients"
```

## When the hook does *not* fire

It bails out silently (so scripted and IDE-driven SSH flows are untouched) if any of these are true:

- shell is non-interactive (`$- != *i*`)
- `SSH_TTY` is unset (scp / sftp / rsync / git-upload-pack / `ssh host cmd` all land here)
- already inside a zmx session (`ZMX_SESSION` is set)
- `VSCODE_IPC_HOOK_CLI`, `CURSOR_SESSION_ID`, `TERM_PROGRAM=vscode`, or `TERMINAL_EMULATOR=JetBrains-JediTerm` is set
- `ZMX_LOGIN_SKIP=1`
- `zmx` or `fzf` not on `PATH` (prints a one-line warning to stderr)

## How it works

One zsh file sourced from `~/.zshrc`. Runs once per shell (guarded by `ZMX_LOGIN_HOOK_DONE`). No `exec` — if `zmx attach` fails, you get a plain shell, not a logged-out SSH session. When the session detaches normally, you're dropped back to the outer login shell; type `exit` to close SSH.

## Development

```sh
make check      # zsh -n, sh -n, shellcheck, sandbox round-trip test
make test       # same as check
```

CI runs the same checks on every push via `.github/workflows/check.yml`.

## License

MIT — see [LICENSE](LICENSE).
