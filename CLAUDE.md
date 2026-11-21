# CLAUDE.md

Private repo. Build phase (design approved 2026-11-21): `docs/design.md` is the source of truth, `docs/goals.md` the expectations.

- Read `docs/design.md` and `docs/engineering-standards.md` before any work. Work packages own only their listed files.
- Window titles, browser tabs and app arguments can hold private text. Never commit or log real ones. Use made-up fixtures.
- Never create virtual monitors on a dev machine. Never run Omarchy's `./test/shell` or `./test/all` on the desktop.
- No live tests or input tests without asking first (design section 10 lists the spikes).
- Never call `hyprctl` synchronously from Lua or QML. Never write outside the seams in design section 3.
- Research that led here: `docs/research/` (00-summary first) and `../docs/research/omarchy-community-demand-2026-11.md`.
