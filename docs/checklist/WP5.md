# WP5 hand checks (live, ask Felipe right before each)

One harmless test app, no synthetic input, never a virtual monitor. Use made-up scene names.

1. Install the plugin folder the README way (`omarchy plugin add` of this folder), check the shell lists it and nothing
   errors in the shell log.
2. `omaplace status` prints `run: ... idle` (or the last run) and exits 0. With the `dofile` line removed and Hyprland
   reloaded, `omaplace save probe` exits 6 and prints the `dofile` line; put the line back.
3. `omaplace list` exits 0 (empty at first). `omaplace remove ghost` exits 3.
4. On a desktop with one test app (and one terminal in a test folder running a harmless program), `omaplace save probe`
   prints the counts and exits 0. `~/.config/omaplace/scenes.toml` holds the app, the folder as `~/...`, no pid, no
   title; `scenes.toml.bak` appears on the second save.
5. Close the test app, go to another empty desktop, `omaplace open probe`: the app starts there, the notification shows
   `1 placed (1 started)`, exit 0. Run it again with the app open on another desktop: it is moved (`placed` counts it,
   `started` does not).
6. On a floating desktop the window lands within 2 px of its saved place; on a tiled one the order matches.
7. `omaplace rule add` with the test app focused adds `[rule.<class>]` to config.toml (`config.toml.bak` written first)
   and the rule works on the next open of the app. `omaplace rule remove <name>` removes it.
8. `omaplace rename probe probe2`, then `omaplace remove probe2`, both exit 0.
9. `omaplace settings` toggles the settings panel.
10. While idle, `pgrep -f procinfo.sh` and `pgrep -f inotifywait` find nothing; result files are in
    `$XDG_RUNTIME_DIR/omaplace/`.
11. `omaplace restore` (empty argument) reaches the service through `omarchy-shell`'s socket path and answers `not_yet`
    (exit 5); nothing else of Service.qml's JavaScript has run before this check.
12. FileView assumptions (batch log "Known limits"): result and plan files are written at their new path each time, and
    a removed scenes.toml reads as empty.
