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

## Live retest after the fixes, 2026-11-21 (main at f948131)

| Check | Result |
|---|---|
| Hand-made `scenes.toml` created after the service started | pass: picked up when the settings window opened (`omaplace list` alone does not rescan) |
| Open all of the 2-column plan | pass: foot left, Omacalc right, both started |
| Zone swap: Omacalc dragged onto foot's zone, focus to foot, "Update plan" | pass: plan zones swapped, foot re-placed into the right half, nothing started, no false zone report afterwards |
| Desktop move out of the 2-window plan onto desktop 4 (no plan), "Update plan" | pass: Omacalc left the plan, new `free` plan on desktop 4 holding it at its rect |
| Full plan, Open all | pass: fullscreen state 1, 1600x975 at 0,25, bar kept |
| Desktops page with plans: "Zones: 2 columns" and "Full screen" badges and previews | pass (`docs/media/desktops-page.png`) |
| Cleanup | same as the first run: hyprland.lua byte-identical, `_G.omaplace` gone, plugin disabled, test windows closed, desktop 9 tiled again, test files trashed, runtime folder removed, view on desktop 2 |

Still open: a real mouse click on the notification button (S13), a second monitor (S7), open at login after a real login.

# Live check after a real reboot, 2026-11-22

Set up before the reboot: `restore_at_login = "ask"`, test plan `reboot-test` (desktop 8, `columns:2`, Omacalc in zone 1,
open at login).

| Check | Result |
|---|---|
| Open at login after a real login (M5 check 6) | **fail, then fixed**: nothing opened. The shell log shows Omarchy rebuilding its plugins 0.5 s after start ("destroyed during incubation"); omaplace had written its login marker first, so the new service copy did nothing. Fix: the login marker is written when the login plans are done, the restore marker when the restore ran or its question was sent. Replayed with a shell restart inside the login window: Omacalc opened once on desktop 8, left half |
| Restore at login, `ask` (D26) | question sent after the fix (marker `ask` written only after the send returned) |
| Restore of the session from before the reboot (M3 check 3) | pass: `omaplace restore` gave 5 placed (4 started), 1 not reopened, 0 failed; Chrome and two web apps back on their desktops |

Still to confirm with one more real reboot: the fixed login path end to end.

# Second reboot, 2026-11-22 (`restore_at_login = "auto"`, plan with Omacalc and Aether)

| Check | Result |
|---|---|
| Markers after the work (fix of the first reboot) | pass: the login plan and the restore both ran once; a shell restart afterwards ran neither again |
| Automatic restore | pass: 5 placed (3 started), 0 not reopened, Chrome and two web apps on their desktops, no profile picker |
| Order: restore before login plans (D26) | **fail, then fixed**: the plan ran first (Aether opened before everything). The service checked the plans before the restore; now the restore is checked first |
| Aether in the plan's right column | **fail, then fixed**: the plan holds the desktop id's class `aether`, the window is `Aether`, so the slot was never claimed and Aether stayed where it opened. Tickets and plan lookups now compare classes without case. After the fix, `omaplace open reboot-test`: Aether right half and Omacalc left half of desktop 8 |

# Live check of the settings app (design 17), 2026-11-22

Laptop panel plus one external monitor. The app built from `next` (`app/bin/build`), the plugin on `next` after a
shell restart. Felipe agreed to both checks right before them.

| Check | Result |
|---|---|
| Offscreen tests (`app/bin/test`): every control sends its request, refused changes show the saved value, a drawing stays with its desktop, a shell restart is followed, focus comes back after an edit, the problem banner | pass, 15 tests |
| Read only against the real service (`liveReadOnly`): model with 2 monitors, 87 apps; all five pages, no QML warning; `config.toml` and `scenes.toml` unchanged (checksums) | pass |
| Real changes through the real service (a script using the app's request files, made-up values, files backed up first): setting, new rule, rule follow and desktop, a second rule for the same app refused, rule removed, a plan on desktop 9 with an app and open at login, rename, remove, an unknown op refused | pass, 15 of 15; both files put back byte for byte |
| The old launcher entry of the plugin | removed at service start (it carried the marker) |
| The real window | floats, 1040 by 720, centred on the focused monitor (the Lua line's `o.window` rule); the monitor in use is selected first; app icons show |
| A second start | exits at once, no second window, the first window gets the focus |
| Closing | no process and no request file left |

Not checked live: "From a window..." (the 4 second wait for a click needs a hand), the folder chooser, and the
package installed with pacman (Felipe installs it with his password).

## Make these the plan (D41), live 2026-11-22

Through the real service, files backed up first and put back byte for byte after: the laptop panel's desktop 1
(floating, 3 windows) became a Free floating plan for that desktop with the windows' spots; 2 saved, 1 left out (a
floating terminal app omaplace cannot start again), 1 browser window needing its profile. Pass.

## Settings app redesign on `next`, live 2026-11-22 and 2026-11-23

All through the real service, with Felipe's OK each time. Files were backed up first. Only classes and positions were
read, never titles.

- **Hyprland's workspace rules (D50, D51).** hyprmoncfg gives laptop 1 to 3, HDMI 4 to 6, DP-1 7 to 9. Before the fix
  omaplace had placed apps on workspaces 12, 13 and 21. The windows went to 9 and 4, and the workspaces back to their
  monitors. After the fix the app showed each monitor's own numbers. Pass.
- **Put windows back on desktop 1.** Chrome had an unknown profile ("?") and was skipped. Fixed in `lua/tickets.lua` and
  `js/AppResolve.js`: an unknown profile is never started, but its open window is put back. Chrome was moved off and
  came back full screen; state "done". Pass.
- **Quick changes (D53) on desktop 1**, 2 floating windows, through the requests the buttons send. "Side by side":
  left and right halves. One window to "center": it moved, the other stayed. "All full screen": both back, and
  `scenes.toml` the same as the backup byte for byte. Each move took less than 4 seconds. Pass.
- **False "Class is a guess" note (feedback 7).** Fixed and checked after a shell restart: the Reddit web app row has no
  note. The first read straight after a restart can still show it, before the open window list arrives. Pass.
