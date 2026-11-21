# WP9 batch log: app memory (F5), modes `scene` and `last_place`

## What changed
- `lua/memory.lua` (pure, time passed in): `new()`, `key(class, context)`, `update(mem, event, mode, now)`,
  `lookup(mem, class, context)`, `encode(mem)`, `decode(text)`.
  - A place is `{ class, context, fp, slot, rect, floating, n, saved_at }`. `fp` is the monitor fingerprint (flat, only
    strings, booleans and finite numbers kept), `slot` an integer 1 to 10, `rect` four finite fractions or nil.
  - `update` records `placed` in every mode except `off`; `closed` and `moved` only in `last_place` and `auto`, and only
    when `others` (other open windows of the class) is 0. Returns true when the memory changed.
  - Cap: 200 entries. `n` is a counter kept in the file; the lowest `n` goes first. No clock is needed for the order.
  - `encode` writes `return { ... }` with sorted `["key"]` keys, decimal numbers (`%.14g`, not `%q` hex floats) and the
    same string escaping as `js/LuaLiteral.js` (backslash, quote, newline, every control byte as `\ddd`), so the service
    can read the file the same way later. `decode` loads it as text in an empty environment, refuses files over 1 MB,
    and drops entries that do not check out (bad slot, no fingerprint, key that does not match its class and context).
- `lua/omaplace.lua`:
  - Memory is read at file load from `~/.local/state/omaplace/memory.lua`. Missing or unusable file: empty memory and
    one log line (the error is named, the text is never quoted). A reload of the file in the same Lua state keeps the
    memory it had (it can be newer than the file) and does a save the old debounce still owed. `reload_config` does not
    read the file.
  - Run end (`conclude`): every claimed window is recorded (`placed`) with its live place from `Capture.snapshot` on a
    one-window list, the slot's class and context, and the scene's own rect fractions when it is floating. One save
    per run end, only when something changed. In its own `pcall`, so a memory failure never changes the run result.
  - `window.open` with no live run: placed from memory only if `app_memory` is not `off`, the class has an entry for the
    window's context (none for an untagged window), the window is not on a special workspace and no other window of
    the class is open (counted by address, so it does not matter whether the new window is already in the list).
    No enabled rule for the class: silent move to the remembered monitor (`monitors.resolve` with
    `missing_monitor_scene`) and slot. An enabled rule: no move; continue only when the remembered workspace is the one
    the window is on. Then tag `omaplace-slot=memory`, and if the entry is floating with a rect, one `settle_ms` timer
    puts it with `place.lua` `put`, only if the window is floating and has `omarchy-floating-workspace` then (D13).
  - `last_place` and `auto` subscribe to `window.close` and `window.move_to_workspace` (list `M.memory_subs`, synced at
    load and in `reload_config` like the session ones, removed on a reload of the file). A close is read in the handler
    (the window is gone later); a move is read when the debounce fires, after Omarchy re-arranged it. One 2 s one-shot
    debounce for both (generation number plus `set_enabled(false)`), one save per burst. Moves while a run is live are
    ignored (the run records its windows at the end). `auto` is `last_place` for now; WP10 adds the scene moves.
  - `state_dir` moved up the file (the run end needs it).
- Tests: `test_memory.lua` (69 checks), `test_glue_memory.lua` (64 checks). `test_glue_open.lua` now removes
  `memory.lua` from its fixture home at the start, and `fixtures/home-session-off/.local/state/omaplace/.gitignore`
  keeps that file out of git. New fixture `fixtures/home-memory` (config with `session = "off"` and one rule).

## Decisions (design or brief was silent or unclear)
- **`off` is not a config value yet.** `config.lua` and `js/ConfigIO.js` accept only `scene`, `last_place`, `auto`, and
  this package owns neither. The glue already treats `app_memory = "off"` as off (nothing placed, nothing recorded);
  the test sets it directly. Follow-up: add `off` to both enums (and a cross-check fixture).
- **"Not modal"** (design 6.3) is not checked: the `HL.Window` stubs have no modal field.
- **A move counts only for the class's last window**, like a close, so a browser with two windows does not keep
  rewriting its one memory entry.
- **"A rule exists"** means an enabled rule (the spec Hyprland accepted, `M.enabled`) whose `app` is the class. A rule
  switched off because its monitor is missing does not count, since it places nothing.
- **Missing file logs one line** at load, as the brief asks (only at file load, never on `reload_config`).
- **The memory placement tag** is `omaplace-slot=memory` (no run id, no slot number).
- Memory is keyed on class plus context (D18). A hand-opened window has no context tag, so a context entry (a Chrome
  profile from a scene) never places it.

## Verified
- `bash tests/run-all.sh` (twice, `git status` clean after): all pass. `bash tests/scrub.sh`: ok.
- Mutations, one at a time, each failed `test_glue_memory.lua`: no first-window check; rule check removed; the
  floating-tag check before the rect removed; `others` forced to 0 on close.
- Measurement (design 8), fake hl, Lua 5.5, this laptop, `os.clock`, 200 memory entries, 100 windows: `window.open`
  with no run and no entry for the class 0.0007 ms; with an entry and a second window (scans 100 windows) 0.004 ms;
  `encode` of 200 entries 1.6 ms (once per run end or per debounce).

## Not done here
- Not checked live: the argument of `window.close` and `window.move_to_workspace` is assumed to be the window (first
  argument), and the window is assumed to still have its workspace, monitor and place in the close handler.
- The service does not show memory yet (design 4.1 lists `Service.qml` as a reader, for display).
- SKIP: luacheck, stylua, shellcheck are not installed.
