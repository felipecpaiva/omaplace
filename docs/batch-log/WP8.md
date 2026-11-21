# WP8 batch log: Omarchy menu rows, WP10 service wiring, fixes from the live checks

## What changed
- `js/MenuExt.js` (pure): `addRows(text, cli)`, `removeRows(text)`, `hasRows(text)`. One block between
  `// omaplace begin` and `// omaplace end`, put right after the file's opening `{` with a comma after every row, so the
  user's last entry never needs a comma and everything outside the block stays byte for byte. Refuses (and changes
  nothing) when the text is not an object Omarchy's own reader accepts, uses an `items` wrapper, has a begin line with
  no end, or the CLI path is not absolute or holds a quote. An existing block is replaced, never doubled. An empty or
  comment-only file gets a new object after its comments.
- Rows: `omaplace` "Scenes" (submenu), `omaplace.save` "Save this desktop" (`'<cli>' save --ask`), `omaplace.open`
  "Open a scene" (`open --pick`), `omaplace.restore` "Restore last session" (`restore`), `omaplace.rule` "Always open
  here" (`rule add`), `omaplace.settings` "Settings" (`settings`). Omarchy runs an action with `bash -lc`
  (`Commons/Util.qml execDetached`), so `$HOME` would expand, but the block holds the absolute, single-quoted path to
  `bin/omaplace` worked out when it is written (design 7.3).
- `Service.qml`: `menuInstalled()`, `menuAdd()` (writes `omarchy-menu.jsonc.omaplace.bak` first, then the file,
  both atomic), `menuRemove()` (takes out only the block, leaves the backup). Nothing writes the menu file at load.
  `panelData()` carries `menu`. The settings window's General page has the button ("Add omaplace to the Omarchy menu" /
  "Remove from the menu") and a line saying the backup is kept.
- `bin/omaplace`: `save --ask` asks with `omarchy-menu-input`; Enter alone takes the desktop's name from
  `hyprctl activeworkspace -j` (lower case, other characters made `-`, 40 at most). `open --pick` lists the scenes
  with `omarchy-menu-select`. A closed picker exits 0 and does nothing. `restore` prints a counts line like `open`.
  `empty` answers print "nothing to save on this desktop" and exit 3.
- WP10 wiring in `Service.qml`: `Plan.fromScene` gets `scene: <name>`. While `app_memory` is `auto` (read at load,
  after every config write and after every request), a `FileView` watches `moves.json`, and `finish()` reads it again
  (the watch can miss a rename). `js/MovesFeed.js` (pure) picks the events after the highest `at` handled, oldest first;
  a file whose newest `at` is older than that means Hyprland restarted, so all events count again (AutoMove skips the
  ones already applied). `AutoMove.apply` runs on the scenes doc; scenes.toml is written (`.bak` first) only when an
  event was applied, and `at` only moves on once the write worked. Skipped reasons other than "already applied" are
  logged with the class only. No timer.
- Fix (a): a save with nothing to save answers `{"ok":false,"code":"empty"}` (design 7.2 lists the code; the settings
  window has a word for it).
- Fix (c): `js/SceneStore.js` `mergeCapture` matches in passes: all exact (class, context) pairs first; then a
  captured `?` window takes an unused old slot of its class (one whose context was picked first), and a window with no
  context takes only a slot whose context was picked. Such a window gets the old slot's context. `context` is now in
  `EDITABLE` (and `Settings.KEEPABLE`), so picking a profile or folder marks it edited. This closes the WP6 known limit.
- Review fixes: `finish()` deletes the request's plan file (it holds launch arguments) and capture file, and the
  previous request's result file, with `rm -f --` on paths built from our own ids. `hyprctl eval` calls go through
  `js/LuaCall.js`, which returns `omaplace:<code>`: `no_lua` only when `_G.omaplace` is really missing, and Lua's own
  errors (`busy`, `bad_plan`, `no_monitor`, `no_runtime`, `bad_path`) end the request at once instead of a `no_lua`
  after 2 s. `startRestore` checks the instance name before it becomes a path. A file chooser that never starts clears
  `picking` (`onStarted` plus `onRunningChanged`).

## Verified
- `tests/menu_ext.test.mjs` on made-up fixtures in `tests/fixtures/menu/` (empty object, entries, comments and a
  trailing comma, comment-only), every output read back with a copy of Omarchy's `stripJsonc` and `JSON.parse`, add then
  remove byte for byte, replace, refusals.
- `tests/scene_store.test.mjs`, `tests/settings.test.mjs`: the `?` cases, a `?` window listed first, round trip.
- `tests/moves_feed.test.mjs`, `tests/lua_call.test.mjs` (the Lua text is run in `lua` with and without a fake module).
- `tests/cli.test.sh`: fake `omarchy-menu-input`, `omarchy-menu-select` and `hyprctl` on PATH (81 checks).
- `bash tests/run-all.sh` (37 run, 0 failed, 3 skipped), `bash tests/scrub.sh`, `omarchy-plugin-validate .`.

## Not done / known limits
- Nothing ran in the shell (no reload, no install, the real menu file was only read). `docs/checklist/WP8.md` lists
  the live checks, S6 among them.
- A row started from the menu has no terminal: the CLI's text and errors are not seen. An open or restore still sends
  its notification; a save or rule add from the menu shows nothing. A notification for those is a small follow-up.
- `hyprctl eval` printing the chunk's return value is taken from the WP2 checklist; if it prints nothing, the service
  falls back to the old wait (status watch and the 2 s check).
- The app memory choice "Automatic" in the General page is still marked "(later)" (WP6). The wiring is in; enabling
  the button is a one-word change once the live check of WP10 passes. Until then set `app_memory = "auto"` by hand.
- `autoMemory` follows hand edits of `config.toml` only after the next request or a settings change.
- A one-line object (`{ "a": ... }`) gets a line break after `{` that remove keeps; the file stays valid.

## SKIPs
- luacheck, stylua, shellcheck not installed.
