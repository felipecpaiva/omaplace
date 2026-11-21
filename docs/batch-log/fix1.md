# fix1 batch log: review findings in the Lua core

## What changed
- `monitors.lua`: step 1 first looks for a live monitor with the same description on `fp.last_connector`, so a twin that was plain when it was alone stays itself when its twin is plugged in later. New optional fingerprint field `twin = true`, set when the identity was shared at save time. A serialless twin whose connector is gone is not matched by identity, model or shape (the screen left behind may be another one); it falls to `focused` or `skip`. Old fingerprints without `twin` behave as before.
- `config.lua`: maxima for the seven timing and size settings (and `schema`, to match JS). A section that is not `rule.<name>` or `strategy.<name>` still goes to `extra` and now warns once, also when empty. `js/ConfigIO.js` has the same warning (its maxima were already there).
- `json.lua`: `encode` returns `nil, err` for a key that is not a string or integer, and for two keys that become the same string.
- `shellquote.lua`: `join` returns `nil, err` for an argv with holes or extra keys.
- Fixtures: `app = "a" "b"` added (in a rule with a valid `slot`) to `config-lua/bad.toml` and `config-js/bad_values.toml`; expected JSON regenerated from each side's own parser.

## Known gap (not changed)
- A `[rule.x]` section with only unreadable lines exists in JS but not in Lua. Left alone, outside this batch.
