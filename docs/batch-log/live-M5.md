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
