# WP6 hand checks (live, ask Felipe right before each)

Shell plugin JS and QML are cached: nothing here is live until `omarchy restart shell` (live-M1 lesson). One harmless
test app, no synthetic input, never a virtual monitor. Made-up scene names.

## Opening
0. First: the window shows its pages, not "The omaplace service is not running" (the shell must fill `service`).
1. `omarchy-shell shell toggle io.github.felipecpaiva.omaplace` opens the window; again closes it; Escape and a click
   outside close it. `omaplace settings` does the same.
2. The launcher (SUPER+SPACE) finds "omaplace"; `~/.local/share/applications/omaplace.desktop` holds
   `X-Omaplace-Managed=true`. A hand-made file there without the marker is never written over.
3. Colours and fonts follow the theme (switch theme, reopen). No bar icon, no new keys.
4. On a fresh install (no `~/.config/omaplace`) the first change saves (the folder is made when the window opens).

## Scenes
5. Every scene is listed with its window count. Open opens it (notification as from the CLI, the status line shows Done).
6. Rename: edit the name, Enter. scenes.toml changes, `scenes.toml.bak` holds the old text. A bad name (capitals,
   space) is refused with a plain message.
7. Delete asks first (Cancel keeps it, Delete removes it, keyboard left/right and Enter work), `.bak` kept.
8. Windows unfolds the list: app, position (floating place or tiled position), order, folder, program, profile or
   project. Edit a folder, Enter: scenes.toml has it and `edited = "folder"`; the label says "(edited)". Save the
   scene again from the CLI: the edited folder stays.
9. A Chrome window saved with `context = "?"`: the picker lists the profiles by name and id (compare with Chrome's own
   profile menu); picking one writes `context = "<id>"`. Nothing else from Local State is shown or stored.
10. A VS Code window with `context = "?"`: Choose folder hides the window, Omarchy's chooser opens on top, the picked
    folder is saved as `~/...`, the window comes back. Cancel in the chooser changes nothing.
11. The note about plain text in scenes.toml and dotfiles is shown.

## Rules
11a. Profile and monitor drop-downs open and pick inside the overlay.
11b. Open and Restore with the window still up: does a rule's focus-follow still land, with the overlay holding the
     keyboard? If not, close the window on Open and Restore.
12. "Add a rule for the focused window": with the settings overlay open, does `hyprctl activewindow` still give the app
    underneath? The rule appears for that app, its monitor and desktop.
13. Monitor picker: live monitors by their Omarchy name, plus "Focused monitor"; a rule for an unplugged monitor shows
    "(not connected)". Desktop 1 to 10, Follow and On switches write config.toml (`.bak` first) and the rule acts on the
    next open of the app without a Hyprland reload.
14. Remove asks first, then removes the `[rule.<name>]` section only.

## Session
15. The switch writes `session = "off"` / `"on"`. Restore last session works as `omaplace restore`.
16. Saved sessions list time and window count; this login's own is marked and cannot be restored; another one restores.
17. Restore at login shows Off picked, Ask and Automatic greyed with "(later)".

## General
18. App memory: Scene place and Last place write `app_memory`; Automatic is greyed. The other choices and Ignored apps
    write their keys; a double quote in Ignored apps is refused.
19. Show advanced settings unfolds the seven timing settings with their limits; values outside them cannot be entered.
20. While idle with the window closed: no new process (`pgrep -f "omarchy file select"`, `pgrep hyprctl` empty).
