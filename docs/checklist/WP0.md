# WP0 hand checks

- [ ] Run `omarchy-plugin-validate .` in the repo folder. It passes.
- [ ] Run `bash tests/run-all.sh`. It ends with `summary: ... 0 failed` and lists the SKIPs.
- [ ] Run `bash tests/scrub.sh`. It prints `scrub ok`.
- [ ] Open `manifest.json`: id, name, version 0.0.1 and kinds are right.
- [ ] Nothing shows in the shell yet. The stubs do nothing on purpose.
