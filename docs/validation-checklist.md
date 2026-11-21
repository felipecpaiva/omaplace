# Hand checks

Automated checks (`bash tests/run-all.sh`, `bash tests/scrub.sh`) cover the logic with fake Hyprland and no input sent.
These need a real desktop and your eyes. Gathered from `checklist/WP*.md` (the per package lists keep the exact
commands), duplicates merged. `[x]` passed live on 2026-11-21 on one laptop monitor (`batch-log/live-M1.md`,
`batch-log/live-M5.md`).

Ground rules: ask Felipe right before each check. Harmless apps only (a terminal, Omacalc), made-up scene names, no
synthetic input, never a virtual monitor. Run `omarchy restart shell` after any plugin update (the shell caches plugin
JavaScript). Look at classes, slots and rects only, never titles.

## Install and load

- [x] `omarchy-plugin-validate .` passes; the shell lists the plugin and the shell log has no errors.
- [x] The `pcall(dofile, ...)` line in `hyprland.lua` loads: `hyprctl eval 'return _G.omaplace and _G.omaplace.version'` prints the version, nothing from omaplace in `hyprland.log`.
- [x] Removing the line and reloading leaves Hyprland as before (`_G.omaplace` gone, no rule left behind).
- [ ] With the line removed, `omaplace save x` exits 6 at once and prints the line to add.
- [x] Idle: no omaplace process, no timer, nothing in the log (`pgrep -f procinfo.sh`, `pgrep -f inotifywait` empty).
- [ ] The launcher (Super+Space) finds "omaplace"; `~/.local/share/applications/omaplace.desktop` holds `X-Omaplace-Managed=true`. A hand-made file there without the marker is never written over.

## Placement rules

- [x] A rule with `slot = 5` sends the test app to desktop 5, the view stays (`follow = false`); with `follow = true` the view moves.
- [ ] `omaplace rule add` with the app focused adds `[rule.<class>]` (`config.toml.bak` first); it acts on the next open without a reload. `omaplace rule remove <name>` removes only that section.
- [ ] Second monitor: the rule still works after the monitor moves to another port.
- [ ] Second monitor: with the rule's monitor unplugged the app opens as usual and nothing errors; the rule comes back with the monitor.

## Scenes

- [x] `omaplace save probe` on a desktop with apps prints the counts; `scenes.toml` has the apps, folders as `~/...`, no pid, no title.
- [ ] `omaplace save x` on an empty desktop prints "nothing to save on this desktop", exit 3.
- [x] `omaplace open probe` on another desktop starts the missing apps and moves the open ones (nothing started twice); the notification counts them.
- [x] Floating desktop: each window within 2 px of its place. Tiled desktop: left to right order kept.
- [x] A terminal running a program comes back in its folder running it.
- [x] Two Chrome profiles saved on two desktops open on those two desktops; untagged Chrome windows are not moved.
- [ ] Single-instance app that only raises its old window: after 20 s the item is `not_reopened`, the run `partial`.
- [ ] Scrolling desktop: order kept. Firefox profile and an IDE folder: one new window each.
- [ ] A Hyprland reload during a run: `status.json` says `interrupted`, nothing happens afterwards.
- [x] A second open during a run answers `busy`.
- [ ] `omaplace rename`, `omaplace remove` exit 0; `omaplace remove ghost` exits 3.

## App memory

- [x] Scene mode: an app opened by hand from another desktop goes to its scene desktop and spot; the view stays.
- [ ] A second window of the same app stays where it opened.
- [ ] An app with a rule opens on the rule's desktop, not its memory.
- [ ] `last_place`: open, move to desktop 4, close; opened again it goes back to desktop 4 and its spot.
- [x] `auto`: moving an app from one scene's desktop to another's moves it between the scenes in `scenes.toml`.
- [ ] `auto`: a move to a desktop with no scene adds nothing; two hand moves in a row both reach `scenes.toml`; `omarchy restart shell` replays nothing.

## Session

- [x] The snapshot is written after window events (debounce 15 s), with class, monitor, slot and rect, no title, no pid.
- [x] Closing many windows fast keeps the last good snapshot; writing resumes after the freeze.
- [x] `omaplace restore` with a previous session picks the previous login, not this one, and places each window.
- [ ] After a real logout or reboot: a new `session-<sig>.json`, the old one kept, and `omaplace restore` brings it back.
- [ ] `omaplace restore 2` restores the one before; with no previous session it exits 3.
- [ ] Second monitor unplugged: its windows land on the focused one.

## Desktops page and plans

- [x] Desktops opens first, one card per desktop on each monitor; "No plan, now <mode>" matches `omarchy-hyprland-workspace-layout-current`.
- [x] A "2 columns" plan with an app per zone shows "Zones: 2 columns" and a preview with the icons.
- [ ] Custom zones text gives "Zones: custom (N)"; a bad text shows the reason. A broken plan in `scenes.toml` shows "Bad plan" and the reason.
- [ ] More on a row: profile, folder and program fields are saved. The same app in two plans, or with a rule, says it will not snap. "Class is a guess" goes away after the app was opened once.
- [ ] Remove plan asks first, then the card says "No plan".
- [x] Open all on a zone plan of a tiled desktop turns it floating (toggle fallback) and places each app in its zone.
- [x] A planned app opened by hand from another desktop goes to its zone; the view stays.
- [x] A hand move to another desktop gives one "Update plan" notification; a zone drift gives one after focus leaves the window.
- [x] "Update plan" command: two windows swap zones; a window moved off a many-window plan gets a new free plan.
- [x] Full screen plan: maximized (fullscreen state 1), the bar stays.
- [ ] Pressing the "Update plan" button with a real mouse click (S13).
- [ ] Open at login: off by default; ticked, a real login opens that plan once; `omarchy restart shell` does not open it again.
- [ ] Keyboard: Tab reaches the desktop tiles, Return or Space opens one. Note how much the lost focus after an edit gets in the way.

## Settings window

- [x] The window opens with its pages (not "service is not running").
- [ ] `omaplace settings` and the launcher toggle it; Escape and a click outside close it. Colours follow a theme change.
- [ ] Scenes: rename (bad names refused, `.bak` kept), delete asks first, Windows unfolds each window, an edited folder survives a re-save.
- [ ] Scenes: a Chrome window with an unknown profile offers the profiles by name; a VS Code window opens Omarchy's folder chooser.
- [ ] Rules: monitor and desktop pickers write `config.toml`; an unplugged monitor shows "(not connected)"; "Add a rule for the focused window" picks the app under the window.
- [ ] Session: the switch writes `session`; this login's own session cannot be restored; Ask and Automatic show "(later)".
- [ ] General: each choice writes its key; a double quote in Ignored apps is refused; advanced timings refuse values outside their limits.
- [ ] While closed: no new process.

## Omarchy menu

- [x] "Add omaplace to the Omarchy menu" adds one block between the markers on a copy of a real file, still parses, and "Remove" gives back the same bytes.
- [ ] The Scenes menu rows show their icons; Settings opens the window (S6).
- [ ] Save this desktop asks for a name (Enter alone: the desktop's name; closing saves nothing); Open a scene lists them; Restore last session and Always open here work.
