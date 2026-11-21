# WP9 live checks (F5 app memory, M2 check 6)

Ask Felipe right before each check. No synthetic input, no virtual monitor. The module must be loaded (the WP2 line in
`hyprland.lua`) and the service installed (WP5). Use harmless apps (a terminal, Omacalc). Look at classes, slots and
rects only.

## Scene mode (the default)
1. [ ] Save a scene with one app on a floating desktop at a clear spot (for example the right half of desktop 2).
2. [ ] Go to another desktop and `omaplace open <scene>`: the app is placed. `cat ~/.local/state/omaplace/memory.lua`
   lists the class with `slot = 2`, `floating = true` and the rect.
3. [ ] Close the app. `memory.lua` is unchanged (scene mode records only runs).
4. [ ] Stay on another desktop and open the app by hand (launcher). It goes to desktop 2 without the view following,
   and after about a second it is at the same spot (within 2 px).
5. [ ] With that window still open, open a second window of the same app: it stays where it opened.
6. [ ] An app with a placement rule on another desktop than its memory: it opens on the rule's desktop, at no forced spot.
7. [ ] On a tiled desktop: an app remembered there is moved there and tiles normally (no forced size).

## last_place mode
1. [ ] Set `app_memory = "last_place"` in `~/.config/omaplace/config.toml` and reload (`hyprctl eval '_G.omaplace.reload_config()'`).
2. [ ] Open an app, move it to desktop 4 and put it somewhere, then close it. About 2 s later `memory.lua` lists it on
   slot 4.
3. [ ] Open it by hand from another desktop: it goes back to desktop 4 and its spot.
4. [ ] Leave one app open on desktop 5, log out and back in, open it by hand. Note whether it went to desktop 5 (the
   close at logout was saved) or to its older place (Hyprland exited before the 2 s debounce). Either is acceptable;
   write the result in the batch log.
5. [ ] Set `app_memory` back to `scene` and reload.

## Idle
1. [ ] Open and close a few apps that are not in memory: nothing moves, nothing in `hyprland.log` from omaplace.
