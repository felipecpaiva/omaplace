# WP12a live checks (desktop plans, Lua side)

Ask Felipe right before each check. No synthetic input, no virtual monitor. Harmless apps only. Needs a `plans.lua`
from the service (WP12b) or a hand-written one with made-up scene names.

1. [ ] `hyprctl eval '_G.omaplace.reload_plans()'` with a plan holding one harmless app on a floating zone desktop.
2. [ ] Open that app by hand on another desktop: it moves to the plan's desktop, without the view following, and lands
   in its zone about 1 s later.
3. [ ] Open a second window of the app: it stays where it opened.
4. [ ] A `full` plan (S11): the window is maximized and the bar stays visible.
5. [ ] Move the planned window to another desktop by hand: `$XDG_RUNTIME_DIR/omaplace/plan-moves.json` gets one `desktop`
   event; a second move away adds nothing.
6. [ ] Back on its desktop, drag it out of its zone and click another window: one `zone` event. Clicking back and away
   again adds nothing.
7. [ ] Check `window.active` hands the window to Lua live (the zone check depends on it).
8. [ ] Tick "open at login" on one plan, log out and in: `login.json` names the new instance once. A Hyprland config
   reload does not rewrite it.
9. [ ] `hyprctl eval '_G.omaplace.desktops("t1")'`: `desktops-t1.json` lists every monitor with slots 1 to 10.
