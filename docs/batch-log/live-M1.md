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
