# Prior art: saving and restoring sessions and layouts

Date: 2026-11-21. Goal: find what already exists before designing omaplace (placement rules, per
workspace and monitor scenes, named scenes, session restore on Omarchy, Hyprland 0.56.2 here, Lua config).

Evidence tags on every claim:

- **[docs]** read from a README, docs page or issue text during this research.
- **[source]** read from code in the repo (only a few files per project, named in the text).
- **[search]** search result snippet only.
- **[meta]** GitHub API metadata (license, last push, stars, open issues), read 2026-11-21.
- Nothing here was **[tested]**. No third-party code was installed or run. `hyprctl version` was the only
  live query (Hyprland 0.56.2, matches what the other projects test on).

Earlier research reused, not repeated: snapping tools and Magnet/Moom/FancyZones zones are in
omagnet's `docs/research/existing-solutions.md` (https://github.com/felipecpaiva/omagnet) (sections 1, 3, 4). Alt+Tab and overview plugins are in
omahop's `docs/research/competitors-overviews.md` (https://github.com/felipecpaiva/omahop). This doc adds only session and scene restore.

## Summary

1. **"Nobody offers this" is false.** About 25 session, scene or placement plugins are already in the
   Omarchy marketplace (registry read 2026-11-21, keyword filter on `sources[]`), and several are active
   this month. Whole desktop save and restore is a crowded field.
2. **The closest matches to our idea already exist:** `csnasci/omarchy-sessions` (one workspace saved as a
   named, one-click session), `saidrmdhani/omarchy-scenes` (named scenes, idempotent restore) and
   `brenoperucchi/omasession` (the most careful whole desktop restore). None of them is the full pitch
   (placement rules plus per workspace and monitor named scenes plus exact floating geometry plus session
   restore in one tool), but each is a real starting point.
3. **The hard part is not relaunching apps.** Every tool that broke, broke on Hyprland API drift (the 0.55
   Lua switch killed at least six tools) or on matching windows to slots. Learn their lessons first.
4. **Name collision:** the marketplace already lists `prudhviy99/omascenes`, `saidrmdhani/omarchy-scenes`,
   `kill74/omarchy-scenes` and `gmaxxxie/Scene-Switcher`. We should rename.
5. **Recommended move:** do not build a fourth whole desktop restorer. Build the thin layer nobody has
   (placement rules plus per workspace, per monitor named scenes for floating layouts), reuse proven
   mechanics, and decide early whether to contribute to an existing tool instead.

## Ranked table

Ranked by how much each one matters to omaplace. Last push is the default branch (meta).

| # | Name | Link | License | Last push | Stars / open issues | Verdict |
|---|------|------|---------|-----------|---------------------|---------|
| 1 | omasession | https://github.com/brenoperucchi/omasession | MIT | 2026-11-04 | 7 / 3 | **Learn from** (best engineering; possible base) |
| 2 | omarchy-scenes (saidrmdhani) | https://github.com/saidrmdhani/omarchy-scenes | MIT | 2026-10-22 | 0 / 0 | **Learn from** (closest to named scenes) |
| 3 | omarchy-sessions (csnasci) | https://github.com/csnasci/omarchy-sessions | NOASSERTION (README says MIT) | 2026-11-16 | 1 / 0 | **Learn from** (closest to per workspace scene) |
| 4 | hypr-layout (leftydevkit) | https://github.com/leftydevkit/hypr-layout | MIT | 2026-09-14 | 1 / 1 | **Reuse** (engine) or **Learn from** (its 4 findings) |
| 5 | Tableau (Novuon) | https://github.com/Novuon/omarchy_tableau | MIT | 2026-11-20 | 34 / 0 | **Learn from** (UX, named desks) |
| 6 | omarchy-desktop-restore (dmitry-solomadin) | https://github.com/dmitry-solomadin/omarchy-desktop-restore | MIT | 2026-11-15 | 3 / 0 | **Learn from** (700 ms save cutoff, agent resume) |
| 7 | omarchy-session-restore (westphae, fork of wbarakat) | https://github.com/westphae/omarchy-session-restore | MIT | 2026-11-16 | 3 / 0 | **Learn from** (dock layout switching) |
| 8 | omarchy-session (dataforxyz) | https://github.com/dataforxyz/omarchy-session | GPL-3.0 | 2026-11-15 | 10 / 2 | **Skip** (GPL, restore broken on Lua, issue #24 open) |
| 9 | App Homes, App Placement, Workspace Router | https://github.com/Adolanium/omarchy-app-homes , https://github.com/ioiohori/omarchy-app-placement , https://github.com/Loedn/omarchy-workspace-router | MIT | 2026-09 | 0 to 1 / 0 | **Learn from** (placement rules half) |
| 10 | omarchy-persistent-layouts (matt-shearing) | https://github.com/matt-shearing/omarchy-persistent-layouts | MIT | 2026-11-20 | 0 / 0 | **Learn from** (monitor set identity) |
| 11 | hyprsession (joshurtree) | https://github.com/joshurtree/hyprsession | GPL-3.0 | 2026-01-04 | 100 / 8 | **Skip** (stale, broken on Lua, ask for maintainer open) |
| 12 | HyprSets (agata) | https://github.com/agata/hyprsets | none | 2025-12-19 | 26 / unknown | **Learn from** (hand-made worksets idea) |
| 13 | Other old Hyprland savers (hyprland-session-saver, hyprland-session-restorer, hypr-session, hyprresume) | see details | mixed, some none | 2025 to 2026-03 | 0 to 6 | **Skip** |
| 14 | PowerToys Workspaces (Windows) | https://learn.microsoft.com/en-us/windows/powertoys/workspaces | MIT (PowerToys) | docs 2026-11-17 | n/a | **Learn from** (the UX reference) |
| 15 | i3 `append_layout` | https://i3wm.org/docs/layout-saving.html | BSD | n/a | n/a | **Learn from** (slot matching model) |
| 16 | KDE Plasma and Wayland session restore protocol | https://bugs.kde.org/show_bug.cgi?id=436318 | GPL | n/a | n/a | **Learn from** (what a protocol can and cannot do) |
| 17 | macOS "Reopen windows" and Moom layouts | https://support.apple.com/en-us/102318 | proprietary | n/a | n/a | **Learn from** (the quality bar) |
| 18 | Same-name or nearby plugins that do something else (prudhviy99/omascenes, kill74/omarchy-scenes, gmaxxxie/Scene-Switcher) | see details | MIT | 2026-10 to 2026-11 | 0 to 2 | **Skip** (but avoid the name) |

## 1. Hyprland and Omarchy session tools

### How big is the field [docs]

Registry `omacom/omarchy-plugin-marketplace/registry.json` (not `catalog.json`; `sources[]` has 6825
entries). A keyword filter (session, restore, scene, snapshot, preset, placement, autostart, resume and
similar) on repo names and descriptions gave 58 hits. After dropping unrelated ones (EasyEffects presets,
btrfs snapshots, battery) about 25 are real session, scene or placement tools. Most were added between
2026-08 and 2026-10. Outside the marketplace, `gh search repos` also shows `Anky209e/hyprland-session-saver`,
`HishamLB/hyprland-session-restorer`, `Chris-Alexander-Pop/hyprsession`, `viniciosrab/hypr-session` and
`frank-blueview-ai/Omarchy-Session-Restore` (empty repo, 0 kb) [meta]. The keyword filter can miss tools
with plain names, so the count is a floor, not a total.

Upstream Omarchy has no first party answer [docs]: discussion #2123 (Save/Restore Hyprland sessions) has
no accepted answer, only community links (hyprland-session-saver, HyprSets, hypr-layout, workspace-restorer).
No open upstream PR touches window session restore (PR search "session" returned unrelated items; PR 17435
is a herdr integration). This was a title search only [search].

### 1. omasession (brenoperucchi) [docs, source: `lib/replay.py`, `docs/DESIGN.md`]

- MIT, pushed 2026-11-04, 7 stars, 3 open issues (all "login restore: partial" reports from its own
  Report a problem button, plus one closed bug about quoted launch commands) [meta, docs].
- **Capture:** `hyprctl clients -j` plus a command resolver. The relaunch command comes from the `.desktop`
  index, the systemd scope (Flatpak) and `/proc/<pid>/cmdline` as last resort. Its notes say it resolved 19
  of 19 windows on a real desktop [docs, author's own claim].
- **Relaunch:** `uwsm app -- <cmd>` through `hyprctl repl 'hl.dispatch(hl.dsp.exec_cmd(...))'`. Terminals
  come back in the same folder and tmux session. Browsers are not relaunched with tabs: the plugin resets
  Chromium's `exit_type` flag so the browser restores its own tabs [docs].
- **Matching a new window to a saved slot [source]:** launch one app at a time. Record the set of known
  window addresses, launch, then poll `hyprctl clients -j` for a new address with the same class (15 s
  timeout, 40 s for browsers). Claim it. Try to adopt a surviving window of the same class before launching
  a second one. For browsers it matches by fuzzy title (difflib ratio, exact titles reserved first).
- **Layout:** geometry, floating state, monitor. Rebuilds dwindle splits only when every window of a
  workspace came back. Lua layouts that place by arrival order get a "park on hidden workspace then move in
  saved order" step.
- **Safety:** every save goes to a staging copy, is checked against the screen it came from and only then
  replaces the last one. History is thinned (15 min, 2 h, 1 day, 1 week). Named sessions exist.
- **What breaks:** the open issues are all "partial login restore" reports (16 of 16 placed yet flagged
  partial; 16 of 18). Chrome needs a root-owned policy file to stop first-run pages replacing restore.
  Its design doc says the old tools failed because Hyprland 0.56 Lua rejects `hyprctl dispatch exec ...`
  silently [docs].
- **Verdict: Learn from.** Best engineering in the field (verify by recounting clients, never replace a
  good save with a worse one, resolver, tests with fixtures). It is whole desktop and automatic, not a
  per workspace and monitor scene tool. Check whether it is open to contributions before building a rival.

### 2. omarchy-scenes (saidrmdhani) [docs, source: `bin/scenes`]

- MIT, pushed 2026-10-22, 0 stars. A shell and jq engine (`bin/scenes`, 35 kb) plus a QML picker.
- **User flow matches our goals 3 and 4:** save a scene with a name, restore with Enter, rename, update,
  delete, plus a rolling "Previous session" snapshot restored by one command. Scenes are plain JSON in
  `~/.config/omarchy/scenes/<name>.json`. A `post-boot` hook restores the previous session at login [docs].
- **Capture:** `hyprctl clients -j` and `hyprctl monitors -j` plus `/proc`. Stores geometry relative to the
  monitor, the monitor name and the monitor description; terminals keep folder and foreground program
  (allow list `rerun`); other apps keep a start command [source].
- **Relaunch and matching [source]:** walks workspace by workspace. For each window it installs a one-shot
  `hl.window_rule` (workspace, float, size, position), launches it, waits for it to map, then moves on
  (keeps tiling order). Windows already open are adopted and moved with `hl.dsp.window.move`
  (`find_adoptable`). Restore is idempotent.
- **What breaks:** no issues filed (0 users). Rule based placement is exactly the thing hypr-layout
  documents as failing for apps that hand off to a running instance (see finding 1 under section 1.4).
  Monitor lookup is by connector name; the description is saved but I did not see it used for matching
  [source, partial read].
- **Verdict: Learn from.** Closest to named scenes. Scope is the whole desktop, so a per workspace and
  per monitor scene is a different cut. Name collision with our project name.

### 3. omarchy-sessions (csnasci) [docs, file list read, code not read]

- NOASSERTION in GitHub metadata though the README says MIT (read the LICENSE file before any reuse),
  pushed 2026-11-16, 1 star, Python engine (17 kb) and a QML panel, vendored hypr-layout.
- **This is our goal 2 and 3 almost exactly:** "Save Session stores the apps open on the current
  workspace, with size, position, tiling arrangement and floating windows." Each saved session is a card in
  the bar; click restores. A session opens on the current workspace if empty, else the first empty one.
  Progress ring on the icon; ends green, yellow or red.
- **Capture:** class, position, size, floating, and the `.desktop` entry that launches it (matched by
  `StartupWMClass`, then file name).
- **Relaunch:** only through installed `.desktop` entries (`uwsm-app -- gtk-launch <id>`), so web apps,
  Flatpaks and Electron apps need no special case. Apps without an entry are not relaunched. Wait for the
  window, bring over windows that landed elsewhere, then hypr-layout arranges.
- **Stated limits:** single-window apps already open elsewhere do not open twice (restore reports where it
  is, workspace turns urgent); terminals come back fresh (no folder, no program); app state is the app's job.
- **Verdict: Learn from.** The `.desktop` only relaunch rule is a clean safety line (never runs arbitrary
  commands). Weak on terminals. It does not mention monitors or placement rules.

### 4. hypr-layout (leftydevkit) [docs, issue read]

- MIT, one Python file, standard library only, pushed 2026-09-14, 1 star, 1 open issue (floating windows
  counted as tiles, `splitratio` is a delta on 0.56). csnasci already vendors it and patched exactly that.
- IPC client (command socket plus the `openwindow` event socket). No C++ plugin, no ABI to chase.
- **Four findings worth more than any code** (same text in the Omarchy discussion #2123 comment):
  1. Placing by window rule fails when an app hands its window to an already running instance (the
     process that makes the window never saw the rule). Place **by address** from the `openwindow` event.
  2. Group dispatchers act on the active window. A focus that silently fails makes the next command hit an
     unrelated window. Read `activewindow` back before each group dispatch.
  3. `keyword` is refused under the Lua parser; use `eval hl.config(...)`.
  4. A dwindle tree cannot be set but can be built with `preselect` plus insert in tree order.
- Caveats from the author: tested on Hyprland 0.56.2 with one 4K monitor only; assumes a clean BSP for
  tiled windows.
- **Verdict: Reuse or Learn from.** Our scenes use floating workspaces, so finding 4 (tiling trees) matters
  little. Findings 1 to 3 matter a lot. As a library it is a single file, but multi-monitor was not tested.

### 5. Tableau (Novuon) [docs]

- MIT, pushed 2026-11-20, 34 stars (the most starred Omarchy tool here), 0 issues.
- Captures workspaces, windows, terminals, apps and background services as a named "tableau". Switching
  **closes the current desktop, then opens the chosen one**. Nothing starts at login by itself; it asks
  before recovery. Rename, duplicate, delete, edit config file.
- **Verdict: Learn from.** Shows what users pay attention to: starter presets (Work, Browse), one click,
  no silent restore. The "close everything first" model is not ours (a scene is per workspace). Code not read.

### 6 and 7. desktop-restore (dmitry-solomadin), session-restore (westphae)

- desktop-restore [docs]: automatic checkpoints, `Super+Shift+R` restore, terminals in their folders,
  exact session resume for Claude Code, Codex, OpenCode, herdr. A hard 700 ms limit on the final save so
  shutdown is never held up. Floating geometry, fullscreen, special workspaces. Hooks into the power menu.
- session-restore (westphae) [docs]: fork of `wbarakat/omarchy-session-restore`. Autosave, restore once at
  login, and **dock layout vs laptop layout** (restore the layout that matches the connected screens).
  Needs menu snippets so a final save runs before logout (Omarchy closes windows one by one on the way
  out, so a save in the middle records a half empty desktop; omasession also names this problem).
- **Verdict: Learn from** for the shutdown save problem and agent session resume. Both are whole desktop.

### 8, 11, 13. Older tools that do not work on the Lua config

- `dataforxyz/omarchy-session` (GPL-3.0, 10 stars): rich CLI (profiles, partial restore, dry run plan,
  undo, audit report). Issue #24 (open) says every `hyprctl dispatch ...` call uses removed hyprlang syntax
  and fails on Hyprland 0.55+; the issue lists verified Lua replacements (`hl.dsp.exec_cmd`,
  `hl.dsp.window.move`, `hl.dsp.window.resize`, `hl.dsp.focus`) [docs]. GPL means we cannot copy code.
- `joshurtree/hyprsession` (GPL-3.0, Rust, 100 stars, last push 2026-01-04): saves every 60 s, writes a
  sourceable config, finds the command from `/proc`, then `initial_class`, then `.desktop`; "bridge
  commands" for Flatpak and Snap [docs]. Open issues: not maintained (#20, a fork author asks to take over),
  0.55 Lua incompatibility (#18), random window placement after reboot (#7), tray apps not restored
  (#17), groups (#10). Skip.
- Others [docs, meta]: `Anky209e/hyprland-session-saver` (AGPL-3.0, Python, last push 2026-01-18),
  `HishamLB/hyprland-session-restorer` (no license, 6 kb), `hyprresume` (named by omasession's design doc
  as emitting `exec [workspace ...` and `movetoworkspacesilent`; measured 0 of 6 windows on Lua config
  while reporting `6/6 apps (0 failed)`; its restore-on-start plus autosave can overwrite a good save with an
  empty desktop). The same doc lists hyprflow, hypr-session-restore and hyprdrover as failing for the same
  reason [docs, author's claim, not checked by me].
- **Verdict: Skip.** Licenses (GPL, AGPL, none) and the dead API make them unusable. Their failure modes
  are the useful part (see "What breaks" below).

### 9. Placement rule plugins (the half of our idea that is not session restore) [docs]

- `Adolanium/omarchy-app-homes` (MIT): pin an app to a workspace once (focus a window, press L, class is
  read from Hyprland, so no regex), silent or jump, plus float, opaque, hide from screen share. Profiles
  (whole map duplicated and switched). Uses Hyprland window rules. States it is not a session restore.
- `ioiohori/omarchy-app-placement` (MIT): per app ticks for Floating, 1/4 Right, Empty WS. Ticks become
  window rules, so the compositor places before first show (no flash).
- `Loedn/omarchy-workspace-router` (MIT): app to workspace 1 to 10, silent or switch, generates small Lua
  rules matched by `initial_class`, backs up `hyprland.lua`, assignments in plain JSON.
- Not found in any of them (README level): **monitor choice** per app and rules scoped to a scene.
- **Verdict: Learn from.** Window rules by `initial_class` and "learn the class from the focused window"
  are the right UX. Same limit as above: rules miss apps that hand off to a running instance.

### 10. persistent-layouts (matt-shearing) [docs]

- Saves monitor layouts and restores the match when the same set of screens plugs in. It identifies a
  layout by **the set of connected screens**, not by `DP-3` style names ("connector names renumber"), never
  lets a spare panel stand in for a missing one, flags placeholder EDIDs (serial like `0x01010101`).
- **Verdict: Learn from.** Directly answers our open question 5 (monitor identity). Related: Omarchy
  monitor profile plugins exist (`steveandkureen/omarchy-monitor-profiles`, `hyprmoncfg`, others) but I did
  not read them.

### 12. HyprSets (agata) [docs]

- Rust TUI, no license, 26 stars, last push 2025-12-19. Hand-defined worksets (commands plus an optional
  split layout), launched sequentially or by walking the layout tree, per workset workspace including
  scratchpads. The author uses it to restore scratchpad content and per project editor plus website sets.
- **Verdict: Learn from.** Proves that curated, hand edited sets are wanted next to "snapshot everything".
  An editable scene file is a feature, not a debt.

### 18. Same name, different job [docs]

- `prudhviy99/omascenes` (MIT, 1 star): a scene is a temporary group of desktop settings (silence
  notifications, keep awake, mic) with preview, snapshot and rollback. No windows.
- `kill74/omarchy-scenes` (MIT, 0 stars, pushed 2026-11-21): context rules (focused window, monitor count,
  Wi-Fi, audio sink, power) apply a named profile and restore after. Needs a separate daemon. No windows.
- `gmaxxxie/Scene-Switcher` (MIT, 2 stars): switches which plugins are enabled per scene.
- Not competitors, but "scenes" now means three other things in this marketplace. Rename.

## 2. Reference products outside Hyprland

All of these confirm the same model: **capture, relaunch, wait, move by identity, report each app**.

### PowerToys Workspaces (Windows) [docs, full page read, updated 2026-11-17]

- Capture: you arrange the desktop, press Capture, then edit: name, window sizes, per app CLI arguments,
  remove apps. Launch from the editor, a desktop shortcut, or a CLI (`list`, `launch`, JSON output, exit
  codes, timeout 1 to 600 s; the CLI cannot capture or edit).
- Relaunch: starts apps, then **moves** them. The docs say outright that it cannot tell an app to start at a
  position, so users see windows jump. A progress dialog shows each app (launched, in progress, failed).
- Matching: "Move existing windows" option reuses an already open instance; apps differ (VS Code needs
  `--reuse-window`); single instance apps are repositioned and cannot be opened twice.
- Limits: elevated apps cannot be repositioned (known issue); snapped state is not restored; a recapture
  wipes the CLI arguments; a timed out launch must not be retried because it could open more apps.
- **Lessons:** per app editable arguments, per app status UI, "move existing" switch, honest exit codes,
  and never auto-retry a timed out launch. The visible jump is the same problem we will have.

### i3 `append_layout` [docs]

- Placeholders ("swallows") with criteria on class, instance, role, title, machine (PCRE). A new window that
  matches fills the slot. It does not start apps. Criteria must match one window only or the wrong window is
  swallowed; swallowing beats assignment rules, so a window can land on another workspace.
- **Lesson:** the cleanest slot matching model is "criteria per slot, first match wins, one window only".
  Hyprland has no placeholders, so matching must live in our tool (class plus optional title regex, then
  claim by address).

### KDE Plasma and the Wayland session protocol [search]

- Wayland has no session restore for clients today. A cross-desktop protocol (`xdg-session-management`)
  is merged after about six years; KWin and Qt 6.10 have early support; apps must opt in; it restores
  window positioning, not content; distributions must enable it [search, news and bug tracker snippets].
- **Lesson:** do not wait for a protocol. Hyprland support for it was not checked.

### macOS [docs and search]

- "Reopen windows when logging back in": a checkbox in the logout dialog; forced restarts reuse the last
  choice; apps own their window state (Resume); login items open regardless [docs: Apple support page
  via search; app side details are blog level, [search]].
- Moom and other tools (from the omagnet research) save named window layouts but do not launch apps in
  Spaces [read in omagnet doc; not rechecked].
- **Lesson:** most of the "feels like macOS" quality comes from apps restoring their own content.
  A tool should restore placement and let the app restore content. The final save at logout must run before
  windows close.

## 3. What breaks (patterns across all projects)

1. **API drift.** Hyprland 0.55 turned `hyprctl dispatch <name> <args>` into Lua evaluation, so tools
   that built dispatch strings failed with exit code 7 and sometimes reported success. At least
   hyprresume, hyprsession, dataforxyz/omarchy-session and others hit it [docs]. We must wrap all Hyprland
   calls in one thin module and run a self-test (`hyprctl version` plus a probe) at startup, and verify by
   recounting windows, never by exit code.
2. **Window rules miss hand-off apps** (Firefox style, single instance). Place by address from the
   `openwindow` event.
3. **Silent success.** hyprresume reported 6 of 6 against an empty desktop. Verify.
4. **A bad save overwrites a good one** (empty desktop at login, half closed desktop at logout). Stage,
   validate, then publish; keep a previous copy; freeze autosave while logging out.
5. **Matching** by class alone fails for several windows of one class (browsers, terminals): use order of
   launch plus claim by address, then title similarity as a tiebreak.
6. **Terminals and agents:** folder and foreground program need `/proc`; only re-run a user allow list
   (omasession `terminalPrograms`, saidrmdhani `rerun`) so a restore never repeats a build or a delete.
7. **Browsers** restore their own tabs; first-run pages and Chrome policy can block it (omasession needs a
   root owned policy file for Chrome only).
8. **Monitor identity:** connector names renumber; Omarchy 4.5 per-monitor workspaces also changed
   numbering [from research.md]. persistent-layouts keys by the set of connected panels.
9. **Tool maintenance:** most of these projects have one author, 0 to 10 stars, and a fork graph of
   near copies (omarchy-session-restore has at least two forks in the registry). Expect churn.
10. **Private text:** window titles and folders land in session files (omasession and dataforxyz both warn
    and add a privacy note or exclude list).

## What this means for omaplace

1. **Rename.** Candidates must avoid "scenes", "sessions", "restore", "snapshot" (all taken). Decide with the
   design doc.
2. **Do not claim "nobody offers this".** Fix `docs/research.md` ("Not checked yet" section) and state the
   real gap.
3. **The real gap we can fill** (not seen in any README read):
   - Placement rules with a **monitor** choice, plus per app rules that belong to a scene.
   - **Per workspace and per monitor** scenes with exact floating geometry on 4.5 per-monitor workspaces
     (omasession groups by monitor; csnasci is per workspace; neither is both with named scenes and rules).
   - Tight fit with omagnet (zones: store a scene slot as a zone name or a fraction of the monitor, so a
     scene survives a different resolution) and omahop (switch to a scene's windows).
4. **Decide first: contribute or build.** Options, best first:
   a. Contribute per monitor scenes and placement rules to `csnasci/omarchy-sessions` or
      `brenoperucchi/omasession` (both MIT, both active, both single author). Ask in an issue before coding.
   b. Build a small scene layer on top of `hypr-layout` style mechanics (MIT, stdlib only).
   c. Build from scratch (last resort).
   Both a and b keep us out of the "fourth restore tool" trap.
5. **Copy these mechanics, not code:** launch one app at a time, find the new address by class, claim it,
   place by address (omasession `find_new`, hypr-layout finding 1); adopt a surviving window before
   launching a second (omasession, saidrmdhani); relaunch only through `.desktop` entries and a user allow
   list for terminal programs (csnasci, saidrmdhani); stage, validate, publish, keep previous save
   (omasession); progress and per app status (PowerToys, csnasci); never retry a timed out launch
   (PowerToys); a dry run plan (dataforxyz).
6. **One Hyprland adapter module.** All calls through `hl.dsp.*` via `hyprctl repl/dispatch` and the event
   socket. Pin tests to Hyprland 0.56.2 and the 0.57 we plan for. Never call `hyprctl` synchronously from
   shell Lua or QML (our own rule).
7. **Monitor identity:** save make, model, serial (or the set of connected panels) with the connector as a
   hint. Fall back to "same position in the connected list". Mark placeholder EDIDs. (See research 05.)
8. **Scene file format:** plain JSON, editable, safe for dotfiles, with an explicit schema version.
   Users want hand edited sets (HyprSets, saidrmdhani). Keep titles out by default (privacy).
9. **Session restore stays "open all scenes"** as the original idea says, plus a logout time final save
   with a hard time limit (desktop-restore 700 ms) and freeze of autosave during logout.
10. **Do not copy GPL or AGPL code** (hyprsession, dataforxyz, hyprland-session-saver). csnasci license is
    unclear in metadata: read its LICENSE file before reuse.

## Open questions left

1. Are `csnasci/omarchy-sessions` and `brenoperucchi/omasession` open to changes? Read their code and ask
   in an issue. I read csnasci's README only.
2. Do any of them work on Omarchy 4.5 per-monitor workspaces with two monitors? omasession mentions it;
   no one showed a test. Needs a two monitor test (no virtual monitors on a dev machine; use a real one).
3. How do they behave on Hyprland 0.57? Everything above is on 0.56.2.
4. Does upstream Omarchy plan a core session feature? Only titles were searched. Check maintainers'
   comments on #2123, #472, #15801 and #8535 in full, and the `quattro` branch.
5. Does Hyprland plan `xdg-session-management` support? Not checked.
6. Read the code of Tableau, desktop-restore and westphae. I read READMEs only.
7. Placement rules with monitor choice: confirm a rule can target a monitor on 0.56.2 and that
   `exec_cmd` with workspace options hands off correctly (see research 02, Hyprland mechanics).
8. The marketplace keyword filter is a floor. A second pass with other words (layout, arrange, workset,
   desk, space) is cheap and would find more.

## Not checked

Moom, Stage Manager, GNOME, sway and niri session tools were not researched beyond the omagnet doc.
No tool here was installed or run, so every "works" or "breaks" claim is from the project's own text,
its issues, or code reading.
