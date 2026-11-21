#!/usr/bin/env bash
# bin/omaplace against a fake omarchy-shell: argument mapping, every exit code, the wait for result files, the timeout.
# HOME and XDG_RUNTIME_DIR point at a temp folder, so nothing real is read or written.
# Usage: bash tests/cli.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
cli=$PWD/bin/omaplace
bash_bin=$(command -v bash)

tmp=$(mktemp -d)
export HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" XDG_CONFIG_HOME="$tmp/home/.config"
mkdir -p "$HOME/.config/omaplace" "$XDG_RUNTIME_DIR/omaplace" "$tmp/bin" "$tmp/nobin"
export FAKE_LOG="$tmp/calls" OMAPLACE_NOTIFY=0

# The fake: logs its arguments, prints FAKE_ANSWER, exits FAKE_EXIT, and when FAKE_RESULT is set writes it as the
# result file of request FAKE_REQ after FAKE_DELAY seconds (temp file, then rename, like the service).
cat > "$tmp/bin/omarchy-shell" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
if [ -n "${FAKE_RESULT:-}" ]; then
  (
    sleep "${FAKE_DELAY:-0.3}"
    out="$XDG_RUNTIME_DIR/omaplace/result-$FAKE_REQ.json"
    printf '%s\n' "$FAKE_RESULT" > "$out.tmp"
    mv "$out.tmp" "$out"
  ) > /dev/null 2>&1 &
fi
if [ "${2:-}" = list ] && [ -n "${FAKE_LIST:-}" ]; then printf '%s\n' "$FAKE_LIST"; exit 0; fi
[ -z "${FAKE_ANSWER:-}" ] || printf '%s\n' "$FAKE_ANSWER"
exit "${FAKE_EXIT:-0}"
FAKE
chmod +x "$tmp/bin/omarchy-shell"
# Fake Omarchy pickers and hyprctl (the real pickers would open the live menu): log the arguments, print FAKE_PICK
# (FAKE_PICK_EXIT=1 is a closed picker, like the real ones).
for picker in omarchy-menu-input omarchy-menu-select; do
  cat > "$tmp/bin/$picker" <<'FAKE'
#!/usr/bin/env bash
printf '%s|' "${0##*/}" "$@" >> "$FAKE_LOG.pick"; echo >> "$FAKE_LOG.pick"
[ "${FAKE_PICK_EXIT:-0}" = 0 ] || exit "$FAKE_PICK_EXIT"
printf '%s\n' "${FAKE_PICK:-}"
FAKE
  chmod +x "$tmp/bin/$picker"
done
cat > "$tmp/bin/hyprctl" <<'FAKE'
#!/usr/bin/env bash
printf '{\n    "id": 3,\n    "name": "%s",\n    "monitor": "made-up-1",\n    "windows": 2\n}\n' "${FAKE_WS-Dev Work}"
FAKE
chmod +x "$tmp/bin/hyprctl"
# A PATH without inotifywait, for the 200 ms fallback.
for t in bash sed head grep cat sleep mv mkdir; do ln -s "$(command -v "$t")" "$tmp/nobin/$t"; done
ln -s "$tmp/bin/omarchy-shell" "$tmp/nobin/omarchy-shell"
export PATH="$tmp/bin:$PATH"

cleanup() {
  sleep 0.6 # let the fake's late writers finish
  rm -f "$tmp"/bin/* "$tmp"/nobin/* "$tmp/calls" "$tmp/calls.pick" "$tmp/out" "$XDG_RUNTIME_DIR"/omaplace/* "$HOME/.config/omaplace/config.toml"
  rmdir "$XDG_RUNTIME_DIR/omaplace" "$XDG_RUNTIME_DIR" "$HOME/.config/omaplace" "$HOME/.config" "$HOME" "$tmp/bin" "$tmp/nobin" "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

fail=0 n=0
check() { # check <label> <0 for pass>
  n=$((n + 1))
  if [ "$2" = 0 ]; then echo "ok $1"; else echo "FAIL $1"; fail=1; fi
}
# run <args...>: runs the CLI with the current FAKE_* settings; sets $code and $out (stdout and stderr)
run() {
  : > "$FAKE_LOG"
  : > "$FAKE_LOG.pick"
  code=0
  "$bash_bin" "$cli" "$@" > "$tmp/out" 2>&1 || code=$?
  out=$(cat "$tmp/out")
}
is() { [ "$1" = "$2" ] && echo 0 || echo 1; }
has() { [[ $1 == *"$2"* ]] && echo 0 || echo 1; }
reset() { unset FAKE_ANSWER FAKE_EXIT FAKE_RESULT FAKE_REQ FAKE_DELAY FAKE_LIST FAKE_PICK FAKE_PICK_EXIT FAKE_WS; }

# ---- usage, exit 2, the shell is never called
reset
for bad in "" "save" "save a b" "open" "rename a" "rename a b c" "list x" "rule" "rule add x" "rule remove" "frobnicate" "restore a b"; do
  # shellcheck disable=SC2086
  run $bad
  check "usage error: '$bad' exits 2" "$(is "$code" 2)"
  check "usage error: '$bad' calls nothing" "$(is "$(cat "$FAKE_LOG")" "")"
done
run --help
check "--help exits 0" "$(is "$code" 0)"
check "--help lists the words" "$(has "$out" "rule remove <name>")"

# ---- argument mapping and immediate answers
export FAKE_ANSWER='{"ok":true,"scenes":[{"name":"work","windows":4},{"name":"play","windows":0}]}'
run list
check "list exits 0" "$(is "$code" 0)"
check "list calls the target with no argument" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace list")"
check "list prints names and counts" "$(is "$out" "work  4 windows
play  0 windows")"
run --json list
check "--json passes the line through" "$(is "$out" "$FAKE_ANSWER")"

export FAKE_ANSWER='{"ok":true}'
run rename work dev
check "rename maps two arguments" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace rename work dev")"
run rule remove editor
check "rule remove maps to ruleRemove" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace ruleRemove editor")"
run restore
check "restore always passes one argument" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace restore ")"
run restore 2
check "restore 2 passes the generation" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace restore 2")"
run settings
check "settings exits 0" "$(is "$code" 0)"

export FAKE_ANSWER='{"ok":true,"busy":false,"run":"r3-1700000000000","state":"partial","items":2}'
run status
check "status prints the run" "$(is "$out" "run: r3-1700000000000 partial")"
check "status of a partial run still exits 0" "$(is "$code" 0)"

# ---- error codes
export FAKE_ANSWER='{"ok":false,"code":"not_found"}'
run remove ghost
check "not_found exits 3" "$(is "$code" 3)"
export FAKE_ANSWER='{"ok":false,"code":"bad_name"}'
run save Bad
check "bad_name exits 2" "$(is "$code" 2)"
export FAKE_ANSWER='{"ok":false,"code":"busy"}'
run open work
check "busy exits 5" "$(is "$code" 5)"
export FAKE_ANSWER='{"ok":false,"code":"not_yet"}'
run restore
check "not_yet exits 5" "$(is "$code" 5)"
export FAKE_ANSWER='{"ok":false,"code":"no_lua"}'
run status
check "no_lua exits 6" "$(is "$code" 6)"
check "no_lua prints the dofile line" "$(has "$out" 'pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.felipecpaiva.omaplace/lua/omaplace.lua")')"
export FAKE_ANSWER="" FAKE_EXIT=1
run list
check "shell not reachable exits 5" "$(is "$code" 5)"
check "shell not reachable says so" "$(has "$out" "not reachable")"
reset

# ---- pending requests: wait for result-<req>.json
export FAKE_REQ=q1-1700000000000 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q1-1700000000000"}'
export FAKE_RESULT='{"ok":true,"saved":4,"skipped":1,"need_profile":0,"dropped":0}'
run save work
check "save waits for its result and exits 0" "$(is "$code" 0)"
check "save prints counts" "$(is "$out" "saved work: 4 windows, 1 skipped, 0 need a profile")"

check "save maps its name" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace save work")"

# From the Omarchy menu (no terminal): the same answer goes to a notification, not stdout.
printf '#!/usr/bin/env bash\nprintf "%%s|" "$@" > "%s/notified"\n' "$tmp" > "$tmp/bin/omarchy-notification-send"; chmod +x "$tmp/bin/omarchy-notification-send"
OMAPLACE_NOTIFY=1 "$bash_bin" "$cli" save work >/dev/null 2>&1 </dev/null
check "no terminal: save answer is a notification" "$(grep -q "saved work: 4 windows" "$tmp/notified" 2>/dev/null && echo 0 || echo 1)"
rm -f "$tmp/bin/omarchy-notification-send"

export FAKE_REQ=q2-1700000000001 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q2-1700000000001"}'
export FAKE_RESULT='{"ok":true,"state":"done","run":"r2-1","placed":3,"started":2,"skipped":0,"not_reopened":0,"failed":0}'
run open work
check "open done exits 0" "$(is "$code" 0)"
check "open prints counts" "$(is "$out" "opened work: 3 placed (2 started), 0 skipped, 0 not reopened, 0 failed")"

export FAKE_REQ=q3-1700000000002 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q3-1700000000002"}'
export FAKE_RESULT='{"ok":true,"state":"partial","run":"r3-1","placed":2,"started":1,"skipped":1,"not_reopened":1,"failed":0}'
run open work
check "open partial exits 4" "$(is "$code" 4)"
run --json open work
check "--json prints the final result" "$(is "$out" "$FAKE_RESULT")"

export FAKE_REQ=q4-1700000000003 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q4-1700000000003"}'
export FAKE_RESULT='{"ok":false,"code":"failed","state":"interrupted","run":"r4-1","placed":0,"started":0}'
run open work
check "open failed exits 5" "$(is "$code" 5)"
export FAKE_RESULT='{"ok":false,"code":"no_lua"}'
rm -f "$XDG_RUNTIME_DIR/omaplace/result-$FAKE_REQ.json"
run save work
check "pending no_lua exits 6" "$(is "$code" 6)"

export FAKE_REQ=q5-1700000000004 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q5-1700000000004"}'
export FAKE_RESULT='{"ok":true,"rule":"org-example-editor"}'
run rule add
check "rule add maps to ruleAddFocused" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace ruleAddFocused")"
check "rule add prints the rule" "$(is "$out" "rule added: org-example-editor")"

# without inotifywait: checks every 200 ms
export FAKE_REQ=q6-1700000000005 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q6-1700000000005"}'
export FAKE_RESULT='{"ok":true,"saved":1,"skipped":0,"need_profile":0}' FAKE_DELAY=0.5
code=0
PATH="$tmp/nobin" "$bash_bin" "$cli" save work > "$tmp/out" 2>&1 || code=$?
check "without inotifywait the result is still read" "$(is "$code" 0)"
check "without inotifywait the answer is right" "$(has "$(cat "$tmp/out")" "saved work: 1 windows")"

# timeout from config.toml, no result ever written
unset FAKE_RESULT
printf '%s\n' "# made-up config" "request_timeout_s = 1" > "$HOME/.config/omaplace/config.toml"
export FAKE_REQ=q7-1700000000006 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q7-1700000000006"}'
start=$SECONDS
run open work
check "timeout exits 5" "$(is "$code" 5)"
check "timeout says so" "$(has "$out" "no answer after 1 s")"
check "timeout honours request_timeout_s" "$([ $((SECONDS - start)) -le 3 ] && echo 0 || echo 1)"
start=$SECONDS
code=0
PATH="$tmp/nobin" "$bash_bin" "$cli" open work > "$tmp/out" 2>&1 || code=$?
check "timeout without inotifywait exits 5 in time" "$([ "$code" = 5 ] && [ $((SECONDS - start)) -le 3 ] && echo 0 || echo 1)"

export FAKE_ANSWER='{"ok":true,"pending":true,"req":"../../etc"}'
run open work
check "a bad request id is refused" "$(is "$code" 5)"

# ---- fix: saving an empty desktop, restore counts (the default 60 s limit again)
rm -f "$HOME/.config/omaplace/config.toml"
export FAKE_REQ=q8-1700000000007 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q8-1700000000007"}'
export FAKE_RESULT='{"ok":false,"code":"empty","reason":"nothing to save on this desktop"}'
run save work
check "an empty desktop exits 3" "$(is "$code" 3)"
check "an empty desktop says so" "$(is "$out" "omaplace: nothing to save on this desktop")"
export FAKE_REQ=q9-1700000000008 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q9-1700000000008"}'
export FAKE_RESULT='{"ok":true,"state":"done","run":"r9-1","placed":4,"started":3,"skipped":1,"not_reopened":0,"failed":0}'
run restore
check "restore prints counts" "$(is "$out" "restored the last session: 4 placed (3 started), 1 skipped, 0 not reopened, 0 failed")"
check "restore done exits 0" "$(is "$code" 0)"
reset

# ---- the menu rows: save --ask and open --pick with fake pickers
export FAKE_REQ=q10-1700000000009 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q10-1700000000009"}'
export FAKE_RESULT='{"ok":true,"saved":2,"skipped":0,"need_profile":0}'
export FAKE_PICK="morning"
run save --ask
check "save --ask saves under the typed name" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace save morning")"
check "save --ask offers the desktop name as the default" "$(is "$(cat "$FAKE_LOG.pick")" "omarchy-menu-input|Scene name (Enter for dev-work)|")"
export FAKE_PICK=""
run save --ask
check "save --ask with Enter alone uses the desktop name" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace save dev-work")"
export FAKE_WS="" FAKE_PICK=""
run save --ask
check "save --ask with no default and no name is a usage error" "$(is "$code" 2)"
check "save --ask asks without a default when there is none" "$(is "$(cat "$FAKE_LOG.pick")" "omarchy-menu-input|Scene name|")"
unset FAKE_WS
export FAKE_PICK_EXIT=1
run save --ask
check "closing the name picker saves nothing and exits 0" "$(is "$code:$(cat "$FAKE_LOG")" "0:")"
reset

export FAKE_LIST='{"ok":true,"scenes":[{"name":"work","windows":4},{"name":"play","windows":0}]}'
export FAKE_REQ=q11-1700000000010 FAKE_ANSWER='{"ok":true,"pending":true,"req":"q11-1700000000010"}'
export FAKE_RESULT='{"ok":true,"state":"done","run":"r11-1","placed":1,"started":1,"skipped":0,"not_reopened":0,"failed":0}'
export FAKE_PICK="play"
run open --pick
check "open --pick lists the scenes in the picker" "$(is "$(cat "$FAKE_LOG.pick")" "omarchy-menu-select|Open a scene|work|play|")"
check "open --pick opens the choice" "$(is "$(tail -n1 "$FAKE_LOG")" "io.github.felipecpaiva.omaplace open play")"
check "open --pick prints counts" "$(is "$out" "opened play: 1 placed (1 started), 0 skipped, 0 not reopened, 0 failed")"
export FAKE_PICK_EXIT=1
run open --pick
check "closing the scene picker opens nothing and exits 0" "$(is "$code:$(cat "$FAKE_LOG")" "0:io.github.felipecpaiva.omaplace list")"
unset FAKE_PICK_EXIT
export FAKE_LIST='{"ok":true,"scenes":[]}'
run open --pick
check "open --pick with no scenes exits 3" "$(is "$code" 3)"
check "open --pick with no scenes never opens the picker" "$(is "$(cat "$FAKE_LOG.pick")" "")"
reset
for bad in "save --ask x" "open --pick x" "plan-update" "plan-update 1 2" "plan-update x1" "plan-update -3"; do
  # shellcheck disable=SC2086
  run $bad
  check "usage error: '$bad' exits 2" "$(is "$code" 2)"
  check "usage error: '$bad' calls nothing" "$(is "$(cat "$FAKE_LOG")" "")"
done

# ---- plan-update (WP12b): the "Update plan" notification button
export FAKE_ANSWER='{"ok":true,"scene":"desk-2","changed":true}'
run plan-update 7
check "plan-update maps to planUpdate with the id" "$(is "$(cat "$FAKE_LOG")" "io.github.felipecpaiva.omaplace planUpdate 7")"
check "plan-update exits 0" "$(is "$code" 0)"
check "plan-update says which plan" "$(is "$out" "plan desk-2 updated")"
export FAKE_ANSWER='{"ok":true,"scene":"desk-2","changed":false}'
run plan-update 7
check "plan-update with nothing to change says so" "$(is "$out:$code" "the plan already says so:0")"
export FAKE_ANSWER='{"ok":false,"code":"not_possible","reason":"plan desk-3 would be invalid: desktop 2 of \"Example Corp EX27\" already has plan desk-2, pick another"}'
run plan-update 8
check "plan-update not possible exits 7" "$(is "$code" 7)"
check "plan-update not possible gives the whole reason, commas and quotes too" "$(is "$out" 'omaplace: plan not updated: plan desk-3 would be invalid: desktop 2 of "Example Corp EX27" already has plan desk-2, pick another')"
export FAKE_ANSWER='{"ok":false,"code":"not_found","reason":"that move is too old"}'
run plan-update 9
check "plan-update of an unknown move exits 3 with the reason" "$(is "$out:$code" "omaplace: not found (that move is too old):3")"
export FAKE_ANSWER='{"ok":false,"code":"busy"}'
run plan-update 9
check "plan-update while busy exits 5" "$(is "$code" 5)"
# From a notification button there is no terminal: the answer comes back as a notification.
printf '#!/usr/bin/env bash\nprintf "%%s|" "$@" > "%s/notified"\n' "$tmp" > "$tmp/bin/omarchy-notification-send"; chmod +x "$tmp/bin/omarchy-notification-send"
export FAKE_ANSWER='{"ok":false,"code":"not_possible","reason":"the window is outside every zone"}'
code=0
OMAPLACE_NOTIFY=1 "$bash_bin" "$cli" plan-update 3 >/dev/null 2>&1 </dev/null || code=$?
check "no terminal: plan-update answer is a notification" "$(grep -q "plan not updated: the window is outside every zone" "$tmp/notified" 2>/dev/null && echo 0 || echo 1)"
check "no terminal: plan-update keeps its exit code" "$(is "$code" 7)"
rm -f "$tmp/bin/omarchy-notification-send" "$tmp/notified"
reset

echo "cli: $n checks, $([ $fail = 0 ] && echo all passed || echo FAILED)"
exit $fail
