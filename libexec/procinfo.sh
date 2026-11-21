#!/usr/bin/env bash
# omaplace: the foreground program of a terminal window (design D12). Read only, /proc only.
# Usage: procinfo.sh <terminal pid>
# Prints one line: {"cwd":"<folder>","argv":[...]} for the deepest descendant that is a shell's child, or the shell itself.
# Prints {} when the pid is gone, has no shell, or cannot be read. Never reads or prints the environment.
set -euo pipefail

empty() { echo '{}'; exit 0; }

[ $# -eq 1 ] && [[ $1 =~ ^[0-9]+$ ]] || { echo "usage: procinfo.sh <pid>" >&2; exit 2; }

children() { # children <pid>: child pids, oldest first
  local f out=() kids
  for f in /proc/"$1"/task/*/children; do
    [ -r "$f" ] || continue
    read -r -a kids < "$f" || true
    out+=("${kids[@]}")
  done
  echo "${out[@]}"
}

is_shell() { # is_shell <pid>
  local comm
  read -r comm < /proc/"$1"/comm 2>/dev/null || return 1
  case $comm in bash | zsh | fish | sh | dash | ksh | nu | tcsh | xonsh) return 0 ;; *) return 1 ;; esac
}

json_str() { # json_str <text>: a JSON string, no tools beyond bash
  local s=$1 c i o u
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  for i in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
    printf -v o '%03o' "$i"
    printf -v c "\\$o"
    printf -v u '\\u%04x' "$i"
    s=${s//"$c"/$u}
  done
  printf '"%s"' "$s"
}

[ -d /proc/"$1" ] || empty
# shortcut: the terminal's shell is its newest child; a terminal with several tabs in one process gives that tab only.
read -r -a kids <<< "$(children "$1")"
[ ${#kids[@]} -gt 0 ] || empty
cur=${kids[-1]}
is_shell "$cur" || empty
while :; do
  read -r -a kids <<< "$(children "$cur")"
  [ ${#kids[@]} -gt 0 ] || break
  cur=${kids[-1]}
  is_shell "$cur" || break
done
cwd=$(readlink /proc/"$cur"/cwd 2>/dev/null) || empty
mapfile -d '' -t argv < /proc/"$cur"/cmdline 2>/dev/null || empty
[ ${#argv[@]} -gt 0 ] || empty

out='{"cwd":'"$(json_str "$cwd")"',"argv":['
sep=""
for a in "${argv[@]}"; do out+=$sep$(json_str "$a"); sep=","; done
echo "$out]}"
