# WP7 batch log: session snapshots, Lua half (M3)

## What changed
- `lua/sessionpolicy.lua` (pure, time passed in): `new(debounce_ms)`, `on_event(state, kind, now)` returning
  `{ action = "schedule", at }`, `{ action = "freeze", until_ms }` or `{ action = "none" }`, and `frozen(state, now)`.
  Trailing debounce of `session_debounce_s`. Three `window.close` within 2 s (a close exactly 2 s after the first still
  counts) freeze writing for 60 s; a fourth close extends the freeze. Any schedule that falls inside a freeze moves to
  its end. Only the last 3 close times are kept.
- `lua/omaplace.lua`:
  - With `session = "on"`, one subscription each for `window.open`, `window.close`, `window.move_to_workspace`,
    `window.active`, `monitor.added`, `monitor.removed`, `monitor.layout_changed` (kept in `M.session_subs`, separate
    from the rule and scene ones). `sync_session()` runs at load and in `reload_config()`, so turning the setting on or
    off takes effect without re-running the file.
  - One session timer at most (`M.session_timer`): arming switches the old one off and bumps a generation number. A
    freeze moves a pending write to the end of the freeze. When the timer fires it checks the freeze again and, if
    frozen, re-arms at its end (a write never happens inside a freeze).
  - The write: `Capture.snapshot` with scope `all` and kind `session` (the option building is now shared with
    `capture`), `pid` removed, to `~/.local/state/omaplace/session-<instance>.json` (temp file, then rename).
    `<instance>` is `HYPRLAND_INSTANCE_SIGNATURE` with every character outside `[A-Za-z0-9_]` turned into `_`, cut to 128.
  - Index `~/.local/state/omaplace/sessions.json`, written by Lua only: a JSON array, newest first,
    `[{"instance":"<name>","saved_at":<unix s>}]`. Each write puts the current instance first (no duplicates on a reload),
    keeps `session_keep` entries and `os.remove`s the session files of the ones dropped. The current instance is never
    pruned.
  - `~/.local/state/omaplace` is made at load with `mkdir -p -m 700` through `hl.exec_cmd`, the same way as the runtime
    folder (only when it is missing). `write_atomic` became `write_in(folder, name, text)` plus the old wrapper.
  - `_G.omaplace.session_save_now()`: true, or `nil` and `frozen`, `empty`, `no_instance`, `write_failed`. It writes at
    once and disarms the pending timer, but refuses during a freeze.
  - `_G.omaplace.sessions()`: the index as a Lua list, `{ { instance, saved_at }, ... }`, newest first.
  - Policy state survives a reload of the file (a freeze is kept).
- Tests: `test_sessionpolicy.lua` (22 checks), `test_glue_session.lua` (53 checks).
- Existing tests: the scene and rule glue tests now run with `session = "off"` so their idle and handler-count checks
  stay exact: `test_glue_open.lua` uses the new fixture `fixtures/home-session-off` (config `session = "off"` and an
  existing state folder) instead of `home-none`; `fixtures/home-rules*/config.toml` got `session = "off"` (only that
  test reads them). `fixtures/home-session/.local/state/omaplace/` is the session test's state folder; its
  `.gitignore` keeps what the test writes out of git.

## Decisions (design was silent or unclear)
- **An empty desktop is never written.** Events that come during a close burst (focus moves on as windows close) are
  scheduled at the end of the freeze, as the brief says. After a close-all with no shutdown, that write would find no
  windows and replace the last good snapshot with an empty one. So a snapshot with no windows is skipped. A partial
  close (some windows left) is written after the freeze, which is the real state. A write armed before a burst moves
  to the end of the freeze too.
- **Session subscriptions live in `M.session_subs`**, not `M.subs`, so `sync_session()` can drop them alone when the
  setting is switched off; a reload of the file removes both lists.
- `sync_session()` has its own `pcall` at load and in `reload_config()`, so a session failure never stops the rules.
- **No signature, no session**: with `HYPRLAND_INSTANCE_SIGNATURE` unset, nothing is written (one log line), because a
  shared file name would let the new boot overwrite the previous one.
- **Index on every write**, not only the first: `saved_at` stays current and the extra small file costs nothing
  measurable. The index is read back with a pattern over our own sorted-key JSON (`json.lua` has no decoder).
- `monitor.focused` is not a session event (focus changes come as `window.active`).
- For the service (WP7 restore, later): `sessions.json` is not in the design 4.1 table yet; its format is above. Pick
  the first entry whose `instance` is not the current sanitised signature. `session_save_now()` returning `true` in
  design 7.1 now also has the `nil, err` cases listed above.

## Verified
- `bash tests/run-all.sh`: all pass; `bash tests/scrub.sh`: ok.
- The freeze and empty-desktop guards were broken on purpose once each; the glue test failed both times.
- Measurement (design 8), fake hl, Lua 5.5, this laptop, `os.clock`: a session event handler takes about 0.008 ms
  (reads `/proc/uptime` and re-arms one timer); one session write with 100 windows on 3 monitors takes about 1.8 ms
  (snapshot, encode, two files).

## Not done here
- Restore wiring in `Service.qml` (`Plan.fromSession`, picking the previous instance) is the service side, done later.
- Not checked live: event names come from `/usr/share/hypr/stubs/hl.meta.lua`; that `window.close` fires once per window
  during a real shutdown or close-all burst is assumed.
- SKIP: luacheck, stylua, shellcheck are not installed.
- Two Hyprland instances running at the same time both rewrite `sessions.json`; the last writer wins. Rare, not handled.
