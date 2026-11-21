# WP7s batch log: session restore, service half (M3)

## What changed
- `Service.qml`: `restore(gen)` is live. `startRestore` reads `~/.local/state/omaplace/sessions.json`, picks the
  instance, reads `session-<instance>.json`, then goes through the same flow as `open` (`begin("open", ...)`, plan file,
  `open_file`, status poll, result file, notification titled "omaplace: last session"). Answers `not_found` when no
  previous session exists or the file has no windows.
- Shared helper `launchesFor(wins, cfg)` (AppResolve + DesktopEntries) now serves both scene open and restore.
- `js/Summary.js`: `instanceName` (same rule as Lua) and `pickSession(index, current, gen)`.
- `js/Plan.js` is unchanged: `fromSession` already matches `targets()` in lua/omaplace.lua (read only): `plan.monitors`
  indexed by `w.monitor + 1`, `w.slot` per window, no `target`, `kind = "session"`.
- `bin/omaplace` is unchanged; `tests/cli.test.sh` checks `restore 2`.

## Multi-workspace restore
One plan for everything. Lua's `targets()` resolves monitor and desktop per window when `plan.kind == "session"`, so no
per-group runs are needed.

## Decisions
- Generation: "" or "previous" = newest instance that is not the current one; "1", "2" count the previous ones the same
  way (1 = newest); any other text must be an instance name found in the index.
- Current instance comes from `HYPRLAND_INSTANCE_SIGNATURE` in the shell's environment. If it is unset, nothing is
  excluded and the newest session is used.

## Not done / not checked
- Not run live (the shell caches plugin JavaScript; needs `omarchy restart shell`). QML was not loaded here.
