# WP1 batch log: Lua pure core

## What changed
- `lua/config.lua`: parses the config.toml subset, one defaults table (design 7.5), `[rule.<name>]` and `[strategy.<name>]`. Returns `{ schema, settings, rules, strategies, warnings }`. Unknown keys go in `extra` (top level, and inside a rule or strategy), present only when there are some. Bad values fall back and add a warning.
- `lua/geometry.lua`: `usable`, `place_frac`, `logical_size`, `transfer` copied unchanged from omagnet commit 856de02, plus `to_frac`.
- `tools/gen-geometry-golden.sh <omagnet checkout>` writes `lua/tests/fixtures/geometry-golden.lua` (99 usable areas, 891 place_frac cases, 99 transfers; scales 1, 1.25, 1.6, 2; transforms 0 and 1; reserved areas; margins).
- `lua/monitors.lua`: `fingerprint`, `resolve` (6 ordered steps).
- `lua/slots.lua`: `with(o)` gives `mode`, `workspace_id`, `slot_of`.
- `lua/json.lua`: `encode`, and `object(t)` to force `{}` for an empty table. `lua/shellquote.lua`: `join`.
- `lua/tests/fake_hl.lua`, seven `test_*.lua` files, six config fixtures with `.expected.json`.

## Decisions (design was silent or unclear)
- Identity follows Omarchy's real code: the first of a set of twins is the plain description, later ones get ` #2`, ` #3` (design 5.1 and 5.2 show `#1`; Omarchy never writes `#1`). Twins are numbered by connector name. Omarchy also keeps identities sticky while plugged in; a pure function cannot, so after a replug the numbers could differ.
- `serial_hash` is 8 hex digits (32 bit FNV-1a). An empty serial gives an empty hash, and an empty hash never matches in step 2.
- Step 3 needs exactly one live monitor of that make and model, and a non-empty make or model.
- Step 5 compares pixel size with rotation applied (not divided by scale). The closest shape wins; ties go to the lowest connector name.
- Step 6 `focused` needs a monitor with `focused = true`; with none it returns `nil, "skip"`.
- Mirrors are never candidates.
- Defaults for a rule: `slot = 1`, `follow = false`, `enabled = true`, empty `app` and `monitor` (a rule with no app gets a warning). Strategy: `use = "desktop"`; allowed values are the design's seven plus `skip`.
- Empty JSON tables encode as `[]`. `config.lua` returns plain tables, so the test marks `rules` and `strategies` with `json.object` before encoding. The `.expected.json` files are exactly that output (compact, sorted keys, final newline).
- Warning order: unreadable lines and bad section names first, then settings, then sections in file order. The JS cross-check should compare warning counts, not exact text.

## Verified
- `bash tests/run-all.sh` and `bash tests/scrub.sh` pass.
- Geometry matches omagnet on every golden vector; `to_frac` round trips on all margin 0 cases.
- `shellquote` is also run through a real `sh` (printf only) to count words, including a shell injection attempt that must stay one argument.

## SKIPs
- luacheck, stylua, shellcheck not installed (listed as SKIP by the runner).
