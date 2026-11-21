# WP6 batch log: settings window (M2 check 8)

## What changed
- `SettingsPanel.qml` (next editor after the WP0 stub): an overlay window like omagnet's and omahop's (theme colours and
  fonts from `qs.Commons`), a side list of four pages (D24 pattern), a status line, and a delete confirmation
  (`ConfirmDialog`, also driven by the keyboard). It declares `property var service`, which the shell fills with this
  plugin's own Service.qml (`shell.qml`, panel loader). It reads and writes no file: every read and change is a Service
  function. No IpcHandler of its own: the existing `settings` IPC (`omarchy-shell shell toggle ...`) opens it.
- `pages/`: `ScenesPage`, `SceneRow`, `WindowRow`, `RulesPage`, `RuleRow`, `SessionPage`, `SessionRow`, `GeneralPage`,
  `ChoiceRow`, `Note`. Every list is a `ListView` (scenes, a scene's windows, rules, sessions, timing rows, the side list
  and the button rows of a choice).
- `Service.qml`: only additions. New functions `ensureDirs`, `refreshMonitors`, `panelData`, `contextInfo`,
  `sessionRows`, `setSetting`, `setRuleField`, `setSceneWindow`, `pickFolder`, `onPicked`, `resultOf`,
  `installLauncher`; two Processes (`hyprctl monitors -j`, `omarchy file select --directory`), five read-only FileViews
  and the launcher FileView. `Component.onCompleted` now also installs the launcher; new `Component.onDestruction`
  removes it. Every existing function and flow is unchanged.
- `js/Settings.js` (new, pure) and `tests/settings.test.mjs` (19 tests).
- `omaplace.desktop` (launcher) and `manifest.json` (description only: the shell has no launcher field, same as omagnet).
- `tests/qml_lint.test.sh`: qmllint of `*.qml pages/*.qml` with the shell's `qs` modules on the import path.

## Decisions
- **Writers stay single.** Settings go through `ConfigIO.setValue` / `setRule` and `writeConfig` (.bak first, then the
  async `hyprctl eval "_G.omaplace.reload_config()"`). Window edits go through `SceneStore.serialize` and `writeScenes`.
  Each new writer answers `busy` while a slow request runs, refuses an unwritable scenes.toml (`writableScenes`), and
  catches throws into `{ok:false, code:"failed", reason}`. `writeConfig` reloads Lua for every config write, also for
  `request_timeout_s` (read by the service only); a reload is cheap, so no second write path was added.
- **What the window may change** is a list in `Settings.js` (`PANEL_KEYS`); limits come from ConfigIO's
  `SETTING_SPECS` (a top-level `const` of a `.pragma library` is visible from QML, checked with `qml` offscreen).
  `restore_at_login` ask and auto and `app_memory = auto` are shown as "(later)" and refused by the service too.
  `tiled_order` and a scene's `key` are not shown (no default keys, not asked for).
- **Window edits** (folder, program, context): `Settings.windowEdit` changes a copy and adds the field to `edited`.
  The service checks the window's class at that index again, so a scenes.toml rewritten by the CLI in between is refused
  ("the scene changed on disk") instead of editing the wrong window.
- **Unknown context (`?`).** For a Chromium-family strategy (chrome, chromium, brave in `Settings.PROFILE_DIRS`) the
  service reads `~/.config/<browser>/Local State` and `Settings.profilesFromLocalState` keeps only `profile.info_cache`
  ids and display names; the text is dropped right after. Firefox or a user strategy without a known folder gets a typed
  field. IDEs (context kind `folder`) get Omarchy's file chooser; the window hides while it runs (omahop D22), and the
  folder is saved as `~/...`.
- **Monitors** are named like `lua/monitors.lua` `identity_of` (description, ` #2` for later twins in connector order,
  mirrors left out) from `hyprctl monitors -j`, so a picked monitor is the identity rules match. A rule's monitor that
  is not connected stays in the list as "(not connected)".
- **Answers that come later.** Open, restore and rule add answer pending; the window keeps the request id and, when the
  service's `req` goes back to null, reads `result-<id>.json` through `resultOf`. The folder chooser answers through
  `lastAnswer` and `revision`. `finish()` is untouched.
- **Launcher** like omagnet's: written at service load to `~/.local/share/applications/omaplace.desktop` only when
  absent or carrying `X-Omaplace-Managed=true`, removed at unload with `find ... -exec grep -qx <marker> {} ; -delete`
  (argv, no shell string; omagnet uses `sh -c`). This file is not in design 4.1; it was asked for in the WP6 brief.

## Known limits
- `context` is half of the key `SceneStore.mergeCapture` matches by and is not in its `EDITABLE` list, so marking it
  in `edited` would do nothing. A profile picked for an untagged window is kept until the next save of that scene with
  the window still untagged: that save sees `?` again and the slot's folder and program edits go with it. Once the scene
  is opened, omaplace launches the window with the profile and tags it, so later saves match. Needs a SceneStore change
  (owner WP3) if it bites.
- `markEdited` only adds fields a re-capture keeps (`Settings.KEEPABLE`, tested equal to SceneStore's `EDITABLE`).
- The slot spinner and the timing fields write on every step (each a write with .bak and a Lua reload).
- Twins: Omarchy keeps a twin's identity while plugged in, so a recomputed ` #2` can differ from Omarchy's after a
  replug (same limit as `lua/monitors.lua`).
- Nothing of the window has run in the shell (no reload, no install). `docs/checklist/WP6.md` lists the hand checks.

## Verified
- `bash tests/run-all.sh`: 30 run, 0 failed, 3 skipped. `bash tests/scrub.sh` ok. `omarchy-plugin-validate .` ok.
- `tests/qml_lint.test.sh` resolves `qs.Ui` and `qs.Commons` (a bogus property on a `qs.Ui` Button in a page was
  reported as `missing-property` and failed the test). Left out as noise: `not found on type "QObject"` (Style and Color
  tokens), `[unqualified]`, and `PanelWindow is not creatable` (omagnet's shipped panel gets the same).
- The run-all `qmllint` step (root files, no shell imports) prints import warnings for SettingsPanel.qml and passes, as
  qmllint exits 0 on warnings; the real check is the test above.

## SKIPs
- luacheck, stylua, shellcheck not installed.
