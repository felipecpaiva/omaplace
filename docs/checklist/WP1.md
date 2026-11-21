# WP1 hand checks

Nothing is user visible yet. These are developer checks.

- [ ] `bash tests/run-all.sh` ends with `0 failed`, and lists the SKIPs for missing linters.
- [ ] `bash tests/scrub.sh` prints `scrub ok`.
- [ ] `lua lua/tests/test_geometry.lua` passes without an omagnet checkout next to this repo.
- [ ] Optional: `bash tools/gen-geometry-golden.sh <omagnet checkout>` leaves `git diff` empty when omagnet's geometry has not changed.
- [ ] Open `tests/fixtures/config-lua/bad.toml` and `bad.expected.json`: each bad line has a warning and the default is used.
