# 06: User flow and storage

Research 2026-11-21 for open question 6 in [../research.md](../research.md). Design level only, no code.

## Summary

1. Capture beats building by hand. PowerToys Workspaces and Moom both start from "arrange your windows, then save". Do the same: one action saves the current workspace as a scene.
2. Opening a scene has one hard choice: move a window that is already open, or open a new one. PowerToys makes it one per-workspace switch ("Move existing windows"). We copy that, default on.
3. Storage reuses the omagnet and omahop style: small TOML files in `~/.config/omaplace/`, fractions of the usable area for geometry, dotted sections like omahop's `[profiles.<name>]`. The session autosave is machine state and lives in `~/.local/state/omaplace/`, out of dotfiles.
4. Capture stores no window titles and no arguments. A launch command or folder is only stored when the user types it in. PowerToys shows why: its CLI docs warn that saved arguments leak.
5. v1 is small: save, open, delete, rename, one "always open here" rule, and "restore last session" as a menu item (no autostart yet). Surfaces: Omarchy menu, CLI, settings window. No new keys or bar icon by default.

Evidence tags: [tested] ran it here, [source] read the file or code, [docs] read official docs, [search] seen through a search summary or a summarising fetch only.

## 1. What others do (and what users complain about)

| Product | How it works | Complaints and limits | Tag |
|---|---|---|---|
| PowerToys Workspaces | Editor opens a live "Capture" mode: arrange apps, press Capture, then name it, edit sizes, add CLI arguments per app, remove apps, make a desktop shortcut. Launch from the list, a desktop shortcut, or a CLI (`list`, `launch --name`). A progress dialog shows each app: launching, placed, failed. One option per workspace: "Move existing windows" (move what is open, launch the rest). | Re-capture wipes all arguments and settings (revert exists). Apps visibly open and then jump into place. Admin apps are not placed. Minimized and packaged apps are missed on capture. Web apps opened as a plain browser until a later fix. App order regressed in one release. Many copies of one app landed in the same spot (timer bug, fixed in 0.87). | [docs] for the flow and the known issues; [search] for the GitHub and press complaints |
| FancyZones | Layouts, not apps. Already studied: [omagnet fancyzones-reference](https://github.com/felipecpaiva/omagnet/blob/main/docs/fancyzones-reference/features.md). Relevant rows: F44 "new window goes to the zone that app last used", F26 JSON files "hand editing not recommended", F53 CLI. | See that file. | [docs] (via that study) |
| Moom (macOS) | Arrange, then "save a layout". Two kinds: app-based layouts and "any window" layouts that take the most recently used windows. Trigger from a palette, a key, the menu bar. Renames anything. Layouts adapt to a different display size. Does not launch apps, only moves open ones. | Not checked. | [search] (summarising fetch of manytricks.com/moom) |
| macOS Stage Manager | Groups windows into sets; AppKit apps keep groups between launches. No way to save or name a set, no exact positions. | Positions and sizes shift after sleep or a monitor change; "no way to save window sets"; users go back to Spaces. | [search] |
| Lasso (macOS) | Not checked. No search result said what it saves. | Not checked. | none |
| KDE Plasma 6 | Session restore at login (restore previous session, or a manually saved one). On Wayland it now uses the new session restore protocol, which apps must also support. | Positions not restored (all windows stacked in the centre), windows on the wrong screen and all on one virtual desktop, Firefox and Chromium differ. | [search] |
| GNOME | X11 session code was removed in GNOME 50. Extensions like "Restore Geometry" fill the gap. The new Wayland `xdg-session-management` protocol (wayland-protocols 1.48, 2026) lets an app ask the compositor to save and restore its window; GTK and SDL work is in progress. | No shipped restore yet. | [search] |

What to learn:

- Capture first, edit after. Nobody makes users build a scene from an empty form.
- The "already open" choice must be visible and simple. PowerToys made it one switch per workspace plus per-app arguments as the escape hatch.
- Show progress and failures. Silent half-restores are the top complaint in KDE and PowerToys threads.
- Never wipe user-added fields on re-capture (PowerToys does, and has to offer a revert).
- Automatic session restore is where every desktop is weakest. Treat it as "open the scene called last session", not a separate engine.
- Whether Hyprland 0.57 supports `xdg-session-management` is not checked. It is a later topic, not part of v1.

## 2. Flows (fewest steps)

A **scene** is the apps on one workspace of one monitor, with their place and size. The **session** is a scene list the plugin saves by itself.

### Capture the current workspace as a scene

1. Open the Omarchy menu, Scenes, "Save this workspace" (or `omaplace save`).
2. Type a name, Enter. Done. Two steps.

Capture takes the focused workspace on the focused monitor. A name that exists asks "Replace?" once. Windows it cannot match to an app (no desktop entry, see question 4 in research.md) are listed in the notification as "not saved".

### Name or rename

1. Settings window, Scenes page, click the name, type, Enter. Or `omaplace rename old new`.

### Open a scene

1. Omarchy menu, Scenes, pick one (or its key, or `omaplace open work`). One step.

Where it opens:

- Default: the **current** workspace on the **current** monitor. This makes a scene portable and avoids the 4.5 renumbering problem.
- A scene can pin a home: a workspace name and a monitor (identity from research question 5). Then it opens there and the view follows.

What about apps already open (per scene setting `existing`, PowerToys' switch):

- `move` (default): a matching window anywhere is moved into its slot; missing apps are launched.
- `new`: always launch every app. For apps with many windows by design (terminals, editors).
- Single-instance apps are always moved, whatever the setting (same as PowerToys).

A small progress notification lists each app: placed, launching, failed. It closes when done.

### Update a scene

1. Arrange the windows, then menu, Scenes, "Save this workspace", pick the existing name. "Replace?" Enter.

Re-capture keeps fields the user typed (launch command, folder) for apps still present. It never wipes them, unlike PowerToys.

### Delete a scene

1. Settings window, Scenes page, Delete, confirm. Or `omaplace delete work`. The scene goes to the trash file `scenes.toml.bak` first (one level of undo).

### "This app always opens on workspace 3, monitor X"

1. Focus the app. Menu, Scenes, "Always open here". Done: a rule for its app id, this workspace, this monitor.
2. To edit or remove: Settings window, Rules page.

Rules are the same matching as scenes, one window, no position by default. They map to Hyprland window rules (research question 2 decides how). A rule can also keep the size and place ("and here exactly"), off by default.

### Restore the last session at login

Setting `restore_at_login`: `off`, `ask`, `auto`.

1. `ask`: at login a notification "Restore last session (3 workspaces, 9 apps)?" with Restore and Dismiss. One click.
2. `off`: menu, Scenes, "Restore last session". One step.
3. `auto`: no step. Risky first (wrong monitor, slow apps), so not the default.

The session is written by itself: on a timer and on clean logout, only for workspaces that changed. It is one scene per (workspace, monitor) pair in the state file. "Restore last session" is "open all scenes in the session file", so it uses the same engine.

Whether an Omarchy notification can carry action buttons is not checked here.

## 3. Surfaces

Family rule from omahop D11: no new icons by default, one settings window for everything. Settings window layout from D24: a side list of categories, sub headings, a folded advanced part.

| Surface | What it does | v1? | Notes and evidence |
|---|---|---|---|
| Omarchy menu | A "Scenes" submenu: Save this workspace, the scene list, Always open here, Restore last session, Settings | yes | Omarchy reads `~/.config/omarchy/extensions/omarchy-menu.jsonc`: dotted ids make submenus, `action` is a shell command, `provider` returns JSON rows at runtime (so the list of scenes can be live). [source: comment header of that file only; the code that reads it was not found]. Not checked: whether a plugin can add rows without editing the user's file. Needs a shell-callable entry point (the CLI below), which depends on research questions 2 and 3 |
| CLI | `omaplace save NAME`, `open NAME`, `list`, `rename`, `delete`, `restore`, `rule add` | yes | The one entry point every other surface calls. Power users bind it themselves. Exit codes like PowerToys (no match, partly placed, failed) [docs] |
| Settings window | Pages: Scenes (gallery of thumbnails, like omagnet's LayoutGallery), Rules, Session, General | yes, small | Same panel pattern as omagnet (`manifest.json` kinds `panel`, launcher `.desktop` running `omarchy-shell shell toggle <id>`) [source]. Thumbnails reuse omagnet's thumbnail drawing |
| Keybinds | A `key` field per scene, like omagnet's `[layout_<name>] key` | yes, empty by default | No default keys, so nothing is taken from Omarchy |
| Bar icon | Opt-in icon that opens the menu | later | Off by default, like omagnet's `bar_icon` |
| Dock | Scene entries in the dock | no | omahop D23: the stock dock has no hook |

## 4. Storage

### Where

| File | Holds | Why there |
|---|---|---|
| `~/.config/omaplace/config.toml` | Settings and placement rules | Hand-edited, belongs in dotfiles, same as omagnet |
| `~/.config/omaplace/scenes.toml` | Named scenes | User intent, belongs in dotfiles; separate from settings because the app writes it often and it grows |
| `~/.local/state/omaplace/session.toml` | Last session autosave | Machine state (XDG state dir), written on a timer, never in dotfiles, never committed |

One file for all scenes, not a folder. Same reason as omahop D19: one parser, one watcher, one line-preserving writer, and Lua has no directory listing [source: D19]. Export of one scene is a later feature.

### Format

The family parser is a TOML subset: `key = value`, `[sections]`, comments, booleans, numbers, quoted strings, no arrays, no escapes inside strings [source: omagnet `docs/config.md`]. A scene is a list of windows, so lists become numbered dotted sections, as omahop already does with `[profiles.<name>.windows]` [source: D19].

Tension: a launch command can contain quotes, and the parser has no escapes. Option for v1: a typed launch line may not contain a double quote; one that does is refused with a clear message. Later: add escapes to the shared parser for all three plugins.

Rules:

- `schema = 1` at the top of each file. A newer schema is read-only with a warning, never rewritten. An older one is migrated on the next save and the old file kept as `.bak`.
- Unknown keys are kept on rewrite (line-preserving writer), so a newer version's fields survive an older one.
- Geometry is fractions of the monitor's usable area (`x y w h` from 0 to 1), as omagnet zones. A scene then fits another resolution or scale.
- A scene is never keyed by a workspace number. Its home, if any, is a workspace name plus a monitor reference.
- Monitor and app identity fields are placeholders here. Their real form comes from research questions 5 (monitor) and 4 (app relaunch).

### Sample (made-up data)

```toml
# ~/.config/omaplace/scenes.toml
schema = 1

[scene.work]
existing = "move"          # move | new: what to do with apps already open
home_workspace = ""        # empty: open on the current workspace; or a workspace name
home_monitor = ""          # empty: current monitor; else a monitor reference (research question 5)
key = "SUPER + CTRL + 1"   # optional, empty by default

[scene.work.window.1]
app = "org.example.Editor"             # desktop entry id (research question 4)
class = "org.example.Editor"           # used to match a new window to this slot
rect = "0 0 0.5 1"                     # x y w h, fractions of the usable area
launch = ""                            # empty: launch from the desktop entry; else typed by the user

[scene.work.window.2]
app = "org.example.Terminal"
class = "org.example.Terminal"
rect = "0.5 0 0.5 0.6"
folder = "~/code/demo"                 # typed by the user, never captured

[scene.work.window.3]
app = "chromium-webapp-example"        # a web app's own desktop entry, not the URL
class = "chrome-example.test__-Default"
rect = "0.5 0.6 0.5 0.4"
```

```toml
# ~/.config/omaplace/config.toml (settings and rules)
schema = 1
restore_at_login = "off"     # off | ask | auto
autosave_minutes = 5         # session autosave; 0 turns it off
ignore = "steam, mpv"        # classes never captured, same as omagnet's ignore

[rule.editor]
app = "org.example.Editor"
workspace = "code"
monitor = ""                 # monitor reference, research question 5
keep_rect = false            # true: also restore size and place
```

The session file uses the same shape with one scene per workspace and monitor (`[scene.session-1]` and so on), plus `saved_at`.

### Session autosave vs named scenes

| | Named scene | Session |
|---|---|---|
| Made by | the user, on purpose | the plugin, on a timer and on logout |
| Lives in | `~/.config` (dotfiles) | `~/.local/state` (never in dotfiles) |
| Covers | one workspace on one monitor | every non-empty workspace |
| Home | current, unless pinned | always its saved workspace and monitor |
| User fields (launch, folder) | yes | copied from a matching named scene or rule only |

## 5. Privacy

Never stored, by capture or autosave:

- Window titles (they hold document names, mail subjects, page titles).
- Process arguments and command lines read from `/proc`.
- Browser tabs or URLs. A web app is saved by its own desktop entry, not by the URL it shows.
- The working folder of a terminal, unless the user types it.

Stored only when the user types it: `launch` and `folder`. The settings window marks these fields "you typed this; it is saved in plain text".

Logs and `omaplace list` print app ids and scene names only. A `--details` flag that prints typed fields carries the same warning PowerToys gives [docs].

The session file is in `~/.local/state`, so it does not end up in a dotfiles repo by accident.

## 6. v1 vs later

| Feature | v1 | Later |
|---|---|---|
| Save current workspace as a named scene | yes | |
| Open a scene on the current workspace and monitor | yes | |
| `existing = move / new` | yes | per-app override |
| Rename, delete (with `.bak`) | yes | |
| "Always open here" rule (workspace and monitor) | yes | keep size and place |
| Restore last session | menu item and CLI, `restore_at_login = off` | `ask` notification, then `auto` |
| Session autosave to `~/.local/state` | yes | |
| Surfaces | Omarchy menu, CLI, small settings window, optional scene keys | bar icon, thumbnails editor, drag a slot |
| Typed `launch` and `folder` | yes, plain strings | escapes in the shared parser |
| Pinned home workspace and monitor | yes, if research question 5 lands | auto-pick on monitor change |
| Progress notification | yes, text only | rich progress panel |
| Edit a slot's place in the window | no (re-capture instead) | visual slot editor reusing omagnet's canvas editor |
| Export or import one scene | no | yes |
| `xdg-session-management` (apps restore their own state) | no | check Hyprland support |

## What this means for omaplace

- Build one engine: "open scene". Session restore and named scenes both call it. Rules are one-window scenes without a position.
- The CLI is the base. Menu, keys and settings window all call it, which also answers "a menu action is a shell command".
- Reuse omagnet: the TOML subset, fractions for geometry, `ignore`, the panel and launcher pattern, thumbnails. Reuse omahop: dotted sections for lists, the line-preserving writer, the settings side list (D24).
- Keep capture private by design: no titles, no arguments. Only typed fields are stored, and re-capture never wipes them.
- Default to the current workspace and monitor so scenes survive renumbering and monitor changes. A pinned home is opt-in.

## Open questions for Felipe

1. **Where a scene opens by default.** (a) On the current workspace and monitor, home is opt-in. (b) Always on the workspace and monitor it was saved from. Recommend (a): portable and safe from 4.5 renumbering. Session restore still uses its saved places.
2. **Apps already open when a scene opens.** (a) Move them into place, launch only the missing ones. (b) Always launch new copies. Recommend (a) as the default with a per-scene switch, like PowerToys.
3. **Session restore at login in v1.** (a) Off, with a one-step "Restore last session" menu item. (b) Ask with a notification. Recommend (a) for v1; move to (b) once notification buttons and monitor identity are checked.
4. **Scene storage.** (a) One `scenes.toml` for all scenes. (b) One file per scene in a folder. Recommend (a): same as omahop D19, one parser and one writer; add single-scene export later.
5. **Terminal folders and launch commands.** (a) Never captured, user types them. (b) Captured from the running process, with a warning. Recommend (a): no private text is stored by surprise, and it matches the "no arguments" rule.
