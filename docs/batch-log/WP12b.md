# WP12b batch log: desktop plans, service and CLI side (design 14.8)

Coded against the 14.8 contract and WP12a's notes; rebased onto main after WP12a merged. Lua was not touched. No live
test was run.

## What was built

- `js/ModeSwitch.js` (new, pure): `decide({ want, current, hasSet, userStarted, tries })` gives one step at a time:
  `none`, `set`, `toggle` (with `direction`, next or back), `skip` or `fail` with a reason. The service runs the step,
  reads the mode again and asks again. Omarchy prints and takes `dwindle` for tiled: `fromOmarchy` and `toOmarchy` map
  it, so a tiled plan never reads as different. Set runs once and is verified. Without the set command a user started open
  presses the toggle in the direction that reaches the mode in one press (a test walks Omarchy's next and back cycles for
  all 9 pairs), at most 2 presses, verified after each; at login it skips and says so. An unreadable mode never gets a
  blind press. `workspaceOf(desktops, home_monitor, home_slot)` finds the plan's workspace id (empty monitor: focused).
- `js/PlanMoves.js` (new, pure): `parse` (well formed moves of plan-moves.json; `to.rect` may be absent or null),
  `find`, `zoneAt(layout, rect)` (zone holding the rect's centre, far edges included, first match where zones overlap),
  `edit(doc, move)` (the "Update plan" scene edit, see decisions). The input doc is never changed. Any plan the edit would
  make invalid (`SceneStore.planProblems`, compared with before) refuses it as `not_possible`, so `serialize()` never
  throws on an edit.
- `Service.qml`:
  - plans.lua: `writePlans()` builds `PlansFile.build` and writes `~/.local/state/omaplace/plans.lua` atomically at
    start (after `mkdirProc`, which now also makes the state folder and runs at load), after every `writeScenes`, and
    when `scenes.toml` changes on disk (now watched). Same text as last time: no write. After a write: `reload_plans`
    through `LuaCall.wrap` on its own Process pair, one call at a time plus one more if a write came meanwhile; a non-ok
    answer is logged; `reply-plans.txt` is deleted after it is read. The first write of a start always happens, so
    `reload_plans` runs at every start (WP12a: Lua's retry of its login.json write); only a failed build calls it alone.
    After every `reload_plans` answer the service checks login.json again.
  - Opening a plan: `startOpen` marks plan scenes and refuses one with a plan error; `step()` sends plans through
    `planDesktops`: `desktops(req_id)` through `LuaCall.wrap` with its own reply file (`reply-<req>-desktops.txt`); Lua
    writes `desktops-<req>.json`; one `cat` reads both; then `layout-current`, then set or focus + `activeworkspace`
    check + toggle, then `layout-current` again; then the existing `writePlan` flow. `full` skips all of it. A missing
    desktop, a skip or a fail does not stop the open: the reason goes into the result as `note` and into the open
    notification. `no_lua` from desktops() ends the request. The set command is called through `env`, whose exit 127
    means not installed (argv only, no shell; caveat commented: a set command that itself exits 127 reads the same, the
    toggle fallback still verifies). Every chain launch gets a token; `finish()` stops the three chain Processes, clears
    the callback and bumps the token, so a late answer does nothing and the next request starts clean.
    IPC `openPlan(name)` is the same entry as `open`.
  - Moves: Lua sends the "Update plan" notification itself (design change after WP12a). The service only reads
    plan-moves.json inside `planUpdate(id)`.
  - Notifications: open summaries go through one queue (`notices`, `noticeProc`), so none is dropped while one runs.
  - IPC `planUpdate(id)`: busy guard, finds the move by id, `writableScenes` guard, `PlanMoves.edit`, `writeScenes`
    (which also rewrites plans.lua). Answers `{ok, scene, changed}` or `not_found` / `not_possible` / `failed` with a reason.
  - Login: `login.json` watched and read at start, after every `reload_plans` and at every request end; when its instance
    is this Hyprland's and no `login-done-<sig>` marker is in the runtime folder, the marker is written first, then the
    listed plans open one request after another. Each name is checked again: still a valid plan with `open_at_login`.
- `bin/omaplace`: `plan-update <id>` (digits only, else usage error 2) maps to `planUpdate`; prints `plan <name> updated`
  or `the plan already says so`; `not_possible` exits 7 (new code, in usage and header) with the whole reason;
  `not_found` prints its reason when there is one. `field` now reads a whole JSON string (commas, escaped quotes).
  Without a terminal (the notification button) the answer comes back as a notification, like save and rule.

## Decisions (contract gaps)

1. `to.rect` is read as fractions of the usable area, like scene rects; absent or null (tiled windows) is fine.
   `seq` is not used, moves go by `id`. The set command is assumed to take Omarchy's mode words (`dwindle`).
2. Zone move onto a zone another window of the plan holds: `not_possible` (no swap guessing).
3. Desktop move, single-window plan: rebinds `home_monitor`/`home_slot`; a target desktop with a plan already would be
   two plans on one desktop, so `not_possible`. A plan with `home_monitor = ""` (the focused monitor) keeps "" and only
   its slot changes: the move does not say which monitor had the focus. Same slot counts as the same desktop for it.
4. Desktop move from a many-window plan into the target plan: zone layout takes the zone holding the centre (none or
   taken: `not_possible`); tiled and scrolling append (zone = highest + 1); free takes `to.rect` and `to.floating`;
   full refuses a second window. A desktop move out of a plan holding two windows of the same class and context is
   `not_possible` (which one moved is not known). A target plan with `home_monitor = ""` is not matched.
5. `omaplace open <plan>` from the CLI also gets the mode switch (14.8 lists it with the other ways to open a plan).
6. Watches (scenes.toml, login.json) are re-armed after each change event (`watchChanges` off and on), with a
   `shortcut:` note.

## Known limits

- A FileView watch on a file replaced by rename may still lose events (live-M1). Re-arming is unverified live; login.json
  is also read after every `reload_plans` and request end.
- Move ids go on from the file across a Lua reload (WP12a), so an old "Update plan" button never names a new move.

## Verified

- `bash tests/run-all.sh`: 45 run, 0 failed, 3 skipped (luacheck, stylua, shellcheck not installed).
- Tests: `tests/mode_switch.test.mjs` (9), `tests/plan_moves.test.mjs` (12), `tests/cli.test.sh` (102 checks, plan-update
  incl. exit 7 and a reason with commas and quotes). qmllint via `tests/qml_lint.test.sh`: ok.
- `bash tests/scrub.sh`: ok.
- Not verified: anything live (checklist `docs/checklist/WP12b.md`).
