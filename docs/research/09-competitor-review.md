# 09 Competitor review: features and Omarchy standards

Reviewed 2026-11-21. Read only: shallow clones (`git clone --depth 1`) and `gh pr diff`, nothing run, sourced, built or installed. Clones are in `/tmp/claude-1000/-home-felipe-Work/6e02d931-9f68-4efc-ab28-f885fbee62d2/scratchpad/review/` (`gio trash` refuses `/tmp`, so they stay there).

Tags: [source] is `file:line` in the project's default branch HEAD (PR cites are line numbers inside the `gh pr diff` output). [docs] is an Omarchy or marketplace document. [meta] is GitHub or registry metadata from `gh` or `registry.json`.

Scope: 17 projects. The 14 in the brief, plus three added on request: monswiklund workspace-presets, CJgarcia1229 monitor-layout, n8group-oss session-memory. Section 6 reconciles with `08-gap-check.md`.

## 1. Omarchy standards checklist

Plugin rules come from the shell manual, the `omarchy-make-plugin` skill and the marketplace. Core rules (`AGENTS.md` style, naming, `test/shell.d`) bind only the three core PRs; for plugins they are n/a.

| Id | Rule | Source |
|---|---|---|
| S1 | `manifest.json` at the repo root, `schemaVersion: 1`, an id outside `omarchy.*`, namespaced and unique | [docs] manual/32-shell-plugins.md:34, :77; SUBMISSION.md:10, :13, :20 |
| S2 | Root README with install AND removal steps, root LICENSE, external deps documented | [docs] SUBMISSION.md:11-12 |
| S3 | Never overwrite user config without explicit consent | [docs] SUBMISSION.md:88 |
| S4 | No sudo/pkexec, installer, package manager, systemd units or bundled binaries; each is a "review capability" the maintainer must accept | [docs] SECURITY.md:63-73; manual/32-shell-plugins.md:44 (plugin add never runs hooks or sudo) |
| S5 | Network only when explicit: fixed HTTPS, timeouts, never run downloaded content | [docs] omarchy-make-plugin/SKILL.md:139; SECURITY.md:53 |
| S6 | React to events, do not poll with a timer; idle widgets start no timers or processes | [docs] AGENTS.md:124; agents/skills/shell-dev.md:43-52; omarchy-make-plugin/SKILL.md:59 |
| S7 | Use Omarchy helpers: `omarchy-notification-send` (never `notify-send`), launch helpers; no presence checks around default commands | [docs] AGENTS.md:107-118 |
| S8 | Follow the theme (`Style`, `Commons.Color`), `Text.PlainText` for untrusted text, ship strings in `i18n/` | [docs] omarchy-make-plugin/SKILL.md:29, :125-128, :170-199 |
| S9 | Drive Hyprland 0.55+ with Lua dispatch (`hl.dsp.*`, `hyprctl eval`); old `keyword`/`dispatch exec` syntax fails silently | [docs] 00-summary.md:31; omasession README.md:29-32 |
| S10 | Ship no default keybindings; bindings follow the hotkey planes and never move existing ones | [docs] AGENTS.md:136 |
| S11 | Tests only where they catch a real regression (parsing, routing, edge cases), in proportion | [docs] AGENTS.md:163-173 |
| S12 | Marketplace "Snapshot verified": listed commit has a passed baseline or a maintainer review, and HEAD still equals that commit; otherwise "Update unverified" or "Unverified" | [docs] VERIFICATION.md:9-22 |
| H1 | House rule, not in Omarchy docs: no synchronous `hyprctl` from Hyprland Lua or QML | our rule (workspace CLAUDE.md omahop row) |
| C1 | Core only: `#!/bin/bash`, `[[ ]]`, two spaces; commands start `omarchy-`; tests in `test/shell.d`; menu rows without aliases | [docs] AGENTS.md:28-35, :39, :131, :175 |

Useful seam seen in passing: `ioiohori/omarchy-app-placement` writes its rules to `~/.local/state/omarchy/toggles/hypr/`, which Omarchy re-requires on reload, so it never edits `hyprland.lua` [source] AppPlacement.qml:23-24.

## 2. Feature matrix

F1 per-app rule with monitor; F2 named scene, one workspace on one monitor; F3 exact floating geometry (best: fractions of usable area); F4 monitor identity that survives port change; F5 open in one step, move open apps, launch only missing; F6 whole-session restore after reboot; F7 place only; F8 no titles or private args stored; F9 CLI plus Omarchy menu, no default keys; F10 safe save; F11 Omarchy 4.5 per-monitor workspaces.

| Project | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 | F9 | F10 | F11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| PR 18858 Scenes (core) | no | yes | yes | no | no | no | no | no | yes | n/a | yes |
| PR 18092 Reopen windows (core) | no | no | no | partial | partial | yes | no | no | yes | partial | no |
| PR 10353 Session restore (core) | no | no | no | no | partial | yes | no | yes | yes | partial | no |
| omasession (brenoperucchi) | no | no | partial | partial | yes | yes | partial | no | partial | yes | partial |
| omarchy-sessions (csnasci) | no | yes | partial | no | partial | no | no | partial | partial | n/a | no |
| omarchy-scenes (saidrmdhani) | no | no | partial | partial | yes | partial | no | no | partial | partial | no |
| omascenes (prudhviy99) | no | no | no | no | no | no | no | n/a | partial | n/a | no |
| app-homes (Adolanium) | partial | no | no | no | no | no | no | n/a | partial | n/a | no |
| app-placement (ioiohori) | partial | no | partial | no | no | no | no | n/a | partial | n/a | no |
| workspace-router (Loedn) | partial | no | no | no | no | no | no | n/a | yes | n/a | no |
| persistent-layouts (matt-shearing) | no | no | no | partial | no | no | no | n/a | partial | n/a | no |
| omarchy_tableau (novuon) | no | no | no | partial | no | partial | no | not checked | partial | n/a | partial |
| hypr-layout (leftydevkit) | no | no | partial | no | partial | partial | no | no | partial | n/a | no |
| workspace-layout-presets (smariconde) | no | yes | yes | no | no | no | no | yes | partial | n/a | no |
| workspace-presets (monswiklund) | no | partial | partial | no | partial | no | no | no | partial | n/a | no |
| monitor-layout (CJgarcia1229) | no | no | no | no | no | no | no | n/a | partial | n/a | no |
| session-memory (n8group-oss) | no | no | partial | partial | partial | partial | no | no | partial | yes | no |

### Evidence notes

PR 18858 (bronsontaylor, +2370): F2 one named scene per workspace, opens a fresh copy on the next empty workspace (so F5 no) [source] pr18858.diff:82. F3 work area with `reserved` subtracted [source] diff:851-857. F4 saves the connector name [source] diff:1466. F8 stores window titles and browser tab URLs and titles [source] diff:1288, :1450. F9 menu row plus `bin/omarchy-saved-workspaces` [source] diff:1, :57. F11 resolves the target in the monitor's block via `omarchy/monitors/workspaces` [source] diff:1682-1683, :1702. Only reviewer so far is the greptile bot (9 bot reviews, no human) [meta].

PR 18092 (stevederico, +563): F6 save on logout or reboot, restore at login [source] pr18092.diff:416, :448. F4 partial: refocuses the saved workspace per monitor name [source] diff:38-43. F5 partial: moves windows by class and title as they appear [source] diff:57-60. F8 no: stores `title` [source] diff:144. F10 partial: saves from `omarchy-system` before windows close [source] diff:416.

PR 10353 (jordanhubbard, +559): F8 yes, "never replay process arguments or window titles" [source] pr10353.diff:163, :415. F3 no: floating geometry not persisted [source] diff:415. F5 partial: a second restore must not duplicate an app [source] diff:485. F10 partial: empty autosaves ignored, saves before logout, reboot, shutdown [source] diff:413. Polls every 30 s [source] diff:372.

omasession: F3 absolute px [source] lib/capture.py:204-205, lib/replay.py:281-290. F4 partial: connector name only [source] lib/capture.py:201. F5 adopts a surviving window of the same class before launching [source] lib/replay.py:422-430. F6 login line in autostart.lua [source] README.md:202-205. F7 partial: browsers reopen their own tabs; an already running browser is left alone [source] README.md:70-78, lib/replay.py:869. F8 no: `title` and `launch_cmd` stored [source] lib/capture.py:198-199. F10 yes: refuses 0-window or incomplete saves [source] lib/session-save.sh:386-391. F11 partial: groups by monitor, raw workspace ids, no block math [source] README.md:102-104.

omarchy-sessions: F2 one workspace per session [source] bin/omarchy-sessions:2-9. F3 absolute px via vendored hypr-layout. F5 partial: only reuses windows already on the target workspace, else first empty workspace [source] vendor/hypr-layout.patch:24-32, bin/omarchy-sessions:349. F8 partial: drops cmd and cwd [source] bin/omarchy-sessions:203-208, but the vendored capture keeps `title[:80]` [source] vendor/hypr-layout:691.

omarchy-scenes: F3 size plus offset from monitor origin [source] bin/scenes:500-512, :790-806. F4 partial: description saved but matched by connector, move skipped if missing [source] bin/scenes:495, :780-806. F5 yes, idempotent restore [source] README.md:23-27, bin/scenes:815. F6 partial: "Previous session" picked by the user [source] README.md:29-31. F8 no: `title` stored [source] bin/scenes:505. F9 CLI [source] bin/scenes:8-16, no menu. F10 partial: refuses an empty desktop only [source] bin/scenes:713.

omascenes (prudhviy99): not a window tool, scenes are settings (DND, night light, power) [source] scenes.json:1-20, README.md:7.

app-homes: F1 partial: per-app workspace and float rule, no monitor field [source] Model.js:477-481, :516-524.

app-placement: F1 partial: float, right quarter, empty workspace rules; sized for the focused monitor only [source] Placement.js:238-242, :271-296.

workspace-router: F1 partial: app to workspace 1-10, silent or follow, no monitor [source] README.md:13-15. F9 Setup menu entry [source] README.md:94.

persistent-layouts: F4 partial: EDID make/model/serial and a fingerprint that ignores the connector [source] bin/persistent-layouts:122-151, :257-262; it profiles monitors, not windows [source] README.md:11.

omarchy_tableau: F4 partial: setup fingerprint from description and size [source] bin/omarchy-tableau:160-167. F6 partial: offers restore, never silent [source] README.md:27-28, :50-51. F11 partial: maps slots 1-10 into the 4.5 block but reads the 4.5 path `monitor-workspaces` [source] bin/omarchy-tableau:53-56, which quattro moved to `monitors/workspaces` [docs] 03-omarchy-seams.md:103.

hypr-layout: F3 absolute px [source] hypr-layout:688-690. F5 partial: reuses open windows unless forced [source] hypr-layout:990. F8 no: title and cmd [source] hypr-layout:686, :691.

workspace-layout-presets: F2 yes, F3 yes: fractions of the usable rectangle, clamped [source] backend/capture.py:166-184. F4 no: connector compare, warns only [source] backend/restore.py:615-627. F5 no: restores only into an empty workspace [source] README.md:8-10, backend/restore.py:704. F8 yes: no titles, URLs, command lines [source] backend/capture.py:3, backend/capture_store.py:4.

workspace-presets (monswiklund): F2 partial: records the current workspace by default, but a preset spans many raw workspace ids [source] scripts/record-preset:4-9, README.md:7-12. F3 partial: absolute px as exec rules [source] Model.js:737-743, scripts/record-preset:443-449. F5 partial: "skip apps already running" skips but never moves [source] Model.js:701-705. F8 no: full command lines and URLs stored [source] README.md:183-185.

monitor-layout (CJgarcia1229): a monitor arrangement editor, not windows [source] README.md:5-8. Writes rules by connector name [source] monitor_layout.py:140, :601. Open PR #1 asks to save by description instead [meta].

session-memory (n8group-oss): tmux sessions plus their terminal window only [source] README.md:3-6. F3 partial: fractions of the full logical monitor (not usable area), terminals only [source] src/desktop.rs:176-189, src/hypr.rs:82-94. F4 partial: description first, then connector, then focused monitor [source] src/desktop.rs:196-209, used on restore [source] src/desktop.rs:1667. F8 no: stores agent conversation titles and the first prompt line by default [source] src/config.rs:105, README.md:126-142. F10 yes: never deletes the newest snapshot that has placement [source] README.md:712-714.

## 3. Standards matrix

pass / fail / review (marketplace capability, needs maintainer acceptance) / n/a.

| Project | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 i18n | S9 | S10 | S11 | S12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PR 18858 | n/a | n/a | pass | pass | pass | pass | pass | pass | pass | pass | pass | n/a |
| PR 18092 | n/a | n/a | n/a | pass | pass | pass | pass | pass | pass | pass | pass | n/a |
| PR 10353 | n/a | n/a | pass | review | pass | fail | pass | n/a | pass | pass | pass | n/a |
| omasession | pass | pass | fail | review | pass | fail | pass | fail | pass | pass | pass | Update unverified |
| omarchy-sessions | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass | fail | Update unverified |
| omarchy-scenes | pass | fail | pass | pass | pass | pass | pass | fail | pass | pass | fail | Update unverified |
| omascenes (prudhviy99) | pass | pass | pass | pass | pass | pass | n/a | fail | n/a | pass | pass | Snapshot verified |
| app-homes | pass | pass | fail | pass | pass | pass | n/a | fail | pass | pass | pass | Snapshot verified |
| app-placement | pass | pass | pass | pass | pass | pass | pass | fail | pass | pass | pass | Snapshot verified |
| workspace-router | pass | pass | pass | review | pass | pass | n/a | fail | pass | pass | pass | Snapshot verified |
| persistent-layouts | pass | pass | pass | pass | pass | pass | n/a | fail | pass | pass | pass | Update unverified |
| omarchy_tableau | pass | pass | pass | review | pass | fail | pass | fail | pass | pass | pass | Update unverified |
| hypr-layout | fail | fail | pass | pass | pass | pass | fail | n/a | pass | pass | pass | not listed |
| workspace-layout-presets | pass | pass | pass | pass | pass | pass | pass | fail | pass | pass | pass | Snapshot verified |
| workspace-presets (monswiklund) | pass | pass | pass | review | pass | pass | pass | fail | pass | pass | pass | Unverified |
| monitor-layout | pass | pass | pass | review | pass | pass | n/a | fail | fail | pass | fail | Snapshot verified |
| session-memory | pass | pass | pass | review | review | fail | n/a | fail | pass | pass | pass | Snapshot verified |

H1 (no sync hyprctl from Lua/QML): no project ships a Hyprland Lua module that shells out. The QML plugins call hyprctl through async `Process` or `execDetached` (for example workspace-presets Panel.qml:441, app-homes HyprlandSync.qml:42-50). Pass or n/a everywhere.

### Standards evidence

- S1: every plugin has a root manifest with a namespaced id [meta] (`jq .id manifest.json`). hypr-layout is a standalone script with no manifest and is not in `registry.json` [meta].
- S2 fail: omarchy-scenes README has install but no removal step (no `plugin remove` anywhere in README.md) [source]. hypr-layout has no removal section [source] README.md.
- S3 fail: omasession writes a login line into `~/.config/hypr/autostart.lua` on every shell start, no prompt [source] README.md:202-205, bin/omasession:81. app-homes inserts a `dofile` loader into `~/.config/hypr/hyprland.lua` on first run, no prompt [source] HyprlandSync.qml:75-85, Service.qml:20, README.md:95. Pass examples: monitor-layout backs up `monitors.lua` and rolls back on error, only on Save [source] README.md:64-68, monitor_layout.py:615-629; workspace-router backs up `hyprland.lua` [source] README.md:20; app-placement uses the state toggles dir [source] AppPlacement.qml:23-24.
- S4 review: registry capabilities [meta]: omasession service-management, privilege, installer; session-memory the same; tableau service-management; monitor-layout privilege, installer; workspace-router privilege; monswiklund privilege. Real root use is only omasession's optional Chrome policy `sudo install` [source] README.md:224. monswiklund, monitor-layout and router are flagged for a negated "no sudo" sentence that the scanner did not see as negated [source] workspace-presets README.md:23-24, monitor-layout README.md:28-29. PR 10353 adds a systemd user unit [source] pr10353.diff:57-63.
- S5 review: session-memory's `install.sh` downloads a release binary with curl and checks a pinned SHA-256 [source] install.sh:31, :54-59.
- S6 fail: omasession saves on a systemd timer [source] README.md:202-203, :280. tableau polls every 5 s with the timer always running [source] SetupsStore.qml:66, :112-117. session-memory bar widget polls [source] BarWidget.qml:609-613, plus a 120 s fallback loop [source] src/config.rs:70. PR 10353 sleeps 30 s in a loop [source] pr10353.diff:372. Pass example: omarchy-scenes debounces on Hyprland events [source] Service.qml:230-245.
- S7 fail: hypr-layout calls `notify-send` directly [source] hypr-layout:611-614. Minor: omarchy-scenes checks `command -v uwsm-app` around a default command [source] bin/scenes:764 (AGENTS.md:118 says not to).
- S8: QML plugins use `Style` and `Commons.Color` [source] (grep, every QML plugin). Only omarchy-sessions ships `i18n/` (2 files) [meta]. monswiklund, workspace-router, persistent-layouts and prudhviy99 use no `Text.PlainText` at all [source] (grep count 0); monswiklund shows command lines and URLs from its JSON file.
- S9 fail: monitor-layout previews with `hyprctl keyword monitor` [source] monitor_layout.py:601-604; its own open PR #3 is "Preview with hyprctl eval on Lua configs" [meta]. Others use `hl.dsp` or `hyprctl eval` (for example omarchy-scenes bin/scenes:793, persistent-layouts bin/persistent-layouts:859).
- S10: no project ships a default binding; all show opt-in examples [source] for example tableau README.md:64-72, omarchy-scenes README.md:42-46.
- S11 fail: omarchy-scenes, omarchy-sessions, monitor-layout have no tests [meta]. monswiklund has tests under `scripts/test-*` (3 files) [meta].
- S12 derived from `registry.json` baseline and review fields against each clone's HEAD [meta]: listed commit equals HEAD for prudhviy99, app-homes, app-placement, router, layout-presets, monitor-layout, session-memory. HEAD moved for omasession (04ca2658 vs 31a1e4a8), omarchy-scenes, omarchy-sessions, tableau, persistent-layouts. monswiklund is review-required with no maintainer review.

## 3b. Integration and principles

P1 extend or replace (does it only add through documented seams, or does it override Omarchy parts, patch core, or edit user config in place); P2 extensibility (can users or other plugins add rules or behaviour without editing its code); P3 code standards per language, against Omarchy's own style (`#!/bin/bash`, `[[ ]]`, two spaces [docs] AGENTS.md:28-35; most sampled `bin/` scripts use `set -euo pipefail` or `set -e` [meta] 18 of 40 sampled carry one; Python is allowed in shell plugins, upstream ships 19 `.py` files such as `shell/plugins/agents/collectors.py` [meta]); P4 performance and resources; P5 isolation of concerns. Ratings: good / mixed / poor. These weigh heavily in section 5.

| Project | P1 extend | P2 extensible | P3 code | P4 perf | P5 isolation | Largest files (lines) |
|---|---|---|---|---|---|---|
| PR 18858 | good | mixed | good | good | mixed | backend.py 1141, Widget.qml 414 |
| PR 18092 | mixed | poor | good | good | good | omarchy-session-save 264 |
| PR 10353 | mixed | poor | good | mixed | good | session.py 213 |
| omasession | poor | good | mixed | poor | mixed | Panel.qml 1820, bin/omasession 1486, lib/replay.py 1309 |
| omarchy-sessions | good | mixed | mixed | good | mixed | vendor/hypr-layout 2490, Panel.qml 621 |
| omarchy-scenes | good | mixed | good | good | mixed | Overlay.qml 1013, bin/scenes 1007 |
| omascenes (prudhviy99) | good | good | mixed | good | mixed | bin/omaplace 1445, Panel.qml 1394 |
| app-homes | poor | good | good | good | good | Panel.qml 845, Model.js 682 |
| app-placement | good | poor | good | good | good | AppPlacement.qml 792, Placement.js 365 |
| workspace-router | mixed | good | mixed | good | good | bin/omarchy-workspace-apps 418 |
| persistent-layouts | good | mixed | mixed | good | mixed | bin/persistent-layouts 1295 |
| omarchy_tableau | mixed | good | mixed | poor | poor | bin/omarchy-tableau 2604, Panel.qml 760 |
| hypr-layout | mixed | mixed | poor | good | poor | hypr-layout 2473 (whole tool) |
| workspace-layout-presets | good | mixed | good | good | good | backend/restore.py 872, Panel.qml 462 |
| workspace-presets (monswiklund) | good | good | mixed | good | mixed | Panel.qml 1427, Model.js 848 |
| monitor-layout | mixed | poor | mixed | good | mixed | monitor_layout.py 731 |
| session-memory | mixed | mixed | mixed | poor | good | src/restore.rs 3591, src/capture.rs 2160 |

Line counts: `wc -l` on tracked non-doc files; for PRs, added lines per file in the diff [meta].

### P1 evidence: every write outside its own folder

- PR 18858: adds a built-in shell plugin, a menu row and a guard reader [source] pr18858.diff:57, :87-98. No existing behaviour replaced. Data in `~/.local/state/omarchy/saved-workspaces/` [source] diff:632.
- PR 18092: patches `bin/omarchy-system` and the default `default/hypr/autostart.lua` [source] pr18092.diff:416, :448. Expected for a core PR, but it changes the shutdown path everyone runs.
- PR 10353: patches the reboot, shutdown and logout commands and adds a systemd user unit [source] pr10353.diff:66-112, :134, :57-63.
- omasession: inserts a line into the user's `~/.config/hypr/autostart.lua` on shell start [source] README.md:202-205, bin/omasession:81; writes systemd user units into `~/.config/systemd/user` [source] bin/omasession:74; rewrites the browser profile's `exit_type` before launch [source] README.md:74-76; documents optional root-owned browser policies under `/etc/...` [source] bin/browser-setup:45-49, README.md:224. Poor: replaces login and save behaviour by editing user and browser files.
- omarchy-sessions: own dirs only [source] bin/omarchy-sessions:29-31; flips `misc:focus_on_activate` at runtime and back [source] bin/omarchy-sessions:123.
- omarchy-scenes: own dirs only [source] bin/scenes:22-23; temporary window rule removed after restore (08 cites bin/scenes:741).
- prudhviy99 omaplace: changes DND, night light and similar on purpose, with a snapshot and rollback [source] README.md:7-12.
- app-homes: inserts a `dofile` loader into the user's `~/.config/hypr/hyprland.lua` without asking [source] HyprlandSync.qml:20, :75-85; also writes `~/.config/hypr/omarchy-app-homes.lua` [source] HyprlandSync.qml:19.
- app-placement: writes only `~/.local/state/omarchy/toggles/hypr/app-placement.lua` [source] AppPlacement.qml:22-24. Omarchy loads every `*.lua` there on reload [source] ~/omarchy default/hypr/toggles.lua (via `require_all.files(toggles_dir, ...)`), default/hypr/require_all.lua:3. Caveat: that folder is Omarchy's own toggle state, not a documented third-party seam.
- workspace-router: rewrites the user's `hyprland.lua` with a temp file and backups [source] bin/omarchy-workspace-apps:9, :189, :239; adds one marked row to the documented menu extension file [source] bin/omarchy-workspace-apps:12 and [docs] ~/omarchy manual/31-dotfiles.md:52.
- persistent-layouts: refreshes `~/.config/hypr/hyprmon.lua` only if it already exists, never `monitors.lua` [source] bin/persistent-layouts:39, :957-978.
- omarchy_tableau: closes every window and stops services it started when switching [source] README.md:42, :47; own config and state [source] bin/omarchy-tableau:49-50.
- hypr-layout: keeps its data in `~/.config/hypr/layout*.json` and `layouts/` [source] hypr-layout:82-84; flips animations and `auto_group` at runtime [source] hypr-layout:295, :309.
- workspace-layout-presets: XDG data and runtime dirs only [source] backend/profile_store.py:47, backend/plan_store.py:54.
- monswiklund: one file of its own, `~/.config/omarchy/workspace-presets.json` [source] Panel.qml:25, README.md:24-27.
- monitor-layout: overwrites the user's `~/.config/hypr/monitors.lua` on Save, with backup and rollback [source] monitor_layout.py:24, :615-629; optional script writes `~/.local/share/applications` and icons [source] install-app.sh:6-24.
- session-memory: own XDG dirs [source] src/paths.rs:11-24; on explicit `osm install` it adds systemd user units and tmux hooks in the user's tmux server [source] README.md:34-39, :363-365, src/install.rs:356-369.

### P2 evidence

- good: omasession settings and a user Lua hook `window_slot_order()` [source] README.md:62, :116-121, :280; app-homes JSON homes and profiles [source] Model.js:559; workspace-router JSON assignments [source] README.md:94; tableau TOML desks [source] bin/omarchy-tableau:49; monswiklund JSON presets plus IPC `launch`/`list` [source] README.md:96-98, :174-185; prudhviy99 user `scenes.json` [source] lib/common.sh:42.
- mixed: omarchy-scenes CLI engine for hooks [source] README.md:74; omarchy-sessions IPC verbs [source] README.md:43-50; PR 18858 CLI and IPC only; layout-presets fixed launcher kinds [source] backend/restore.py:640; session-memory config.toml for agents and terminal [source] README.md:727-736; persistent-layouts and hypr-layout CLIs.
- poor: app-placement three fixed toggles [source] README.md:3-7; PR 10353 and 18092 on/off only; monitor-layout no config.

### P3 evidence

- Shebang `#!/usr/bin/env bash` against Omarchy's `#!/bin/bash` [docs] AGENTS.md:34: omasession bin/omasession:1, workspace-router bin/omarchy-workspace-apps:1, prudhviy99 bin/omaplace:1, monitor-layout install-app.sh:1 [source]. `#!/bin/bash` used by omarchy-scenes bin/scenes:1 and monswiklund scripts/record-preset:1 [source].
- `set -euo pipefail`: router :3, monswiklund record-preset:19, omasession :28, prudhviy99 :5 [source]; omarchy-scenes uses `set -uo pipefail` [source] bin/scenes:20.
- omasession mixes Portuguese and English comments [source] bin/omasession:30, :84, :101-113.
- QML: theme tokens everywhere; missing `Text.PlainText` in monswiklund, router, persistent-layouts, prudhviy99 (section 3, S8).
- Python: layout-presets is typed and split into modules with CI [source] backend/*.py, .github/workflows/tests.yml; tableau and hypr-layout are single 2.5k-line `#!/usr/bin/env python3` scripts [source] bin/omarchy-tableau:1. hypr-layout calls `notify-send` [source] hypr-layout:614. monitor-layout is a separate GTK app outside the shell [source] README.md:21-26.
- Rust (session-memory) is outside Omarchy's stack and needs a downloaded binary or a cargo build [source] README.md:17-29.

### P4 evidence

- Resident work: omasession runs a systemd timer every 30 s by default [source] bin/omasession:183, each tick a bash, Python, jq and hyprctl run [source] lib/session-save.sh:231-232. tableau polls `omarchy-tableau status --json` (Python) every 5 s, 0.7 s while busy, timer always on [source] SetupsStore.qml:66, :68-72, :112-117. session-memory: a Rust daemon with a 120 s fallback loop [source] src/config.rs:70, plus a bar poll every 5 s by default [source] BarWidget.qml:35, :120-124, :609-613. PR 10353: Python service sleeping 30 s in a loop [source] pr10353.diff:372.
- Event driven: omarchy-scenes debounces 20 s on Hyprland window events [source] Service.qml:230-245. persistent-layouts reacts to monitor events with one-shot retries [source] Service.qml:36-59.
- No background cost: rule tools (app-homes, app-placement, router) hand rules to Hyprland once; layout-presets, csnasci, monswiklund, hypr-layout, monitor-layout and PR 18858 run only on user action.
- Runtimes: Python in omasession, csnasci, persistent-layouts, tableau, hypr-layout, layout-presets, monitor-layout (plus GTK), PR 18858, PR 10353; Rust binary in session-memory; the rest are QML, JS and bash.

### P5 evidence

- good: layout-presets splits capture, capture_store, profile_store, plan_store, launchers, restore [source] backend/; session-memory splits capture, db, desktop, restore, hypr [source] src/ (but restore.rs is 3591 lines); app-homes splits Model.js (pure), HyprlandSync.qml, ConfigStore.qml, UI.
- mixed: omasession has a lib split (capture, resolve, replay, layout) but a 1820-line panel and a 1486-line CLI; omarchy-scenes puts capture, store, match, launch and place in one 1007-line `bin/scenes`; PR 18858 puts all logic in one 1141-line `backend.py`.
- poor: tableau and hypr-layout are one 2.5k-line file each doing everything.

## 4. Per project verdicts

Size is lines in every tracked non-doc file, tests and QML included [meta]. Responsiveness from `gh issue list` and `gh pr list` [meta].

**PR 18858 Scenes.** Strengths: core quality (i18n, menu, focused tests, work-area fractions, 4.5 blocks). Gaps: connector-only monitor, stores titles and tab URLs, fresh copy instead of moving open apps. Fit: core conventions. Core repo, opened 2026-11-14, +2370 lines, tests in `test/shell.d`, no human review yet.

**PR 18092 Reopen windows.** Strengths: hooks the real logout path in `omarchy-system`. Gaps: no geometry, stores titles. Fit: core style. Opened 2026-11-07, +563, one test file, community comments only.

**PR 10353 Session restore.** Strengths: strongest privacy rule of all. Gaps: no geometry, polls 30 s. Fit: core style plus a systemd unit. Opened 2026-09-05, +559, acceptance and shell tests, quiet since 2026-09-27.

**omasession.** Strengths: most complete whole-desktop restore, adopts open windows, never-worse saves, many tests. Gaps: connector monitor, absolute px, titles stored, no per-app rules. Fit: edits autostart.lua without asking, systemd timer, Portuguese comments. MIT, 2026-11-03, 14.5k, 24 test files, 8 of 10 outside PRs merged, 3 open issues (Nov 6-10) unanswered.

**omarchy-sessions (csnasci).** Strengths: one workspace per named session, launches by desktop entry through uwsm, i18n. Gaps: absolute px, no monitor identity, vendored patched script. Fit: good. MIT, 2026-11-16, 3.7k (incl. 2.5k vendored), no tests, no issues or PRs.

**omarchy-scenes (saidrmdhani).** Strengths: idempotent restore, event-debounced autosave, Lua dispatch, Omarchy helpers. Gaps: whole desktop only, connector match, titles stored. Fit: no removal docs, no tests. MIT, 2026-10-22, 2.8k, 0 tests, 1 outside PR merged.

**omascenes (prudhviy99).** Settings scenes, not windows; only the name collides. MIT, 2026-08-24, 6.1k, 14 tests, no activity.

**app-homes.** Strengths: live Lua window rules with named handles. Gaps: no monitor, no geometry. Fit: edits hyprland.lua without asking. MIT, 2026-09-04, 2.2k, 1 test file, no activity.

**app-placement.** Strengths: cleanest rule seam (state toggles dir, no user config edit). Gaps: three fixed placements, focused monitor only. Fit: good. MIT, 2026-09-29, 1.3k, 1 test file, no activity.

**workspace-router.** Strengths: Setup menu integration, backups. Gaps: workspace only, no monitor. Fit: good. MIT, 2026-09-23, 0.7k, tests/run plus CI, no activity.

**persistent-layouts.** Strengths: best EDID identity code. Gaps: monitors only, no windows. Fit: good, event driven. MIT, 2026-11-20, 2.2k, 1 test file, no activity.

**omarchy_tableau.** Strengths: 4.5 slot mapping, asks before recovery. Gaps: closes the whole desk to switch, no per-window geometry. Fit: 5 s polling. MIT, 2026-11-20, 5.2k, 9 tests, 34 stars, 3 outside PRs closed unmerged, 1 issue answered and closed.

**hypr-layout.** Strengths: dwindle tree rebuild, live check script. Gaps: not an Omarchy plugin, absolute px, titles stored. Fit: notify-send, no manifest. MIT, 2026-09-14, 2.7k, 1 test, 1 open issue (Nov 14) unanswered.

**workspace-layout-presets.** Strengths: best standards fit and privacy, usable-area fractions, 23 test files, CI. Gaps: empty workspace only, connector only, author states it is deliberately narrow. Fit: best. MIT, 2026-09-15, 7.4k, no issues or PRs.

**workspace-presets (monswiklund).** Strengths: project launcher with Docker and pages, Lua exec rules. Gaps: raw workspace ids, absolute px, full command lines stored. Fit: unverified listing, no PlainText. MIT, 2026-08-17, 3.5k, 3 test scripts, no activity.

**monitor-layout.** Monitor editor, not windows. Fit: old `keyword` preview. MIT, 2026-08-31, 0.8k, no tests, 3 outside PRs open a month with no reply.

**session-memory.** Strengths: the only window placement with description-first monitor match and fractions. Gaps: tmux terminals only. Fit: binary download, systemd units, polling, 39k test lines for 21k source. MIT, 2026-09-20, 63k, 113 test files, no activity; README still says "not yet submitted" though it is listed [source] README.md:8-9.

## 5. Ranking and answer

Ranking as a base for our wish list, with P1 to P5 weighted heavily:

1. workspace-layout-presets: good on P1, P3, P4, P5, best privacy, F2 and F3 done right. But its author defines it as narrow (empty workspace, no session) [source] README.md:8-10, so F5 and F6 fight its intent.
2. omarchy-scenes: extends only, event driven, Omarchy shell style, idempotent restore. But one 1007-line engine, whole-desktop shape, titles stored, no tests, no removal docs.
3. PR 18858: extends core cleanly and may land with F2, F3, F11. Watch it; do not duplicate its scenes UI.
4. omasession: most features and the only active outside contributors, but poor on P1 (edits autostart.lua, browser profiles, systemd units) and P4 (30 s timer). Dropped from 2nd for that.

Last on principles: tableau (closes the desk, 5 s polling, one 2.6k file), session-memory (Rust daemon plus polls), app-homes (edits hyprland.lua unasked).

Best base: **none, build.** No project is a natural home for F1 plus F4: the per-app rule tools (app-homes, app-placement, router) have no monitor and no geometry, and the scene tools have no persistent rules. Borrow ideas, not code: fractions from layout-presets (backend/capture.py:166-184), monitor order from session-memory (src/desktop.rs:196-209) plus EDID fingerprint from persistent-layouts (bin/persistent-layouts:122-151), adopt logic from omarchy-scenes (bin/scenes:815), event debounce from omarchy-scenes (Service.qml:230-245).

### Seams for omaplace (extend only, never replace)

| Need | Seam | Evidence |
|---|---|---|
| Install, enable, remove | A third-party plugin repo, manifest at root, installed by `omarchy plugin add` | [docs] manual/32-shell-plugins.md:34-59 |
| Hyprland rules and placement code | One Lua module inside the plugin folder, loaded by a single `pcall(dofile, ...)` line the user adds by hand, exactly as omagnet and omahop do. Never write `hyprland.lua` ourselves | [source] omahop README (Install), omagnet README (Install) |
| Live rule changes | Named `hl.window_rule` handles retired and replaced in place (app-homes' pattern), driven from our own Lua, not from QML shelling out | [source] app-homes Model.js:529-540 |
| Menu entry | One marked row in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, only when the user asks | [docs] ~/omarchy manual/31-dotfiles.md:52, docs/menu.md:6 |
| Shell UI and IPC | A shell plugin service plus `omarchy-shell` IPC calls | [docs] ~/omarchy docs/omarchy-shell.md:7, :104-134 |
| Launching apps | `uwsm-app` and Omarchy launch helpers, no launchers of our own | [docs] AGENTS.md:107-118; 00-summary.md:34 |
| Notifications | `omarchy-notification-send` | [docs] AGENTS.md:115 |
| Workspace slots on 4.5 | Read the monitor block through `o.workspaces.workspace_id(monitor, slot)` or the live monitor list, not a hard-coded state path | [docs] 03-omarchy-seams.md:103-107 |
| Saves | Event-debounced, never a timer; data only in `~/.config/omaplace/` and `~/.local/state/omaplace/` | [docs] AGENTS.md:124; 00-summary.md:36 |

Avoid: writing `autostart.lua`, `hyprland.lua`, `bindings.lua` or `monitors.lua`; patching `omarchy-system`; systemd units; changing global Hyprland options (`misc:focus_on_activate`, animations) even briefly; the `~/.local/state/omarchy/toggles/hypr/` folder, which Omarchy loads but owns for its own toggles [source] ~/omarchy default/hypr/require_all.lua:3. Login restore, if ever, belongs in a user-added autostart line, same consent model as the Lua line.

Is F1+F3+F4 unfilled? **Yes, and it turns on F1.** F3 plus F4 together exist in one place now: session-memory, but only for tmux terminal windows and with full-monitor fractions. No project has F1 with a monitor choice.

## 6. Reconciliation with 08-gap-check.md

- **Disagree:** 08 says nobody restores windows by a port-proof monitor identity [docs] 08-gap-check.md:30. session-memory does, description first, connector second, focused last [source] src/desktop.rs:196-209, on restore [source] src/desktop.rs:1667. 08 listed it as not audited [docs] 08-gap-check.md:39. Scope is terminal windows only.
- **Add:** 08 says fraction geometry exists only in layout-presets and PR 18858 [docs] 08-gap-check.md:33. session-memory also has it, of the full logical monitor [source] src/desktop.rs:176-189.
- **Disagree:** 08 picks omarchy-scenes as best base [docs] 08-gap-check.md:37. My evidence: no tests, no removal docs (fails SUBMISSION.md:11), stores titles (bin/scenes:505), whole-desktop shape. Adding F1, F4 and fractions would replace most of its core, so I say build.
- **Add:** tableau's 4.5 support reads the old state path [source] bin/omarchy-tableau:53-56, moved on quattro [docs] 03-omarchy-seams.md:103.
- **Sizes differ** from 08 because I count tests and QML: omasession 14.5k vs 12.8k, layout-presets 7.4k vs 7.2k, tableau 5.2k vs 2.6k.
- **Agree** on every other 08 cell I rechecked: omasession capture.py:201 and :204-205, omarchy-scenes bin/scenes:495 and :805-806, layout-presets restore.py:615-627, app-homes Model.js:516-524, persistent-layouts :122-151 and :257-262, PR 10353 diff:415.
- **Confirm** 00-summary "no maintainer reviewed" the core PRs: 18858 has only greptile bot reviews; 18092 has bot reviews and community comments [meta].

## Not checked

Nothing was run. tableau's stored fields (F8) not traced. hypr-layout and PR 18092 read by grep only. Line counts are a rough size measure, not code quality.
