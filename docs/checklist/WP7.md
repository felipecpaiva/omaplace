# WP7 live checks (M3 session snapshots, Lua half)

Ask Felipe right before each check. No synthetic input, no virtual monitor. The module must be loaded (the WP2 line in
`hyprland.lua`) with `session` on (the default). Read files with `cat`, look at classes, slots and rects only.
`<sig>` below is `$HYPRLAND_INSTANCE_SIGNATURE` with every character outside `A-Z a-z 0-9 _` turned into `_`.

## Snapshot while working
1. [ ] Work normally for a minute: open two or three windows, switch desktops, move one window to another desktop.
2. [ ] Stop and wait 15 s. `ls -l ~/.local/state/omaplace/`: `session-<sig>.json` is there, and `sessions.json`.
3. [ ] `cat ~/.local/state/omaplace/session-<sig>.json`: `"kind":"session"`, every open window on every desktop is
   listed by class, with `monitor`, `slot` and `rect`. There is no `pid` and no `title` key.
4. [ ] `cat ~/.local/state/omaplace/sessions.json`: this instance is first.
5. [ ] `stat -c %a ~/.local/state/omaplace`: `700`.
6. [ ] Keep doing things for 30 s and watch `stat -c %y` of the session file: it changes at most once per 15 s, and only
   after you did something.

## Close everything fast
1. [ ] Note the time of the session file: `stat -c %y ~/.local/state/omaplace/session-<sig>.json`.
2. [ ] Open three or more harmless windows, wait 20 s (the file is written), note the time again.
3. [ ] Close them all quickly (three or more within 2 s).
4. [ ] For 60 s the file time is unchanged and it still lists the windows you closed. After that: if no window is
   left open, it stays unchanged; if other windows are still open, it is rewritten once with those only.
5. [ ] Open one window, wait 15 s: the file is written again with only that window (writing resumes after the freeze).

## Save now and a new instance
1. [ ] `hyprctl eval '_G.omaplace.session_save_now()'` writes the file at once (time changes).
2. [ ] After the next login, a second `session-<new sig>.json` appears and the old one is unchanged; `sessions.json`
   lists the new instance first and the old one second.
