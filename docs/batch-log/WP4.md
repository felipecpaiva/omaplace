# WP4 batch log: scene engine (M2)

## What changed
- `lua/capture.lua` (pure): `snapshot(windows, monitors, opts)` gives design 5.5: per window `class` (initial class),
  `monitor` (0-based index into `monitors`, sorted by connector), `slot`, `order` (left to right by x, then y, per
  workspace), `rect` (fractions of the usable area, 4 decimals), `floating`, `fullscreen`, `minimized`, `context` (from
  the `omaplace-ctx=<hex>` tag) and `pid`. Special workspaces are skipped, except minimized windows, which count on the
  home workspace from Omarchy's `omarchy-minimized-from-<id>` tag. Ignored classes are skipped. No title, no address.
  Helpers: `ctx_hex`, `ctx_unhex`, `tags_of`, `context_of`, `home_of`, `ignore_set`.
- `lua/tickets.lua` (pure): `new`, `claim`, `expire`, `next_launches`, plus `fail`, `finished`, `next_wake`, and
  `swaps(windows)`: the swaps that put tiled windows in saved order from their current places (S8).
- `lua/place.lua` (hl): `to_workspace(window, id, silent)`, `put(window, rect_px, done)`, `fit_shadow_if_present`,
  `find`. All waits are one-shot timers with the body in `pcall`.
- `lua/omaplace.lua`: `_G.omaplace.open(plan)`, `open_file(path)`, `capture(req_id, scope)`; `status()` now also has
  `run`, `state` (`idle` when no run yet) and `items`. Writes `status.json` and `capture-<req>.json` under
  `$XDG_RUNTIME_DIR/omaplace/` (temp file, then rename). One `window.open` subscription, kept in `M.subs` like the
  monitor ones. Reload during a run: the old run stops and the status says `interrupted`; a `"state":"running"` left in
  `status.json` by a Lua state that is gone is rewritten to `interrupted` on load. Rule code untouched.
- `lua/tests/fake_hl.lua`: timer handles also have `set_enabled` and `is_enabled` (Hyprland's real methods); `cancel`
  kept, so old tests still pass.
- `lua/tests/fixtures/runtime/`: the glue test's runtime folder; its `.gitignore` keeps what the test writes out of git.
- `lua/tests/test_glue_rules.lua`: points `XDG_RUNTIME_DIR` at a folder that does not exist, so the rules test never
  reads the real runtime folder.
- Tests: `test_capture.lua` (34 checks), `test_tickets.lua` (64), `test_glue_open.lua` (102).

## Decisions (design was silent or unclear)
- **Context gate.** A class with any context slot launches one slot at a time. The gate stays open while the launched
  slot has no window yet (until it expires) and then until the class has had no new window for `context_quiet_ms`. A new
  untagged window of that class goes to the next waiting slot of the open context, launched or not (so a window the
  browser restores fills a second slot of the same profile without a second launch). Extra windows return nil but keep
  the class busy. A second slot of the same context also waits for the gate, so a restored window is never doubled by
  our own launch.
- **Plain classes** (no context): a new window only claims a slot that was already launched. This keeps a window the
  user opens by hand from jumping into a slot early, and in tiled mode keeps the order.
- **Move pass** claims open windows in `stable_id` order, exact class and context (untagged = `""`). Windows on special
  workspaces other than minimized are left alone. On a tiled target the moves happen in turn with the launches, so the
  left-to-right order is kept.
- `place_only` slots start at once (no tick), wait for the app's own window, and expire like the rest. Context `"?"`,
  an empty class, and mode `skip` are `skipped` from the start.
- **Rects** are put only when, after the settle, the window is floating and either its workspace is the floating scene
  target or Omarchy tagged it `omarchy-floating-workspace`. So a rule desktop gets the scene's rect only if it is a
  floating one, and a tiled one never gets a rect (D13). Settle (`settle_ms`) after a workspace move and for any new
  window; an already-placed existing window is put at once.
- **Focus.** Only windows with `desktop` (rule) move with `follow = true`; when the window is already there the
  workspace is focused. The last rule window claimed wins. A scene target other than the current desktop does not take
  the focus (not stated in the design).
- **Target.** An empty `target.fp` (no identity) means the focused monitor; slot 0 means that monitor's active
  workspace. `missing_monitor_scene` for the scene, `missing_monitor_rule` for a rule desktop (a rule desktop that
  cannot be found falls back to the scene target). Session plans (`kind = "session"`, per-window `monitor` index and
  `slot`) already resolve per window, for WP7.
- **open errors:** `busy`, `bad_plan` (no run id of `[%w_-.]`, at most 64 chars, or no windows list), `no_monitor`,
  `failed` (anything that raised). `open_file` adds `bad_path` (only `$XDG_RUNTIME_DIR/omaplace/plan-*.lua`, no
  sub-folders) and `no_file`; a syntax error, a runtime error (for example calling `os` in the empty environment), a
  binary chunk or a non-table result all give `bad_plan`.
- **Run end:** `done` when every slot is placed or moved, `partial` otherwise; it ends only once no put is pending.
  The engine keeps at most one run timer (re-armed with `set_enabled(false)` plus a generation number) plus one
  one-shot per pending put.
- **Clock:** milliseconds from `/proc/uptime` (omahop's method; `os.clock` is CPU time). Tests replace
  `_G.omaplace._m.now_ms`. `since` in the status is wall seconds.
- **Folder:** Lua cannot make a folder, so at load (only when it is missing) the glue runs
  `mkdir -p -m 700 '<runtime>/omaplace'` through `hl.exec_cmd`, and again if a write fails. WP5's service should also
  make it before its first call, so the very first capture after login cannot fail on the race.
- `pid` is in the capture file only (runtime folder) so the service can run `procinfo.sh`; scenes and session files
  must never store it.
- Old `omaplace-slot=` tags of an earlier run are removed when a window is claimed again.

- **Live results folded in (main, S2, S3, S8, S9).** At the end of a tiled run the glue reads each claimed window's
  `at` on its target workspace and dispatches `hl.dsp.window.swap` (by `address:` selector) as `Tickets.swaps` says.
  At the end of every run the view goes back to the target workspace, or to the last rule desktop (D9), with
  `hl.dsp.focus({ workspace })`. All window selectors are `"address:<addr>"` strings, like Omarchy's own dispatches.
- **Layout.** The glue looks at the target workspace at `open`: a window with `omarchy-floating-workspace` means
  floating, a tiled window without it means tiled; an empty target keeps `plan.layout`. So for an empty target WP5 must
  send the right `layout` (Plan.js defaults to `floating`); reading Omarchy's mode file is not done (design section 3
  lists `~/.local/state/omarchy/**` as never touched). On a wrong `floating` guess for an empty tiled target the windows
  are not floating, so no rect is forced; only the order fix is lost.
- **Nothing fails silently.** A put that ends `size_refused`, `gone` or `not_floating` marks the item `failed` with that
  reason (not floating on a tiled desktop is not an error). A moved window that is gone before its turn fails with
  `gone`. A raise in a step, a start, an apply or a put fails the slot (`error`); a raise in a step ends the run as
  `partial`, so a later `open` is never stuck on `busy`.
- `open_file` logs a fixed text for a bad file, never the parser message (it can quote plan text).

## Verified
- `bash tests/run-all.sh` (22 run, 0 failed, 3 skipped) and `bash tests/scrub.sh` pass, after merging main twice
  (fix1 and the `open_file` design update).
- Glue tests run against the fixture runtime folder in the repo; the real `~/.config` and runtime folder are never
  touched. The test cleans its files at the start and the end.

## Known limits (not fixed)
- The one-time `mkdir` through `hl.exec_cmd` at load (only when the folder is missing) is a short process the design
  does not list.
- A reload stops the run timer, but settle and put one-shots already armed still fire once (they act on the window
  only; the old run is not live, so its status is not touched).
- Capture takes a minimized window's monitor from the special workspace it sits on, not from its home workspace.
- The tiled reorder runs as soon as the last slot is final; if Hyprland's `at` is not final by then (animation), the
  order check could see old places (live check in the checklist).

## Measurement (plain `lua`, this laptop)
- Capture of 120 windows plus JSON encode: about 2 ms.
- 100 claims plus 100 `next_wake` on a 100 slot book: under 1 ms in total.
- Idle: `window.open` returns after one table check when no run is live; no timer while idle (tested).

## Only a live test can confirm (checklist WP4)
- Tag names with `=` and `/` (`omaplace-slot=r1/1`) are accepted by the tag dispatcher.
- `hl.dsp.window.move({ workspace, follow, window })` and `hl.dsp.focus({ workspace })` behave as in Omarchy's code.
- The settle and the 40 ms size check land the exact rect (S4). (S2 done on main: `window.open` about 0.2 s after
  launch. S3 done: no `window.open`, the ticket expires.)
- The swap fix on a real dwindle and scrolling workspace, end to end (S8 found the problem; the fix is untested live).
- Restored windows of a closed profile inside the quiet window (S9 part 2, S10); the view going back at the end.

## SKIPs
- luacheck, stylua, shellcheck not installed.
