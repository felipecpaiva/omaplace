# 07. Fit with our own plugins (omagnet, omahop, omadials, OmaBarConfigurator)

Open question 7 of `../research.md`. Written 2026-11-21. Read only: nothing was run on the desktop, no window was moved.

Evidence tags: **[source]** = read in the code, with file:line. **[docs]** = read in a project doc or record. Nothing here is
**[tested]**; every claim about runtime behaviour is from reading.

## Summary

1. omagnet already has the hard part of "put a window at this rectangle": usable area per monitor, fractions to pixels,
   moving a rectangle between monitors, and a resize then move with a size check. Most of it is pure Lua we can copy.
2. A scene slot should be a **fraction of the monitor's usable area**, not a pixel box and not an omagnet zone number.
   Zones have no stable id, omagnet does not track which zone a window sits in, and a zone ties scenes to omagnet's config.
3. Neither plugin places windows when they open. omagnet's open handler only fixes the shadow, omahop only listens to focus
   and close. The real clashes are small: a stale shadow, omagnet's restore tag, and omahop's recently-used order.
4. Packaging: **a separate private plugin** (`omascenes`) with a small copied set of pure helpers, plus a cross-check test
   against omagnet's copy. Not a feature inside omagnet, and no shared library yet.
5. omagnet's roadmap has no scenes item. The nearest are per-workspace layouts (L2, built), "refit on layout change"
   (Z10, not planned) and FancyZones' "move new windows to last known zone" (F44, marked "maybe").

## Reuse table

| Piece | Where | Verdict | Why |
|---|---|---|---|
| Usable area of a monitor (scale, rotation, bar, extra reserve) | `omagnet/lua/geometry.lua:231` `G.usable` | **Reuse as-is** (copy) | Pure, no `hl` calls, same formula as Omarchy's own `place()` [source] |
| Fractions to pixels, with optional margin | `omagnet/lua/geometry.lua:34` `G.place_frac` | **Reuse as-is** (copy) | Pure. Call with `margin = 0` for a saved window (see the margin trap below) [source] |
| Logical size of a monitor | `omagnet/lua/geometry.lua:400` `G.logical_size` | **Reuse as-is** (copy) | Pure [source] |
| Move a rectangle from one area to another | `omagnet/lua/geometry.lua:63` `G.transfer` | **Reuse as-is** (copy) | Pure. Exactly what a scene needs when its monitor is now a different size [source] |
| Monitor order left to right | `omagnet/lua/geometry.lua:74` `G.next_monitor` | Skip | Scenes find a monitor by identity, not by order (question 5) |
| Resize first, move second, check the size after 40 ms, at most twice, stop if the app refuses | `omagnet/lua/omagnet-snap.lua:133` `put` | **Adapt** (copy about 20 lines) | It is `local`, so it cannot be called from outside [source]. The logic is what scenes need for slow and stubborn apps |
| Leave maximized first, then place | `omagnet/lua/omagnet-snap.lua:162` `M.apply` | **Adapt** | Exported, but it refuses windows that are not on a floating workspace or are on omagnet's ignore list (`:84` to `:90`), and it writes the `omagnet-orig` tag (`:152`), so omagnet's Restore would later go back to where the app spawned [source] |
| Window lookup by address, monitor of a window | `omagnet/lua/omagnet-snap.lua:93`, `:97` | Adapt | Two lines each; copy the idea [source] |
| "Is this workspace floating" from Omarchy's state files | `omagnet/lua/omagnet-snap.lua:77`; `omahop/lua/omahop.lua:108` | Adapt | Both read `~/.local/state/omarchy/workspace-layouts/<id>.lua`. omahop's version also trusts the tag and caches per call [source] |
| Zone layouts, zone under the pointer, zone stepping | `omagnet/lua/geometry.lua:266`, `:293`, `:323`, `:358` | Skip for v1 | Only needed if a slot is a zone, which we advise against |
| Shadow fix for a full-height window | `omagnet/lua/omagnet-snap.lua:116` `M.fit_shadow` | **Call at runtime if present** | Exported on `_G.omagnet` (`:654`). Look it up at use time, not at load time, so load order does not matter [source] |
| Event hooks (`hl.on`) | `omagnet/lua/omagnet-snap.lua:661` to `:662`; `omahop/lua/omahop.lua:876` to `:877` | Pattern only | Both plugins register on `window.active` and both run on this machine, so several listeners on one event live side by side [source, docs: omagnet and omahop records]. Wrap in `pcall` like omahop |
| Binds guarded once per Lua state, a duplicate shortcut skipped and reported | `omagnet/lua/omagnet-snap.lua:664` to `:716` | Pattern only | Survives `hyprctl reload` without double binds [source] |
| Config: flat TOML subset, one parser per side, cross-checked | `omagnet/lua/config.lua`, `omagnet/ConfigIO.js` | Adapt for settings only | Scenes are lists of records, which a flat TOML subset handles badly. Use JSON for the scene store; omadials' versioned migration (`omadials/logic/ConfigMigrate.js:1` to `:20`) is the model [source] |
| Settings app shell (panel, service, launcher entry, bar widget that hides itself) | `omagnet/manifest.json`, `Service.qml`, `SettingsStore.qml`, `BarWidget.qml` | **Adapt** | Copy the service that writes the `.desktop` file and the store that runs `hyprctl eval` as an async `Process` (`omagnet/SettingsStore.qml:41`, `:66`) [source] |
| Spec-driven settings window (categories, sub headings, nothing hand-coded per setting) | `omahop/spec.json`, `omahop/tools/gen-spec.lua`, decision D24 | Adapt later | Better for a growing settings list than omagnet's hand-written 441 line panel [docs: omahop decisions D24] |
| Layout editor (split, dividers, merge, canvas) | `omagnet/LayoutEditor.qml`, `omagnet/LayoutOps.js` | Skip | Edits zone grids. A scene editor shows real windows, not zones. `LayoutThumb.qml` (64 lines) is a good model for a scene thumbnail [source] |
| Named saved items with Apply and Delete | `OmaBarConfigurator/panel/SavedLayoutRow.qml:7` | Adapt | "One saved layout: an editable name, the time, then Apply and Delete" is our scene row [source] |
| Window listing as plain tables, minimized windows mapped back to their workspace | `omahop/lua/omahop.lua:80` to `:105` (`minimized_origin`, `describe`) | **Adapt** (copy) | `local`, not callable. It knows Omarchy's `omarchy-minimized-from-<id>` tag, so a save can include minimized windows [source] |
| Window filters (ignore by class, title fragments) | `omahop/lua/windows.lua:17`, `omahop/lua/rules.lua:5` | Reuse as-is (copy) | Pure [source] |
| App icon for a window class | `omahop/IconResolve.js:65` `resolve`, plus `DesktopEntries.heuristicLookup` (`omahop/Service.qml:290`) | **Reuse as-is** (copy) for the scene list UI | Pure JS with Node tests. Note: it finds icons only. Nothing in omahop finds a launch command for a class [source] |
| Rule "never call hyprctl synchronously from Lua" | omahop decision D14 | Keep | `io.popen("hyprctl binds")` froze the desktop for 5 s [docs: omahop decisions D14, omahop record] |

## Should a scene slot be an omagnet zone?

Three ways to store where a window goes:

| Option | Survives a new resolution or scale | Holds a hand-placed window | Coupled to omagnet | Breaks when |
|---|---|---|---|---|
| Raw pixels | No | Yes | No | Any monitor change |
| **Fractions of the usable area** (same `x y w h` as omagnet's zones) | Yes | Yes | No | Only if the bar or reserve changes a lot (then still close) |
| omagnet zone (layout X, zone 2) | Yes | No | Yes | Layout edited, renamed, deleted, or omagnet removed |

Facts that decide it:

- **Zones have no stable id.** A zone is a position in a list (`omagnet/lua/geometry.lua:293` parses `"x y w h; ..."`).
  A split or merge in the editor renumbers them, so "zone 2" can silently become a different rectangle [source].
- **omagnet does not know which zone a window is in.** FancyZones' "refit on layout change" was left for later because it
  "needs zone membership state" (`omagnet/docs/zones-design.md:24`) [docs]. A save would have to guess the zone from the
  rectangle.
- **Which layout applies is not fixed.** It depends on a key-picked override kept only in memory, then the workspace, then
  the monitor name, then the screen shape (`omagnet/lua/omagnet-snap.lua:221`, `:233` to `:240`) [source].
- Many real windows are not in any zone: placed by hand, or snapped to a Magnet half that is not a zone.

**Recommendation:** store fractions of the usable area, in omagnet's own number format, so the two stay readable side by
side. Optionally keep a `zone` hint ("came from layout coding, zone 2") for display only, never for placement.

What fractions buy: resolution and scale independence, no dependency, and `G.place_frac` already converts them.
What they cost: about 1 px rounding per edge, and a scene saved under a tall bar replays slightly off under a short one.

**Margin trap:** a rectangle read from a live snapped window already has omagnet's margin taken off. Replaying it through
`place_frac` with a margin would take it off twice. Save the window's real rectangle and replay with `margin = 0` [source:
`omagnet/lua/geometry.lua:34` to `:51`].

## Conflicts

| Possible clash | What the code says | Risk | Answer |
|---|---|---|---|
| Both plugins react to `window.open` | omagnet's `window.open` handler only runs `fit_shadow` (`omagnet/lua/omagnet-snap.lua:661`). omahop does not listen to `window.open` at all, only `window.active` and `window.close` (`omahop/lua/omahop.lua:876` to `:877`) [source] | Low | Nothing in our plugins moves a new window. Omarchy core's own placement of a new floating window is the likelier race; that belongs to question 3 |
| omagnet "moves new windows to the last known zone" | Not built. It is FancyZones F44, marked "maybe, last zone memory is extra state" (`omagnet/docs/fancyzones-reference/features.md:99`, `:169`) [docs] | None today | If omagnet ever adds F44 it would fight scene restore. Keep F44 out of omagnet, or let it skip windows that omascenes claims (a window tag such as `omascenes-slot=...`) |
| Stale shadow | `fit_shadow` runs on open, on focus and after an omagnet snap. A window omascenes makes full height after open keeps its shadow over the bar until next focus [source: `:116`, `:661` to `:662`] | Low, cosmetic | After placing, call `_G.omagnet.fit_shadow(win)` if it exists, inside `pcall` |
| omagnet's Restore tag | `M.apply` writes `omagnet-orig=x,y,w,h` on the first snap (`:152` to `:157`) [source] | Medium, if we call `M.apply` | Do not call `M.apply`; use our own copy of `put`. Then omagnet's Restore still means "before the user's first snap" |
| omagnet's ignore list | `on_floating_workspace` returns false for ignored classes (`:86`) [source] | Medium, if we call `M.apply` | Same answer: our own placement code, our own rules |
| omagnet's floating-only guard | Every omagnet action checks the floating tag [source: `:84` to `:90`; docs: `omagnet/docs/ROADMAP.md:19`] | Design question | Placement rules (which workspace and monitor) make sense on tiled workspaces too; exact positions only on floating ones. This is a reason not to live inside omagnet |
| omahop recently-used order | omahop reorders on every `window.active` (`omahop/lua/omahop.lua:876`) [source] | Low | A full restore that focuses many windows scrambles Alt+Tab order. Place without focusing where Hyprland allows it (question 2) |
| Keybinds | omagnet: `CTRL + ALT` with arrows, `U I J K`, `D F G`, `E T`, `C`, `RETURN`, `BACKSPACE`, `[` `]`; `SUPER + CTRL + ALT + LEFT/RIGHT`; `SUPER + SHIFT` drag; its docs suggest `SUPER + CTRL + ALT + 1` for a layout key (`omagnet/docs/config.md:66` to `:78`, `omagnet/lua/config.lua:40`, `omagnet/docs/zones-design.md:55`). omahop: `ALT + TAB`, `ALT + GRAVE` (`omahop/lua/config.lua:65`) [source, docs] | Medium | Ship omascenes with **no default keys**, like omagnet's layout keys. Opening a scene goes through the launcher and an optional per-scene key the user picks. Reuse omahop's "only take a chord the bind snapshot shows free" rule (D14) |
| Two (or four) settings apps | Each plugin has its own panel and launcher entry [source: manifests]. omahop decision D11 says "one settings app for everything" within a plugin [docs] | Low | One more launcher entry is fine. A combined app is not worth the coupling now |
| Monitor workspace blocks | Omarchy keeps ten workspaces per monitor ever seen; virtual monitors in tests pushed real monitors to workspaces 261 and 271 [docs: `docs/omagnet-record-2026-11.md`, item 5] | High for tests | omascenes tests must never create virtual monitors (already in `CLAUDE.md`), and scenes must not store raw workspace numbers alone (question 5) |

## Packaging options

| Option | Pros | Cons |
|---|---|---|
| **A. Separate plugin `omascenes`**, own Lua module and settings panel, copied pure helpers | Private while omagnet is public. Own release pace. Works on tiled workspaces for placement rules. omagnet's marketplace approval is bound to a validated commit, so no new pushes are needed there [docs: `docs/omagnet-record-2026-11.md:56`]. Matches the house pattern: plugins share file contracts, not code (`omagnet/docs/architecture.md:42`) | About 150 lines of copied Lua. A fix in one copy must be carried to the other. A third launcher entry and a third load line in `hyprland.lua` |
| **B. Feature inside omagnet** | Geometry and the settings shell already there. One load line | omagnet is public and scenes start private. omagnet's bar is Magnet, which has no scenes [docs: `omagnet/docs/ROADMAP.md:6`, `omagnet/docs/research/existing-solutions.md:177`]. Its floating-only rule fights placement rules on tiled workspaces. Every change re-opens the marketplace review. omagnet becomes harder to keep small |
| **C. Shared small library** (`geometry.lua` plus `put`) used by both | One copy of the code | No dependency mechanism found in Omarchy plugins: discovery is only `plugins/*/manifest.json` [docs: `docs/omahop-record-2026-11.md`, S1.0; not checked further]. A library means a submodule or vendoring in each public repo, version skew, and a third repo to release. Two consumers do not justify it |

**Recommendation: A.** A separate plugin with a `lua/vendor/geometry.lua` copied from omagnet (only `usable`,
`place_frac`, `logical_size`, `transfer`, with a header naming the omagnet commit it came from), its own `put`, and a
small test that runs the same inputs through omagnet's and omascenes' copies, the same way omagnet cross-checks
`ConfigIO.js` against `config.lua`. Soft link to omagnet only for `fit_shadow`, looked up at use time.

Revisit C when a third plugin needs the same geometry (the workspace "3 uses" rule, applied to code). Revisit B only if
Felipe decides scenes should be public and floating-only.

## What omagnet's roadmap already points at

- **L2, a layout per workspace** (`omagnet/docs/ROADMAP.md:180`, built and tested): the closest existing idea of
  "this desktop has its own arrangement". It stores zones, not windows.
- **Z10, refit on layout change** (`omagnet/docs/ROADMAP.md:173`, not planned) and F43 (`omagnet/docs/zones-design.md:24`):
  needs "which window is in which zone", the same state a scene save needs.
- **F44 and F45, new windows to the last zone or the current monitor** (`omagnet/docs/fancyzones-reference/features.md:99`
  to `:100`, `:169`): "maybe; Hyprland window rules cover monitor placement". This is omascenes goal 1.
- **Saved layouts / window sets**: only Moom has them among the Mac tools surveyed
  (`omagnet/docs/research/existing-solutions.md:177`) [docs]. omagnet left them out.
- Nothing in the roadmap names scenes, sessions or launching apps. omascenes does not overlap planned omagnet work.

## What this means for omascenes

- Store slots as fractions of the usable area of an identified monitor, saved with `margin = 0`. No pixels, no zone ids.
- Copy four pure functions from `omagnet/lua/geometry.lua` and the `put` retry logic; keep a cross-check test.
- Copy omahop's `describe` idea so minimized windows are saved with their home workspace.
- Copy omahop's `IconResolve.js` for icons in the scene list. Launch commands are new work (question 4).
- Do not call `_G.omagnet.apply`. Call `_G.omagnet.fit_shadow` after placing, if omagnet is loaded.
- Tag placed windows (for example `omascenes-slot=<scene>/<n>`) so a future omagnet F44 or omahop can step aside.
- No default keys. Per-scene keys are opt in and checked against a bind snapshot taken by a detached `hyprctl`.
- Store scenes as versioned JSON with omadials' migration pattern; settings can stay in the house TOML style.
- Never run `hyprctl` synchronously from Lua or QML; never create virtual monitors in tests.

## Open questions for Felipe

1. **Where do exact positions apply?**
   (a) Floating workspaces only, like omagnet and omahop. (b) Placement rules (workspace and monitor) everywhere, exact
   positions only on floating workspaces.
   Recommendation: (b). Opening an app on the right desktop is useful on tiled desktops too, and Hyprland tiles the window
   anyway, so there is nothing to break.
2. **Should omascenes talk to omagnet at runtime at all?**
   (a) No link: fully independent, a stale shadow until next focus. (b) A soft link: call `_G.omagnet.fit_shadow` if
   present, and tag windows so omagnet can skip them later.
   Recommendation: (b). Two `pcall` lines, no load-order dependency, and nothing breaks without omagnet.
3. **Public or private when it ships?**
   (a) Stay private, plugin installed from the local repo. (b) Go public like omagnet once the design is reviewed, with a
   scrub test from day one.
   Recommendation: decide at design review, but write the code public-safe now (fixture titles only, scrub test), because
   the demand (`../research.md`, discussions #2123 and #472) is a public audience.
