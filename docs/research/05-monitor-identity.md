# 05. Monitor identity and geometry

Open question 5 of `../research.md`. Written 2026-11-21.
Tags: [tested] ran on this machine, [source] read in code, [docs] read in docs, [search] from GitHub or the web, [memory] from my background knowledge, not re-checked today.

## Summary

1. Name a monitor by what Omarchy already uses: `description` (make, model, serial), plus a `#2` suffix for twins. Never the connector (DP-1) and never the Hyprland id.
2. Omarchy 4.5 already keeps this identity in `~/.local/state/omarchy/monitors/workspaces`. We should read that file, not invent a second registry.
3. The identity is not unique in many cases: the laptop panel here has an empty serial and its description has no serial at all. So a scene stores a small "monitor fingerprint", not one string.
4. Store window rectangles as fractions of the monitor work area (like omagnet zones), plus the pixel size of the last save as a hint.
5. When the saved monitor is missing: match fingerprint, then same role (internal, or same shape and size class), then the focused monitor, then ask. Never fail silently.

## Recommendation table

| Question | Recommendation | Why |
|---|---|---|
| Monitor key | `identity` string = Omarchy's identity (description, `#N` for twins) | Same key as monitor settings and workspace blocks, so we agree with the shell |
| Extra fields saved | make, model, serial (masked in logs), pixel size, scale, transform, internal flag, last connector | Fallback matching needs more than one string |
| Workspace key | Slot 1-10 inside the monitor block, not the global id | Block numbers change, slots do not |
| Position storage | Fractions x, y, w, h of the work area, plus last pixel rect | Survives scale and resolution change |
| Work area | `size/scale`, swap on odd transform, minus `reserved` | Same as omagnet and Omarchy `place()` |
| Missing monitor | Ordered fallback, report which rule fired | See below |
| Re-resolve time | On every monitor add event, not only at load | Dropouts happen mid-session |
| Dock overlay | Ignore by default, one setting later | Dock reserves 0 px |

## 1. What Hyprland gives

[tested] `hyprctl -j monitors` on the Z13 (serial masked, none reported):

- `id` 0, `name` `eDP-1`, `description` `Tianma Microelectronics Ltd. TL134ADXP03`, `make`, `model`, `serial` is the empty string.
- `width` 2560, `height` 1600, `scale` 1.6, `x` 0, `y` 0, `transform` 0, `reserved` [0,25,0,0].

| Field | Stable? | Notes |
|---|---|---|
| `name` (connector) | No | Changes with port. A dock renames connectors between plugs [source: Omarchy comment in monitor-workspaces.lua] |
| `id` | No | Hyprland gives a free id to whichever display turns up next [source: same file] |
| `description` | Mostly | Built from EDID make, model and serial when present. Same text across ports. Twins give the same text. Laptop panels have no serial in it [tested] |
| `make`, `model` | Yes | EDID strings. Some panels give junk: another monitor here shows `Invalid Vendor Codename - RTK 0x2555 0x<serial>` [tested, state file, serial masked] |
| `serial` | When present | Often empty (tested here) or a repeated placeholder on cheap panels [memory] |
| size, scale, transform, x, y | No | The user can change them in the display panel |

EDID serial gaps [memory, widely reported]: some monitors report no serial, some report the same serial on every unit, some change string after a firmware update. Rule: a serial helps only if it is non-empty. Two identical monitors with no serial cannot be told apart by anything stable. The honest answer for twins is "left one and right one" by position.

## 2. How others solve it

| Tool | Identity | Fallback | Notes |
|---|---|---|---|
| Hyprland `monitor = desc:...` | Description text, no connector | None, rule just does not match | [docs] Wiki says use `desc:` so a rule follows the monitor. Prefix `desc:` match [memory] |
| Omarchy 4.5 | Identity = name in `monitors/workspaces`, else description, else connector | Twins get a `#2` suffix | [source: bin/omarchy-hyprland-monitor-identity] Used for workspace blocks and for saved mode, scale, position, transform [source: monitor-settings.lua] |
| kanshi | Output by name, `make model serial` string, or `*` | A profile applies only if all listed outputs are present | [docs, memory] Profile-level matching, no partial fallback |
| shikane | Search by model, vendor, serial, name, or regex | Profiles tried in order | [memory] Same idea as kanshi |
| nwg-displays | Writes `monitors.conf` by connector name | None | [memory] Fragile on docks |
| hyprmoncfg (Z13 plugin, off) | Profiles of monitor rules | Our notes only say it is off [docs: omarchy-z13-tweaks.md line 305] | Not researched further, not needed |
| macOS | Display UUID from EDID vendor, product, serial | Remembers arrangement per set of displays | [memory] Windows are moved to the main display when their display is gone, and come back when it returns |
| Windows | Monitor device path from EDID, remembers per monitor set | Windows go to the primary display | [memory] Remembers positions per topology |

Lessons: (a) key by EDID not port, (b) the saved layout is tied to the set of monitors present, (c) when a monitor is gone, move windows to a fallback and move them back when it returns. Omarchy already does (c) for workspaces.

## 3. The Omarchy 4.5 workspace model

[source] `default/hypr/monitor-workspaces.lua`:

- Each monitor owns a block of ten global workspace ids: laptop 1-10, next monitor 11-20, and so on. Super+3 means "slot 3 of the focused monitor's block".
- The block belongs to the identity, kept in `~/.local/state/omarchy/monitors/workspaces` (tab separated: block, connector while plugged, identity) [tested, read on this machine: 3 lines, block 0 is the laptop, 1 and 2 are external monitors currently unplugged].
- When a monitor is unplugged, its workspaces join another block after its own. A second file, `workspaces-merged`, remembers where each came from so it goes back under its old number.
- Note: omagnet's gotcha says the file is `~/.local/state/omarchy/monitor-workspaces`. It is now under `monitors/workspaces` [tested]. The omagnet note is stale.
- Every monitor ever seen keeps its block forever, headless ones too [omagnet gotchas].

Known bugs [search, gh api]:

- #16328: after a 2 second dropout (nvidia-modeset trigger) workspaces 1,2,3 become 3,4,5 and the record of origin is dropped, so the shift is permanent. Omarchy 4.5.0rc1.
- #17759: Super+number now means the focused monitor's local slot. Users who had global workspace rules and a custom workspace widget lost their workflow. Three monitors, scale 1.25, one rotated.
- #17647 (discussion, not readable with the issues API, 404): 25 up in our earlier survey. Not read in detail. Open question.

What this means: a global workspace id is not a safe scene key. After a dropout, the user's "workspace 1" may be id 3 or id 13. Save (monitor identity, slot 1-10). On restore, find the block for that identity from the state file, then the global id is `block*10 + slot`. If the bug has shifted the windows, a scene restore can also act as a repair, because it places apps by slot.

Caveat: slot to id math is [source] from the header comment and my reading of the first 150 lines; the exact helper name was not read. Check the rest of the file before coding.

## 4. Storing positions

Reuse [tested, omagnet hyprland-capabilities.md section 1]:

- Dispatchers take integers, logical pixels, global layout coordinates. No percent. Resize first, then move (resize is center-anchored). No clamping by Hyprland, so we must clamp.
- Work area: logical size `width/scale` (swap when `transform % 2 == 1`), minus `reserved`. Origin is `monitor.x + reserved.left`, `monitor.y + reserved.top`. Here that is a 25 px top bar [tested today, reserved [0,25,0,0]].
- Dock reserves 0 px (`exclusiveZone: 0`) [source, omagnet]. Overlap is accepted by default.
- Fractional scale: use `math.floor`. `%d` rejects non-integers [omagnet gotchas].
- `move` in a window rule is relative to the monitor, not the layout [omagnet gotchas]. Dispatcher `move` is global. Do not mix them.
- omagnet already stores zones as fractions `x y w h` per monitor [omagnet zones-design.md]. Same format here, so one parser can serve both.

Absolute pixels versus fractions:

| | Pros | Cons |
|---|---|---|
| Absolute logical px | Exact restore on the same setup | Breaks on a new monitor, new scale, rotation |
| Fractions of work area | Survives any resolution, scale, bar height | Rounding, app minimum sizes, aspect ratio changes |
| Both | Fraction is the truth, px is a hint to check "same setup" | Slightly bigger file |

Recommendation: save both. On restore, if monitor fingerprint, scale, transform and work area size are all equal, use the saved px (exact). Otherwise use fractions. Rotation: fractions are of the rotated work area, so a scene saved landscape and restored portrait stretches. Treat a transform change as "different shape" and warn, do not guess.

App sizes: some apps snap to a cell grid (kitty rounds, [tested in omagnet]). Restore may be off by a few pixels. Accept.

## 5. Fallback when the saved monitor is missing

Order, stop at the first hit. Always tell the user which one fired.

1. Exact identity match (including `#N`).
2. Same make and model, serial different (a replacement unit, or a work and home pair of the same model).
3. Same role: saved monitor was internal (name starts `eDP`, `LVDS`, `DSI`, as Omarchy's `internal()` does [source]) and an internal one exists.
4. Same shape class: same orientation and a size within about 15 percent. Fractions make this easy to accept.
5. The focused monitor.
6. Ask the user (a prompt in the scene picker), with "always do this for this monitor" remembered.

Two scenes for different monitors that both fall to the same target: do not stack them. Apply only the one the user picked.

Monitor dropout while a scene is open: Omarchy and Hyprland move windows themselves. We should not fight that. Rule: scenes act only on a user action (restore) or at login, never reactively on a monitor event. A dropout then only matters for the next restore, not for a live one.

## What this means for omascenes

- Scene file schema gets a `monitor` block: `identity`, `make`, `model`, `serial_hash` (hash, never the raw serial in logs or git), `internal`, `px_size`, `scale`, `transform`, `slot`. Windows get `x y w h` fractions plus last px.
- Do not build a second identity system. Read Omarchy's `monitors/workspaces` file and the `omarchy-hyprland-monitor-identity` script behavior [source]. That keeps us aligned if upstream fixes #16328.
- Treat slot (1-10) as the workspace key and resolve to a global id at restore time. This is also the answer to renumbering.
- Resolve monitors at restore time only, with the fallback list in section 5.
- Session restore after reboot should wait until the monitors are all present (poll `hl.get_monitors()`, bounded rounds, then fall back), because docked monitors appear late.
- Test fixtures: made-up identities and serials only. Never real serials in the doc, repo or logs. The real state file has two real monitor serials, so never copy it into fixtures.
- Multi-monitor and rotated behavior is still from source and docs only. Only one real monitor was connected for this research. Live tests need the real second monitor (no virtual monitors on this machine, per project rules).

## Open questions left

1. Exact slot to id function in `monitor-workspaces.lua` (read past line 150). Does a public Lua function exist, or only the state file?
2. Discussion #17647 content. Is a fix planned for dropout renumbering (#16328)?
3. Do twin monitors with no serial keep the same `#N` after a reboot? Omarchy assigns it by order of appearance, so the order may flip.
4. Does the laptop description change between the Z13 and the X1C for the same model? Different laptops mean a different identity, so a scene from one laptop falls to the "internal" rule on the other. Is that what we want, or should "internal" be saved as a role instead of an identity?
5. Hyprland 0.57 `monitor added` and `monitor removed` events: do they fire during a brief dropout, and in what order? Needed for the login wait. Not tested.
6. Should the dock overlay be subtracted by default? Decide with the omagnet answer.
7. Fraction rounding with app minimum sizes: clamp to the work area only, or also shift the window to fit?
