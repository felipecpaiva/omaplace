# WP0 batch log: scaffold

## What changed
- `manifest.json` (id `io.github.felipecpaiva.omaplace`, version 0.0.1, kinds service and panel).
- Stub `Service.qml` and `SettingsPanel.qml`. They load and do nothing. WP7 fills the service, WP9 the panel.
- `tests/run-all.sh`: finds Lua, node and bash tests by glob, runs the linters that are installed, runs scrub and the plugin validator, prints a one-line summary.
- `tests/scrub.sh`: private data check. `docs/research/` is skipped for the home path and machine name checks only.
- `LICENSE` (MIT), README sections Install, Load the Lua module, Remove, Tests.

## Verified
- `bash tests/run-all.sh`: exit 0, 3 run, 0 failed, 3 skipped. Lua 5.5 check passed, qmllint passed on both stubs.
- `bash tests/scrub.sh`: ok on the whole repo. A throwaway file with a home path, LAN address, machine name, e-mail, client name and em dash was reported by every check (file deleted after).
- `omarchy-plugin-validate .`: passes.

## SKIPs
- luacheck, stylua, shellcheck are not installed. They are listed as SKIP in the run output.
- No test suites exist yet (`none yet`).
