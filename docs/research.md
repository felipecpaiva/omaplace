# omascenes research

Started 2026-11-21. Wider survey this came from: workspace `docs/research/omarchy-community-demand-2026-11.md`.

## The idea

One machine has many virtual desktops (Hyprland workspaces) and often more than one monitor. We want:

1. **Placement rules.** Say which desktop and which monitor an app opens on.
2. **Scenes.** Save the apps plus their window positions and sizes for one desktop on one monitor.
3. **Named scenes.** Keep scenes for the desktops we use often ("work", "music", "review"). Open one in one step.
4. **Session restore.** After a reboot, bring back every desktop. This is "open all scenes", so it is the same feature.

Our desktops use floating workspaces, so exact window positions matter (omagnet already snaps and places
floating windows; omahop switches between them).

## Community demand (omacom/omarchy, measured 2026-11-21)

| Link | Votes | Ask |
|---|---|---|
| Discussion #2123 | 35 up, 5 comments | Save/restore Hyprland sessions |
| Discussion #472 | 23 up, 5 comments | Start/restart with a save option for opened apps |
| Discussion #15801 | 4 up | Save the workspace layout on shutdown, offer to restore at login |
| Issue #8535 | 6 reactions | Window layout snapshots (save and restore workspace arrangements) |
| Discussion #10064 | 3 up | Per-workspace backgrounds (nearby: per-desktop identity) |
| Discussion #17647, issue #17759, issue #16328 | 25, 14, 5 | 4.5 per-monitor workspaces broke numbering and renumber after a monitor dropout. Scenes must survive this |

Measured with: GraphQL search `repo:omacom/omarchy sort:top` (top 1000 discussions) and
`gh issue list -R omacom/omarchy --search "sort:reactions-+1-desc"`. Titles and vote counts only, not every comment.

## Known risks (from the survey, not yet checked)

- Some apps do not reopen the same way: single-instance apps, apps that restore their own windows
  (browsers, editors), terminals that need a working folder or a command, web apps (Chromium `--app`).
- Window class or title may not be enough to match a new window to a saved slot.
- Monitors change (dock, undock, monitor dropout). Per-monitor workspace numbers changed in Omarchy 4.5.
- Windows appear late (slow apps), so placing them is a race.
- Private text: window titles and app arguments can hold private data.

## Correction: others already offer this

"Nobody offers this" was wrong. Three core PRs (#18858, #18092, #10353) and many marketplace plugins
(omasession, omarchy-sessions, omarchy-scenes, and one already named `omascenes`) exist. Our angle is the
gap they leave. See [research/00-summary.md](research/00-summary.md).

## Open questions for the deep dive

1. Prior art: existing Hyprland session and layout tools, plus Omarchy plugins in the marketplace. What works, what breaks.
2. Hyprland mechanics: window rules, `exec` rules with workspace and monitor, how to match a new window to a slot, events to listen to.
3. Omarchy seams: plugin API, shell IPC, the 4.5 per-monitor workspace model, the dock, existing launch helpers.
4. App relaunch: how to bring back each app type (native, Flatpak, terminal + folder, web app, browser).
5. Monitor identity: how to name a monitor so a scene finds it again after unplug or a new port.
6. User flow: save, name, open, edit, delete; what the user sees; where scenes are stored.
7. Fit with omagnet and omahop: reuse, conflicts, shared code.
