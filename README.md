# zellij-login

a zsh hook. ssh into a box, get prompted for a [zellij](https://zellij.dev/) session — attach to one you already have, or spin up a new one in a directory you pick with fzf. sessions survive disconnect, cmd+q, flaky wifi, whatever. that's zellij doing the work; this just asks the right question at the right time.

out of the box: mouse works (click tabs, drag borders, scroll scrollback), chrome/macos-style tabs via `alt+t` / `alt+w` / `alt+1..9`, no prefix-key mode dance. the installer full-replaces your `~/.config/zellij/config.kdl` with a curated one; your old one, if any, is preserved at `config.kdl.zellij-login.bak` and restored on uninstall. opt out with `--no-zellij-config`.

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
- `fzf` 0.48+ on PATH

the installer **bootstraps everything it needs if it's missing** — on mac it installs Homebrew (if absent) then `brew install`s `zellij` and `fzf`; on linux it `apt install`s (or `dnf` / `pacman`) zellij, fzf, and zsh. it prints exactly what it's doing and may prompt for your sudo password once for the Homebrew bootstrap. pass `--no-install-deps` if you'd rather handle all of that yourself — the hook still installs, and you get copy-pasteable warnings with the exact commands to run.

missing any of the three at runtime (not at install)? the hook prints one stderr line and lands you in a normal shell. no silent breakage.

### flags

```
sh install.sh --no-wire             # place the file, don't touch .zshrc (source it yourself)
sh install.sh --no-install-deps     # don't try to auto-install zellij / fzf
sh install.sh --no-zellij-config    # skip BOTH the "zellij-login" layout AND our config.kdl override
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
enter=pick · esc=skip · ctrl-x=kill/delete · ctrl-k=clean dead
zellij session >
   [ skip · plain shell ]      ← highlighted by default
   [+ new session ]
 ● main           │ session:  main
 ● scratch        │ status:   active
 ✗ old-notes      │ created:  3h 21m ago
                  │ last:     12m ago
                  │ cwd:      /Users/you/dev/app
```

- **enter immediately (don't type anything)** → skip. plain shell, no zellij, no persistence. one-keystroke bypass.
- type a session name (or arrow down) → enter → attach. cwd + scrollback preserved.
- `●` = active session, `✗` = exited (attach to resurrect). sorted by most-recently-attached first.
- right-side preview pane shows cwd (for sessions this hook created), status, created-ago, last-attached.
- **ctrl-x** kills the highlighted session. if it's already exited (`✗`), it force-deletes (nukes resurrection state too). list reloads in place.
- **ctrl-k** sweeps every `✗` EXITED session in one keystroke. the usual answer to "32 sessions, half are dead ghosts, why did I let this happen".
- pick `[+ new session ]` → type a name → pick a directory (recently-used dirs listed first) → land inside, attached.
- ctrl-n in the dir picker → prompts for a subdir name, `mkdir -p`s it, selects it.
- esc anywhere → also skips, plain shell.

### inside the session

new sessions use a minimal layout this installer ships: **one plain pane and a one-line status bar at the bottom** (session name + current mode). no tab bar, no stacked status rows, no nagging — it feels like a regular terminal with persistence, not a tmux clone.

mouse works out of the box: click a tab to switch, click a pane to focus, drag a border to resize, scroll to see scrollback, hover follows focus. select-to-copy uses your terminal's own clipboard integration.

you can cmd+q your terminal mid-session and the process survives. that's the whole point.

### keybinds

chrome/macos-parallel. `alt` = `option` on mac. no prefix-key dance — these are always active.

| shortcut | what (chrome/macos parallel) |
| --- | --- |
| `alt+t` | new tab (cmd+t) |
| `alt+w` | close tab (cmd+w) |
| `alt+1`..`alt+9` | jump to tab 1..9 (cmd+1..9) |
| `alt+]` / `alt+[` | next / prev tab (cmd+shift+] / cmd+shift+[) |
| `ctrl+tab` / `ctrl+shift+tab` | next / prev tab (same as above, for terminals that forward these) |
| `alt+n` | new pane |
| `alt+q` | close pane |
| `alt+h` / `alt+j` / `alt+k` / `alt+l` | focus pane left / down / up / right |
| `alt+z` | zoom focused pane fullscreen (toggle) |
| `alt+r` | rename tab (enter commits, esc cancels) |
| `alt+d` | detach — session keeps running; ssh back and pick it |
| `ctrl+o` | zellij session manager (attach / rename / kill / resurrect) |

> **heads-up for macOS Terminal.app users**: "use Option as Meta key" is **off by default** there — `alt+t` fires nothing until you enable it (Settings → Profiles → Keyboard). iTerm2 / WezTerm / Ghostty / Alacritty / Kitty all have it on by default.

### wait, what about cmd+t?

mac `cmd` keys are eaten by the terminal emulator before zellij sees them — it's a terminal-layer thing, not a zellij-layer thing. every serious mac terminal lets you remap `cmd+t` to emit what zellij reads as `alt+t` (literally `ESC` + `t`). pick your terminal, paste into its config, `cmd+t` now opens a new zellij tab:

**iTerm2** — Settings → Keys → Key Bindings → `+`, keystroke `⌘T`, action "Send Text with 'vim' Special Chars", text `\<M-t>`. Repeat for `w n [ ] 1..9`.

**WezTerm** (`~/.wezterm.lua`):

```lua
local wezterm = require 'wezterm'
local act = wezterm.action
return {
  keys = {
    { key='t', mods='CMD',       action = act.SendString '\x1bt' },
    { key='w', mods='CMD',       action = act.SendString '\x1bw' },
    { key='n', mods='CMD',       action = act.SendString '\x1bn' },
    { key='[', mods='CMD|SHIFT', action = act.SendString '\x1b[' },
    { key=']', mods='CMD|SHIFT', action = act.SendString '\x1b]' },
    { key='1', mods='CMD',       action = act.SendString '\x1b1' },
    -- ...repeat for 2..9
  },
}
```

**Ghostty** (`~/.config/ghostty/config`):

```
keybind = cmd+t=text:\x1bt
keybind = cmd+w=text:\x1bw
keybind = cmd+n=text:\x1bn
keybind = cmd+shift+bracket_left=text:\x1b[
keybind = cmd+shift+bracket_right=text:\x1b]
keybind = cmd+one=text:\x1b1
# ...repeat for two..nine
```

**Alacritty** (`~/.config/alacritty/alacritty.toml`):

```toml
[[keyboard.bindings]]
key = "T"
mods = "Command"
chars = "\u001bt"

[[keyboard.bindings]]
key = "W"
mods = "Command"
chars = "\u001bw"
# ...repeat for N / bracket keys / Key1..Key9 — chars is "\u001b" + that key's character
```

**Kitty** (`~/.config/kitty/kitty.conf`):

```
map cmd+t send_text all \x1bt
map cmd+w send_text all \x1bw
map cmd+n send_text all \x1bn
map cmd+1 send_text all \x1b1
# ...repeat for 2..9 and the bracket keys
```

**Terminal.app** has no real GUI for this — either learn `option+t` or switch terminals.

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

### your old zellij config

if you already had a `~/.config/zellij/config.kdl`, the installer moves it aside to `~/.config/zellij/config.kdl.zellij-login.bak` before writing ours. uninstall puts it back byte-for-byte.

if you ever edit our managed `config.kdl` (keeping the `// managed-by: zellij-login` marker on top), uninstall will notice and **keep your edits** — your `.bak` gets renamed to `config.kdl.zellij-login.restored` so the original is still on disk but no longer in zellij's path.

want to own the file entirely? remove the `// managed-by: zellij-login` marker line. the uninstaller then leaves it alone.

if both `config.kdl` (user-owned, no marker) and `config.kdl.zellij-login.bak` already exist when you run the installer, it refuses-on-collision — exits non-zero with a clear error rather than silently clobbering your edits. move or remove one and re-run.

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

**i want to test changes without nuking my `.zshrc` or `config.kdl`.**
sandbox pattern:

```sh
tmp=$(mktemp -d)
export ZDOTDIR=$tmp \
       XDG_DATA_HOME=$tmp/.local/share \
       XDG_CACHE_HOME=$tmp/.cache \
       XDG_STATE_HOME=$tmp/.local/state \
       ZELLIJ_CONFIG_DIR=$tmp/.config/zellij
sh install.sh --no-install-deps
# poke around: cat $tmp/.zshrc, ls $tmp/.local/share/zellij-login/,
#              cat $tmp/.config/zellij/config.kdl
sh uninstall.sh
rm -rf $tmp
```

`XDG_STATE_HOME` matters — the config.kdl sha sidecar lives there, and without the override the sandbox would write into your real `~/.local/state`.

**i want to see what's in my `.zshrc` without opening the file.**

```sh
ssh host 'awk "/zellij-login:hook \{\{\{/,/zellij-login:hook \}\}\}/" ~/.zshrc'
```

## how it works

one zsh file (`zellij-ssh-login.zsh`) sourced from `.zshrc`. runs once per login shell, guarded on a chain of `SSH_TTY` / interactive / IDE-remote / in-zellij / skip-flag checks — in that order, cheapest-and-most-likely-to-fail first. on pass: an fzf picker listing sessions parsed from `zellij list-sessions -n`, then for new sessions a `find`-backed fzf picker for the directory with `ctrl-n` as "make subdir." then `zellij [--layout zellij-login] attach -c -- $name` in the chosen directory — `--layout` is a zellij top-level flag and must precede the `attach` subcommand, and the `--` before `$name` keeps a dash-prefixed name from being parsed as flags.

no `exec` — if zellij crashes or exits, the hook returns and you get a normal shell instead of getting logged out.

the installer and uninstaller are POSIX sh. they run under `dash`, pass `shellcheck --shell=sh`, and talk to each other through a pair of marker lines. the installer also detects any previous zmx-login install and migrates it — same one-liner, no manual steps. the sandbox test (`test/roundtrip.sh`) verifies the install → re-install-is-idempotent → uninstall-restores-byte-for-byte → legacy-migration contract on every CI run.

## dev

```sh
make check      # zsh -n, sh -n, shellcheck, sandbox round-trip + migration test
make test       # alias for check
make hooks      # one-time: point git at .githooks/ so pre-push runs make check
```

no remote CI — the same stack runs client-side as a `pre-push` git hook after `make hooks`. a failing check aborts the push; `git push --no-verify` bypasses it. the sandbox test uses a throwaway `$HOME`, so it never touches your real dotfiles.

see `AGENTS.md` if you're an AI agent working on this repo.

## license

mit. see [LICENSE](LICENSE).
