# WP4 live checks (M2 engine, Felipe)

Ask Felipe right before each spike. One harmless test window each, no synthetic input, never a virtual monitor. The
module must be loaded (the WP2 line in `hyprland.lua`). Calls go through `hyprctl eval` from a terminal; read results
with `hyprctl clients -j` (look at `initialClass`, `workspace`, `at`, `size`, `tags` only, not titles) and
`cat $XDG_RUNTIME_DIR/omaplace/status.json`. `<app>` below is a small app such as Omacalc (`omacalc.desktop`).

Before any check: `mkdir -p -m 700 "$XDG_RUNTIME_DIR/omaplace"` (WP5's service will do this later).

## S2: does `window.open` arrive for a `uwsm-app` launch, and how fast?
1. [ ] Close `<app>` if it is open. On a floating desktop, run:
   `hyprctl eval '_G.omaplace.open({ run = "s2", target = { fp = {}, slot = 0 }, layout = "floating", existing = "new", windows = { { class = "<class>", mode = "launch", launch = { "uwsm-app", "--", "<app>.desktop" }, rect = { 0.5, 0, 0.5, 1 } } } })'`
2. [ ] Within a few seconds `status.json` shows the item `placed` and the run `done`. Note the delay you saw.
3. [ ] `hyprctl clients -j`: the window has the tag `omaplace-slot=s2/1` (this also proves `=` and `/` are fine in tags).
Undo: close the window.

## S3: a single-instance app that only raises its old window
1. [ ] Open `<single-instance app>` by hand. Run the S2 command for it with run `s3` and `existing = "new"`.
2. [ ] Expected: no new window; after 20 s the item is `not_reopened` and the run `partial`. Nothing else moves.
Undo: none needed.

## S4: does our put land the exact rect after Omarchy's open rule on a floating desktop?
1. [ ] On a floating desktop, run the S2 command with run `s4`, rect `{ 0.5, 0, 0.5, 1 }`.
2. [ ] After about 1.2 s the window covers the right half of the usable area within 2 px (`at` and `size` against the
   monitor size minus the bar).
3. [ ] Move mode: drag the window somewhere else, switch to another floating desktop, run it again with `existing =
   "move"` and run `s4b`. The window comes to this desktop and lands on the right half again.
Undo: close the window.

## S8: tiled order (dwindle and scrolling)
1. [ ] On an empty tiled desktop, run a plan with `layout = "tiled"` and three windows of `<app>` (or three terminal
   windows, `launch = { "uwsm-app", "--", "xdg-terminal-exec" }`), run `s8`.
2. [ ] Launches happen one at a time (each after the previous window opened). Read `at.x`: left to right matches the
   plan order. No rect was forced.
3. [ ] Same on a scrolling desktop (run `s8b`).
Undo: close the windows.

## S9: two Chrome profiles
Needs Chrome with two profiles. Use profile folder names, not display names (`Default`, `Profile 1`).
1. [ ] With Chrome running, run a plan with two windows of class `google-chrome`, `context = "Default"` with
   `desktop = { monitor = "", slot = 7 }` and `context = "Profile 1"` with `desktop = { monitor = "", slot = 8 }`,
   launches `{ "google-chrome-stable", "--profile-directory=Default", "--new-window" }` and the same for `Profile 1`,
   run `s9`.
2. [ ] The second launch waits about 2 s after the first window. Each window lands on its own desktop and has its
   `omaplace-ctx=` tag (`hyprctl clients -j`). The focus ends on desktop 8.
3. [ ] Untagged Chrome windows you had open before were not moved.
4. [ ] With Chrome closed, run it again (`s9b`): restored windows of the first profile that open inside the quiet
   window are given only that profile's slots; note how many windows each profile opened.
Undo: close the two new windows.

## S10: Firefox and an IDE
1. [ ] Same as S9 with class `firefox`, `launch = { "firefox", "-P", "<profile>", "--new-window" }`, run `s10`.
2. [ ] An IDE with `launch = { "<ide>", "--new-window", "<made-up folder>" }`, context = that folder, run `s10b`.
3. [ ] Note whether each opens exactly one new window and when it arrives.
Undo: close the windows.

## Reload during a run
1. [ ] Start S3 (it waits 20 s), then save `hyprland.lua` unchanged (Hyprland reloads). `status.json` says
   `interrupted`. Nothing else happens afterwards.
