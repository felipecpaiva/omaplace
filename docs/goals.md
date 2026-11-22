# omaplace goals

What we are building, what "done" means for each step, and the plan for today. How it is built is in
[design.md](design.md); this page is the expectations. Written 2026-11-21.

## The goal in one sentence

Every app opens where it belongs, on the right desktop and monitor, and a whole desktop (or the whole session) comes back
in one step, without omaplace replacing anything in Omarchy or costing anything while idle.

## Milestones and what "done" means

Each line under "Done when" is a check Felipe can do himself. A milestone is done only when every line passes and the
engineering standards hold (tests, linters or a logged SKIP, scrub, no file outside the plugin written).

### M1: Placement rules (F1, F4)

"This app always opens on slot N of monitor M."

Done when:
1. A rule in `~/.config/omaplace/config.toml` sends a test app to the named slot of the named monitor when it opens.
2. The rule still works after the monitor moves to another port (fingerprint match, not `DP-1`).
3. With the rule's monitor unplugged, the app opens normally and nothing errors (rule disabled, `missing_monitor_rule = skip`).
4. Removing the one `dofile` line and reloading leaves Hyprland exactly as before.
5. Idle cost: no timer armed and no process started while nothing happens.

Work packages: WP0, WP1, WP2. Live checks: S7 needs a real second monitor, so 2 and 3 may be signed off later.

Status 2026-11-21: checks 1, 4 and 5 passed live ([batch-log/live-M1.md](batch-log/live-M1.md)). 2 and 3 open (need a second monitor).

### M2: Scenes and app memory (F2, F5, D18)

"Save this desktop. Open it again in one step. Apps I open by hand go back to their place."

Done when:
1. `omaplace save work` saves the focused desktop: apps, places on a floating desktop, left-to-right order on a tiled one.
2. `omaplace open work` on another desktop rebuilds it: open apps are moved, missing apps are started, an app with a rule
   goes to its own desktop and the focus follows it.
3. On a floating desktop each window lands at its saved place (within 2 px). On a tiled desktop the left-to-right order
   matches.
4. Terminals reopen in their folder with their program (for example an agent in its project folder). Nothing that looks
   like a password or token is saved.
5. Two Chrome profiles saved on two desktops open on those two desktops again.
6. An app opened by hand after a scene placed it goes back to that place (`app_memory = scene`).
7. A result notification lists what was placed, started, skipped or not reopened. Nothing fails silently.
8. The settings window lists scenes and rules, renames and deletes, and lets the user pick a profile for an unknown window.

Work packages: WP3, WP4, WP5, WP6, WP9.

Status 2026-11-21: checks 1 to 7 pass live; 8 the window renders and lists scenes, its other pages are hand checks in [checklist/WP6.md](checklist/WP6.md) ([batch-log/live-M1.md](batch-log/live-M1.md)).

### M3: Session restore (F3)

"After a reboot, bring back what I had."

Done when:
1. While working, omaplace keeps a snapshot of all desktops, written only after window events, at most once per 15 s.
2. Closing all windows at shutdown does not erase the last good snapshot.
3. After a reboot, "Restore last session" (menu or `omaplace restore`) brings back the previous login's desktops, each
   window on its own monitor and slot.
4. The previous login is chosen by default, never the current one.

Work package: WP7.

Status 2026-11-21: checks 1, 2 and 4 pass live; 3 passes with a hand-made previous session. A restore after a real new login is still to do.

### M4: Polish and later options

Menu entry with consent (WP8), `app_memory = auto` (WP10), restore at login (`ask`, `auto`), release work if it goes public.

Status 2026-11-21: WP8 and WP10 built; auto mode passes live; the menu block round-trips on a copy of the real file. Open: clicking a real menu row (S6), restore at login, release work.

### M5: Desktops page and desktop plans (F6, design section 14)

Done when:
1. The Desktops page shows one card for each desktop on each monitor, and each card shows its layout.
2. Choosing "2 columns" with App A left and App B right, then pressing "Open all", gives that desktop in floating mode with A left and B right.
3. Opening App A by hand later puts it in its zone on that desktop.
4. Moving A by hand sends one "Update plan" notification; pressing it changes the plan, ignoring it does not.
5. Tiled, full screen and free floating plans work the same way, and the preview matches what opens.
6. Nothing starts at login unless "open at login" is ticked.

Work packages: WP11, WP12 (12a Lua, 12b service), WP13. D22 decided (option 1; upstream PR omacom/omarchy#19671, fallback toggle until it ships).

Status 2026-11-21: WP11 to WP13 built, reviewed and merged; 46 suites pass. Live 2026-11-21 (`batch-log/live-M5.md`): checks 1, 2, 3 pass; 4 sends the notification but the update was `not_possible` in both tried cases; 5 partial (full plan not maximized by Open all); 6 not tried. S11 pass, S12 fallback pass, S13 click not done. Retest after the D24 fixes: 4 and 5 pass (swap, new plan, full maximized). S13 real click passed while recording the demo GIFs (2026-11-22). Open: 6 (needs a real login), second monitor. Turned on for daily use on the laptop 2026-11-21.

## Not goals (for now)

- Replacing or patching any part of Omarchy, or editing the user's Hyprland files.
- Restoring browser tabs or app contents (apps restore their own).
- Forcing exact positions on tiled or scrolling desktops (order only, D13).
- Placing a Chrome window opened from Chrome's own profile menu (its profile cannot be seen, D18).
- Window groups, special workspaces, a bar icon by default, default keys.

## Quality bar for every step

- Extend, never replace (design section 3).
- Pure logic has unit tests; Hyprland glue has fake-Hyprland tests; user-visible behaviour has a hand check.
- No polling, no resident process of our own, no extra runtime.
- No window titles, URLs or secrets stored or logged; scrub test passes.
- Live checks only after asking Felipe right before each one.

## Today (2026-11-21): up to WP5 (Felipe chose option B)

Target: by the end of today, `omaplace save work` and `omaplace open work` work from the command line, rules work from
`config.toml`, all proven by tests, and the live checks Felipe approves at the moment pass.

| Step | Work packages | Proof | Checkpoint with Felipe |
|---|---|---|---|
| 1 | WP0 scaffold | `tests/run-all.sh`, `tests/scrub.sh`, `omarchy-plugin-validate` pass | look at the repo shape |
| 2 | WP1 Lua core and WP3 JS core, in parallel | unit tests, config cross-check, geometry golden vectors | none |
| 3 | WP2 placement rules | fake-Hyprland tests | live: add the `dofile` line, one rule, open a test app (M1 checks 1, 4, 5) |
| 4 | WP4 scene engine | fake-Hyprland tests | live spikes S2, S3, S4, S8, S9, S10, each asked first |
| 5 | WP5 service and CLI | CLI tests with a fake shell | live spikes S1, S5, then save and open one real scene |

Every package: built by a builder agent in its own git worktree, checked by a separate reviewer agent against
`engineering-standards.md`, then merged. Not today: WP6 to WP10, M1 checks 2 and 3 (need a second monitor).
Missing linters today: shellcheck, luacheck, stylua (logged as SKIP until installed).
