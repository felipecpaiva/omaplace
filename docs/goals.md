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

### M3: Session restore (F3)

"After a reboot, bring back what I had."

Done when:
1. While working, omaplace keeps a snapshot of all desktops, written only after window events, at most once per 15 s.
2. Closing all windows at shutdown does not erase the last good snapshot.
3. After a reboot, "Restore last session" (menu or `omaplace restore`) brings back the previous login's desktops, each
   window on its own monitor and slot.
4. The previous login is chosen by default, never the current one.

Work package: WP7.

### M4: Polish and later options

Menu entry with consent (WP8), `app_memory = auto` (WP10), restore at login (`ask`, `auto`), release work if it goes public.

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

## Today (2026-11-21): M1, placement rules

Target: by the end of today, a rule in `config.toml` puts a test app on the right desktop, proven by tests and one live
check.

| Step | What | Who | Proof |
|---|---|---|---|
| 1 | WP0 scaffold: manifest, stubs, test runner, scrub, README with install and removal | builder agent | `bash tests/run-all.sh` and `bash tests/scrub.sh` pass |
| 2 | WP1 Lua pure core (config, geometry with golden vectors, monitors, slots, json, shellquote, fake Hyprland) | builder agent | unit tests pass |
| 2b | WP3 JS pure core, in parallel with WP1 | builder agent | Node tests pass, config cross-check with Lua passes |
| 3 | WP2 rules and the first `omaplace.lua` | builder agent | fake-Hyprland tests: rule created, replaced by name, disabled when the monitor is gone |
| 4 | Review of every package against the standards | separate reviewer agent | review notes in `docs/batch-log/` |
| 5 | Live check: Felipe adds the `dofile` line, one rule, opens one test app | Felipe, with Claude watching | M1 checks 1, 4 and 5 pass on this machine |

Not today: M1 checks 2 and 3 (need a second monitor), M2 and later.

Checkpoints with Felipe: after step 1 (shape of the repo), after step 3 (tests green, before anything touches the live
desktop), and at step 5.
