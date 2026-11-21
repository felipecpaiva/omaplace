#!/usr/bin/env bash
# libexec/procinfo.sh against real, harmless process trees: "terminal" -> shell -> program.
# Usage: bash tests/procinfo.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
script=$PWD/libexec/procinfo.sh

tmp=$(mktemp -d)
work="$tmp/my dir"
mkdir "$work"
mkfifo "$tmp/fifo"
printf '%s\n' 'cd "$1"; ( exec -a "$2" sleep 300 ); :' > "$tmp/prog.sh"
printf '%s\n' 'cd "$1"; exec 3<>"$2"; read -r -u 3 _; :' > "$tmp/idle.sh"
groups=()
cleanup() {
  local g
  for g in "${groups[@]}"; do kill -- "-$g" 2>/dev/null || true; done
  rm -f "$tmp/prog.sh" "$tmp/idle.sh" "$tmp/fifo"
  rmdir "$work" "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

fail=0 n=0
check() { # check <label> <condition result>
  n=$((n + 1))
  if [ "$2" = 0 ]; then echo "ok $1"; else echo "FAIL $1"; fail=1; fi
}

# expect <label> <json> <node expression on o>
expect() {
  local r=0
  node -e "const o = JSON.parse(process.argv[1]); process.exit(($3) ? 0 : 1)" "$2" || r=1
  check "$1" "$r"
}

# The "terminal" is its own process group, so cleanup takes the whole tree.
export OMAPLACE_TEST_SECRET=made-up-secret-value
setsid bash -c 'bash "$0" "$1" "$2"; :' "$tmp/prog.sh" "$work" 'we"ird\name' &
groups+=("$!")
term1=$!
setsid bash -c 'bash "$0" "$1" "$2"; :' "$tmp/idle.sh" "$work" "$tmp/fifo" &
groups+=("$!")
term2=$!

out1="{}"
for _ in $(seq 50); do
  out1=$(bash "$script" "$term1")
  [[ $out1 == *'"300"'* ]] && break
  sleep 0.1
done
expect "program: cwd is its folder, with a space" "$out1" 'o.cwd.endsWith("/my dir")'
expect "program: argv with a quote and a backslash" "$out1" 'JSON.stringify(o.argv) === JSON.stringify(["we\"ird\\name", "300"])'

out2="{}"
for _ in $(seq 50); do
  out2=$(bash "$script" "$term2")
  [[ $out2 == *idle.sh* ]] && break
  sleep 0.1
done
expect "shell itself when it has no child" "$out2" 'o.argv[0] === "bash" && o.argv[1].endsWith("idle.sh") && o.cwd.endsWith("/my dir")'

sleep 0 &
gone=$!
wait "$gone"
check "gone pid prints {}" "$([ "$(bash "$script" "$gone")" = "{}" ] && echo 0 || echo 1)"
sleep 300 &
lone=$!
check "no shell child prints {}" "$([ "$(bash "$script" "$lone")" = "{}" ] && echo 0 || echo 1)"
kill "$lone"
r=0
bash "$script" "not-a-pid" 2>/dev/null || r=$?
check "bad argument exits 2" "$([ "$r" = 2 ] && echo 0 || echo 1)"

all="$out1$out2"
check "no environment values" "$([[ $all != *made-up-secret-value* ]] && echo 0 || echo 1)"
check "no NAME=value lines" "$(printf '%s\n' "$out1" "$out2" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' && echo 1 || echo 0)"
check "one line each" "$([ "$(printf '%s\n' "$out1" | wc -l)" = 1 ] && echo 0 || echo 1)"

echo "procinfo: $n checks, $([ $fail = 0 ] && echo all passed || echo FAILED)"
exit $fail
