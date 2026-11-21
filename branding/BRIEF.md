# omaplace brand brief

The brief behind every logo variation. Written 2026-11-21, before the explorations were judged, so they can be
judged against it and not against taste alone. Same shape as the omagnet, OmaBar and omadials briefs.

## What the project is, in one line

Saved desktop scenes for Omarchy: say which desktop and monitor each app opens on, plan a desktop as zones, save and
reopen named scenes, and restore the whole session after a reboot.

## Who it is for

Omarchy users with several desktops and monitors who want every app back where it belongs without dragging windows
around each morning. Terminal-comfortable people who judge a project by its logo and its first screenshot in a few
seconds.

## What the brand has to say

1. **Everything lands in its place.** Apps open where you put them, every time.
2. **A plan, not a mess.** A desktop is a layout of zones; each app has its slot.
3. **At home on Omarchy.** Looks like it belongs beside Omarchy's own apps and themes, without pretending to be
   official.
4. **Small and precise.** Sibling of omagnet, omahop, OmaBar and omadials by the same maker.

## Name

`omaplace`, all lower case, like omagnet, omahop and omadials. `oma` is the community's Omarchy prefix; `place` is
what it does to every window. Say it "oh-ma-place". Plugin id: `io.github.felipecpaiva.omaplace`.

## The idea to draw from

Apps landing in their place: a desktop drawn as a grid of zones with one zone filled, a pin or target marking where
an app goes, or a row of slots with one app dropping into its own.

## References, and what not to take from them

| Reference | What to learn from it | What must NOT be copied |
|-----------|----------------------|-------------------------|
| **Omarchy** (`/usr/share/omarchy/logo.svg`, `icon.png`) | Chunky blocks, one bright colour on a plain ground, monospace. | Its logo or icon, or anything that reads as an official Omarchy mark. Omarchy has not endorsed this project. |
| **Map pins, floor plans, window layout tools** | The idea of a marked place and a planned layout. | Any vendor's icon, name or styling. |
| **Family** (`../../omagnet/branding/`, `../../omahop/branding/`, `../../OmaBarConfigurator/branding/`, `../../omadials/branding/`) | Graphite ground `#16181d`, one accent, JetBrains Mono Bold, SVG on a 16 grid, works at 16 px. | Their marks: omagnet is a square ring of four corner pieces, omahop two tiles under an arc, OmaBar pills on a rail, omadials a corner frame with arcs. omaplace needs its own silhouette. |

Taken accents: omagnet violet `#8b7bff`, OmaBar mint `#5cdbc0`, omahop citrus `#ffc83d` (on `#1a1812`), omadials coral
`#ff8c78`. omaplace's accent must be clearly different from all four.

Names appear only as plain text, with the disclaimer: not affiliated with or endorsed by Omarchy.

## Directions to explore (3)

- **v1-plan:** a monitor showing a desktop plan of unequal zones, one zone filled by a landed app. The product,
  simplified.
- **v2-pin:** a map pin with a window in its head, landing on a slot. "This app goes here."
- **v3-drop:** a row of desktop slots, one app dropped into its own. The motion of placing.

## Constraints every variation must meet

- **Works small.** Readable at 16 and 32 pixels, in one colour. Filled shapes on whole grid units, gaps of at least
  1 unit; the landed element differs by shape, not only by colour.
- **Mono-friendly.** The idea survives as a one-colour stencil, graphite on light and near white on dark.
- **Works on light and dark.** The accent passes WCAG contrast on graphite; a deep accent passes 4.5:1 on paper
  `#f4f3f0` for light grounds (Omarchy themes "White" and "Tokyo Night").
- **No gradients needed.** The mark stands without gradient, shadow or glow.
- **Vector first.** A real SVG source for the icon and the wordmark; PNG exports come from it.
- **Own idea.** Different from Omarchy's and every sibling's mark at a glance, even as a thumbnail.
- **Text rules.** No em dash or en dash anywhere; plain English.
- **Licence.** Made for this project; released under the project's MIT licence unless the maintainer chooses otherwise.

## Deliverables for the chosen variation (the full kit, after the pick)

1. Icon: `icon.svg`, PNG at 1024, 512, 256, 128, 64, 32, 16; one-colour light and dark; a monochrome mask.
2. Wordmark and horizontal lockup, on light, dark and transparent.
3. GitHub social preview, 1280 by 640, under 1 MB.
4. README banner with the tagline.
5. Marketplace `preview.png` at the repo root.
6. Terminal banner in plain text (half-block letters).
7. Demo GIFs per feature, screenshots of the settings window.
8. One-page brand sheet: palette with contrast ratios, type, spacing, do and do not.

## Where things are now

- `explorations/v1-plan`, `v2-pin`, `v3-drop`: icon (dark, light, mono, mono dark), PNG at 512, 64, 32, 16, wordmark,
  lockup, a 1024 px `concept.png` and `notes.md` each.
- `board.html` and `board.png`: the three side by side at 512, 64 and 16 px on dark and light, with accent hex and
  contrast ratios, and the taken family accents.
- `tools/`: `wordmark.py` (marks, palette, contrast, lettering), `build.py`, `board.py`, copied from omadials and
  adapted. Rebuild with `python3 -B branding/tools/build.py && python3 -B branding/tools/board.py`. Needs
  `rsvg-convert`, `chromium`, Python with fontTools and JetBrains Mono Nerd Font.
