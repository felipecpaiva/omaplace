# WP8 live checks (menu rows, CLI pickers, WP10 wiring, fixes)

Ask Felipe right before each check. No synthetic input, no virtual monitor. Needs `omarchy restart shell` first (the
shell caches plugin JavaScript).

0. [ ] First: plain `omaplace save x` and `omaplace open x` still work (every `hyprctl eval` now sends the wrapped
   chunk from `js/LuaCall.js`); `hyprctl eval '<the chunk>'` prints `omaplace:ok`.
1. [ ] Copy `~/.config/omarchy/extensions/omarchy-menu.jsonc` aside. Settings window, General: "Add omaplace to the
   Omarchy menu". The file has one block between the markers, the rest unchanged (`diff` with the copy), and
   `omarchy-menu.jsonc.omaplace.bak` equals the copy. The button now reads "Remove from the menu".
2. [ ] The row icons render in the menu.
2b. [ ] S6: Omarchy menu, Scenes, Settings opens the settings window (the full-path action runs).
3. [ ] Scenes, Save this desktop: the name prompt shows "(Enter for <desktop>)"; Enter alone saves under that name;
   closing the prompt saves nothing.
4. [ ] Scenes, Open a scene: the list shows the scenes; picking one opens it (notification).
5. [ ] Scenes, Restore last session and Always open here do what `omaplace restore` and `omaplace rule add` do.
6. [ ] "Remove from the menu": the file equals the copy again; the Scenes menu is gone.
7. [ ] `omaplace save x` on an empty desktop prints "nothing to save on this desktop", exit 3.
8. [ ] `omaplace restore` prints a "restored the last session: ..." line.
9. [ ] `omaplace open x` with the Lua line taken out of `hyprland.lua` says the module is not loaded at once (no 2 s
   wait); with it in, a scene whose monitor is gone and `missing_monitor_scene = "skip"` ends with `failed (failed)`.
10. [ ] After an open, `$XDG_RUNTIME_DIR/omaplace` holds no `plan-*.lua` and at most one `result-*.json`.
11. [ ] A Chrome window saved with `?`, a profile picked in settings, the scene saved again with the window still
    untagged: the profile, folder and program stay.
12. [ ] WP10 steps 5 and 6 of `docs/checklist/WP10.md`.
13. [ ] Auto mode, no `moves.json` yet when the shell starts: two hand moves in a row with no omaplace command
    between; both reach `scenes.toml` (the watch on a file created later by a rename).
14. [ ] `omarchy restart shell` after step 13: no scene changes (events already in the file are not replayed).
