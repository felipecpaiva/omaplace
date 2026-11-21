# WP2 live checks (M1, Felipe)

Needs one harmless test app. Do not use a second monitor yet (M1 checks 2 and 3 wait for one).

1. [ ] Add the load line to `hyprland.lua` (README, "Load the Lua module"). Reload Hyprland. No error on screen.
   Check the log for omaplace lines (a silent load failure shows here):
   `grep omaplace "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" | tail`
   and `hyprctl eval 'return _G.omaplace and _G.omaplace.version'` should print the version.
2. [ ] Create `~/.config/omaplace/config.toml` with one rule for the test app. Find its class with `hyprctl clients`
   while it is open. Example:
   ```toml
   [rule.test]
   app = "org.example.TestApp"
   slot = 5
   ```
   (empty `monitor` means the focused monitor)
3. [ ] Reload Hyprland. Close the test app if it was open, then open it. It lands on slot 5 and the view does not jump
   (`follow = false`). Set `follow = true`, reload, open it again: the view jumps to slot 5.
4. [ ] Other apps still open where they used to.
5. [ ] Idle: nothing runs in the background (no new process, `omaplace` has none).

Undo: delete the load line from `hyprland.lua`, reload Hyprland. Delete `~/.config/omaplace/config.toml` if you want.
