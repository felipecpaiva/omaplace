# WP3 batch log: JavaScript pure core

## What changed
- `js/ConfigIO.js`: `parse`, `setValue`, `setRule`, `removeRule`. Line-preserving writers: comments, blank lines, unknown keys and sections stay.
- `js/SceneStore.js`: `parse`, `serialize`, `migrate`, `mergeCapture`.
- `js/AppResolve.js`: `defaultStrategies`, `mergeStrategies`, `resolve`.
- `js/ArgFilter.js`: `filter`. `js/Plan.js`: `fromScene`, `fromSession`. `js/LuaLiteral.js`: `encode`.
- Tests: one `tests/*.test.mjs` per module. Config fixtures in `tests/fixtures/config-js/` (empty, full, bad_values, unknown_keys, two_rules, strategy), each with `.expected.json`, for the later cross-check against `config.lua`.
- The Lua half of the cross-check (`lua/tests/test_config_crosscheck.lua`) is not part of this package: the brief gave WP3 only the JS files. WP1 or the integrator adds it.

## Decisions where the design was open
- `parse()` result has the five listed keys; `extra` is added only when the file has unknown keys. It is a flat map of `"key"` or `"section.key"` to the value. `schema` is both top level and in `settings`.
- Warnings are short and stable (`key: reason, using default`), with a line number only for lines that are not `key = value`.
- Defaults for a rule: `slot = 1`, `follow = false`, `enabled = true`; an empty `app` or an empty strategy `match` adds a warning.
- Strategy patterns: case-insensitive, `|` for alternatives, `*` for a wildcard. Launch templates split on spaces with quotes (no shell), and `{context}` / `{folder}` replace whole substrings of an argv element. A context or folder that starts with `-` is refused (`mode: "skip"`) so it cannot be read as a flag.
- `resolve` result has one extra field, `reason` (empty unless skipped), so the result can list why. A slot may carry `home` to expand a leading `~` in a folder, because argv has no shell.
- A typed `launch` wins over any strategy except `terminal`, where `launch` is the captured program.
- A context app with no saved context uses its plain desktop entry; context `"?"` is skipped.
- `SceneStore`: `edited` is a window field (space separated names, only `app rect order floating launch folder` count; `class` and `context` are the match key). Unknown keys in scenes and windows are kept in `extra`. Windows are renumbered 1..n on write. A scene name made of digits only would move first in the file (JS object key order).
- `Plan.fromScene(scene, launches, target, rules)`: `launches[i]` belongs to `scene.windows[i]`; `target` is `{ run, fp, slot, layout, expiry_s }`. The rule desktop is `desktop = { monitor, slot, follow }` on the window. Windows are sorted by `order`.
- `Plan.fromSession(snapshot, launches, opts)` takes a third argument `{ run, layout, expiry_s }` because the two-argument form has no run id. Windows keep `monitor` (an index into `plan.monitors`) and `slot`. The design gives no per-monitor layout for a session, so `layout` is one value.
- `LuaLiteral`: a reserved Lua word as a key is written as `["end"]`. Whole floats come out as integers.
- `ArgFilter` also drops flags such as `--session` and `--cookie` and `NAME=value` even as the first argument. When unsure, drop.

## Verified
- `node --test tests/*.test.mjs` for each module, all pass (counts in the commit message and the run output).
- `bash tests/run-all.sh` and `bash tests/scrub.sh` pass.

## SKIPs
- luacheck, stylua, shellcheck are not installed.
