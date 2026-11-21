# CLAUDE.md

Private repo. Research phase: docs only, no code until a design doc is written and reviewed.

- The source of truth is `docs/research.md` until `docs/design.md` exists. Update it when a decision changes.
- Window titles, browser tabs and app arguments can hold private text. Never commit or log real ones. Use made-up fixtures.
- Never create virtual monitors on a dev machine. Never run Omarchy's `./test/shell` or `./test/all` on the desktop.
- No live input tests by default. Ask first.
- Never call `hyprctl` synchronously from shell Lua or QML (same rule as omahop).
- Workspace-wide research that led here: `../docs/research/omarchy-community-demand-2026-11.md`.
