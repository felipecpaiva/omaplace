# Demo GIFs

`branding/tools/demo.py` records the feature GIFs (and an MP4 of each) from the real plugin on the spare, empty
workspace 8. It never makes a virtual monitor and sends no keys: mouse moves and clicks through `/dev/uinput`, pointer
warps and window moves through `hyprctl eval`, plus the omaplace CLI. It is built on omakit (input, recorder, GIF
builder and the Stage that guards workspace 8 and puts everything back): 12 fps, 960 wide, a 96 colour palette,
captions at the top. The README and the release notes show these files.

| Scene | File | What it shows |
|-------|------|---------------|
| `desktops` | `desktops.gif` | The Desktops page, the desktop 8 card with its 2 column plan and preview, Open all, both apps in their zones |
| `snap` | `snap.gif` | Omacalc opened by hand jumps into its zone |
| `update` | `update.gif` | Omacalc dragged onto the left zone, the "Update plan" notification, its button, the two windows swap |
| `samespot` | `samespot.gif` | A rule with Same spot: Omacalc opens in its spot, is moved away and closed, and opens there again |
| (app) | `settings-app.gif` | The settings app: the Desktops map and editor, then each page |
| (app) | `app-names.gif` | Two apps with one name told apart in the app list, and the note on a shared window class |
| (app) | `layout-picker.gif` | The layout list on a tiled desktop (Tiled first) and a floating one (its omagnet layout first) |
| (app) | `draw-zones.gif` | Draw zones without omagnet: pick a zone, split it |
| `scenes` | `scenes.gif` | Two windows arranged by hand, `omaplace save demo`, closed, `omaplace open demo` brings them back |

Session restore and restore at login have no GIF: they need a new login, and would show your real apps.

## Before the first run: calibrate

The coordinates at the top of `demo.py` (settings window buttons, the notification button, the grab point on Omacalc)
depend on the live screen. Run

```
! python3 branding/tools/demo.py --calibrate
```

It writes `calibrate.png` (the Desktops page), `calibrate-windows.png` (the plan opened) and `calibrate-notify.png`
(a made-up notification with a button, which expires by itself) here, all gitignored. Read the coordinates, put them
in the constants, set `DESK8_CARD`, and run it again for `calibrate-card.png` (desktop 8's editor, to place `OPEN_ALL`
and `EDITOR_SCROLL`). A scene refuses to run while a coordinate it needs is still `(0, 0)`, and the run refuses a
monitor whose size differs from `CALIBRATED_FOR`.

## Run

Needs omakit next to this repository (`../omakit`, or set `OMAKIT_PATH`), one monitor, an empty workspace 8, no
Omacalc open, the plugin enabled with its Lua line loaded, grim, ffmpeg, kitty, bat, omacalc and gio. The recorded
area is the screen below the bar, read from the monitor.

```
! python3 branding/tools/demo.py                 # all scenes
! python3 branding/tools/demo.py update scenes   # some of them
```

Hands off the keyboard, mouse and screen for about 2 minutes (it waits 10 s first).

## Privacy and restore

- Do Not Disturb is on for the whole run, and your notifications are never dismissed. Before the `update` scene turns
  Do Not Disturb off, it waits up to 10 s for any card on screen to expire; if one is still there it stops with "run
  the update scene again". Do Not Disturb is then off only from the click that triggers the notification until the
  pointer is on its button. The capture zooms onto the notification area for that part, and no GIF is written if any
  other card showed meanwhile.
- Demo windows show only this repository's README (a terminal with class `omaplace-demo`, so your own terminals are
  never planned) and Omacalc. App memory and the session snapshot are off during the run.
- Put back after the run, also on an error, by omakit's Stage: `scenes.toml`, `config.toml` and their `.bak` files and
  the temporary launcher entry `omaplace-demo.desktop` (their bytes, or the trash if they did not exist), workspace
  8's layout mode and Omarchy's layout file for it, Do Not Disturb, the pointer and your workspace. Then the script
  reloads omaplace's Lua settings, rebuilds `plans.lua` and says whether it still names the demo plan. Both print a
  `restored:` line.

## The settings app's animations

The four "(app)" rows come from the app itself, offscreen, with made-up data (never the live desktop): the Qt test
`demo` in `app/tests/settings_tests.cpp` saves frames and captions, and `app/tests/demo_gifs.py` builds the GIF and
MP4 with omakit:

```
cd app && bin/test        # builds the tests
OMAPLACE_DEMO_OUT=/tmp/frames QT_QPA_PLATFORM=offscreen build-tests/settings-tests demo
python3 tests/demo_gifs.py /tmp/frames
```
