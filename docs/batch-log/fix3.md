# fix3: review findings, round 3

What changed and how it was checked. All tests: `bash tests/run-all.sh`, `bash tests/scrub.sh`.

1. **session_keep minimum is 2** (`lua/config.lua`, `js/ConfigIO.js`). Pruning also always keeps the newest instance
   that is not the current one, so the first save of a new login cannot delete the previous login's session, even if
   the value is forced lower. Tests: `test_config`, `config_io.test.mjs`, `test_glue_session` (keep forced to 1).
2. **ArgFilter** drops the value after `-a`, `-p`, `-u`, `--user`, `--pass`, `--auth`; joined forms like `-pPASS`;
   any argument containing `authorization` or `bearer` (any case) and the `-H` / `--header` before it; `user:pass@`
   and bare `user:pass`. Decision: `-p` with a purely numeric value (`-p 8080`, `-p8080`) is a port and is kept;
   a numeric `host:port` is kept too. Everything else is dropped (when unsure, drop). Cost: `ls -a /tmp` loses
   `/tmp`, and `find -print` style words that start with `-p` are dropped.
3. **Session debounce**: one timer, made once, then `set_timeout` + `set_enabled(true)`. `sessionpolicy.lua` owns the
   cap: a write is owed at most 2 x debounce after the first event of a burst (`first_at`, cleared by
   `Policy.fired` when the glue writes). The freeze still wins over the cap. `fake_hl` timers now re-arm on
   `set_enabled(true)` and have `set_timeout`.
4. **Scene bindings** are made only in `auto` mode, and `unbind_empty` runs after every close or move in
   `last_place` and `auto`, so a left over binding expires when its desktop empties. In `scene` mode memory
   events are not subscribed, so nothing can be bound there and nothing is dropped.
5. **Close without place**: a small `address -> place` map (`M.places`), set on open, move and run placement, removed
   on close. Used only when the closing window gives no place. Checked live 2026-11-21: close carries workspace
   and monitor, so this is a robustness test, not the main path.
6. **Loaded files**: `Memory.run_limited` runs the chunk with a count hook (1e6 instructions) and removes it
   afterwards; used by `open_file` and `Memory.decode`. `memory.lua` and plan files are read at most 1 MB + 1 byte.
   Tests: endless loop refused in `test_memory` and `test_glue_open`.

Also touched: `tests/settings.test.mjs` (one expected message, "from 2 to 50", because the limit text comes from the specs).

Not checked: the real `HL.Timer` behaviour when `set_enabled(true)` is called on a timer that is already running
(the callback re-arms itself if it wakes early). Linters not installed print SKIP in run-all.
