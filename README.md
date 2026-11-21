# omaplace

Private for now. App placement rules, scenes and session restore for Omarchy, with monitors it recognizes again.

- Say which desktop and which monitor an app opens on.
- Save a scene: the apps and their window positions on one desktop and one monitor.
- Keep named scenes for the desktops you use often. Open one again in one step.
- Restore the whole session after a reboot.

Status: **built** (2026-11-21): work packages WP0 to WP10 done; M1 to M3 pass live, open items in [docs/goals.md](docs/goals.md). How it is built: [docs/design.md](docs/design.md); live results: [docs/batch-log/live-M1.md](docs/batch-log/live-M1.md).

## Install

The repo is private, so clone it into the plugin folder with git:

```
git clone <git-url> ~/.config/omarchy/plugins/io.github.felipecpaiva.omaplace
```

Or let Omarchy do it: `omarchy plugin add <git-url>`.

## Load the Lua module

Add this line to your `hyprland.lua`:

```
pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.felipecpaiva.omaplace/lua/omaplace.lua")
```

The `pcall` means a missing or broken file never breaks the rest of your config. Rules are read from `~/.config/omaplace/config.toml` when Hyprland loads.

## Use it

From a terminal (the command is `bin/omaplace` in the plugin folder; add it to your PATH or an alias):

```
omaplace save <name>        save the focused desktop as a scene
omaplace save --ask         same, asking for the name in the Omarchy menu (Enter alone: the desktop's name)
omaplace open <name>        open a scene on the focused desktop
omaplace open --pick        pick the scene from a list
omaplace restore [n]        bring back the last session (n = 1 for the one before, 2 ...)
omaplace list | rename <from> <to> | remove <name>
omaplace rule add           the focused app always opens on this desktop and monitor
omaplace rule remove <name>
omaplace status
omaplace settings           open the settings window
```

`--json` before the word prints the service's answer as is. Exit codes: 0 ok, 2 bad usage, 3 not found or nothing to
save, 4 partial, 5 failed, 6 the Lua module is not loaded.

## Settings window

`omaplace settings`, or "omaplace" in the app launcher. Four pages: Scenes (open, rename, delete, pick a browser
profile or a project folder for a window), Rules, Session (restore an older session) and General (app memory, what a
scene does with open apps, missing monitors, ignored apps, timing). Every change is saved at once; the file before the
change is kept as `.bak` next to it.

## Omarchy menu

omaplace never touches the Omarchy menu by itself. In the settings window, General, press "Add omaplace to the Omarchy
menu". That adds a Scenes menu with Save this desktop, Open a scene, Restore last session, Always open here and
Settings to `~/.config/omarchy/extensions/omarchy-menu.jsonc`, as one block between `// omaplace begin` and
`// omaplace end`. The file as it was is kept as `omarchy-menu.jsonc.omaplace.bak`. "Remove from the menu" takes the
block out again and leaves the rest of the file alone.

## Automatic app memory

With "App memory" set to `auto` in `config.toml`, moving an app by hand from one scene's desktop to another
scene's desktop moves it from the first scene to the second in `scenes.toml` (a `.bak` is kept).

## Placement rules

Put this in `~/.config/omaplace/config.toml` (made-up app and monitor):

```toml
[rule.editor]
app = "org.example.Editor"      # the app's initial class
monitor = "Example Corp EX27"    # the monitor's name as Omarchy knows it; empty = the focused monitor
slot = 3                        # 1 to 10 inside that monitor
follow = false                  # true: switch to that workspace when the app opens
```

The app then opens on that slot. If the monitor is unplugged, the rule switches itself off and the app opens as
usual. It comes back when the monitor does.

## Remove

1. If you added the menu: press "Remove from the menu" in the settings window first, or delete the lines from
   `// omaplace begin` to `// omaplace end` in `~/.config/omarchy/extensions/omarchy-menu.jsonc` by hand.
2. Delete the line above from `hyprland.lua`.
3. Run `omarchy plugin remove io.github.felipecpaiva.omaplace`.
4. If you want, delete `~/.config/omaplace`, `~/.local/state/omaplace` and
   `~/.config/omarchy/extensions/omarchy-menu.jsonc.omaplace.bak`.

## Tests

```
bash tests/run-all.sh
```

A linter that is not installed prints `SKIP <tool> not installed`.
