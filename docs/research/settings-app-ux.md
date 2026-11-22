# Settings app: user experience research

Date: 2026-11-22. Status: research only, nothing built. Asked for in [feedback.md](../feedback.md) item 3: a click
outside the settings closes them, and Felipe wants a real window that stays open while he arranges apps.

## 1. Summary

- **Make it a real window in two steps.** Step 1 (small, fixes the complaint): swap the full screen overlay in
  `SettingsPanel.qml` for a Quickshell `FloatingWindow`, the way Omarchy's own dev gallery panel does; the 18 page
  files stay as they are (section 6). Step 2 (its own effort): the page changes of sections 3 to 5.
- **The cause is our own code, not a shell rule.** `SettingsPanel.qml` draws a full screen `PanelWindow` on the
  Overlay layer with exclusive keyboard focus, and its dimmed background has a `MouseArea` that calls `dismiss()`.
  A normal window removes all three.
- **Five sidebar pages, named for what the user wants to do:** Desktops, Apps, Scenes, Restore, General. "Rules"
  becomes "Apps" and takes the per-app settings (app memory, ignored apps) out of General.
- **The desktop map is the home page.** Pick a monitor at the top, see its desktops as tiles, edit the chosen one
  beside the map (side by side when the window is wide, below it when narrow).
- **Keep "changes save at once"** (Microsoft's guide says so; omadials and omaplace do it today). Replace the delete confirmation dialogs with an Undo bar for
  10 seconds, as omadials does. Keep a confirmation only where Undo cannot work.
- **No global search.** There are about 15 settings. Add a filter box to the two lists that grow (Apps, Scenes).
- **Fix three things a real window breaks:** "Add a rule for the focused window" would pick the settings window
  itself; the launcher uses `shell toggle`, so a second launch would close the window; and the window has class
  `org.quickshell`, so it must never be captured into a scene or the session.
- **Words:** sentence case, plain verbs, no config keys in labels (`keep_rect`, `plan`, `slot` only as a secondary
  hint in help text if at all), units in the help line.

## 2. What omaplace has today (from the code)

**Window frame** (`SettingsPanel.qml`): title "omaplace" with the caption `~/.config/omaplace`; Close button; side
list of five pages; status line at the bottom (last answer, or "N problem(s) in the config files", or "Changes are
saved at once."); delete confirmation dialog (scene, plan, rule); "service is not running" message; Escape closes;
click on the dimmed background closes; the window hides itself while the file chooser is open.

**Desktops** (`DesktopsPage`, `MonitorDesks`, `DeskTile`, `DesktopCard`, `ZoneRow`, `ZoneEditor`, `ZoneThumb`):
- Notes: scenes.toml read only; reason the desktops could not be read; "Reading the desktops..."; "No monitors found yet."
- One section per monitor; a grid of 10 tiles: "Desktop N, M windows", a small preview, a badge (mode or plan), "No plan".
- Editor of the chosen tile: heading "Desktop N on <monitor>, plan <name>", badge, plan problem note, monitors read failed note.
- Layout dropdown: No plan, Tiled, Scrolling, Full screen, Free floating, 2 columns, 3 columns, 2 rows, 2 by 2 grid,
  Priority, "omagnet: <name>" for each omagnet layout, Custom zones. Picking "No plan" asks to delete the plan.
- Custom zones text field (x y w h fractions, separated by `;`).
- Draw zones (when omagnet is not loaded) opens the zone editor: Grid or Canvas; Split vertical, Split horizontal,
  Click to split, Line vertical or horizontal, Select several, Merge (grid); Add zone (canvas); Delete zone; drag
  dividers, move and resize zones; overlap and "percent with no zone" notes; zones as text; Save, Cancel; Delete key, Escape.
- Edit in omagnet (when omagnet is loaded); help note; mode note (accent).
- Preview with each app's icon and name in its zone.
- One row per zone: zone name, searchable app picker ("Pick an app"), More or Less, Clear, notes on why it may not
  snap; under More the window fields (as on Scenes: folder, program, profile or project).
- Open all; Open at login switch; Remove plan; two help notes.

**Scenes** (`ScenesPage`, `SceneRow`, `WindowRow`): privacy note (scenes.toml is plain text); read only note; empty
note ("omaplace save <name>"). Per scene: name field (Enter renames), window count, Open, Windows or Hide windows,
Delete. Per window: "app, position, order"; Folder, Program, Profile or project fields, each marked "(edited)";
for an unknown profile or folder: a profile dropdown, "Choose folder...", a typed field, and a note.

**Rules** (`RulesPage`, `RuleRow`): "Add a rule for the focused window" with its note; empty note. Per rule: app name,
On switch, Remove, Monitor dropdown (Focused monitor, Laptop panel (any laptop), live monitors, "(not connected)"),
Desktop 1 to 10, Follow switch, Same spot switch (only when the rule has a spot).

**Session** (`SessionPage`, `SessionRow`): Keep a session snapshot switch; Restore last session; Restore at login
(Off, Ask, Automatic) with a note; Saved sessions list: time, "(this login)", window count, Restore; empty note.

**General** (`GeneralPage`): App memory (Scene place, Last place, Automatic, Off); Apps already open when a scene opens
(Move them, Open new ones); Scene monitor not connected (Use the focused monitor, Skip); Rule monitor not connected
(same two); Ignored apps (comma list); Omarchy menu (Add or Remove) with a note; Show advanced settings (7): wait for a
started app, settle time, time between two launches, session save delay, sessions to keep, quiet time per profile or
folder, request timeout.

**Only in config.toml:** `tiled_order`, the `[strategy.*]` tables (how an app is matched and relaunched), a rule's
`rect` value itself (the window shows only the Same spot switch). Drift: the README says app memory "auto" is not in
the window, but General offers "Automatic".

## 3. Proposed information architecture

Sidebar on the left, one page at a time, page title at the top of the content. Same pattern as omadials, PowerToys,
KDE and GNOME Settings, Windows and macOS settings. Tabs (omagnet's Settings and Layouts) stop working past 3 pages.

| Sidebar | What the user does there | Today |
|---|---|---|
| **Desktops** | See every desktop, give it a layout and an app per zone, open it | Desktops |
| **Apps** | Say where one app always opens; how apps you open by hand behave; apps to leave alone | Rules, part of General |
| **Scenes** | Open, rename, delete saved desktops, fix a window's folder or profile | Scenes |
| **Restore** | Bring back the last session, now or at login | Session |
| **General** | What happens when things are missing, the Omarchy menu, timings, about | rest of General, frame |

Mapping of every control (nothing dropped):

| Control today | New home |
|---|---|
| Header path, warnings count | General, "About": version, file paths with "Open folder", problems listed in words |
| Status line | A small toast at the bottom of the window ("Saved", "Opening Work...", errors stay until closed) |
| Close button, Escape, background click | Window close (Super+W or Ctrl+W); Escape closes only the open sheet or picker |
| Service not running message | Full page empty state with the fix command (section 5) |
| Desktops: all of it | Desktops; the zone editor opens as a sheet over the editor side |
| Remove plan, "No plan" | Desktops editor, "Remove plan" in a "..." menu, with Undo |
| Open at login (per desktop) | Desktops editor, switch "Open these apps at login" |
| Window fields under More | Desktops zone row, "Details" expander (same component as Scenes) |
| Rules list, add, On, Remove, Monitor, Desktop, Follow, Same spot | Apps, card "Always open here" |
| App memory | Apps, card "Apps you open yourself": "Go back to" Where the scene put it, Where you left it, Automatic, Nowhere special |
| Ignored apps | Apps, card "Leave these apps alone": app chips with an app picker, plus "Type a window class" for apps with no launcher entry |
| Scenes list, rename, open, delete, windows, unknown profile or folder | Scenes, same rows plus a filter box |
| Scenes privacy note (plain text file) | Scenes, one line of help under the page title |
| Apps already open when a scene opens | Scenes, card "When a scene opens" |
| Scene monitor not connected | Scenes, same card: "If its monitor is not connected" |
| Rule monitor not connected | Apps, card "Always open here": "If the monitor is not connected" |
| Keep a session snapshot, Restore last session, Restore at login, saved sessions | Restore, in that order |
| Sessions to keep, session save delay | Restore, "Advanced" expander |
| Omarchy menu | General, card "Omarchy menu" |
| The other 5 timings | General, "Advanced" expander, with "Use the default" per row |
| `tiled_order`, `[strategy.*]` | Stay in config.toml for now; General, About says "More settings in config.toml" with Open folder |

Names: say "desktop", never "workspace" or "slot"; "monitor", never "output"; "plan" only as "Remove plan" and in
help text ("a plan is the layout and apps of one desktop"). "Same spot" becomes "Open in the same spot" with help
"Only on a floating desktop". "Follow" becomes "Switch to that desktop when it opens".

## 4. Key screens

**Desktops, the map.** The FancyZones editor starts with "which monitor", then the layout. The map is the
place where the user decides, so it gets the most room. Badges show the real Omarchy mode of each desktop (feedback
item 2) and the plan's layout when there is one. Arrow keys move between tiles, Enter opens the editor.

```
+-----------+------------------------------------------------------------------+
| Desktops  | Desktops                       Monitor: [Example 27 v] [Laptop]  |
| Apps      | +------+ +------+ +------+ +------+ +------+                     |
| Scenes    | | 1    | | 2 ** | | 3    | | 4    | | 5    |   Desktop 2         |
| Restore   | |[][]  | |[ | ]| |      | |      | |      |   Layout [2 columns v]|
| General   | |Float | |2 col | |Tiled | |Tiled | |Tiled |   +-------+-------+   |
|           | +------+ +------+ +------+ +------+ +------+   |Editor |Browser|   |
|           |  6 .. 10 (same)                               +-------+-------+   |
|           |                                                Left   [Editor v]  |
|           |                                                Right  [Pick... v] |
|           |                                                [Open all]  Login o|
+-----------+------------------------------------------------------------------+
```

- Below about 1000 px the editor moves under the map. One monitor: no monitor picker.
- A tile with no plan says "No plan" and its editor starts with one line and the layout picker (empty state).
- "Draw zones" opens the zone editor as a sheet over the editor side; Save and Cancel stay at its bottom.
- App pickers show the app's own icon and a hint when two apps share a name (feedback item 1).

**Apps, the rule list and editor.** KDE Window Rules edits one rule at a time, with "Detect window properties"
to fill the match from a live window. PowerToys FancyZones keeps excluded apps as a plain list. For omaplace, a rule is small (5 fields), so edit it inline in an expanded row, not on a sub page.

```
Apps                                               [Filter apps        ]
Always open here                                   [+ Add app v]
  (icon) Editor     Example 27, desktop 3    On o   (v)
  (icon) Browser    Laptop panel, desktop 1  On o   (^)
         Monitor [Laptop panel v]  Desktop [1]
         Switch to that desktop when it opens  o
         Open in the same spot                 o   (only on a floating desktop)
         [Remove]
  If the monitor is not connected   (o) Open as usual  ( ) Use the focused monitor
Apps you open yourself ...
Leave these apps alone   [Game x] [Video player x] [+ Add]
```

- "+ Add app" offers two ways: "From an installed app" (the same searchable picker as Desktops) and "From an open
  window" (a list of open windows by app name, monitor and desktop; picking one fills monitor and desktop). This
  replaces "the focused window", which in a real window is the settings window itself.

**Restore.** One clear action on top, then the automatic part, then history.

```
Restore
  [Restore last session]   Last saved: today 09:12, 14 windows
  Restore at login   (o) Off  ( ) Ask with a notification  ( ) Automatic
  Keep a session snapshot                                      o
Older sessions
  yesterday 18:40   12 windows   [Restore]
  21 Nov 09:02       9 windows   [Restore]
  > Advanced: sessions to keep, save delay
```

## 5. Interaction rules

- **Save model:** every change saves at once (Microsoft guidance, read; Apple and GNOME, general knowledge; omadials
  and omaplace today). No Save
  button, except inside the zone editor sheet, where many small edits make one change (Save, Cancel).
- **Undo instead of confirm:** Delete scene, Remove rule, Remove plan act at once and show "Deleted Work. Undo" for
  10 seconds (Ctrl+Z too). The service already keeps a `.bak`; Undo writes back the text from before the change.
  A confirmation stays only for actions Undo cannot reverse: "Restore last session" when windows are open (it moves
  them) shows one line "Moves 8 open windows. Restore?" inline, not as a modal.
- **Live preview:** the tile and editor previews redraw on every change (they do today). No "show on screen"
  overlay for now; Open all is the real preview.
- **Actions vs settings:** Open all, Open, Restore move real windows. Show them as filled buttons, separate from
  switches, with a running state ("Opening, 3 of 5") and the summary in the toast.
- **Empty states:** one sentence and one button. Scenes: "No scenes yet. A scene is the apps of one desktop." plus
  "Save a desktop..." (pick the desktop on the map). Apps: "No app has a fixed place yet." plus "+ Add app". Restore:
  "Nothing saved yet. omaplace saves after your windows change." Service down: "omaplace is not running" with the
  two fix steps and a "Copy command" button.
- **Errors:** next to the control that caused them, in words ("scenes.toml has a problem on line 12, plans are read
  only until it is fixed", with "Open folder"). The window never fails silently and never hides a problem in the toast.
- **Read only:** when a file cannot be written, controls are shown disabled with one banner that says why.
- **Keyboard:** Tab and Shift+Tab through every control; Ctrl+1 to Ctrl+5 for the pages; arrow keys and Enter on the
  map; Ctrl+F focuses the filter on list pages; Escape closes the open picker or sheet; Ctrl+Z undo; Ctrl+W close.
  Keep the focus on the same control after a save (DesktopsPage already does this with `focusTag`).
- **Window:** floating, centered on the focused monitor the first time, about 1040 by 720, minimum 720 by 520. It
  stays open when focus moves away. One instance: opening it again (launcher, `omaplace settings`, menu row)
  brings the existing window forward. It reopens on the page it was on. Remembering the size across opens is optional
  and can wait (shortcut: Hyprland places it by the float rule each time).

## 6. Technical options for the real window

> Decision (Felipe, 2026-11-22): option (b), one settings app built like omadials-settings, and the plugin panel removed. See design D36 to D40. The text below is the research as written.

| | (a) `FloatingWindow` in the plugin panel | (b) Separate app, like `omadials-settings` |
|---|---|---|
| How | `SettingsPanel.qml` keeps `kinds: panel`; replace `PanelWindow` with `FloatingWindow { title; minimumSize }` | C++ and Qt Quick binary, PKGBUILD, own `.desktop` |
| Proven here | Omarchy's `dev-gallery` panel plugin does exactly this (`GalleryPanel.qml`); the shell comment says the Loader keeps "the plugin's FloatingWindow + state" between summons | omadials v0.7.0, `app/` |
| Reuse | All 18 page files and every `Service.qml` call unchanged; `qs.Ui` and `qs.Commons` work in a FloatingWindow (the gallery renders the real components, `Dropdown` among them) | Pages import `qs.Ui` and `qs.Commons`, so all of them are rewritten; the page calls reach about 110 in-process `Service.qml` functions, while its `IpcHandler` has 12 |
| Theme | Exact and live | Rebuilt from `colors.toml` |
| Install | Nothing new; still `omarchy plugin add` | A package and `sudo pacman -U`; breaks the README promise "no root, no packages" and design 8 "No new process" |
| Isolation | Lives in the shell; `omarchy restart shell` closes it | Own process; a crash spares the shell |
| Window identity | Class is `org.quickshell` for every shell window; match by title | Own app id `omaplace-settings` |
| Effort | Small | Large |

**Recommendation: (a).** It solves the complaint with a small change and keeps one code base. What it needs:

1. **Window:** `FloatingWindow { title: "omaplace settings"; implicitWidth; implicitHeight; minimumSize }`. Remove the
   scrim, the `MouseArea` dismiss, `WlrLayershell` focus, and the "hide while the file chooser runs" rule (the chooser
   is a normal window and can sit on top). On `onVisibleChanged` to false, call `shell.hide(id)` like the gallery.
2. **Float rule:** on a tiled desktop a toplevel tiles. omaplace's Lua already declares rules with `hl.window_rule`;
   add one for class `^org.quickshell$` and title `^omaplace settings$` with float, size and center (field names to
   confirm in a spike; `o.window` matches on title). Omarchy does the
   same for the gallery in `default/hypr/apps/omarchy-shell.lua` (`o.window({ class, title }, { maximize = true })`).
   Without the Lua line the window still works, it just tiles.
3. **Never capture itself:** capture, session and app memory skip classes in `ignore` (`lua/capture.lua`
   `ignore_set`). Add `org.quickshell` to a built-in ignore set, so no shell window ever lands in a scene.
4. **Rule add:** `startRuleAdd` reads `hyprctl activewindow -j` (`Service.qml` `activeProc`). With a real window that
   is the settings window. Use the "+ Add app" picker of section 4, or skip `org.quickshell` and take the last other
   active window. The CLI `omaplace rule add` keeps today's behaviour.
5. **Single instance:** `omaplace.desktop` and `omaplace settings` call `shell toggle`, which hides an open panel
   (`shell.qml` `toggle` = `isPluginOpen ? hide : summon`). Switch them to `shell summon`, which calls `open()` again
   on a loaded panel (`deliverIfLoaded`). In `open()`, when the
   window is already visible, focus it with an async `Hyprland.dispatch` (in the Quickshell Hyprland qmltypes), since the
   `FloatingWindow` type lists no raise or activate method (checked in `quickshell-window.qmltypes`, Quickshell 0.3.2).
6. **Focus on Hyprland:** a toplevel gets normal focus: click to focus, it keeps its content when focus moves to the
   app being arranged, and keys go to it only while it is focused. Escape no longer closes the window; Super+W closes
   it like any app. Text fields keep working, as there is no exclusive grab.
7. **Tests and checks:** a QML load test of the new window; hand checks: opens floating on a tiled desktop, second
   launch raises, click outside keeps it open, "Add app" from an open window, not captured by `omaplace save`.

Choose (b) only if crash isolation or a store listing as an app becomes a goal. It can be added later on the same
files, as omadials did.

## 7. Sources

Local files read:
- `omaplace`: `README.md`, `SettingsPanel.qml`, `pages/*.qml` (all 18), `Service.qml` (IPC, `startRuleAdd`,
  `activeProc`), `js/Settings.js`, `js/ConfigIO.js`, `js/Desktops.js`, `lua/capture.lua`, `lua/omaplace.lua`,
  `manifest.json`, `omaplace.desktop`, `docs/design.md` (7.2, 7.5, 8, 14), `docs/feedback.md`.
- `omadials`: `README.md` (Install), `app/README.md`, `app/omadials-settings.pro`, `app/qml/` listing,
  `docs/settings-ux.md`, `docs/architecture.md` section 9.
- `omagnet`: `SettingsPanel.qml` (Settings and Layouts tabs, `PanelWindow` overlay), `LayoutGallery.qml`, `manifest.json`.
- Omarchy: `/usr/share/omarchy/shell/shell.qml` (summon, hide, toggle, panel Loader),
  `/usr/share/omarchy/shell/plugins/dev-gallery/GalleryPanel.qml` and `manifest.json`,
  `/usr/share/omarchy/default/hypr/apps/omarchy-shell.lua`, the `omarchy-app` skill.
- Quickshell 0.3.2: `/usr/lib/qt6/qml/Quickshell/_Window/quickshell-window.qmltypes`.

Web (fetched): Quickshell FloatingWindow https://quickshell.org/docs/types/Quickshell/FloatingWindow/ ;
PowerToys FancyZones https://learn.microsoft.com/en-us/windows/powertoys/fancyzones ; Microsoft app settings guidelines
https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings ; libadwaita
PreferencesDialog https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/class.PreferencesDialog.html ; KDE Window
Rules contents https://docs.kde.org/stable_kf6/en/kwin/kcontrol/windowspecific/

Web (search result summaries only, pages not opened): PowerToys general https://learn.microsoft.com/en-us/windows/powertoys/general ;
GNOME Multitasking https://help.gnome.org/gnome-help/multitasking.html ; KDE UserBase
https://userbase.kde.org/KWin_Rules_Window_Attributes ; macOS Desktop & Dock https://support.apple.com/guide/mac-help/mchl118087b0/mac ;
Rectangle https://github.com/rxhanson/Rectangle ; nwg-displays https://github.com/nwg-piotr/nwg-displays .
Apple HIG settings (https://developer.apple.com/design/human-interface-guidelines/settings): fetch gave no page text;
points used are general knowledge.

Not read: GNOME HIG (404), Magnet, Moom, Stage Manager, Workspace Matrix type extensions, Hyprland settings GUIs
other than nwg-displays. No claims are made from them.
