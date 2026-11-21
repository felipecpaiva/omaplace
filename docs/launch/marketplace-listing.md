# Marketplace listing (draft, do not submit without Felipe's go)

The marketplace is `omacom/omarchy-plugin-marketplace`. It reads `manifest.json` and the root `preview.png`. The form
is `.github/ISSUE_TEMPLATE/submit-plugin.yml` in that repo (read 2026-11-21): category and tags come from fixed lists,
one to three tags, more are rejected. A listing is bound to the commit the bot validates: keep `main` frozen at the
submitted commit until it is approved, work on a branch (omahop and OmaBar lesson).

## Checks against the submission rules

| Rule | Status |
|---|---|
| Public repo, one plugin, `manifest.json` in the root | **not yet**: the repo is private |
| Root README with install and removal | ok (Install, Uninstall) |
| Root licence file | ok (`LICENSE`, MIT) |
| External dependencies documented | ok (README "Requirements"; none required, `inotifywait` optional) |
| Unique ID outside `omarchy.*` | `io.github.felipecpaiva.omaplace`; **not yet searched** in the marketplace (the ID is permanent once listed) |
| Does not overwrite user config without consent | ok: it never edits `hyprland.lua` (the user adds one line); the Omarchy menu block is added only on a button press, with a backup; the launcher entry is replaced or removed only when it carries its own marker |
| Optional `preview.png` in the root | **being made** (1280x640) |
| Passes Omarchy's own validation | `omarchy-plugin-validate .` passes (in `tests/run-all.sh`) |

## Listing values

The form's lists (2026-11-21). Categories: Appearance, Desktop, Developer Tools, Hardware, Kids, Productivity, System,
Widgets, Other. Tags: AI, Bar, Education, Games, Hyprland, Kids, Launcher, Media, Power management, Quickshell,
Security, System, VPN, Workspaces.

- **Category:** `Desktop` (second choice: `Productivity`). omagnet and omahop used `Desktop` too.
- **Tags (3):** `Workspaces`, `Hyprland`, `Quickshell` (same set as omagnet and omahop; `Workspaces` is the subject)
- **Suggest a missing tag:** `window-management` (there is no tag for window placement or session restore)

## Maintainer notes (goes in the form)

> Every app opens where it belongs: placement rules per app (desktop and monitor), a Desktops page with a layout plan per
> desktop (zones, tiled, full screen), scenes you save and open in one step, and a session restore after a reboot.
> Monitors are recognized by their identity, not their port.
>
> `kinds: ["service", "panel"]`, no bar widget and no keys. The placement code is a Lua file loaded from `hyprland.lua`
> with one guarded `pcall(dofile, ...)` line the user adds; the plugin never edits that file.
>
> **Writes:** `~/.config/omaplace/` (settings, scenes), `~/.local/state/omaplace/` (session snapshots, app memory),
> `$XDG_RUNTIME_DIR/omaplace/`, and a launcher entry with its own marker. The Omarchy menu block is added only when the
> user presses the button, with a backup first. Desktop modes are switched with Omarchy's own commands. No window titles
> or addresses are stored.
>
> No network, no root, no packages, no process of its own while idle. Validated with `omarchy plugin validate` and
> 46 test suites. Known limits: tested on one monitor; a real second monitor and open at login after a real login are
> still to check. Not affiliated with Omarchy.

## Submit (when approved)

Open https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml with the values above
and `https://github.com/felipecpaiva/omaplace`, and tick the five checklist boxes once each is true. Before that: make
the repo public, add `preview.png`, search the marketplace for the ID, and re-run the test count for the notes.
