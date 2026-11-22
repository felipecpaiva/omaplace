# omaplace-settings

The settings app of the omaplace plugin: a C++ and Qt Quick window with five pages (Desktops, Apps, Scenes, Restore,
General). It keeps no logic and writes no file of its own. Each change is one request to the omaplace service: a JSON
file in `$XDG_RUNTIME_DIR/omaplace/` plus one `omarchy-shell` call, and the reply carries what to show next (design
section 17, D36 to D40). The service also pushes `app-model.json` when something changes, for example after the live
desktops are read. Without the plugin running, the window says so and how to fix it.

The plugin's pure `js/` libraries (layouts, zones, settings words) are copied into the binary at build time by
`prepare.py`, so the app and the plugin share one copy of that logic.

| Script | What |
|---|---|
| `bin/build` | builds `build/omaplace-settings` |
| `bin/test` | Qt tests offscreen: a stand-in for `omarchy-shell` (`tests/fake-shell.sh`) and made-up data (`tests/make_fixture.mjs`). They click every control and check the request it sends, and check that no QML warning shows |
| `bin/install` | builds the package and installs it with pacman (asks for your password) |

A read-only check against the real plugin, which sends no change and keeps its pictures out of the repository:
`OMAPLACE_LIVE=1 OMAPLACE_LIVE_OUT=<folder> build-tests/settings-tests liveReadOnly`.

Needs `qt6-base`, `qt6-declarative`, `qt6-wayland`, `gcc`, `make`, `python`, and `node` for the tests.

| Key | Action |
|---|---|
| Ctrl+1 to Ctrl+5 | the pages |
| F5 | read the desktops again |
| ? or F1 | the keys |
| Ctrl+W, Ctrl+Q | close |
