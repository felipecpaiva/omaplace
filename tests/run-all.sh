#!/usr/bin/env bash
# All omaplace checks. Usage: bash tests/run-all.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0 ran=0 skipped=0

step() { # step <label> <command...>
  local label=$1; shift
  ran=$((ran + 1))
  if "$@"; then echo "PASS $label"; else echo "FAIL $label"; fail=$((fail + 1)); fi
}

have() { # have <tool>: true if installed, else print SKIP
  if [ -x "$1" ] || command -v "$1" >/dev/null 2>&1; then return 0; fi
  echo "SKIP ${1##*/} not installed"; skipped=$((skipped + 1)); return 1
}

# Hyprland embeds Lua 5.5; 5.4 accepts code that 5.5 rejects.
lua -e 'assert(_VERSION == "Lua 5.5", "run with Lua 5.5, like Hyprland (found " .. _VERSION .. ")")'

shopt -s nullglob
lua_tests=(lua/tests/test_*.lua)
mjs_tests=(tests/*.test.mjs)
sh_tests=(tests/*.test.sh)
qml_files=(*.qml)
shopt -u nullglob

[ ${#lua_tests[@]} -gt 0 ] || echo "lua tests: none yet"
for t in "${lua_tests[@]}"; do step "$t" lua "$t"; done
[ ${#mjs_tests[@]} -gt 0 ] || echo "node tests: none yet"
for t in "${mjs_tests[@]}"; do step "$t" node --test "$t"; done
[ ${#sh_tests[@]} -gt 0 ] || echo "bash tests: none yet"
for t in "${sh_tests[@]}"; do step "$t" bash "$t"; done

if have luacheck; then step luacheck luacheck lua; fi
if have stylua; then step stylua stylua --check lua; fi
if have shellcheck; then step shellcheck shellcheck tests/*.sh; fi
if have /usr/lib/qt6/bin/qmllint && [ ${#qml_files[@]} -gt 0 ]; then
  step qmllint /usr/lib/qt6/bin/qmllint "${qml_files[@]}"
fi

# the settings app (design 17): Qt tests offscreen against a fake shell
if have qmake6; then step "app tests" bash app/bin/test; fi

step scrub bash tests/scrub.sh
step validate omarchy-plugin-validate .

echo "summary: $ran run, $fail failed, $skipped skipped"
[ "$fail" -eq 0 ]
