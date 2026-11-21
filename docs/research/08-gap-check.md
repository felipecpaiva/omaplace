# 08 Gap check: is A+B+C unfilled?

Audited 2026-11-21 from source code (shallow clones, read only, nothing run). Cites are file:line in each repo's default branch. PR cites are line numbers inside the `gh pr diff` output.

A = per-window exact floating geometry (ideally monitor-relative fractions). B = monitor identity that survives port change (description or make/model/serial), tied to saved scenes. C = per-app placement rule with a monitor choice, applied on every open. D = named scenes per single workspace. E = whole-desktop restore after reboot.

## Table

| Project | A | B | C | D | E | License / last commit / size | Quality note |
|---|---|---|---|---|---|---|---|
| omasession (brenoperucchi) | yes, absolute px: lib/capture.py:204-205, lib/replay.py:284-293 | partial: saves description (lib/session-save.sh:430), used only to draw a preview (lib/layout.py:81); restore never reads monitor (no hit in lib/replay.py); window monitor is connector name (lib/capture.py:201) | no | no (named sessions are whole desktop, README.md:23) | yes: README.md:7, autostart README.md:205 | MIT / 2026-11-03 / about 12.8k lines | Many tests (test/*.py). Lua dispatch yes (README.md:30, lib/tiled_layout.py:116). Largest, most careful |
| omarchy-sessions (csnasci) | yes, via vendored hypr-layout (bin/omarchy-sessions:263 `save --floating`) | no | no | yes: one workspace per named session (bin/omarchy-sessions:2-9) | no | MIT / 2026-11-16 / 449 lines + vendored 2.5k | No tests. Lua yes (README: needs 0.55+ Lua). Depends on a patched copy of hypr-layout |
| hypr-layout (leftydevkit) | yes, absolute px: hypr-layout:688-690, 1256-1265 | partial: saves name, mode, scale only (hypr-layout:700-702); restore ignores them | no | no (one save file, all workspaces) | yes: autostart recipe README.md:291 | MIT / 2026-09-14 / 2.5k lines, one script | Live end-to-end check (tests/replay-check). Lua yes (README.md:24-29) |
| omarchy-scenes (saidrmdhani) | yes: size plus monitor-origin offset (bin/scenes:798-808) | partial: description saved (bin/scenes:495) but matched by connector name (bin/scenes:783); if the monitor is missing, the move is skipped (bin/scenes:803-806) | partial: temp window_rule while restoring only (bin/scenes:928-937), removed after (bin/scenes:741) | no (whole desktop) | partial: "Previous session" snapshot, picked by the user or a login hook (bin/scenes:17, 525) | MIT / 2026-10-22 / about 1.8k lines | No tests. Lua yes (hl.dsp, hl.window_rule). Idempotent restore |
| omascenes (prudhviy99) | no | no | no | no | no | MIT / 2026-08-24 / 4.5k lines | Not a window tool: scenes are settings (DND, volume, night light), scenes.json:1-20. Tests yes. Name overlaps ours |
| omarchy-app-homes (Adolanium) | no (float and center only, Model.js:518-520) | no | partial: per-app workspace rule on every launch (Model.js:516-538); no monitor field | no | no ("not a session restore", README.md:41) | MIT / 2026-09-04 / 2.1k lines | tests/model.test.js. Lua yes (hl.window_rule). v0.0.1 |
| omarchy-app-placement (ioiohori) | no (fixed right quarter, not saved per window: Placement.js:292-293) | no | partial: float/quarter/empty-WS rules on every open (Placement.js:283-296); monitor is only the focused one (Placement.js:238) | no | no | MIT / 2026-09-29 / 1.3k lines | tests/placement.test.js. Lua yes |
| omarchy-workspace-router (Loedn) | no | no | partial: app to workspace 1-10, silent or follow (bin/omarchy-workspace-apps:144); no monitor | no | no | MIT / 2026-09-23 / 620 lines | tests/run. Lua rules yes (README) |
| omarchy-persistent-layouts (matt-shearing) | no | yes for the key: EDID make/model/serial parse (bin/persistent-layouts:122-151), fingerprint ignoring connector (bin/persistent-layouts:257-262); but it profiles monitor setups, not windows | no | no | no | MIT / 2026-11-20 / 1.4k lines | tests/test_cli.py. Best monitor-identity code found |
| omarchy-workspace-layout-presets (smariconde) | yes, fractions of usable area, clamped: capture.py:166-184, backend/restore.py:563-571 | no: connector name only (backend/restore.py:615-625); mismatch only warns | no | yes: one preset = one workspace (README.md:7-12) | no (no autostart, README.md:22-23) | MIT / 2026-09-15 / 7.2k lines | 19 test files. Lua bridge checked (backend/restore.py:325-339). Best geometry code found |
| omarchy_tableau (Novuon) | no (tiled by dwindle splits, sizes fixed at the end, bin/omarchy-tableau:11-17) | partial: fingerprint of description+size per monitor set (bin/omarchy-tableau:162-166) picks the remembered arrangement; windows tied to connector (bin/omarchy-tableau:492-504) | no | no (whole setups) | partial: offers restore after restart, never silent (README.md:28, 50) | MIT / 2026-11-20 / 2.6k lines | 8 test files. Lua yes (bin/omarchy-tableau:1098). Per-monitor workspace blocks (Omarchy 4.5) |
| omacom/omarchy PR 18858 (bronsontaylor) | yes, scaled to work area: diff 1739-1741 | no: connector name (diff 1466, 1706) | no | yes: named scene per workspace (diff 82) | no | core repo / opened 2026-11-14 / 2370 added lines | Open, has tests (test/shell.d), core Lua. Browser tabs, modes |
| PR 18092 (stevederico) | no: only class, title, workspace (diff 407-410) | partial: active workspace per monitor name (diff 40, 407-410) | no | no | yes: logout/reboot save, login restore (diff 21-23) | open / 2026-11-07 / 563 lines | Fresh shell scripts, Lua dispatch yes |
| PR 10353 (jordanhubbard) | no: "floating geometry ... not persisted" (diff 415) | no | no | no | yes: 30 s watcher plus final snapshot (diff 413) | open / 2026-09-05 / 559 lines | Has focused tests (diff 417) |

## Verdict

**A+B+C together is unfilled.** No project does all three, and B is the weak spot everywhere:

- Nobody restores windows by a monitor identity that survives a port change. Every window tool keys on the connector name (DP-1). The description is saved by omasession (session-save.sh:430) and omarchy-scenes (bin/scenes:495) but never used to match a monitor on restore.
- The only good identity code (EDID make/model/serial, fingerprint) lives in omarchy-persistent-layouts and does not touch windows. omarchy_tableau uses description+size for a setup fingerprint but still ties windows to connectors.
- C with a monitor choice does not exist. Three tools do per-app rules on every open (app-homes, app-placement, workspace-router) but none has a monitor field.
- Proportional floating geometry (A) exists in layout-presets and PR 18858, but only per workspace, not tied to a monitor identity.

**Closest single project: omarchy-scenes.** It has A (absolute offset from monitor origin), whole-desktop capture, a "Previous session" snapshot, and a temp window rule. It lacks: stable monitor match (it matches by connector and skips the move if the monitor is gone), persistent per-app rules (its rule is removed after the restore), per-workspace scenes, tests. omasession is the more complete restorer (E, tests, browsers) but is 12.8k lines and ignores monitors on restore.

**Best base to contribute to:** omarchy-scenes (small, MIT, Lua-ready, idempotent restore, the right shape). Borrow the fingerprint from persistent-layouts (bin/persistent-layouts:122-151, 257-262) and the fraction maths from layout-presets (backend/restore.py:563-571). Add C by reusing the rule generation in app-homes (Model.js:516-538) with a monitor field. Caveat: PR 18858 is heading for core Omarchy and covers A and D, so keep our work to B and C and avoid duplicating its scenes UI.

Not audited (seen in the marketplace tree, may overlap): monswiklund workspace-presets, cjgarcia monitor-layout, n8group session-memory, csfh/omadesk (named desks).

## Name check

Checked the marketplace tree (11,933 paths) and `gh search repos`.

| Name | Marketplace | GitHub | Free? |
|---|---|---|---|
| omastage | no entry | jvlianodorneles/omastage, eddieor/omarchy-omastage | taken |
| omaplace | none | none | free |
| omaroost | none | none | free |
| omahome | fishmacc-omahome | FishMacc/omahome, bishwenduk029/omarchy-omahome | taken |
| omadesk | castarrillo-omadesk | five repos, incl. csfh/omadesk (named-desk overlay) | taken |
| omaspots | none | none | free |

Free: **omaplace, omaroost, omaspots.** (GitHub search matches names and descriptions only; a repo with a spaced or hyphenated variant would not show.)
