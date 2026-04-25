#!/bin/sh
# zellij-login preview — renders right-pane metadata for the fzf session picker.
# Invoked once per highlighted line as: sh zellij-login-preview.sh "<picker line>".
# POSIX sh on purpose — runs many times during scroll, startup cost matters.

name=$1
[ -z "$name" ] && exit 0

# Strip our icon prefix ("● " / "✗ ") if present. Literal-prefix match so
# the multi-byte glyph can't confuse a char-based `cut` implementation.
case "$name" in
  "● "*) name=${name#"● "} ;;
  "✗ "*) name=${name#"✗ "} ;;
esac

# Sentinels — nothing to preview.
case "$name" in
  "[ skip · plain shell ]")
    printf 'skip the picker. land in a plain shell — no zellij, no persistence.\n'
    exit 0 ;;
  "[+ new session ]")
    printf 'create a new zellij session. you'\''ll be prompted for a name and a\n'
    printf 'starting directory.\n'
    exit 0 ;;
esac

cache="${XDG_CACHE_HOME:-$HOME/.cache}/zellij-login"

# Pull this session's line out of the hook's list-sessions snapshot.
# Fall back to a live `zellij list-sessions -n` only if the snapshot is
# missing (first install, sandboxed tests) or doesn't contain the name
# (stale by one keystroke after an external session change). Snapshot read
# avoids the per-keystroke zellij fork that scrolling the picker used to
# trigger.
list_cache="$cache/.sessions.txt"
status_line=""
if [ -r "$list_cache" ]; then
  status_line=$(awk -v n="$name" '$1 == n { print; exit }' "$list_cache")
fi
if [ -z "$status_line" ]; then
  status_line=$(zellij list-sessions -n 2>/dev/null \
    | awk -v n="$name" '$1 == n { print; exit }')
fi

if [ -z "$status_line" ]; then
  printf 'session:  %s\n' "$name"
  printf 'status:   (not currently known to zellij)\n'
  exit 0
fi

case "$status_line" in
  *EXITED*) status='exited (attach to resurrect)' ;;
  *)        status='active' ;;
esac

# Parse the `Created <duration> ago` window.
created=$(printf '%s' "$status_line" | sed -n 's/.*\[Created \(.*\) ago\].*/\1/p')

cwd=""
[ -f "$cache/cwds/$name" ] && cwd=$(cat "$cache/cwds/$name")

last=""
if [ -f "$cache/attached/$name" ]; then
  # GNU stat first — `-f %m` on Linux misparses as filesystem-info mode and
  # pollutes stdout with garbage; `-c %Y` works on Linux, BSD falls through.
  ts=$(stat -c %Y "$cache/attached/$name" 2>/dev/null \
       || stat -f %m "$cache/attached/$name" 2>/dev/null \
       || echo 0)
  if [ "$ts" -gt 0 ]; then
    now=$(date +%s)
    delta=$(( now - ts ))
    if   [ "$delta" -lt 60    ]; then last="${delta}s ago"
    elif [ "$delta" -lt 3600  ]; then last="$(( delta / 60 ))m ago"
    elif [ "$delta" -lt 86400 ]; then last="$(( delta / 3600 ))h ago"
    else                              last="$(( delta / 86400 ))d ago"
    fi
  fi
fi

printf 'session:  %s\n' "$name"
printf 'status:   %s\n' "$status"
[ -n "$created" ] && printf 'created:  %s ago\n' "$created"
[ -n "$last" ]    && printf 'last:     %s\n' "$last"
[ -n "$cwd" ]     && printf 'cwd:      %s\n' "$cwd"
