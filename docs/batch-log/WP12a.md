# WP12a batch log: desktop plans, Lua side (design 14.7, 14.8)

## What changed

- `lua/plans.lua` (new, pure): `validate` (checks the table plans.lua returns; a bad plan is skipped with a reason, a bad
  window keeps its index but never snaps; at most 100 plans, 64 windows each), `held` and `lookup` (class plus context;
  the same key in two plans or `snap = false` never snaps, the first window of a key in a plan wins), `login_plans`,
  `drifted` (D23, 2 percent per edge and size, as fractions of the usable area), `desktops` (slots 1..10 per monitor,
  mirrors left out, sorted by connector).
- `lua/omaplace.lua` (glue):
  - `load_literal`: the capped, text-only, empty-environment, instruction-budget loader, now shared by `open_file` and
    plans (same log lines for plan files as before).
  - Plans load at file load, on `reload_config` and on `_G.omaplace.reload_plans()`. Missing file: no plans, silent. A
    bad or oversize file: one log line, ignored, the plans loaded before stay; `reload_plans` answers `bad_plans`.
  - `window.open` with no run live: plan before app memory. A class and context any plan holds never goes through app
    memory, even when it is not snapped (snap false, rule, second window, missing monitor). Snap: first window of the
    class, no enabled user rule, not on a special workspace, the plan's monitor resolves (policy `skip`; an empty
    `home_monitor` is the focused monitor, as for rules). Silent move to the workspace, float on for a floating plan,
    rect with `place.lua` after `settle_ms`. Tiled plans move only. `fullscreen = 1`:
    `hl.dsp.window.fullscreen({ mode = "maximized", action = "set" })` after the settle (form from the Hyprland
    binary's own error strings: modes fullscreen/maximized, actions toggle/set/unset; behaviour is spike S11).
  - Own moves marked in `plan_own` (and `memory_own` while memory records moves), consumed by the first move event.
  - Subscriptions to `window.close`, `window.move_to_workspace`, `window.active` only while a plan is loaded, removed
    on reload. All in `pcall`. No new timer beyond the one-shot settle per snap.
  - `plan-moves.json` (last 20, `seq` and the list kept over a reload): `desktop` when a snapped window is moved by hand
    to another desktop (once, until it is back or closed); `zone` when focus leaves a placed floating snapped window on
    its desktop that is more than 2 percent off (once, until back within 2 percent or closed). Not while a run is live.
    A move that cannot be read (special workspace) does not count as reported. Move ids go on from the file's seq in a
    new Lua state, so an old "Update plan" action never hits a new move.
  - A run of a plan scene ("Open all", login; the plan literal carries `scene` from `Plan.fromScene`) tracks the
    windows it placed like snapped ones when it ends (`track_run`). Run windows come sorted by order, so
    `Plans.match_run` maps them back to the scene window index by class and context, same rect first. Windows open
    before Lua loaded stay untracked.
  - On every plans load a tracked window is looked up again: it keeps its scene and window number while that window
    still holds its class and context (so snap = false or same-class windows placed by Open all stay), else a lookup;
    it follows the new desktop and rect (flags cleared), or is dropped when no plan holds it or Hyprland no longer has
    the window. A missing plans.lua clears all tracking; a bad one keeps the plans and their subscriptions.
  - Notification (review fix 5): after a move is written to plan-moves.json, Lua runs, through `hl.exec_cmd` (async)
    with every argument quoted by `shellquote.lua`: `omarchy-notification-send -g <glyph> omaplace "<class> moved.
    Update the plan <scene>?" --action "Update plan" <plugin dir>/bin/omaplace plan-update <id>`. Plugin dir is the
    folder above `lua/` of omaplace.lua's own path. Class and scene only, never a title. Own moves send nothing.
  - `login.json` `{ instance, plans }` once per Lua state when a plan has `open_at_login`, skipped when the file already
    names this instance; a failed write (at a real login the runtime folder can still be missing, mkdir is async) is
    tried again on the next plans load, so the service must call reload_plans() at start.
  - `_G.omaplace.desktops(req_id)`: returns the table, and with a request id also writes
    `$XDG_RUNTIME_DIR/omaplace/desktops-<req_id>.json` (LuaCall cannot return a table through `hyprctl eval`).
- Tests: `lua/tests/test_plans.lua` (44 checks), `lua/tests/test_glue_plans.lua` (143 checks, fixture
  `lua/tests/fixtures/home-plans`). Live checks: `docs/checklist/WP12a.md`.

## Verified

`bash tests/run-all.sh`: 43 run, 0 failed, 3 skipped (luacheck, stylua, shellcheck not installed). `bash tests/scrub.sh`
ok. Nothing was run against the live desktop.

## Not verified live

`window.active` passing the window to Lua; fullscreen state 1 keeping the bar (S11); the float dispatch on a window that
Omarchy already floats.
