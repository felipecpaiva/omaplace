# 03. Omarchy seams: where omaplace can hook in

Research date 2026-11-21. Open question 3 of `docs/research.md`.
Checked on installed Omarchy 4.5 (`/usr/share/omarchy`, version file says `4.0.0.alpha`, package 4.5.x) and `upstream/quattro` at `9f2e2e94a` (fetched today).
Hyprland on this machine is **0.56.2** (`hyprctl version`: tested), not 0.57. Re-check Lua APIs on 0.57 before the design.

Evidence tags: **[tested]** a command was run, **[source]** a file was read (path given), **[docs]** a doc or skill file says it, **[search]** GitHub search or page read through `gh`.
Earlier research reused, not redone: `omagnet/docs/research/omarchy-app-stack.md` (plugin shapes, marketplace rules, Lua loading), `omagnet/docs/upstream-integration-plan.md`, `omahop/docs/decisions.md` (D23: stock dock has no third-party hook).

## Summary

1. **Upstream core is already building this.** Three open PRs add session restore or scenes in core: #18858 "Scenes" (saves apps and arrangement, menu-bar dropdown), #18092 "Reopen windows after logout or reboot", #10353 "opt-in session restore". No maintainer has reviewed any of them. Our value must be the part they skip: exact floating geometry, per-monitor identity, named scenes per workspace and monitor, and one place to manage it [search].
2. **A shell plugin plus a Lua module is the right shape**, same as omagnet and omahop. A plugin can ship a menu row, a bar widget, a service and a panel. Lua (loaded by one consented `require`) owns window events and placement. [source]
3. **There is no official pre-shutdown hook.** Omarchy's power paths run `omarchy-system` (logout, reboot, shutdown), but there is no `pre-shutdown` hook in `omarchy-hook`. Safest design: save continuously (debounced on window events), not "on exit". [source]
4. **The per-monitor workspace model is the biggest moving part.** 4.5 gives each physical monitor a block of 10 workspace ids. The state file already moved paths on `quattro`. A scene must store "monitor identity + slot 1-10", never a raw workspace id. [source]
5. **Autostart seam for restore** is `~/.config/hypr/autostart.lua` (`o.launch_on_start`) or the `post-boot` hook. Both are user-owned and survive updates. [source]

## Seam table

| Seam | File / path | What we can do there | Stability risk |
|---|---|---|---|
| Shell plugin manifest | `~/.config/omarchy/plugins/<id>/manifest.json`, spec in `docs/omarchy-shell.md` | Kinds `bar-widget`, `bar`, `panel`, `overlay`, `menu`, `service`; several per plugin. Panel for the scene manager, service for background save, widget optional | Low. `schemaVersion: 1`, same as omagnet/omahop in use today |
| Shell IPC | `omarchy-shell shell call/toggle/summon <id>` | Open our panel from a menu row or key; call our service from Lua or a script | Low. Documented table of methods |
| Omarchy menu extension | `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Add a "Scenes" top-level menu with `action`, `provider` (JSON rows from a command), `when`. No plugin API needed | Low to medium. User file, documented in its own header, but the user must write it (consent) |
| Lua config order | `~/.config/hypr/hyprland.lua` requires `hypr.monitors, input, bindings, looknfeel, autostart` after defaults | One consented `require("omaplace")` line (omagnet option 2). Rules go in user files, loaded after defaults | Low. User-owned, never rewritten by updates |
| Window rules helper | `o.window(match, rules)` in `default/hypr/helpers.lua`; `hl.window_rule` | "App X opens on workspace N / monitor M" as static rules (goal 1) | Medium. `o.*` is Omarchy-internal; `hl.window_rule` is Hyprland-native and safer |
| Autostart | `~/.config/hypr/autostart.lua`: `o.launch_on_start("cmd")`; `hl.on("hyprland.start", ...)`; hook dir `~/.config/omarchy/hooks/post-boot.d/` | Reopen scenes after login. `post-boot` runs `sleep 2 && omarchy-hook post-boot` | Low |
| Power paths | `omarchy-system logout/reboot/shutdown` (menu rows call it). It runs `omarchy-hyprland-window-close-all --wait` then `uwsm stop` / `systemctl` | Observe only. No hook point (see details) | High if we patch it. Do not patch |
| Per-monitor workspaces | `default/hypr/monitor-workspaces.lua`; state `~/.local/state/omarchy/monitor-workspaces` (4.5), moves to `.../monitors/workspaces` on quattro | Read the identity-to-block map to turn a monitor into workspace ids | **High**. Path and API changed within one cycle; open bugs #16328, #17759; opt-out PRs #17868, #16213 |
| Launch helpers | `omarchy-launch-webapp`, `-tui`, `-terminal`, `-or-focus`, `uwsm-app --` | Relaunch apps the way Omarchy launches them | Low to medium |
| Workspace mode state | `~/.local/state/omarchy/workspace-layouts/<id>.lua` (`o.workspace_mode({workspace="1", mode="floating"})`) | Read which workspace is floating or tiled. Keyed by workspace id, so it breaks on renumber (#16928) | Medium to high |
| Dock | `shell/plugins/dock` (`omarchy.dock`, service kind) | No hook for third parties. Do not target it | High |
| Per-user state | `~/.local/state/omarchy/` is Omarchy's. `~/.config/<tool>/` for ours | Config and named scenes in `~/.config/omaplace/`; transient state in `~/.local/state/omaplace/` | Low |
| Marketplace | `omacom/omarchy-plugin-marketplace` | List the plugin. Static scan of the exact commit | Low, but see rules below |

## Details

### 1. Shell plugin API [source, docs]

- Manifest fields and kinds: `docs/omarchy-shell.md` on quattro (read today). Kinds: `bar-widget`, `bar`, `panel`, `overlay`, `menu`, `service`. A manifest may list several. `keepLoaded: true` keeps a panel/menu/service mounted across hot reload.
- Third-party plugins get **capability-scoped facades**. They can control only their own service and lifecycle. Menu plugins also get an app-library facade. No access to other plugins' services. Fine for us: we do not need them.
- Unsandboxed: same user rights as the shell. We may run `hyprctl`, `bash`, read `/proc`. (omagnet already does.)
- IPC: `omarchy-shell shell toggle <id> <payload>` opens our panel. `call <id> <method> <arg>` calls an already-loaded plugin. Our Lua side can reach the shell with `hl.dsp.global` or `omarchy-shell` (never synchronously from Lua or QML; project rule).
- Hot reload on file save under `~/.config/omarchy/plugins/`; fallback `omarchy-shell shell rescanPlugins`.
- Installed plugin list on this machine (tested, `ls`): omagnet, omahop, omadials, bar-configurator, spaces, mission control, others. So the plugin route is already proven by three of our own.
- **Settings:** the manifest `barWidget.schema` array only covers bar-widget options. For a real settings page we do what omagnet/omahop do: own panel plus own `config.toml` [source: omagnet app-stack doc, section 3].
- **Menu rows from a plugin:** a `menu` kind is a whole separate menu surface, not rows in the main menu. To get a row in the main menu, use the extension file (next item).

### 2. Omarchy menu: can "Scenes" be a menu entry? [source]

Yes, without a plugin API. `~/.config/omarchy/extensions/omarchy-menu.jsonc` exists on this machine with the documented header. It takes dotted ids and fields `icon, label, action, target, provider, aliases, description, when, checked`. A `provider` runs a command that returns JSON rows, so the "Open scene" submenu can list saved scenes live. Example shape (made-up names):

```jsonc
"scenes": {"icon":"󰍹","label":"Scenes","aliases":["scenes"]},
"scenes.save": {"label":"Save this workspace as scene","action":"omaplace save --ask"},
"scenes.open": {"label":"Open scene","provider":"omaplace menu-rows"}
```

Costs and risks:
- We must not overwrite the user's extension file without consent (marketplace checklist). Offer "add to menu" with a diff, like the fenced block idea in omagnet.
- The same file is also what core PR #18858 changes (`default/omarchy/omarchy-menu.jsonc` plus `MenuModel.js`). If core ships a "Scenes" id, our id must differ or we override theirs on purpose.
- `system.logout/reboot/shutdown` rows are plain `omarchy-system ...` actions. We can add a sibling row ("Save scenes and reboot") in the same file without touching Omarchy code.

### 3. Lua config layout and where user rules go [source]

`/usr/share/omarchy/config/hypr/hyprland.lua` (the template copied to `~/.config/hypr/`) does: `bootstrap`, `require("default.hypr.omarchy")`, then user files in order `hypr.monitors, input, bindings, looknfeel, autostart`, then `default.hypr.toggles`, then "any other personal configuration below".
- Window rules: `o.window("class", { workspace = "5" })` is the documented example in that template. It is a thin wrapper over `hl.window_rule`.
- `package.path` includes `~/.config/?.lua`, so `require("omaplace")` finds `~/.config/omaplace.lua` or, with dots, `~/.config/omaplace/init.lua` (omagnet research, section 4).
- Rules in user files load after Omarchy defaults and are never rewritten by updates.
- Hyprland Lua events we can use, all seen in Omarchy's own Lua: `hyprland.start`, `window.open`, `window.destroy`, `window.move_to_workspace`, `workspace.created`, `workspace.active`, `monitor.added`, `monitor.removed`, `config.reloaded` (grep of `default/hypr/*.lua`: tested). No `hyprland.shutdown` event is used anywhere in Omarchy; whether Hyprland has one in Lua is for the Hyprland agent to confirm.

### 4. Autostart and login (restore after reboot) [source]

- `default/hypr/autostart.lua` runs on `hyprland.start`: shell, first-run, powerprofiles, monitor-watch, udiskie, herdr server, and finally `sleep 2 && omarchy-hook post-boot`.
- Three places we can add restore, all user-owned:
  1. `o.launch_on_start("omaplace restore")` in `~/.config/hypr/autostart.lua` (documented in that file's template comment).
  2. A script in `~/.config/omarchy/hooks/post-boot.d/` (`omarchy hook install post-boot <script>`). Runs after the 2 s sleep, so the shell and monitor reconcile have started. This dir already exists here (tested).
  3. A `service` plugin that restores when the shell starts.
- Best choice: the plugin's Lua module registers it on `hyprland.start` itself (no user file edit beyond the one `require`). Timing: `monitor-workspaces.lua` runs `reconcile()` on `hyprland.start` and again on every `monitor.added`/`config.reloaded`. Restoring must wait for monitors to settle, or it will place windows on blocks that then get renumbered.
- Nothing already restores windows. PR #18092 adds `omarchy-session-restore` to `autostart.lua`; if it merges, both would run. We need an off switch or detection.

### 5. Shutdown, logout, reboot: where to save state [source]

`/usr/share/omarchy/bin/omarchy-system`:
- `logout` is `uwsm stop`; `reboot` is `systemctl reboot --no-wall`; `shutdown` is `systemctl poweroff --no-wall`.
- Flow: shows an OSD, clears `re*-required` state, runs `timeout 2s omarchy-hyprland-window-close-all --wait`, then the command. Close-all captures window pids, sends `window.close` to every client, jumps to workspace 1, then waits for the processes (bounded by the 2 s timeout).
- Shutdown also takes a systemd inhibitor (blocks lid and idle). Called from a transient user unit (`systemd-run --user`, 30 s max).
- **There is no `pre-shutdown` or `pre-logout` hook** in `omarchy-hook`. Hook names today: `battery-low, font-set, post-boot, post-update, pre-refresh-pacman, theme-set` (hooks.md, listing: tested).
- Bypass cases: `systemctl reboot` typed in a terminal, power button (logind), lid/battery death, a crash, `omarchy-update-restart`. None of these go through `omarchy-system`.
- Options:
  - A. **Continuous save** (recommended). Listen to `window.open/destroy/move` and the monitor events, write a debounced snapshot (for example 2 s after the last change, atomic write). Then "last session" exists whatever way the machine went down. This is the same approach PR #10353 uses (every 30 s).
  - B. **Wrap the menu actions**: extension rows "Reboot and restore" that call our save first, then `omarchy-system reboot`. Covers only menu use.
  - C. **Patch `omarchy-system`**: what PR #18092 does (`omarchy-session-save` right before close-all, under a 10 s timeout). Only works in core. Not for a plugin. It changes with every release (quattro already adds a `firmware` action).
  - D. A systemd user service with `ExecStop` for the session. Not checked; unclear whether windows still exist at that point.
- Critical detail: close-all closes every window **before** the command runs, so any save must run before `omarchy-system` reaches close-all, or use a snapshot already on disk. Because of this, continuous save (A) must also **freeze** on shutdown, or the snapshot will shrink as windows close. (#10353 does "freeze subsequent saves"; we need the same trigger, for example a marker file set by our menu row, or ignore snapshots where all windows vanish within one second.) Open design question.
- Upstream issue #7085: "Multi-window session not fully restored after reboot , close-all does not wait for apps to exit". Some apps write their own state only on clean exit. Not our job, but it limits what "restore" can promise.

### 6. The 4.5 per-monitor workspace model [source, search]

How it works (`default/hypr/monitor-workspaces.lua`, read in full):
- Each **physical monitor owns a block of 10 workspace ids**: block 0 = ids 1-10, block 1 = 11-20, and so on. `Super+3` goes to slot 3 of the focused monitor's block.
- A monitor's identity is `monitor.description` (make, model, serial), not the connector. Duplicates (no serial) get ` #2`, ` #3` by connector order at first sight. The internal panel (`eDP/LVDS/DSI`) always takes block 0 first.
- Persisted in `~/.local/state/omarchy/monitor-workspaces` (4.5, tab-separated: block, current connector, identity), plus `monitor-workspaces-merged` for guest workspaces. **On quattro both moved** to `~/.local/state/omarchy/monitors/workspaces` and `.../workspaces-merged`, and a sibling `monitors/settings` (mode, scale, position per identity) was added. Quattro also exports `M.identities()` (connector to identity). So the path changes inside one release cycle. Do not hard-code it.
- Public Lua API, `o.workspaces`: `focus(slot, monitor?)`, `move_window(slot, follow)`, `move_to_monitor(dir)`, `workspace_id(monitor, slot)`, `reconcile()`. These are bind-action builders; `hyprctl dispatch 'o.workspaces.focus(3)'` also works (used by `omarchy-hyprland-window-close-all`). We can read the live mapping with `hl.get_monitors()` plus the description, instead of parsing the state file.
- Unplug/replug: workspaces of a gone monitor are renumbered into another monitor's block ("merged"), and are meant to go back under their old number when it returns. Known broken: #16328 (renumber to next free slot after a brief dropout, 5 reactions), #17759 (14, global shortcuts and cloned workspace widgets break, saved workspace layouts not migrated), discussion #17647 (25, asks for an opt-out). Fix PRs in flight: #16349, #17213, #16750 (merged: teardown), #17868 "toggle to bring back global workspaces", #16213 "per-monitor workspace toggle".
- Consequences for scenes:
  - **Store `{monitor identity, slot 1-10}`**, never a global id. Resolve to an id at restore time with the live block, or with `o.workspaces.workspace_id(monitor, slot)`.
  - **Support global mode too.** If #17868 or #16213 merge, a user can turn per-monitor numbering off. Then ids are global and a monitor may show any workspace. Scenes need a "workspace id" mode as a fallback. Detection method: not found yet (a toggle file or flag is expected; check when the PR lands).
  - Floating mode is stored per **workspace id** in `~/.local/state/omarchy/workspace-layouts/<id>.lua`. After a renumber, the saved mode can point at the wrong workspace (reported in #17759, fix PR #16928). A scene should record the mode itself (floating, tiled, scrolling) and re-apply it, as PR #18858 does ("saved tiling, floating or scrolling mode is applied before the apps launch").
  - Identity strings contain make/model/serial. Treat as private-ish (project rule on private text): scenes in git or shared must not carry real ones. Agent 05 covers naming in depth.

### 7. App launch helpers [source]

- `o.launch(cmd)` is `uwsm-app -- cmd`. Everything user-facing goes through it so apps are systemd scopes inside the graphical session.
- `omarchy-launch-webapp <url> [args]`: picks a Chromium-based default browser, runs `--app=<url>` via `omarchy-cmd-browser-handoff` or `uwsm-app`. Web app class is derived from URL (helper `omarchy-webapp-window-class` exists).
- `omarchy-launch-tui [--app-id=ID] cmd args`: `xdg-terminal-exec --app-id=<ID> -e cmd`; default app id `org.omarchy.<cmd>`. A TUI is identifiable by that class.
- `omarchy-launch-terminal [--pid=P] [cmd]`: opens in the working directory of terminal `P` (`omarchy-cmd-terminal-cwd`). For restore we need `--dir` directly: `xdg-terminal-exec --dir=<path>`.
- `omarchy-launch-or-focus <pattern> <cmd>` and `-webapp`, `-tui`: focus an existing window by regex on class or title, else launch. Useful for "do not open a second copy". Matching is by `\bpattern\b` on class or title, so it can hit the wrong window.
- Hyprland Lua: `hl.exec_cmd(cmd, { workspace = "N silent" })` style placement is used by PR #18092. Rule-based placement and the race with slow apps belong to agent 02 (Hyprland mechanics) and agent 04 (app relaunch; `04-app-relaunch.md` already exists in this folder).

### 8. The dock [source, docs]

`omarchy.dock` is a `service` plugin with a `Dock.qml` and `DockModel.js` (pinned apps from `dock.pinned`, windows from `Quickshell.Hyprland` toplevels). It shows on floating workspaces only. It takes no registrations from third parties (omahop D23, `omarchy-app-stack`). Cloning it leaves the app grid empty (#18826). Open PRs touch it heavily (#18852 window instances, #19402, #19403, #19405). **Do not integrate with the dock.** A possible light touch later: a pinned-app `.desktop` that runs `omaplace open <name>`. A `.desktop` in `~/.local/share/applications` is how two existing plugins already get launcher entries (omagnet app-stack doc, 1b).

### 9. Marketplace rules and review [source]

From `omacom/omarchy-plugin-marketplace` (`SUBMISSION.md`, `VERIFICATION.md`, read today):
- One public repo, `manifest.json` at root, root README with install and **removal** steps, root license, unique id outside `omarchy.*` (suggested `io.github.<name>.<plugin>`). Retired ids are never reusable.
- One category (`Desktop` or `System` or `Productivity` fit) and one to three tags from a fixed list: `hyprland, quickshell, workspaces, system, launcher, ...`. Suggested for us: `Desktop`; `hyprland, quickshell, workspaces`.
- Checklist includes "does not overwrite user configuration without explicit consent". So the `require` line, the menu extension file and any autostart edit all need a consent step with a diff and an undo.
- Review is an automated static scan of the exact commit (`passed`, `review-required`, `needs-fixes`) plus maintainer approval. It is "not a security review". The catalog marks a listing "Snapshot verified" only for the scanned commit; any newer upstream commit is "Update unverified" until a verify PR/issue is filed. So every release needs a follow-up verification request (omagnet and omahop already live with this).
- A real example of a scan finding that applies to us: marketplace issue #12786 / #14824 (`eric.session-restore`, `westphae/omarchy-session-restore`) flagged that a restore timeout copied the first 40 characters of **unmatched window titles into a `notify-send` body**, leaking private document and web app titles. The author fixed it. Rule for us: never put titles, URLs or arguments in notifications or logs (matches project CLAUDE.md).
- Unlisted competitor in the same lane already in review: `eric.session-restore` (listed as a verify request, 2026-11), and a closed earlier "Session Restore" submission #12786 [search]. Prior-art agent should examine it.

### 10. Where state should live [source]

- `~/.local/state/omarchy/` is Omarchy's. It holds `monitor-workspaces*`, `workspace-layouts/`, `toggles/`, `windows/about.fit` (tested `ls`). Omarchy migrations can rename or delete files there (it just did for monitors). Read it only through an indirection, never write.
- Config lives in `~/.config/<tool>/` and Omarchy's Lua resolves it via `paths.config_home` (`XDG_CONFIG_HOME` empty means unset). Use the same rule.
- Proposed split, same as omagnet:
  - `~/.config/omaplace/config.toml` (settings) and `~/.config/omaplace/scenes/<name>.toml` or `.json` (named scenes the user may back up or version).
  - `~/.local/state/omaplace/last-session.json` (the continuous snapshot) and a lock/marker for "restore already done this login", so a Hyprland restart does not open everything twice (PR #18092 does the same).
- Atomic writes (temp file then rename), private permissions (`0600`), because scene files can hold URLs, paths and folder names. PR #18858 also writes "atomically with private permissions".
- Format: flat TOML subset for settings (Lua-friendly). For scenes with nested window lists, JSON is easy for QML and bash/jq, but Lua has no JSON parser in Omarchy (omagnet research). Open: one format for both, or QML/bash owns scene files and Lua only gets a line-based export. Decide in design.

### 11. Upstream: what exists today on session restore and scenes [search]

Counts and states measured 2026-11-21 with `gh`. All still open, no maintainer review found on any of them (only a bot and community comments).

| Item | What | State |
|---|---|---|
| Discussion #2123 | Save/restore sessions. 35 up, 5+ comments. Users point to hyprland-session-saver, hypr-layout (stdlib Python IPC client; its author lists four silent failure points, the first being placement), hyprdrover, hyprsession, a forked plugin | Open, no maintainer answer |
| Discussion #472 | Start/restart with save option. 23 up. Includes a fork by pawlobanano with a JSON state file and a "start fresh or restore" window at boot | Open |
| Discussion #15801 | Save layout on shutdown, offer restore at login. 4 up. Proposal: snapshot `~/.local/state/omarchy/session.json` before menu shutdown, "Restore last session" entry, an `omarchy-session save|restore` command | Open |
| Issue #8535 | Window layout snapshots. `omarchy hyprland layout save|restore <name>` suggested, "keyed per monitor setup", "breaks when monitors change" | Open |
| Issue #7085 | After reboot multi-window session not fully restored; close-all does not wait for apps | Open |
| **PR #18858 "Add Scenes for reusable app arrangements"** (bronsontaylor, +2370, 12 files, 2026-11-14, updated 11-19) | A `saved-workspaces` shell plugin with a Python backend and `omarchy-saved-workspaces` CLI. Saves apps plus arrangement for a workspace, named scenes in a menu-bar dropdown (save, rename, update, delete), same scene on several workspaces, opens on the current workspace if empty else the next empty one, applies tiling/floating/scrolling mode first. Captures Chromium and Firefox tab URLs, Spotify playlist, terminal cwd. Tested on **one monitor** only. Not floating-geometry focused, no per-monitor identity | Open, mergeable, no maintainer review |
| **PR #18092 "Reopen windows after logout or reboot"** (stevederico, +563, 11 files, 2026-11-07) | Adds `omarchy-session-save` (called from `omarchy-system` before close-all, 10 s timeout) and `omarchy-session-restore` (from `autostart.lua`). Toggle `omarchy toggle reopen-windows`. Writes `~/.local/state/omarchy/session/windows.json`. Terminal cwd, Claude Code/Grok resume, web apps. Maintainer-side comments: one contributor against (prefers fresh sessions), two for opt-in | Open |
| **PR #10353 "opt-in application session restore"** (jordanhubbard, +559, 2026-09-05) | Watcher saves every 30 s (desktop entry ids, class, workspace number). `System > Session` menu. Conflicts with master | Open, `enhancement` label, CONFLICTING |
| PR #15650 / #15659 "Sense" | Learns scenes by itself from repeated layouts, classes and workspace only (no titles) | Open |
| PR #15954 | Save a workspace layout under a name, open it later (depends on #15951) | Open |
| Marketplace | `eric.session-restore` (westphae), earlier "Session Restore" #12786 closed | Verify request open |

What this means: **the demand is real (about 60 reactions across the four threads) and a maintainer answer has not come in 3 months to 2 years**. Core may adopt one of the three PRs; a plugin should not depend on that, and should avoid fighting it. The sentence in the omagnet plan applies: "if core takes the basics, we become the extras".

Gap check against our four goals:

| Goal | #18858 Scenes | #18092 Reopen | #10353 | omaplace must add |
|---|---|---|---|---|
| 1. Placement rules (app to workspace and monitor) | No | No (only restore) | No | Yes |
| 2. Save apps + exact geometry per workspace per monitor | Partly (arrangement, not shown as pixel geometry; one monitor tested) | Workspace only, no geometry | No geometry | Yes (floating geometry) |
| 3. Named scenes, open in one step | Yes | No | No | Overlap |
| 4. Restore after reboot | No (not its goal) | Yes | Yes | Overlap |

## What this means for omaplace

1. **Shape:** one plugin repo, id `io.github.felipecpaiva.omaplace`, kinds `panel` + `service` (+ optional self-hiding `bar-widget`), a Lua module for events and placement, a small CLI or script set for save/open/menu rows. Same skeleton as omagnet and omahop, so the build, test and release method is already known. [source]
2. **Hook points to use:** (a) consented `require("omaplace")` for Lua; (b) menu extension rows for "Scenes" with a live `provider`; (c) `hyprland.start` or `post-boot.d` for restore; (d) `~/.config/omaplace` and `~/.local/state/omaplace` for data. All are user-owned or documented, and survive updates.
3. **Do not hook:** `omarchy-system` (no hook, changes each release), the dock (no API), Omarchy's `~/.local/state/omarchy/*` files for writing. Read the monitor map through live `hl.get_monitors()` descriptions, not the state file, because its path already moved.
4. **Save model:** continuous debounced snapshot as the base for "restore after reboot", with a freeze trigger during shutdown (close-all empties the desktop before power-off). Named scenes are explicit saves, stored separately.
5. **Scene schema must carry monitor identity plus slot**, the floating/tiled/scrolling mode, and geometry as a fraction of the monitor work area (so a scene survives a different resolution). Never a raw workspace id.
6. **Coexist with core:** detect `omarchy-session-restore`, `omarchy-saved-workspaces`, or a `reopen-windows` toggle at load and turn off our overlapping restore or warn. Keep our scope to what core's PRs do not do: placement rules, exact geometry, per-monitor scenes, one manager.
7. **Consider contributing upstream too.** Same strategy as omagnet D12: before building, comment on #18858 and #2123 with the floating-geometry and per-monitor-identity gap, and offer scope. Core might want the geometry piece as a PR.
8. **Release cost:** each marketplace listing is commit-bound; every release needs a verify request. Plan release batching, as with omahop.

## Open questions left

1. Is there a Hyprland Lua event or hook for compositor shutdown on 0.56 or 0.57? Needed to decide the freeze trigger. (Hyprland-mechanics agent.)
2. Does the user extension menu file support a `provider` that spawns a command fast enough for a live scene list? Read `MenuModel.js` (provider handling near line 658) and test with a harmless row. Not tested here.
3. How will a plugin detect global-workspace mode once #17868 or #16213 land? Flag file, Lua global, or setting is unknown.
4. Where does a restore move windows when a saved monitor is absent (laptop alone after the dock)? Policy needed; interacts with "merged" guest workspaces in the 4.5 reconciler.
5. Timing: how long after `hyprland.start` is it safe to restore (monitor reconcile, shell up, `post-boot` 2 s sleep)? Needs a measured trace on this machine (read-only: a log of events, no input).
6. Menu consent flow: can the plugin edit `omarchy-menu.jsonc` safely (fenced block, diff, undo), or should it only print the lines for the user to paste?
7. Does a `menu` kind plugin give us anything the extension rows do not (own surface, live search of scenes)? Not tested.
8. What does the maintainers' silence on three open PRs mean for adoption? Check again in two weeks; if one merges, redo the gap table.
9. State file format split (TOML for settings, JSON or line format for scenes) to be settled with agent 06 (user flow) and agent 04 (app relaunch fields).
10. What do #18858 and `eric.session-restore` capture and where do they fail? Read their code before design (not run, per rules).
