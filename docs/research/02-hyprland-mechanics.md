# 02 Hyprland mechanics

Open question 2 of [../research.md](../research.md). Written 2026-11-21 on Hyprland 0.56.2, Omarchy 4.5 (the task
brief said 0.57; the installed version is 0.56.2, and 0.57.2 is already released).

Evidence labels: **[tested]** read-only live check here, **[source]** Hyprland or Omarchy source read,
**[docs]** wiki.hypr.land (raw wiki repo, `main` branch), **[search]** GitHub release notes.
Reused, not repeated: [omagnet hyprland-capabilities](https://github.com/felipecpaiva/omagnet/blob/main/docs/research/hyprland-capabilities.md),
[omagnet gotchas](https://github.com/felipecpaiva/omagnet/blob/main/docs/gotchas.md). Titles and classes below are made up.

## Summary

1. Capture is easy: `hyprctl clients -j` gives class, initialClass, title, pid, at, size, floating, workspace, monitor, tags, xdgTag and a `stableId`. It does NOT give the launch command. [tested]
2. Placement is easy once a window exists: `resize`, then `move`, both with integers (omagnet). The hard part is the first launch.
3. Exec rules (`hl.exec_cmd(cmd, {workspace=..., move=..., size=...})`) match by process id and an env token. Omarchy launches through `uwsm-app`, which hands the command to a daemon, so **exec rules will not match Omarchy-style launches**. [source]
4. The robust match is "new window appears, claim it by class (and a hint)", using `window.open` plus dispatchers, with a per-slot timeout. No field is a perfect key; pid is shared (4 of 8 windows here share one pid). [tested]
5. Biggest risks: apps that open late or change title, the 1 s Omarchy re-arrange after moves, and monitor identity. Never call `hyprctl` synchronously from Lua.

## Feasibility table

| Capability | How | Checked how | Risk |
|---|---|---|---|
| Read all windows | Quickshell `Hyprland.toplevels` + `lastIpcObject` (omahop does this), or `hyprctl clients -j` run async | [tested] fields below; omahop code | Low |
| Read from Lua | `hl.get_windows()` (omahop does) | omahop `lua/omahop.lua:137` | Low, API young |
| Get launch command | `/proc/<pid>/cmdline`, or the app's `.desktop` file by class | [tested] file exists and is readable | Medium: private args, wrappers, browser sub-processes |
| Move a live window to workspace and monitor | `hl.dsp.window.move({workspace=..})`, `({monitor=..})` | omagnet [docs] only | Low |
| Exact rect for a live window | `resize` then `move`, integers, retry size check | omagnet [tested] | Low (1 px, cell grid) |
| Launch onto a workspace with a rect, Hyprland does it | `hl.exec_cmd(cmd, {workspace="3 silent", float=true, move=.., size=..})` | [source] Executor.cpp, WindowRule.cpp | **High with `uwsm-app`**: no match. Fine for direct spawn of a single-process app |
| Launch then claim (our own matching) | Spawn via `uwsm-app`, wait for `window.open`, match, dispatch | [docs] events, [source] | Medium: races, wrong claim |
| Named rule per slot, enabled while a slot waits | `hl.window_rule({name=..., match={class=..}, workspace=.., move=.., size=..})`, `:set_enabled(false)` after match | [docs] | Medium: static effects are fixed at open, rule must exist before the window |
| Event stream | Lua `hl.on(...)` (best) or socket2 | [docs]; socket2 connect [tested], silent while idle | Low |
| Monitor identity | make + model + serial, as Omarchy's `monitor-workspaces` file does | [source] | Medium: serial can be empty (it is here) |
| Workspace identity under 4.5 | block of 10 per monitor identity, ids global (11-20 ...) | [source] monitor-workspaces.lua | Medium |

## (a) What capture gives

Per window from `hyprctl clients -j` [tested, 0.56.2]:

| Field | Meaning | Use for scenes |
|---|---|---|
| `address` | `0x...` pointer. Changes on every open. | Runtime handle only |
| `stableId` | 8 hex chars. Same window keeps it while it lives. A `stableid:` selector exists since 0.56.0 [search]. | Better runtime handle than address. NOT stable across restarts |
| `class`, `initialClass` | App id. Class can change later. All 8 windows here had class equal to initialClass. | Main match key. Prefer `initialClass` |
| `title`, `initialTitle` | 4 of 8 titles here differed from the initial one. | Weak. Hint only. Private |
| `pid` | Process. 4 of 8 windows here shared one pid (a browser). | Never an identity |
| `at`, `size` | Global layout pixels, logical. | The saved rectangle (convert to monitor-local) |
| `floating`, `fullscreen` (0/1/2/3), `pinned`, `pinFullscreened` | State | Save floating and fullscreen; restore after placement |
| `workspace` {id,name} | Special workspaces have negative ids (`-98`) | Skip specials by default |
| `monitor` | Numeric id. Reused by Hyprland for whichever display comes next. | Map to a monitor identity at save time |
| `grouped` | Addresses of the group | Groups are out of scope for v1 |
| `tags` | Includes rule tags with `*` (for example `terminal*`) and Omarchy's `omarchy-floating-workspace` | Floating guard (omagnet) |
| `xdgTag`, `xdgDescription` | App-set hint. Empty on all windows here. | Rare helper for apps that set it |
| `xwayland` | X11 or Wayland | Capture, since X11 windows have odd class and size behaviour |
| `swallowing`, `focusHistoryID`, `contentType`... | Runtime | Ignore |

`hyprctl monitors -j`: `name` (connector), `description`, `make`, `model`, `serial` (empty here), `x`, `y`, `width`, `height`,
`scale` (1.6 here), `transform`, `reserved`, `activeWorkspace`. `hyprctl workspaces -j`: `id`, `name`, `monitor`, `monitorID`,
`windows`, `tiledLayout`. [tested] The `monitors all` list showed only the internal panel, so multi-monitor is [source] only.

What is NOT available: the launch command and arguments, the working directory of a terminal, the app's own document or
tab state. Those come from `/proc/<pid>/{cmdline,cwd}` (question 4, another agent), and they are private data.

Scale note: this machine is scale 1.6 now (omagnet saw 2). Window `size` and `at` are logical, so a scene saved at one scale
reopens correctly at another only if stored as a fraction of the monitor's usable area (see "What this means").

## (b) Launching onto a workspace and position

1. **Exec with rules** [docs, source]. Lua: `hl.exec_cmd("kitty", { workspace = "13 silent", float = true, move = {x, y}, size = {w, h} })`.
   Shell form: `[workspace 3 silent; float; move 100 100; size 800 600] cmd`. Effects `workspace`, `monitor`, `float`, `move`,
   `size`, `center`, `no_initial_focus` are static (applied once at open). `move` is **monitor-local** [docs], matching omagnet's finding.
   Tables or strings both work; strings split at the first space, `"800x600"` is a config error [docs].
2. **How the match works** [source, `Executor.cpp`, `WindowRule.cpp`]. Hyprland forks the process and sets env
   `HL_EXEC_RULE_TOKEN`. A new window matches the rule if its process environment holds that token, or, when there is
   no token, if its pid equals the spawned pid. The wiki says a forking launcher does not work; the source suggests env
   inheritance can rescue it. Only a test settles this.
3. **Why it fails for Omarchy launchers** [source]. `o.launch(cmd)` returns `uwsm-app -- cmd`, and `omarchy-launch-terminal`
   uses `uwsm-app` too. `/usr/bin/uwsm-app` only writes its arguments into a pipe (`uwsm-app-daemon-in`); a systemd service
   starts the app. The token and the pid are lost. Direct spawn (no `uwsm-app`) matches, but then the app is a child of
   Hyprland and not in its own systemd scope, which is why Omarchy wraps launches. A scene restorer should not change that.
4. **Window rules in the Lua config** [docs]. `hl.window_rule({ name, match = {class, initial_class, title, initial_title, xdg_tag, workspace, tag, float...}, workspace, monitor, float, move, size, center })`.
   Last matching rule wins. Named rules return a handle with `set_enabled`. This is the right tool for **permanent placement
   rules** (feature 1: "this app opens on workspace 3"): a stable class match, no race. Omarchy's own open rule
   (`workspace-modes.lua`, rule names `OPEN_RULE..i`, size `min(1100,monitor_w*0.64)`) floats and sizes every window on a floating workspace, so our rule must
   come after it (last wins) [source]. Whether an exec rule beats a config rule was not tested.
5. **Dispatchers after open** [omagnet tested]: `workspace` move, `monitor` move, `resize` then `move`, `float`,
   `fullscreen`. Moving to another workspace triggers Omarchy's 1 s re-arrange (`window.move_to_workspace`, `workspace-modes.lua:524-529`),
   which can re-float or re-place the window. Apply the rect after about 1.1 s, or prefer a rule so no move is needed.
6. **`persistent_size` rule** [docs]: remembers a floating window's size per class and title. Size only, not position; a possible helper, not a base.
7. **Special case, Hyprland itself**: Omarchy sets `misc.initial_workspace_tracking = 0` [source, looknfeel.lua:114], so
   "open on the workspace the launcher ran on" is off. Rules must name the workspace explicitly (Omarchy's qconsole does the same).

## (c) Matching a new window to a saved slot

A slot stores: `initialClass`, an optional title pattern, an optional pid-free hint, and a rect.

| Key | Stable across restarts? | Verdict |
|---|---|---|
| `initialClass` | Yes for most apps. Flatpak and web apps have their own ids (for example a Chromium `--app` window has a class derived from its URL; made-up: `chrome-example.com__-Default`). | Primary key |
| `class` | Can change after open | Use only as fallback |
| `initialTitle` | Often a placeholder, sometimes the document name | Hint, regex, user-editable, never required |
| `title` | Changes all the time | Do not store (also private) |
| `xdgTag` | If the app sets it | Optional extra key |
| `pid`, `address`, `stableId`, monitor id | No | Runtime only |
| spawn token / pid | Only for direct spawn | Do not depend on it |

Algorithm that survives the above:

1. Group saved slots by `initialClass`. Keep the order slots were saved in (by `focusHistoryID`, or left to right).
2. On launch, for each slot make one "claim ticket": class, optional title regex, expiry (say 20 s), and the target rect.
3. On `window.open` (rules are applied by then), find the first unexpired ticket whose class matches. If the title hint
   exists and the title is not yet set, keep the ticket and look again on `window.title` for a short time.
4. Place by dispatchers (resize, then move after the 1 s settle) and mark the window with a tag `omaplace-slot=<id>` so it is
   never claimed twice and survives a Lua reload (omagnet used a tag the same way).
5. Many windows of one app (browser, editor): N slots with the same class produce N tickets. The first N windows
   of that class take them in order. Tell the user that order, not content, decides. Browsers restore their own windows,
   so for browsers the safe default is "claim existing windows, do not launch more" (question 4).
6. Single-instance apps (a second `exec` just raises the first window): the ticket expires with no window. Report "not reopened",
   do not retry forever. Windows that were already open before the scene opened can be claimed by class in a "move existing" mode.
7. Late windows: the expiry must be per app and user-tunable, with a short default and a "still waiting" state. Never block.

## (d) Events

Lua events (`hl.on`) [docs, list verified against the wiki `events.md`]: `window.open_early` (before rules), `window.open`
(after rules), `window.close`, `window.destroy`, `window.title`, `window.class`, `window.update_rules`, `window.move_to_workspace`,
`window.fullscreen`, `window.pin`, `window.active`, `window.update_state` (flags such as floating or pinned, new in 0.57 [search]),
`monitor.added`, `monitor.removed`, `monitor.layout_changed`, `monitor.focused`, `workspace.created`, `workspace.removed`,
`workspace.move_to_monitor`, `config.reloaded`, `config.unload`, `hyprland.start`. There is **no** window move or resize
event (omagnet [tested] with socket2 too).

Socket2 [docs, `ipc/_index.md`], lines `name>>data`, comma separated:

| Event | Payload |
|---|---|
| `openwindow` | `ADDRESS,WORKSPACENAME,CLASS,TITLE` (the docs table says workspace address; the wiki text calls it the workspace; check live before parsing) |
| `closewindow` | `ADDRESS` |
| `movewindowv2` | `ADDRESS,WORKSPACEID,WORKSPACENAME` (v1 `movewindow` is a workspace move, not a drag) |
| `windowtitlev2` | `ADDRESS,TITLE` |
| `monitoraddedv2`, `monitorremovedv2` | `ID,NAME,DESCRIPTION` |
| `createworkspacev2`, `destroyworkspacev2`, `moveworkspacev2` | `ID,NAME[,MONITOR]` |
| `changefloatingmode` | `ADDRESS,0/1` (back in 0.56 [search]) |
| `configreloaded` | empty |

Titles can contain commas, so split with a limit. The `openwindow` event fires before the title is final and carries
the title (private text in logs: never log it). Socket2 connected here and stayed silent for 3 s while idle [tested];
I did not trigger events. Use Lua `hl.on` for placement (in-process, rules already applied) and the Quickshell
`Hyprland.rawEvent` or socket2 only for a UI that must follow state. Hot-plug: Omarchy reconciles monitors itself
(monitor-workspaces.lua); a scene engine should listen to `monitor.layout_changed`, wait for it to settle, then re-place.

## (e) Races

| Race | What happens | Handling |
|---|---|---|
| Rule matched before title is set | Static rules see `initialTitle` only [docs]. Title rules fire on the first title, which may be a placeholder. | Match by class; treat title as hint |
| Late window | App takes seconds. | Ticket with expiry, per-app timeout, visible "waiting" state |
| Move straight after open | Omarchy re-arranges 1 s after `move_to_workspace` and `fullscreen` | Wait 1.1 s, then resize, then move, then verify size and retry (omagnet gotcha 31) |
| Resize is centre-anchored | Move before resize lands wrong | Always resize first |
| Fullscreen or maximized window refuses a move | Move ignored | Unset first, wait about 60 ms (omagnet gotcha 15) |
| Two tickets, one class, windows open out of order | Wrong window in wrong slot | Accept; same class and size are interchangeable in most cases |
| Launcher global lock | `uwsm-app` serialises on a lock | Launch one per tick, do not flood |
| Sync `hyprctl` from Lua | Freezes desktop about 5 s (omahop gotcha) | Use `hl.get_*` in Lua; run `hyprctl` only from a detached process or QML `Process` |
| Lua reload during restore | Lua state is gone (`config.unload`) | Keep tickets in a state file plus slot tags; never hold only in a table |
| Monitor appears after login | The scene's monitor is not there yet | Wait for `monitor.added`, then continue; fall back to the primary monitor after a timeout |
| Omarchy theme picker opens when the shell reloads | Steals focus (omagnet gotcha 37) | Close with Escape, never in a restore run |

## (f) What changed in Hyprland 0.5x and the Omarchy Lua config

From GitHub release notes [search] and the wiki [docs]:

- 0.55 (2026-05): Lua config already present (vec2 tables and clear-tag API added; exact first release not checked), `auto_consuming` bind flag, vec2 rule tables, clear-tag API.
- 0.56 (2026-07): `stableid:` selector, `is_key_down`, `change_id` workspace call, `monitor` rule effect gets `silent`, socket2
  `changefloatingmode` and `togglegroup` back, monitor `physicalWidth`/`reserved` in Lua, `hyprctl reload` variants.
- 0.57 (2026-10): `config.unload` event, `reload_config()`, `window.update_state`, `window.minimize`, `hl.get_devices()`,
  `workspace.created` split into `created_early` and `created`. Omarchy on 0.57 would hit the last rename: its `qconsole.lua` listens to `workspace.created`. Re-test this pair after upgrade.
- Timer handle: the `main` wiki shows `hl.timer` returning an object with `set_enabled`; omagnet found no handle on 0.56.2. Treat as version-dependent; chain one-shots as omagnet does.
- Omarchy 4.5: per-monitor blocks of ten workspaces keyed by make, model and serial, state in `~/.local/state/omarchy/monitor-workspaces` and `monitor-workspaces-merged`; mode per workspace in `~/.local/state/omarchy/workspace-layouts/<id>.lua`; open rule for floating workspaces; launches go through `uwsm-app`.
- Window rule `move` and `size` accept expressions (`monitor_w*0.5`) only in rules, not in dispatchers (omagnet tested).

## What this means for omaplace

1. **Do not build on exec rules.** They do not survive `uwsm-app`. Build on "spawn, then claim on `window.open`", with slot tickets and tags. Optionally add an exec-rule fast path only for apps launched directly, after a live test.
2. **Permanent placement rules (feature 1) are a Lua `hl.window_rule` per class**, generated from a user file, with `workspace`, `monitor`, and optional `move`/`size`. Keep them named so they can be turned off. They must load after Omarchy's open rule.
3. **Store rectangles as fractions of the monitor's usable area** (width/height minus `reserved`, logical, scale-independent), with the monitor identity (make, model, serial, description; connector only as a last resort) and the workspace as a slot number in that monitor's block (1 to 10), not the global id. This is the 4.5 rename-proof form. Convert at restore using the live monitor, as omagnet's geometry does.
4. **Save exactly:** initialClass, optional title regex (user-written, never auto-saved), floating, fullscreen, rect fraction, slot order, xdgTag if set. **Do not save** titles, addresses, pids, stableIds, or raw command lines in the scene file.
5. **Reuse omagnet:** geometry (resize then move, integer rounding, retry), the tag-as-state trick, and the floating guard. **Reuse omahop:** async window reading. Restore runs in Lua (events, dispatchers); the UI and the file work live in a Quickshell plugin.
6. **Timing budget:** 1.1 s settle after any workspace move; claim expiry per app; one launch per tick.

## Open questions left

1. Does `HL_EXEC_RULE_TOKEN` survive `uwsm-app` or a forking app? (Source says no for `uwsm-app`.) Needs one harmless live test; ask first.
2. Does an exec rule beat a config `hl.window_rule` (and Omarchy's open rule) when both match? Source order not read.
3. Exact `openwindow` payload (workspace id vs name) on 0.56.2: read it live from a harmless window open, with the user's consent.
4. Does `hl.dsp.window.move({monitor=...})` keep the relative rect between monitors of different scale? omagnet only had one monitor.
5. Can a rule put a window on a workspace that belongs to a currently unplugged monitor, and what does Hyprland do with it? Needs a second monitor or a headless test (not allowed on a dev machine).
6. Does `window.open` fire for a window of a single-instance app that only raises an old window? Probably not; confirm.
7. Which `/proc` data (cwd, args) the capture step may keep, and how to scrub it (question 4 and 6).
8. Do the 0.57 renames (`workspace.created`) already affect Omarchy's shipped Lua? Check when Omarchy moves to 0.57.
