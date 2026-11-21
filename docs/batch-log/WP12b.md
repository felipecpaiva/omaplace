# WP12b batch log: desktop plans, service and CLI side (design 14.8)

Coded against the 14.8 contract only; the Lua side (WP12a) was built in parallel and not touched. No live test was run.

## What was built

- `js/ModeSwitch.js` (new, pure): `decide({ want, current, hasSet, userStarted, tries })` gives one step at a time:
  `none`, `set`, `toggle`, `skip` or `fail` with a reason. The service runs the step, reads the mode again and asks
  again. Omarchy prints and takes `dwindle` for tiled: `fromOmarchy` and `toOmarchy` map it, so a tiled plan never reads
  as different. Set runs once and is verified. Without the set command a user started open presses the toggle at most 2
  times (two presses reach any of the three modes); at login it skips and says so. An unreadable mode never gets a blind
  press. `workspaceOf(desktops, home_monitor, home_slot)` finds the plan's workspace id (empty monitor: the focused one).
- `js/PlanMoves.js` (new, pure): `parse` (well formed moves of plan-moves.json), `fresh` (ids above the last notified;
  a newest id below it means Lua's counter started again, so all count as new), `find`, `notice` (class and scene name
  only), `zoneAt(layout, rect)` (zone holding the rect's centre, far edges included, first match where zones overlap),
  `edit(doc, move)` (the "Update plan" scene edit, see decisions). The input doc is never changed. Any plan the edit would
  make invalid (`SceneStore.planProblems`, compared with before) refuses it as `not_possible`, so `serialize()` never
  throws on an edit. Reasons hold no commas or double quotes (the CLI's field reader stops at either).
- `Service.qml`:
  - plans.lua: `writePlans()` builds `PlansFile.build` and writes `~/.local/state/omaplace/plans.lua` atomically at
    start (after `mkdirProc`, which now also makes the state folder and runs at load), after every `writeScenes`, and
    when `scenes.toml` changes on disk (now watched). Same text as last time: no write. After a write: `reload_plans`
    through `LuaCall.wrap` on its own Process pair and reply file (`reply-plans.txt`), one call at a time plus one more
    if a write came meanwhile; a non-ok answer is logged. `reload_plans` is also called at every start even when
    plans.lua did not change (WP12a: it is Lua's retry of its login.json write).
  - Opening a plan: `startOpen` marks plan scenes; `step()` sends them through `planDesktops` (`desktops(req_id)` through
    `LuaCall.wrap`; Lua writes `desktops-<req>.json`, read with the reply in one `cat`, deleted in `finish()`; then `layout-current`, then set or focus + `activeworkspace` check + toggle, then `layout-current`
    again) before the existing `writePlan` flow. `full` skips all of it. A missing desktop, a skip or a fail does not
    stop the open: the reason goes into the result as `note` and into the open notification. `no_lua` from desktops()
    ends the request. The set command is called through `env`, whose exit 127 means not installed (argv only, no shell).
    A scene with a plan error is refused before anything runs. Each callback checks it still belongs to the running
    request. IPC `openPlan(name)` is the same entry as `open`.
  - Moves: `plan-moves.json` watched; one `omarchy-notification-send <headline> <body> --action "Update plan" <cli path>
    plan-update <id>` per new move, queued on one Process. Moves in the file at load are marked as notified.
  - IPC `planUpdate(id)`: busy guard, finds the move by id, `writableScenes` guard, `PlanMoves.edit`, `writeScenes`
    (which also rewrites plans.lua). Answers `{ok, scene, changed}` or `not_found` / `not_possible` / `failed` with a reason.
  - Login: `login.json` watched and read at start; when its instance is this Hyprland's and no `login-done-<sig>` marker
    is in the runtime folder, the marker is written first, then the listed plans open one request after another
    (`finish()` starts the next). Each name is checked again: still a valid plan with `open_at_login = true`.
  - `finish()` also reads plan-moves.json and login.json again (a watch can miss a rename).
- `bin/omaplace`: `plan-update <id>` (digits only, else usage error 2) maps to `planUpdate`; prints `plan <name> updated`
  or `the plan already says so`; `not_possible` exits 5 with the reason; `not_found` now prints its reason when there is
  one. Without a terminal (the notification button) the answer comes back as a notification, like save and rule.

## Decisions (contract gaps, see report)

1. `to.rect` is read as fractions of the usable area, like scene rects; absent or null (tiled windows, WP12a) is fine.
   `seq` is not used, moves go by `id`. The set command is assumed to take Omarchy's mode words (`dwindle`).
2. Zone move onto a zone another window of the plan holds: `not_possible` (no swap guessing).
3. Desktop move, single-window plan: rebinds `home_monitor`/`home_slot`; when the target desktop already has a plan that
   would be two plans on one desktop, so `not_possible`.
4. Desktop move from a many-window plan into the target plan: zone layout takes the zone holding the centre (none or
   taken: `not_possible`); tiled and scrolling append (zone = highest + 1); free takes `to.rect` and `to.floating`;
   full refuses a second window.
5. `omaplace open <plan>` from the CLI also gets the mode switch (14.8 lists it with the other ways to open a plan).
6. The notification's action runs the CLI by its full plugin path: `omaplace` is not on PATH.
7. Watches are re-armed after each change event (`watchChanges` off and on, `Qt.callLater`), with a `shortcut:` note.

## Known limits

- A FileView watch on a file that is replaced by rename may still lose events (live-M1). Re-arming is unverified live.
  A plan-moves.json that does not exist when the shell starts may not be watched at all, so the first move after a
  login may wait for the next request end.
  A missed plan move is only noticed at the next request end. If the live check fails, the clean fix is Lua calling an
  IPC method after it writes plan-moves.json (no polling allowed).
- Move ids restart with Hyprland; a notification left from an old instance can name a new move with the same id.
- If a request times out while a mode switch command still runs and a new plan open starts at once, its first command
  is not started (same Process) and that request times out too.

## Verified

- `bash tests/run-all.sh`: 43 run, 0 failed, 3 skipped (luacheck, stylua, shellcheck not installed).
- New tests: `tests/mode_switch.test.mjs` (8), `tests/plan_moves.test.mjs` (11), `tests/cli.test.sh` (+15 checks for plan-update, 102 total). qmllint via `tests/qml_lint.test.sh`: ok.
- `bash tests/scrub.sh`: ok.
- Not verified: anything live (checklist `docs/checklist/WP12b.md`).
