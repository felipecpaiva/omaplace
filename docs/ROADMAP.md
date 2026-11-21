# omaplace roadmap

Method, same as omagnet and omahop: small batches. Each row has a design, an implementation, tests and a live check. No
row is done until its tests pass and the real desktop shows it. Every row meets
[engineering-standards.md](engineering-standards.md). Live checks only after asking Felipe right before each one.

## Release plan

| Release | Goal | Contents |
|---|---|---|
| **v0.1** (2026-11-21, tag v0.1.0; notes `releases/v0.1.0.md`) | Every app opens where it belongs | Placement rules with monitor identity (M1), scenes and app memory (M2), session snapshots and manual restore (M3), the Omarchy menu with consent and `app_memory = "auto"` (M4), the Desktops page and desktop plans (M5). Goals and live results: `goals.md`, `batch-log/live-M1.md`, `batch-log/live-M5.md` |
| v0.2 (planned) | Close the open checks | The live checks below, then the fixes they find |
| Later (ideas, not promised) | See "Later ideas" | |

## Open items from v0.1

| Item | What is needed | Source |
|---|---|---|
| Second monitor | A rule still works after its monitor moves to another port; with the rule's monitor unplugged the app opens normally (M1 checks 2 and 3, spike S7). Scenes and restore with a missing monitor land on the focused one | goals M1, `checklist/WP7s.md` |
| Open at login | A ticked plan opens once after a real login, not again on a shell restart or config reload (M5 check 6) | goals M5, `checklist/WP12b.md` |
| Restore after a real login | `omaplace restore` after a real logout or reboot (M3 check 3 passed only with a hand-made previous session) | goals M3 |
| Notification button click | Pressing "Update plan" with a real mouse click runs the command (S13) | `batch-log/live-M5.md` |
| Menu row click | Clicking a real Omarchy menu row (S6) | goals M4 |
| Set any desktop's mode | Use `omarchy-hyprland-workspace-layout-set` once [omacom/omarchy#19671](https://github.com/omacom/omarchy/pull/19671) ships, and drop the toggle fallback (D22). The code already uses it when present | design 14.4 |
| Settings window hand checks | The pages beyond Scenes and Desktops were checked by screenshot, not by clicks | `validation-checklist.md` |
| `app_memory = "auto"` in the window | Works from `config.toml` and passed live; the General page still shows it greyed | design D17 |
| Keyboard focus on the Desktops page | After each edit the page is rebuilt and keyboard focus is lost | `checklist/WP13.md` |
| Release media | `branding/demo/desktops.gif`, `scenes.gif`, `restore.gif`, recorded on a real screen with made-up names | `releases/README.md` |

## Later ideas (not promised)

- **Restore at login:** `restore_at_login = "ask"` (one notification with a Restore button) and `"auto"`. Off stays the default (D15).
- **Visual zone editor** on the Desktops page, instead of typing zones as text (omagnet has the format).
- **Exact place on open for rules** (`keep_rect`): a rule that also sets the size and spot, done after the app opens (design 5.2).
- **"Update plan" for twins:** two windows of the same app in one plan, and a second window in a Full screen plan (today `not_possible`).
- **Instant pickup of a hand-made `scenes.toml`** without a folder watch or polling, if Quickshell gains a folder watch.
- **The laptop panel as a role:** save "the laptop panel" as a role, so a scene moves between laptops of different models (research 05, open question 4).
- **Going public:** repo public, marketplace listing (`launch/marketplace-listing.md`), repo settings (`launch/repo-metadata.md`). Felipe's call.

## Not goals

From `goals.md`: replacing or patching any part of Omarchy, editing the user's Hyprland files, restoring browser tabs or
app contents, forcing exact positions on tiled or scrolling desktops, placing a Chrome window opened from Chrome's own
profile menu, window groups, special workspaces, a bar icon by default, default keys.
