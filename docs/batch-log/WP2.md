# WP2 batch log: placement rules (M1)

## What changed
- `lua/rules.lua` (pure): `build(cfg_rules, live, resolve, ws_id, focused, previous, policy)` gives specs
  `{ name = "omaplace-rule-<name>", match = { initial_class }, workspace, enabled }` sorted by name, and the vanished names.
- `lua/omaplace.lua` (the only hl and file user): reads the config, declares rules, handles the four monitor events
  through one 500 ms debounce, exposes `_G.omaplace = { version, reload_config, status }`.
- Tests: `test_rules.lua` (23 checks), `test_glue_rules.lua` (34 checks), fixtures `lua/tests/fixtures/home-*`.
- `fake_hl.lua`: `hl.timer` also takes Hyprland's real form `(fn, { type = "oneshot", timeout = ms })`; new
  `fake.pending_timers()`. Old calls still work.
- README: "Placement rules" section.

## Decisions (design was silent or unclear)
- `build` has two extra optional arguments after `focused`: `previous` (names from the last build) and `policy`
  (`missing_monitor_rule`).
- A rule with an empty `monitor` uses the focused monitor (the brief); design 5.2 says "any monitor, keep the slot", which
  is the same thing in per-monitor mode for one rule, but note the rule follows the focused monitor at build time.
- A rule with no app, a bad slot, no focused monitor, or a missing monitor is disabled, never an error.
- Monitor lookup passes `{ identity = rule.monitor }` to `monitors.resolve`, so only step 1 can match, plus the focused
  fallback when the policy is `focused`.
- Debounce: Hyprland's timer handle has no documented stop, so a re-arm bumps a generation number; the older timer
  fires once and does nothing. The handle's `cancel` is called when it exists. Five events give one rebuild.
- Once-per-state guard and the previous load's rule names live on fields of `_G.omaplace` (`_bound`, `_m`), not on a
  second global.
- Initial build runs at load, using whatever `hl.get_monitors()` gives then; monitor events fix it afterwards.

## Verified
- `bash tests/run-all.sh` and `bash tests/scrub.sh` pass. The glue test uses fixture HOME folders, never `~/.config`.
- Idle: no timer after load, none after a rebuild (`fake.pending_timers() == 0`).
- Not verified live: the real `hl.timer` and `hl.window_rule` field names (`initial_class`, `workspace`) are copied from
  omagnet and Omarchy source, not run. See the checklist.

## Measurement
- A rebuild is one pass over the rules and monitors: work is rules x monitors, tiny, and only after a monitor event.

## SKIPs
- luacheck, stylua, shellcheck not installed (listed as SKIP by the runner).
