# Demo GIFs

`branding/tools/demo.py` records the feature GIFs (and an MP4 of each) from the real plugin on the spare, empty
workspace 8. It never makes a virtual monitor and sends no keys: mouse moves and clicks through `/dev/uinput`, pointer
warps and window moves through `hyprctl eval`, plus the omaplace CLI. `gifkit.py` builds each file: 12 fps, 960 wide,
a 96 colour palette, captions at the top.

| Scene | File | What it shows |
|-------|------|---------------|
| `desktops` | `desktops.gif` | The Desktops page, the desktop 8 card with its 2 column plan and preview, Open all, both apps in their zones |
| `snap` | `snap.gif` | Omacalc opened by hand jumps into its zone |
| `update` | `update.gif` | Omacalc dragged onto the left zone, the "Update plan" notification, its button, the two windows swap |
| `scenes` | `scenes.gif` | Two windows arranged by hand, `omaplace save demo`, closed, `omaplace open demo` brings them back |

## Before the first run: calibrate

The coordinates at the top of `demo.py` (settings window buttons, the notification button, the grab point on Omacalc)
depend on the live screen. Run

```
! python3 branding/tools/demo.py --calibrate
```

It writes `calibrate.png` (the Desktops page), `calibrate-windows.png` (the plan opened) and `calibrate-notify.png`
(a made-up notification with a button) here, all gitignored. Read the coordinates, put them in the constants, set
`DESK8_CARD`, and run it again for `calibrate-card.png` (desktop 8's editor, to place `OPEN_ALL` and `EDITOR_SCROLL`).
A scene refuses to run while a coordinate it needs is still `(0, 0)`.

## Run

Needs one monitor (the size in `SCREEN`), an empty workspace 8, no Omacalc open, the plugin enabled with its Lua line
loaded, grim, ffmpeg, kitty, bat, omacalc, and the omahop repository next to this one (its uinput helper).

```
! python3 branding/tools/demo.py                 # all scenes
! python3 branding/tools/demo.py update scenes   # some of them
```

Hands off the keyboard, mouse and screen for about 2 minutes (it waits 10 s first).

## Privacy and restore

- Do Not Disturb is on for the whole run. The `update` scene turns it off only from the click that triggers the
  notification until its button is pressed, zooms onto the notification area for that part, and writes no GIF if any
  other notification showed meanwhile (run that scene again).
- Demo windows show only this README (a terminal with class `omaplace-demo`, so your own terminals are never planned)
  and Omacalc. App memory and the session snapshot are off during the run.
- Put back after the run, also on an error: `scenes.toml`, `config.toml` and their `.bak` files (moved to the trash
  if they did not exist), the demo launcher entry, workspace 8's mode (through Omarchy's own toggle, and its mode file
  moved to the trash if it was new), Do Not Disturb, the pointer and your workspace. The last line it prints says
  whether the files match and `plans.lua` no longer names the demo plan.
