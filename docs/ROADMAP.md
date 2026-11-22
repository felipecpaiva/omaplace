# omaplace roadmap

Method, same as omagnet and omahop: small batches. Each row has a design, an implementation, tests and a live check. No
row is done until its tests pass and the real desktop shows it. Every row meets
[engineering-standards.md](engineering-standards.md). Live checks only after asking Felipe right before each one.

## Release plan

| Release | Goal | Contents |
|---|---|---|
| **v0.1** (2026-11-21, tag v0.1.0; notes `releases/v0.1.0.md`) | Every app opens where it belongs | Placement rules with monitor identity (M1), scenes and app memory (M2), session snapshots and manual restore (M3), the Omarchy menu with consent and `app_memory = "auto"` (M4), the Desktops page and desktop plans (M5). Goals and live results: `goals.md`, `batch-log/live-M1.md`, `batch-log/live-M5.md` |
| **v0.2** (2026-11-22, tag v0.2.0; notes `releases/v0.2.0.md`) | Close the open checks, then the first ideas | Second monitor and real reboot checks with their fixes, restore at login, `keep_rect` (Same spot), Draw zones, omagnet layouts, the laptop panel role, "Update plan" for twins, Automatic app memory in the window (D25 to D31) |
| Later (ideas, not promised) | See "Later ideas" | |

## Open items after v0.2

| Item | What is needed | Source |
|---|---|---|
| Third reboot | Restore at login runs before the plans, and an app picked by launcher name lands in its zone, after a real reboot (fixed and checked by hand) | `batch-log/live-M5.md` |
| Hand clicks | Draw zones, "Edit in omagnet", the Same spot toggle, the Laptop panel choice, the menu row click (S6), "Update plan" pressed with a real click | `validation-checklist.md` |
| Set any desktop's mode | Use `omarchy-hyprland-workspace-layout-set` once [omacom/omarchy#19671](https://github.com/omacom/omarchy/pull/19671) ships, and drop the toggle fallback (D22). The code already uses it when present | design 14.4 |

## Later ideas (not promised)

- **Instant pickup of a hand-made `scenes.toml`** without a folder watch or polling, if Quickshell gains a folder watch.

## Not goals

From `goals.md`: replacing or patching any part of Omarchy, editing the user's Hyprland files, restoring browser tabs or
app contents, forcing exact positions on tiled or scrolling desktops, placing a Chrome window opened from Chrome's own
profile menu, window groups, special workspaces, a bar icon by default, default keys.
