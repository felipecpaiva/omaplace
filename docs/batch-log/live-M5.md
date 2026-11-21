# Live checks, M5 (Desktops page and plans), 2026-11-21

Felipe approved and was away. Laptop panel only (eDP-1). Test apps: foot and Omacalc. Plans written into
`scenes.toml` by hand (no synthetic input). Omarchy without `omarchy-hyprland-workspace-layout-set` (PR #19671 open),
so the toggle fallback was used.

| Check | Result |
|---|---|
| Desktops page renders: 10 cards on eDP-1, badges "No plan, now Tiled/Floating", editor below | pass (screenshot) |
| Card of a plan: "Zones: 2 columns", preview with foot and Omacalc icons | pass |
| Snap: Omacalc opened by hand on desktop 2 went to desktop 9, right half (799x974 at 800,25 of 1600x975 usable), view stayed on 2 | pass |
| Open all (`omaplace open livetest-plan`): desktop 9 tiled -> floating by Omarchy's toggle (S12 fallback), foot started left, Omacalc moved right, 1.4 s | pass |
| Hand move to desktop 4: `desktop` report in plan-moves.json and a notification "omacalc moved. Update the plan livetest-plan?" with an "Update plan" button | pass |
| Zone drift on the same desktop, then focus to another window (D23): `zone` report | pass (only once the settings window was closed: its keyboard grab refuses focus changes) |
| "Update plan" command (`omaplace plan-update <id>`), run by hand (no click tool without synthetic keys) | works, but both answers were `not_possible` (see findings) |
| Full plan, Open all: window fills the desktop under the bar, but Hyprland fullscreen state stays 0 | partial (see findings) |
| S11: `hl.dsp.window.fullscreen({ mode = "maximized", action = "set" })` | pass: fullscreen 1, 1600x975 at 0,25, bar kept |
| S13: pressing the notification button with a real click | not done (needs a real click) |
| Cleanup | hyprland.lua byte-identical to backup, `_G.omaplace` gone, plugin disabled, test windows closed, desktop 9 back to tiled (its Omarchy mode file removed, as before the test), test config and state trashed, runtime folder removed, view on desktop 2 |

## Findings

1. A `scenes.toml` created after the service started is not seen until its next change (the watch on a missing file
   never fires). Only a hand-made first file hits this; the page writes through the service.
2. "Update plan" is often `not_possible`: a zone move onto a zone another window holds (no swap), and a desktop move out
   of a plan with several windows onto a desktop with no plan. The button is offered anyway.
3. Open all of a `full` plan places by rect only; the maximize dispatch is only in the snap path.

## Fixes (2026-11-21, not yet checked live)

1. **New `scenes.toml` not seen** (finding 1). `Service.rescanScenes()` reads `scenes.toml` again (`writePlans`, which
   writes `plans.lua` and reloads Lua only when the plans changed) and re-arms the watch. It runs at the start and end
   of every request (`begin`, `finish`) and on every settings window open. No folder watch: Quickshell.Io has none
   (checked its qmltypes: FileView, Process, Socket, IpcHandler, ...), and `Qt.labs.folderlistmodel` would add a module
   and fire on our own `.bak` writes. No polling. A hand-made first file is
   therefore picked up by the next command or settings open, not instantly.
2. **"Update plan" not_possible** (finding 2, D24). `PlanMoves.edit`:
   - zone move onto a held zone: the two windows swap zones and rects; the answer carries `replace`, and the service
     then opens the plan with every window `place_only` and a 1 s expiry (Lua's existing mode: open windows move,
     nothing starts, closed ones end the run `partial`). That run sends no summary notification (the CLI already said
     "plan updated"), and like every run it ends with the view on the plan's desktop, where a zone move happens anyway.
   - zone move outside every zone: the plan becomes `free`, each window keeps its zone rect, the moved one the move's rect.
   - zone move in a `free` plan: the new rect is stored (Lua reports zone drift for any placed floating window).
   - desktop move out of a many-window plan onto a desktop with no plan: the window leaves its plan, a new `free` plan
     (`Desktops.newSceneName`, `open_at_login` false, home monitor "" when the old plan had "") holds it at the move's
     rect, or `[0, 0, 1, 1]` for a tiled window. A plan with home monitor "" on the target slot now counts as that
     desktop's plan (the window joins it).
   - desktop move of a single-window plan onto a desktop that has a plan: the window joins that plan like any other
     (zone by centre, tiled and scrolling last, free at its rect) and the empty old plan is removed (Felipe, follow-up).
   - still `not_possible`: twins (class and context twice), `full` receiving a second window, a join into a zone plan
     where the zone is taken or missing, a zone move without a rect, a zone move in a tiled or scrolling plan (Lua never
     reports those). Design 14.8's `plan-update` row now says the same.
3. **Open all of a `full` plan not maximized** (finding 3). The run now carries `fullscreen` per window into its slot
   info and, after placing (or on a tiled desktop, instead of placing), dispatches
   `hl.dsp.window.fullscreen({ mode = "maximized", action = "set" })` like the snap path.

Tests: `tests/plan_moves.test.mjs` (swap, free conversion, free-plan rect, new plan, "" monitor, names),
`lua/tests/test_glue_plans.lua` (full run on a floating and a tiled desktop, place_only re-place launches nothing).
`bash tests/run-all.sh`: 46 run, 0 failed, 3 skipped (luacheck, stylua, shellcheck not installed). Scrub ok.
Still to check live: a swap re-place, and the full Open all reaching fullscreen state 1.

Review follow-ups (same day):
- The swap re-place sets `only_tracked = true` in the plan literal; Lua's move pass then takes only windows tracked for
  that plan (`M.snapped[address].scene`), never the same app on another desktop.
- A re-place that failed still sends its notification (only a run with a state is quiet). If the re-place cannot start,
  the answer says so: "plan X updated; windows not moved: busy".
- The answer names the plan that now holds the window (join target or new plan) and `removed` when a plan was emptied;
  the CLI prints "plan X updated, plan Y removed".
- A tiled window moved to a desktop with no plan stays tiled in its new free plan (`floating = to.floating`).
- Lua: a zone run never maximizes; a full run on an already maximized window unsets, places, then sets again
  (fake_hl expresses it, so no live checklist entry was needed).
