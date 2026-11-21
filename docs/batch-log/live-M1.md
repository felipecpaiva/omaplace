# Live check M1 (placement rules), 2026-11-21

Machine: laptop, one monitor, Hyprland 0.56.2, Omarchy 4.5. Felipe was away and asked Claude to run it; no synthetic
input was used. Apps were started with `hl.exec_cmd("uwsm-app -- omacalc.desktop")` and closed with
`hl.dsp.window.close`, both through `hyprctl`. Results were read with `hyprctl clients -j` and `hyprctl activeworkspace -j`.

| Check | Result |
|---|---|
| Module loads from the one `pcall(dofile, ...)` line (Hyprland reloaded the config by itself on save) | pass: `_G.omaplace.status()` showed version 0.1.0 and rule `omaplace-rule-calc` enabled |
| Rule `app = "omacalc"`, `slot = 5`, laptop panel identity, `follow = false` | pass: Omacalc opened on workspace 5, the view stayed on 2 |
| Same rule with `follow = true` after `_G.omaplace.reload_config()` | pass: Omacalc opened on workspace 5 and the view moved to 5 |
| Match key `initial_class` (not confirmable from the stubs) | confirmed by the two checks above |
| No log lines, no errors, no process | pass: nothing from omaplace in hyprland.log, no omaplace process |
| Undo: remove the line, config reload | pass: `_G.omaplace` gone, `hyprland.lua` identical to the backup, Omacalc opened on the current workspace again (no rule left behind) |

Goals M1 checks 1, 4 and 5 pass. Checks 2 and 3 (port change, unplugged monitor) wait for a real second monitor (S7).

# Live check WP4 engine (no service), 2026-11-21

Plans written by hand to `$XDG_RUNTIME_DIR/omaplace/plan-<run>.lua` and opened with `_G.omaplace.open_file`.

| Check | Result |
|---|---|
| First run: 3 terminals on tiled workspace 8 | **fail**: every window opened but none was claimed. Cause: Hyprland passes windows to Lua as userdata, and the `window.open` handler returned early on `type(w) ~= "table"`. The fake hl uses tables, so all unit tests passed. Fixed, and `tests/hl_userdata.test.sh` now fails on that pattern |
| After the fix: 3 terminals, tiled workspace 8, `existing = new` | pass: run `done`, 3 placed, all tagged `omaplace-slot=...`, left-to-right order 1, 2, 3 |
| 2 terminals on floating workspace 1 with rects left half and bottom-right quarter | pass: 800x974 at 0,25 and 799x487 at 800,512 on a 1600x975 usable area (within 1 px) |

# Live check WP5 round trip (service + CLI + engine), 2026-11-21

Plugin installed by cloning the repo into `~/.config/omarchy/plugins/io.github.felipecpaiva.omaplace` and enabling it
(`omarchy-shell shell setPluginEnabled ... true`). Test apps: foot (tiled) and Omacalc (floats itself).

| Check | Result |
|---|---|
| `omaplace status` through the plugin's own IPC target | pass |
| `omaplace save livetest` on workspace 8 | pass: 2 windows, no titles in scenes.toml, terminal folder captured |
| First `omaplace open livetest` on workspace 9 | **fail**, two bugs: (1) the terminal was relaunched with `xdg-terminal-exec`, which starts the default terminal with another class, so the slot expired; (2) the service missed the final status (Lua replaces status.json by rename, the file watch lost it) and reported a timeout after 53 s. Fixed: terminals relaunch as themselves with their own folder flag; the service also reads status every 250 ms while a request waits. Also: a tiled window's rect was saved as 1.0006, now clamped |
| Service code reload | a rescan or a disable and enable keeps the old JavaScript; `omarchy restart shell` loads it (then close the theme picker with `omarchy-shell image-selector cancel <path>`) |
| `omaplace open livetest` on workspace 9 after the fixes | pass in 2.6 s: foot and Omacalc started and placed, view on 9 |
| `omaplace open livetest` on workspace 7 with the windows still open (`existing = move`) | pass: both moved to 7, nothing started twice |

# Live check WP7 session (Lua + service), 2026-11-21

| Check | Result |
|---|---|
| Snapshot written after window events (debounce 15 s) | pass: `session-<instance>.json` with 7 windows, keys class, floating, fullscreen, minimized, monitor, order, rect, slot; no title, no pid; index `sessions.json` written |
| Close burst: 4 windows closed in under a second | pass: 25 s later the snapshot still holds the 10 windows from before |
| `omaplace restore` with a hand-made previous session (instance `testprev`: foot on slot 8 tiled, Omacalc on slot 9 floating at 0.1, 0.1, 0.25, 0.58) | pass in 2.6 s: picked the previous instance, not the current one; foot on 8, Omacalc on 9 at 160,122 size 400x565 (exact) |
| A real restore after a new Hyprland login | not done (needs a logout or reboot) |

Note: `omaplace restore` prints only `ok`; a counts line like `open` would be nicer.
