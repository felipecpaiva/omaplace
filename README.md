# omaplace

Private for now. App placement rules, scenes and session restore for Omarchy, with monitors it recognizes again.

- Say which desktop and which monitor an app opens on.
- Save a scene: the apps and their window positions on one desktop and one monitor.
- Keep named scenes for the desktops you use often. Open one again in one step.
- Restore the whole session after a reboot.

Status: **design** (2026-11-21). Goals and today's plan: [docs/goals.md](docs/goals.md). How it is built: [docs/design.md](docs/design.md); research in [docs/research/](docs/research/00-summary.md).

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

1. Delete the line above from `hyprland.lua`.
2. Run `omarchy plugin remove io.github.felipecpaiva.omaplace`.
3. If you want, delete `~/.config/omaplace` and `~/.local/state/omaplace`.

## Tests

```
bash tests/run-all.sh
```

A linter that is not installed prints `SKIP <tool> not installed`.
