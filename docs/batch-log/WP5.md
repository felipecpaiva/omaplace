# WP5 batch log: shell service and CLI (M2)

## What changed
- `Service.qml` (next editor after the WP0 stub): `IpcHandler { target: "io.github.felipecpaiva.omaplace" }` with typed
  functions `save`, `open`, `restore` (answers `not_yet` until WP7), `list`, `rename`, `remove`, `ruleAddFocused`,
  `ruleRemove`, `status`, `settings`. Each returns one line of JSON. Flows per design 6.2 and 6.3; all data work goes
  through the js/ modules; every process is a `Process` with an argv array.
- `js/Summary.js` (new, pure) and `tests/summary.test.mjs` (11 tests): name check, desktop entries to AppResolve's list,
  capture to scene windows (`sceneCapture`), terminal fields from procinfo plus ArgFilter, the scene's layout for the
  plan, status to result (`runResult`), notification text, rule for the focused window, scene list.
- `libexec/procinfo.sh`: read only, `/proc` and bash only (no jq), never reads `environ`.
- `bin/omaplace`: words of design 7.3, waits for `result-<req>.json` with `inotifywait` (1 s slices) or a 200 ms check,
  never longer than `request_timeout_s` (grep of config.toml, default 60).
- `tests/cli.test.sh` (62 checks, fake `omarchy-shell` first on PATH, temp HOME and XDG_RUNTIME_DIR),
  `tests/procinfo.test.sh` (10 checks, real `terminal -> shell -> program` trees in their own process group).
- Merged main (WP4) before the commit; `js/AppResolve.js` from main is kept as it is.

## Decisions
- **One slow request at a time.** While save, open or rule add runs, every method that writes (`rename`, `remove`,
  `ruleRemove`, and the slow ones) answers `busy`, so scenes.toml and config.toml never see two writers.
- **Every pending request ends in exactly one result file** (`finish()`), which also stops both timers, the status watch
  and clears busy. Each step is inside try/catch: a throw from SceneStore, ConfigIO, Plan or LuaLiteral becomes
  `{"ok":false,"code":"failed","reason":...}`.
- **Waiting without polling.** `hyprctl eval` returns after the Lua call ran, so the capture file is read once when the
  eval process exits. Missing: one 2 s one-shot, read again, still missing: `no_lua`. For open, status.json is read when
  the eval exits and then watched (`watchChanges` bound to `watching`, on only while an open runs, same as omahop's state
  file that Lua also writes by rename). No status for our run within 2 s: `no_lua`, or `busy` when status.json shows
  another run still `running`. The request timeout is one one-shot, set 0.5 s inside `request_timeout_s` so the CLI
  reads the service's timeout result instead of giving up first.
- **Folders.** One `mkdir -p -m 700 <runtime>/omaplace ~/.config/omaplace` Process before the first slow request of the
  service's life (the config folder gets 700 too when the service creates it).
- **Writes.** `FileView` with `atomicWrites` (temp file, then rename) and `blockWrites`. Before every write of scenes.toml
  or config.toml the old text goes to `scenes.toml.bak` / `config.toml.bak`. A scenes.toml with a newer schema or a
  section with a bad scene name is never rewritten (`SceneStore.serialize` writes the whole file and would drop it).
- **Save.** Windows AppResolve cannot start are not saved and counted as `skipped`; a window of a context app (strategy
  `use = context`: Chrome, Firefox, the VS Code family) with no `omaplace-ctx` tag (capture gives no context) is saved
  with context `?` and counted as `need_profile` (design 5.4a rule 3). An empty desktop fails (`no app on this desktop can be saved`) instead of erasing the
  scene. Terminal windows (strategy `use = terminal`) with a `pid` get `procinfo.sh`, one at a time; argv goes through
  ArgFilter; a shell in the foreground keeps no program; the folder under HOME is saved as `~/...`. An argument or
  folder holding a double quote or a line break (scenes.toml has no escapes) is dropped and counted in `dropped`.
- **Open.** `Plan.fromScene` with target `{ fp: {identity: home_monitor} or {}, slot: home_slot, layout, expiry_s }`.
  `layout` is the scene's own: `floating` when every saved window was floating, else `tiled` (Lua uses it only for an
  empty target, WP4). Rules come from config.toml, so Plan adds `desktop` per D9.
- **Counts.** Status item `moved` is a window that was already open, `placed` one omaplace started. The result's
  `placed` = moved + placed, `started` = placed, plus `skipped`, `not_reopened`, `failed`. Run `done` and `partial` are
  `ok: true` (CLI exit 4 for partial); `interrupted` or `failed` are `code: failed`.
- **Notification.** One `omarchy-notification-send "omaplace: <scene>" "<counts>"` after every open, also when it
  failed (`could not open (no_lua)`). Never titles.
- **Rule add.** `hyprctl activewindow -j` gives the focused window's `initialClass`; a `focused` capture gives its
  monitor identity and slot. Rule name is the class in lower case with other characters as `-`. Then
  `hyprctl eval _G.omaplace.reload_config()`.
- **Ids.** Request `q<counter>-<ms>`, run `r<counter>-<ms>`, made in QML; JS stays clock free.
- **CLI exit codes.** ok 0; usage and `bad_name` 2; `not_found` 3; `partial` 4 (save, open, restore only); `busy`,
  `not_yet`, `failed`, timeout, shell not reachable, bad answer 5; `no_lua` 6 with the README line. `--json` prints the
  final answer (the result file for a pending request).

## Lua contract used (WP4, read from lua/omaplace.lua on main)
- `capture(req, "focused")` writes `capture-<req>.json`: `monitors[].fp.identity`, `windows[]` with `class`, `monitor`
  (index), `slot`, `order`, `rect`, `floating`, `context`, `pid`. The capture has no focused-window marker, hence
  `hyprctl activewindow` for rule add.
- `open_file(path)` only takes `$XDG_RUNTIME_DIR/omaplace/plan-*.lua`; status.json is `{run, state, items[{class, state}]}`.

## Verified
- `bash tests/run-all.sh`: 25 run, 0 failed, 3 skipped. `bash tests/scrub.sh` ok. `omarchy-plugin-validate .` ok.
- `qmllint Service.qml SettingsPanel.qml`: no warnings. It resolves the Quickshell imports (checked by adding a bogus
  property to a copy, which it reported as `missing-property`).
- No live run: no shell reload, no plugin install, nothing under ~/.config or Hyprland touched.

## Known limits (need the live check)
- `hyprctl eval` output is not read. A plan Lua refuses at once (`bad_plan`, `no_monitor`) writes no status, so it is
  reported as `no_lua` after 2 s. If WP4 writes a failed status for those, the service reports them correctly.
- `FileView` behaviour assumed from the Quickshell types and omahop: `reload()` plus `waitForJob()` with `blockLoading`
  gives the current text; `setText` right after a `path` change writes the new path (result and plan files);
  `onSaveFailed` fires before `setText` returns with `blockWrites`. Rename, remove and rule remove answer from that.
- `procinfo.sh` follows the terminal's newest child down through shells (a program started straight by the terminal,
  as `xdg-terminal-exec --dir=X prog` does, is the answer itself); a terminal that runs many tabs in one process gives that
  tab only (`shortcut:` comment in the script).
- Result, capture and plan files stay in the runtime folder (tmpfs, cleared at logout); nothing deletes them.

## SKIPs
- luacheck, stylua, shellcheck not installed.
