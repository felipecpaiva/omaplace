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

# Live check WP9 app memory, 2026-11-21

| Check | Result |
|---|---|
| `omaplace open livetest` on 9 writes `~/.local/state/omaplace/memory.lua` (mode scene) | pass: foot and omacalc remembered with monitor fingerprint, slot 9 and rect |
| Omacalc closed, then started by hand from workspace 2 | pass: it opened on 9 at its scene spot (600,229 400x568); the view stayed on 2 |
| Finding: Hyprland's Lua monitor object has no `make` or `model` (only `description`, `serial`) | fixed: the model key now comes from the description without the serial, so the "model" fallback works live |

# Live checks M2 contexts and terminals, 2026-11-21

| Check | Result |
|---|---|
| Two scenes with Chrome profile `Default` (opened on 8) and `Profile 1` (opened on 9); both profiles already running (checked in Chrome's `Local State` first, so new windows are empty and safe to close) | pass: one new window each, on 8 and 9, tagged `omaplace-ctx` with the right profile; the two existing untagged Chrome windows on 1 were not moved |
| Re-save the Chrome scene on 8 | pass: `context = "Default"` read from the tag, nothing to pick |
| Terminal running a program: `foot --working-directory=<dir> sleep 300`, save, close, open on another workspace | pass: foot came back running `sleep 300` in `<dir>` |
| App memory vs a hand-opened terminal | as designed: the hand-opened foot went to its remembered slot 9 (from an earlier scene) |
| Saving an empty workspace | reports `failed`; should say "nothing to save" (follow-up) |

# Live checks after the second review, 2026-11-21

| Check | Result |
|---|---|
| `window.close` payload | carries `workspace.id`, `monitor.name` and `at` (userdata window) |
| Session cap with one reused timer (fix3) | **fail**: no write during 48 s of focus changes. Probe: a fired one-shot `HL.Timer` cannot be re-armed (`set_timeout` plus `set_enabled(true)`, or off then on, never fire again; `is_enabled` returns nil). The reused timer was dead after its first fire, so sessions would have stopped after one write. Fixed: a fresh timer per arm; the fake timer now refuses to re-arm a fired one-shot, and the session test fails on the old code |
| Session cap after the fix | pass: written 34 s after the first of nonstop focus changes (cap 30 s plus the 4 s check step) |
| One quiet cycle after that | pass: written 15 s after the last event |

# Final live checks, 2026-11-21

| Check | Result |
|---|---|
| `hyprctl eval` output | prints only `ok`, never the chunk's return value, so WP8's error mapping could not work; fixed: the Lua chunk writes its answer to `reply-<req>.txt`, the service reads it after hyprctl exits |
| Open through the reply file, and a second open during a run | pass: open works; the second answers `busy` in 0.06 s |
| Spent request files | pass: plan, capture, reply and the previous result are removed when a request ends |
| `app_memory = "auto"`: Omacalc moved from the desktop showing `livetest` (8) to the one showing `chromea` (9) | pass: one event in `moves.json`, and scenes.toml moved the slot from livetest to chromea |
| Menu block on a copy of the real `omarchy-menu.jsonc` | pass: added, still parses, removed back to byte-identical; rows call the CLI by full path. Clicking a real menu row (S6) not done (needs a click) |
| Settings window | renders (screenshot `docs/media/settings-scenes.png`); other pages need clicks, see `docs/checklist/WP6.md` |
| Cleanup | hyprland.lua restored byte-identical to its backup, `_G.omaplace` gone, plugin disabled (still installed), test config and state moved to trash, runtime folder removed |
