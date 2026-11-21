# omaplace engineering standards

These rules apply to every work package and every agent brief. Briefs must quote this file. A package is not done until
it meets all of them. Base: omahop's standards, plus Felipe's principles for Omarchy work.

## Principles

1. **Extend, never replace.** Use only the seams in `design.md` section 3. Never write under `/usr/share/omarchy`,
   `~/.config/hypr/`, `~/.local/state/omarchy/`, systemd units or global Hyprland options. The one consented exception is
   the menu row (WP8), with a backup.
2. **Minimum resources.** Event driven. No polling loops, no periodic timers, no resident process of our own, no runtime
   beyond Lua (in Hyprland), QML and JS (in the shell) and bash (CLI). One-shot debounce timers are allowed.
3. **Isolation of concerns.** One job per module (`design.md` 4.3). Pure modules never call `hl`, never read files,
   never read the clock (time is passed in). Only `lua/omaplace.lua` calls `hl`; only `Service.qml` calls `Process`.
   Each file on disk has one writer (`design.md` 4.1).
4. **Flexibility.** Behaviour is a setting with a safe default in one defaults table. Strategies are data, not code.
   Unknown config keys are kept; bad values fall back and are reported.
5. **Scalability.** Smooth with 100+ windows and several monitors. Work per event is bounded. Lists in the UI are
   `ListView`, not a `Repeater` of everything.
6. **Privacy.** Never store or log titles or URLs. Terminal folders and programs are captured only through `procinfo.sh` and `ArgFilter.js` (design D12). Logs print classes and
   scene names only. Fixtures are made up.

## Code standards per language

| Language | Standard | Check |
|---|---|---|
| Lua (Hyprland 5.5) | Everything `local`, one module table per file, no globals except `_G.omaplace`. Pure functions for logic. snake_case, 2-space indent, early returns. Errors returned as `nil, err` or logged, never swallowed. Loop variables are read-only in 5.5. Every `hl.on` handler wrapped in `pcall`. Never `io.popen` or `os.execute` of `hyprctl` | `lua lua/tests/test_*.lua`; `luacheck` and `stylua --check` when installed |
| QML (Quickshell) | One component per file, PascalCase files, camelCase ids. No logic in delegates (call the JS modules). Colours and sizes from the shell theme. `Process` with an argv array, never a shell string | `qmllint`, `qmlformat` (`/usr/lib/qt6/bin`) |
| JavaScript (`.js` for QML) | `.pragma library`, pure functions, `const` first, no side effects at import, so Node can test them | `node --test tests/` |
| Bash (`bin/omaplace`, tests) | `#!/usr/bin/env bash`, `set -euo pipefail`, quote everything, no logic beyond argument mapping | `shellcheck` when installed |
| Markdown | Plain words, commas and hyphens, never em or en dashes, no private data | `tests/scrub.sh` |

A missing linter prints `SKIP <tool> not installed` in `tests/run-all.sh` and is listed in `docs/batch-log/WP<n>.md`. A skip is
visible debt, never a silent pass.

## Testing layers

1. **Pure** Lua and JS modules: unit tests with made-up fixtures, including bad input.
2. **Glue** with a fake `hl` and a fake `o.workspaces` (`lua/tests/fake_hl.lua`): events, rules, runs, expiry, reload.
3. **Cross-checks**: config parsing in Lua and JS on the same fixtures; geometry against golden vectors generated from omagnet.
4. **Live** only with Felipe's OK, one harmless window, no synthetic input, never a virtual monitor, never Omarchy's
   `./test/shell` or `./test/all`.

## Definition of done for a work package

1. Only the files the package owns, or is the named next editor of, were changed (`design.md` section 11).
2. Pure logic has unit tests; glue has fake-`hl` tests; user-visible parts have a line in `docs/checklist/WP<n>.md`.
3. Linters pass or are logged as SKIP.
4. `bash tests/run-all.sh` and `bash tests/scrub.sh` pass.
5. No new timer, process or file writer outside what `design.md` lists.
6. The package is written in `docs/batch-log/WP<n>.md`: what changed, what was verified and how.
