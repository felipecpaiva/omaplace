# omaplace roadmap

Method, same as omagnet and omahop: small batches. Each row has a design, an implementation, tests and a live check. No
row is done until its tests pass and the real desktop shows it. Every row meets
[engineering-standards.md](engineering-standards.md). Live checks only after asking Felipe right before each one.

## Release plan

| Release | Goal | Contents |
|---|---|---|
| **v0.1** (2026-11-21, tag v0.1.0; notes `releases/v0.1.0.md`) | Every app opens where it belongs | Placement rules with monitor identity (M1), scenes and app memory (M2), session snapshots and manual restore (M3), the Omarchy menu with consent and `app_memory = "auto"` (M4), the Desktops page and desktop plans (M5). Goals and live results: `goals.md`, `batch-log/live-M1.md`, `batch-log/live-M5.md` |
| **v0.2** (2026-11-22, tag v0.2.0; notes `releases/v0.2.0.md`) | Close the open checks, then the first ideas | Second monitor and real reboot checks with their fixes, restore at login, `keep_rect` (Same spot), Draw zones, omagnet layouts, the laptop panel role, "Update plan" for twins, Automatic app memory in the window (D25 to D31) |
| **v0.3** (2026-11-22, tag v0.3.0; notes `releases/v0.3.0.md`) | One settings app | `omaplace-settings` with five pages (D36 to D40), feedback items 1 to 3 (`feedback.md`), the plugin panel removed |
| **v0.4** (on branch `next`, not released; package 0.3.0-8 for testing) | The settings app feels good to use | Feedback items 4 to 7 (`feedback.md`). A picture-first desktop editor with Remember this desktop, Put windows back and Update from now (D41 to D44). The omagnet bridge: zones go to omagnet's config, its window is never opened (D43). Desktops that say if they match what was remembered (D45). Remember all, Undo, the one restart question and a progress list (D46 to D49). Desktop numbers from Hyprland's workspace rules and hyprmoncfg's strategies (D50, D51). Floating desktops drawn as their windows sit (D52) and changed in one click (D53). Fixes: an unknown browser profile is put back but never started; a real window's class beats the launcher file. Felipe is still collecting small experience issues: no release until he says so |
| Later (ideas, not promised) | See "Later ideas" | |

## Open items

| Item | What is needed | Source |
|---|---|---|
| Third reboot | Restore at login runs before the plans, and an app picked by launcher name lands in its zone, after a real reboot (fixed and checked by hand) | `batch-log/live-M5.md` |
| Hand clicks | Draw zones, "Edit in omagnet", the Same spot toggle, the Laptop panel choice, the menu row click (S6), "Update plan" pressed with a real click | `validation-checklist.md` |
| v0.4 hand checks | Undo, Remember all and Give it a home pressed by hand; the quick arrange buttons clicked in the app (the same requests passed live); per display and interleaved numbering on a real hyprmoncfg profile | this file |
| v0.4 release work | Demo GIFs of the new flows, README and `releases/v0.4.0.md`, a version bump of the app package | `releases/README.md` |
| Quick changes for tiled desktops | D53 covers Free floating only; on a tiled desktop the order of the apps is the layout | D53 |
| Small known limits | `appAttached` never clears. With no window open, a Chrome web app's class comes from its launcher file, which is wrong on Wayland (`crx_<id>` against `chrome-<id>-Default`) | `feedback.md` 7 |
| Set any desktop's mode | Use `omarchy-hyprland-workspace-layout-set` once [omacom/omarchy#19671](https://github.com/omacom/omarchy/pull/19671) ships, and drop the toggle fallback (D22). The code already uses it when present | design 14.4 |

## Later ideas (not promised)

- **Instant pickup of a hand-made `scenes.toml`** without a folder watch or polling, if Quickshell gains a folder watch.

## Not goals

From `goals.md`: replacing or patching any part of Omarchy, editing the user's Hyprland files, restoring browser tabs or
app contents, forcing exact positions on tiled or scrolling desktops, placing a Chrome window opened from Chrome's own
profile menu, window groups, special workspaces, a bar icon by default, default keys.
