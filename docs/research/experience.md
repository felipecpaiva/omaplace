# Experience: from settings to "my desktops come back"

Date: 2026-11-22. Research only, nothing built. Felipe: "right now it is not a good experience, we are just throwing
settings on the user; it needs to be intuitive and delightful."

Builds on two things and does not repeat them. [settings-app-ux.md](settings-app-ux.md) already decided: the five
page window, Undo instead of confirm, a toast for results, one sentence empty states, errors next to their control,
"desktop" not "slot". The desktop editor redesign is agreed: a big picture of the desktop as it is now, "Remember this
desktop", then "Put windows back" and "Update from now", with layouts and zones under "Change layout". This file is
about everything around that editor: the concepts, first run, reboot, per app behavior, and small moments.

## 1. Summary: the changes that matter most, ranked

1. **One thing to save, not four.** Plans and scenes are already the same record (`plan = true` and `home_slot` in
   `scenes.toml`). Show one noun, "saved desktop". Users cannot hold four overlapping ideas.
2. **Every save starts from the screen, never from a form.** Capture first, edit after, as PowerToys Workspaces
   ("Capture") and Raycast ("Save Current Layout" opens a filled draft) do. Picking a layout and then an app per zone
   becomes the rare path.
3. **One question about restarts, asked once.** Today "Open at login" per desktop and "Restore at login" on another
   page do the same job. Merge them into "After a restart" with one choice.
4. **One choice per app: where it opens.** Rules, app memory and ignored apps become one list of apps, each with
   "Where I left it", "On its saved desktop", "Always on ...", or "Leave it alone". macOS does this with one menu,
   "Assign To".
5. **Show progress while windows move.** A small list: each app with a spinner, a check, or a cross, plus Cancel
   (PowerToys Workspaces). Windows visibly jump into place; the list explains the jumps.
6. **Show what changed, not every state.** A desktop card gets a small mark when its windows no longer match what is
   saved. "Put windows back" and "Update from now" appear only then. A button with nothing to do is noise.
7. **Name things for the user.** A saved desktop is named from its apps ("Editor and Browser"); monitors by model or
   "Laptop screen", never `DP-2`. Rename is one click on the name.
8. **Show the desktops that matter.** Ten empty tiles per monitor read as ten tasks. Show desktops in use or saved;
   fold the rest into "7 empty desktops".
9. **Zones edit in place, always.** omagnet layouts appear as ready made choices inside "Change layout". No hop to
   another app (Felipe's complaint); omagnet stays a source of presets.
10. **First run is the real page, with one button.** No wizard. A one line banner and "Remember all my desktops".

## 2. What users actually want (jobs to be done)

- After a restart, I want my work back where it was, without thinking about it.
- When a desktop is set up just right, I want to keep it in one click, without describing it in a form.
- When I open an app by hand, I want it to land where it belongs, so I never drag it twice.
- When my setup drifts, I want to be asked once, at the moment it happens, never nagged.
- I want to trust it: see what it will do before, and undo what it did after.

## 3. Concept model: three things, not four

Today's words (plan, scene, rule, app memory, slot, session) are the builder's view: how it is stored. Users think
"this desktop", "this app", and "after a restart". So:

| Concept | What the user thinks | Shown as |
|---|---|---|
| **Saved desktop** | "Keep this desktop the way it is" | A card on Desktops: its picture, name, home, and one Open button |
| **Where an app opens** | "This app always goes there" | A row per app on Apps with one choice |
| **After a restart** | "Bring my stuff back" | One choice on Restore, plus "Bring back the last session" |

A saved desktop has a **home** (Desktop 3 on the big screen) or none ("open it on any desktop", today's scene with
`home_slot = 0`). Each desktop has at most one saved desktop at home; the Desktops page shows it. Saved desktops
without a home are listed under "Saved desktops you can open anywhere" (today's Scenes page, renamed). Storage does not
change: still `scenes.toml`, still `plan = true` for the one at home.

Where every feature of today goes (checklist: section 2 of settings-app-ux.md):

| Today | Goes to |
|---|---|
| Plan of a desktop | Saved desktop with a home |
| Scene (`omaplace save work`) | Saved desktop, no home; "Give it a home" button turns it into the one at home |
| Layout, zones, custom zones, Draw zones | "Change layout" inside the editor (agreed); omagnet layouts as presets there |
| App picker per zone | Under "Change layout": drag an app icon onto a zone, or "Put an app here" |
| Window details (folder, program, profile) | "Details" on one app, opened only when omaplace could not tell (a yellow dot says so) |
| Open all | "Open" on the card (starts missing apps, moves open ones) |
| Apps snap (planned app opened by hand) | Implied by "On its saved desktop", the default for apps in a saved desktop |
| "Update the plan?" notification | Kept, worded "Desktop 3 changed. Update it?" with Update and Keep |
| Open at login, per desktop | Folded into "After a restart"; per desktop only as an exception ("Not this one") |
| Rule (monitor, desktop, follow, same spot) | Apps: "Always on Desktop 3, Big screen", then "Go there with it" and "Same size and spot" |
| Rule On switch | The app's choice set to "Where I left it" keeps the rule text for Undo; no separate switch |
| Rule `rect` (only in config.toml today) | Stays in config; "Same size and spot" shows a tiny picture of it |
| Rule or scene monitor not connected | One line per app or desktop: "If the big screen is missing: open as usual"; default never asks |
| App memory `scene` | "On its saved desktop" (default for apps in a saved desktop) |
| App memory `last_place` | "Where I left it" (default for every other app) |
| App memory `auto` | The "Desktop 3 changed" question when a saved app moves between saved desktops |
| App memory `off` | "Open as usual" |
| Ignored apps | "Leave it alone" on that app, plus "Add an app that has no icon" for a window class |
| Apps already open when opening (move or new) | Default "move them" (as PowerToys "Move existing windows"); the other choice under More on a saved desktop |
| Keep a session snapshot | Always on; off only in Advanced ("Stop keeping a snapshot") |
| Restore last session, older sessions | Restore: one button, then "Earlier" folded |
| Restore at login (Off, Ask, Automatic) | "After a restart": Ask me, Bring everything back, Only my saved desktops, Nothing |
| Timings, sessions to keep, save delay | General, Advanced, folded (as agreed before) |
| `tiled_order`, `[strategy.*]` | Stay in config.toml |
| Omarchy menu rows | General, rows renamed: Remember this desktop, Open a saved desktop, Bring back last session |
| CLI `save`, `open`, `restore`, `rule add`, `list`, `rename`, `remove` | Unchanged verbs (scripts keep working); help text uses the new words |

Two decisions for Felipe, not details: (a) should "After a restart" default to **Ask** instead of Off (today Off, D15);
Ask is one notification and cannot hurt. (b) should "Only my saved desktops" exist, or is it enough to have "Bring
everything back"?

## 4. The ideal flows

Entry points stay the app launcher, the Omarchy menu, notifications and the CLI. No default keys.

**First run (nothing saved).**
1. The window opens on Desktops. Each monitor shows its desktops in use, drawn from the real windows.
2. One banner: "omaplace can put these back after a restart, and send apps where they belong." Button:
   "Remember all my desktops". A smaller link: "Pick one at a time".
3. One press saves each desktop in use as it is, named from its apps. Toast: "Remembered 3 desktops. Undo".
4. Right after, in the same banner: "After a restart: Ask me (recommended) / Bring everything back / Nothing".
   Asked here because this is the moment it means something (Apple: ask in context).
Two clicks, and the core promise is set.

**Remember a desktop.**
1. Arrange the desktop by hand, as usual.
2. From the Omarchy menu "Remember this desktop", or click its card and press "Remember this desktop".
3. Toast with the picture shrinking into the card: "Desktop 2 remembered: Editor and Browser. Undo".
Done. No name, layout or zone question. Rename later by clicking the name.

**A desktop changed later.**
1. Felipe moves Chat to another desktop by hand. One notification: "Desktop 2 changed. Update it?" Update, Keep.
2. Ignored, the card on Desktops shows a small mark and "1 window moved".
3. Opening the card shows both pictures side by side ("Saved" and "Now"), with "Put windows back" and "Update from
   now". Either one is one click, with Undo.

**Open everything after a reboot.**
1. On login, with "Ask me": one notification, "Bring back 3 desktops and 9 apps?" Bring back, Not now.
2. Bring back: a small progress list (each app: waiting, check, or cross). Windows jump into place as they open.
3. It closes itself when all are placed. If something failed: "8 of 9 back. Terminal in ~/project did not open.
   Show". Nothing silent.
4. "Not now" keeps the offer under Restore until the next snapshot replaces it.

**One app always on one monitor.**
1. On Apps, press "Add an app", pick it from open windows or installed apps (the list shows where each open window is).
2. Its row says "Where I left it". Change to "Always on ...", pick from a small picture of monitors and desktops,
   with the app's current place selected.
3. Optional under it: "Go there with it" and "Same size and spot".
Or from anywhere: Omarchy menu "Always open here" on the focused app. Toast: "Chat always opens on Desktop 1,
Laptop screen. Undo".

## 5. Small delight details

- Draw desktop pictures from real window rectangles, with app icons, and stacked windows as one stack with a count.
- Animate the card: when a desktop is remembered, its picture slides into the card. Under 200 ms, no bounce.
- The toast names the result in user words ("Desktop 2 remembered"), with Undo for 10 seconds.
- Default names from apps ("Editor and Browser"); if two match, add the desktop ("Editor and Browser, 2").
- Monitors by model or "Laptop screen"; show a tiny outline of the monitor shape next to the name.
- A yellow dot only where omaplace needs help (a terminal folder it could not read); nothing else is yellow.
- Hover or focus on a card shows "Open" and "Put windows back" right there, so most work never opens the editor.
- The progress list during an open shows app icons in the order they land, so it feels like things arriving.
- Live updates when windows change; F5 stays but is never needed.
- Buttons say what happens: "Bring back", "Update it", "Keep it", never Yes or No (NN/g).
- Counts in words a person says: "2 windows, full screen", "1 window moved", "9 apps".
- After the first restart that worked: one quiet toast, "Your desktops are back." Once, then never again.
- Help lines speak only when there is something to decide, never under every control.

## 6. What to remove or hide by default

- The words plan, scene, rule, app memory, slot, session, zone (zone only inside "Change layout").
- "No plan" under every empty tile, and empty desktops beyond the first empty one per monitor.
- Connector names (`DP-2`, `eDP-1`) as headings; keep them in a tooltip.
- Per zone rows with Zone 1, More, Clear; the zone text field; "Edit in omagnet" (presets instead).
- The always visible help paragraphs on Desktops ("A zone layout or Free floating switches...").
- Per desktop "Open at login" switch (folded into "After a restart").
- On Apps: the always visible Monitor, Desktop and Follow controls for every rule; they open under the chosen row.
- "From a window... click the app's window within 4 seconds" (a list of open windows replaces it).
- "Focused monitor" as a choice; a rule says a real place.
- The app memory radio (Scene place, Last place, Automatic, Off) as a separate card.
- "Apps already open" and "monitor not connected" radios at page level; defaults, with a per item override under More.
- The snapshot switch and the older sessions list (folded under Advanced and Earlier).
- Never hidden: errors, the read only banner, and anything that would lose data.

## 7. Sources

Read (fetched):
- PowerToys Workspaces: https://learn.microsoft.com/en-us/windows/powertoys/workspaces (Capture, edit after,
  launch status list with Cancel, "Launch & Edit" re-capture that can be reverted, "Move existing windows")
- PowerToys FancyZones: https://learn.microsoft.com/en-us/windows/powertoys/fancyzones (layout picker with live
  preview, layout name shown briefly on switch, "Move newly created windows to the last known zone")
- Windows Snap layouts and Snap groups: https://support.microsoft.com/en-us/windows/snap-your-windows-885a9b1e-a983-a3b1-16cd-c531795e6241
  (groups form by themselves, restore from the taskbar, Snap Assist suggests what to fill next)
- Raycast window management: https://manual.raycast.com/window-management ("Save Current Layout" fills a draft,
  "Other Windows": leave, minimize or close)
- Moom: https://manytricks.com/moom/ (arrange, then save a layout; app based or "any window" layouts; no display
  change trigger described)
- Rectangle Pro: https://rectangleapp.com/pro (workspace arrangement on display connect; no save layout described)
- Magnet: https://magnet.crowdcafe.com/ (drag to edges and keys only; no saved layouts, simplicity is the point)
- macOS Stage Manager: https://support.apple.com/guide/mac-help/use-stage-manager-mchl534ba392/mac (grouping by
  drag; the page says nothing about groups surviving a restart)
- macOS Spaces "Assign To": https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac
- NN/g progressive disclosure: https://www.nngroup.com/articles/progressive-disclosure/ (two levels at most)
- NN/g confirmation dialogs: https://www.nngroup.com/articles/confirmation-dialog/
- NN/g empty states: https://www.nngroup.com/articles/empty-state-interface-design/
- Apple HIG onboarding: https://developer.apple.com/design/human-interface-guidelines/onboarding
- GNOME HIG writing style: https://developer.gnome.org/hig/guidelines/writing-style.html

Search snippets only (pages not read in full):
- Windows "restartable apps" at sign in: techrepublic.com, pureinfotech.com, elevenforum.com results
- Chrome "Restore pages?" prompt and the newer infobar: windowsreport.com results
- KDE Plasma session restore (userbase page was a 404): bugs.kde.org and discuss.kde.org results; three modes
  (last logout, manually saved, empty), manual save reported unreliable
- PowerToys Workspaces reviews: windowsforum.com, windowscentral.com results ("Move existing windows" can disturb an
  app in use)

Not covered: GNOME session restore and KDE Activities had no usable page in this pass.

Local files: `README.md`, `CLAUDE.md`, `docs/design.md` (sections 6.3, 14.2: plan is a scene with `plan = true`),
`docs/feedback.md`, `docs/research/settings-app-ux.md`, `docs/research/09-competitor-review.md`,
`app/qml/DesktopsPage.qml`, `app/qml/DesktopEditor.qml`, `app/tests/page-desktops-plan.png`,
`app/tests/open-now.png`, `app/tests/page-apps.png`.
