# Draft: upstream PR for omacom/omarchy (not sent)

Branch: `workspace-layout-set` in `~/omarchy`, commit "Set the layout of any workspace, not only the focused one".

**Title:** Set the layout of any workspace, not only the focused one

**Body:**

`omarchy-hyprland-workspace-layout-toggle` can only cycle the workspace you are looking at. A tool that sets up
another workspace (in my case a plugin that lays out each desktop with its apps) has two bad choices today: jump to
that workspace and press the toggle until the layout matches, or write the saved mode file itself and hope the format
never changes.

This adds `omarchy-hyprland-workspace-layout-set <workspace-id> <dwindle|scrolling|floating>`. It is the second half
of the toggle moved into its own command: apply with `o.workspace_mode`, save (or forget, when it is the default),
announce, refresh the bar and the dock, load titlebars on the first floating workspace. The toggle now only picks the
next layout and hands it over, so nothing is in two places.

- Same checks as before: a named workspace (negative id) and a bad mode are refused, nothing is applied.
- `test/shell.d/hyprland-workspace-layout-test.sh`: all old cases pass unchanged, plus two new ones (set on another
  workspace, set back to the default, refused arguments).
