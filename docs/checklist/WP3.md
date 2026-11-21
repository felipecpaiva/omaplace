# WP3 hand checks

WP3 is pure JavaScript with no user visible part yet. Hand checks:

- [ ] `bash tests/run-all.sh` ends with `0 failed` and lists the node suites.
- [ ] `bash tests/scrub.sh` prints `scrub ok`.
- [ ] Each file in `js/` starts with `.pragma library` and has no `import` line.
- [ ] Read `tests/fixtures/config-js/bad_values.expected.json`: every bad value shows its default and one warning.
- [ ] When WP5 loads these files in `Service.qml`, run `qmllint Service.qml` and open the shell once to check the libraries load.
