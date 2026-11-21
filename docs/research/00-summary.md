# Deep dive summary (2026-11-21)

Seven parallel research passes, one per open question in `../research.md`. Each file tags its claims
[tested], [source], [docs] or [search]. Key claims below were rechecked by hand with `gh` (marked rechecked).

## The headline: this space is crowded

- Omarchy core has three open, unreviewed PRs: #18858 "Add Scenes for reusable app arrangements"
  (2026-11-14, +2370 lines), #18092 "Reopen windows after logout or reboot", #10353 opt-in session restore.
  (rechecked) See 03.
- The plugin marketplace already lists many session and scene plugins. Closest: `brenoperucchi/omasession`
  (whole-desktop restore, 7 stars), `csnasci/omarchy-sessions` (bar plugin, same size and position),
  `saidrmdhani/omarchy-scenes`, `prudhviy99/omascenes`. (rechecked) See 01.
- The working name `omascenes` was taken in the marketplace by `prudhviy99/omascenes` (a settings-scenes plugin). **Renamed to `omaplace`** on 2026-11-21 (free on GitHub and in the marketplace, see 08).

## The gap nobody fills (our angle)

1. Placement rules with a monitor choice: "this app always opens on slot 3 of monitor X".
2. Named scenes per workspace and per monitor, with exact floating geometry.
3. Monitor identity that survives unplug, dock, and the Omarchy 4.5 workspace renumbering.

Checked against source code of 17 projects plus core PRs in 08 (gap check) and 09 (review with Omarchy
standards and Felipe's principles), and rechecked by hand:
- 1 is unfilled everywhere. `omarchy-app-placement` always uses the focused monitor (`pickMonitor`); app-homes
  and workspace-router have no monitor field at all. (rechecked)
- 3 exists in one place only: `n8group/omarchy-session-memory` matches by monitor description first
  (`src/desktop.rs:196-209`, rechecked), but only for tmux terminal windows, with a daemon and a 5 s poll.
- 2 with fractions exists in `workspace-layout-presets` and PR #18858, both keyed on the connector name.

Verdict of 09: **no project is a good base; build**, extending Omarchy only through documented seams.
Whole-desktop restore is covered by others (omasession, omarchy-scenes, PR #18092). Whether omaplace still
does it, or leaves it to them, is Felipe's choice at design review.

## Technical findings that shape any design

| Topic | Finding | File |
|---|---|---|
| Window identity | Only `initialClass` is stable across restarts. Pid is shared (browsers, Electron), titles change. Never match on titles | 02, 04 |
| Launch and place | Hyprland exec rules do not reach apps started by `uwsm-app`. Use "spawn, then claim on window.open" with expiring claim tickets and a tag | 02 |
| Timing | Omarchy re-arranges windows about 1 s after a workspace move. Place after about 1.1 s | 02 |
| Hyprland 0.55+ | `hyprctl dispatch` now evaluates Lua; it broke at least six older tools | 01 |
| Monitor key | Reuse Omarchy 4.5's monitor identity (make, model, serial, `#2` for twins) plus a fingerprint fallback. Save (monitor, slot 1-10), never a raw workspace id | 05, 03 |
| Geometry | Fractions of the monitor's usable area, plus last pixel rect as a hint. Same math as omagnet (`geometry.lua`) | 05, 07 |
| Relaunch | By desktop entry id plus a small per-type extra. "Place only" mode for browsers and Electron apps. Reuse `omarchy-launch-*`, write no launchers | 04 |
| Save time | `omarchy-system` closes all windows before power off and has no hook. Continuous debounced snapshots, never overwrite a good save with a worse one | 03, 01 |
| Storage | Named scenes in `~/.config/<name>/scenes.toml` (TOML like omagnet/omahop), autosave in `~/.local/state/<name>/`. No titles, typed-only folders and commands | 06 |
| Surfaces | CLI first; menu via `~/.config/omarchy/extensions/omarchy-menu.jsonc`; no default keys | 06, 03 |
| Our plugins | Separate plugin. Copy omagnet's 4 geometry functions with a parity test. Do not call `_G.omagnet.apply`. Do not use omagnet zones as slots | 07 |

## Decisions for Felipe

Decided 2026-11-21: name `omaplace`. Build vs contribute: 09 recommends build.

Deferred to design review (recommendations from 06 and 07):
- Scene opens on the current workspace and monitor by default (saved home optional).
- Apps already open: move them, launch only what is missing.
- Restore at login: off in v1.
- One `scenes.toml` file.
- Terminal folders and commands: typed only.
- Placement rules everywhere, exact positions on floating workspaces.
- Soft link to omagnet (`fit_shadow`, tag placed windows).
- Private now, written public-safe.

## Not checked anywhere

No live tests (no window moves, no input). One monitor only, Hyprland 0.56.2 (not 0.57). Most other plugins
were read from README only; csnasci's and omasession's code were not read line by line.
