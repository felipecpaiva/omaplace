# omaplace branding

**Chosen direction: [v1-plan](explorations/v1-plan/), picked on 2026-11-21.** A monitor drawn as a desktop plan: one
tall zone and two stacked zones on a short stand, the lower right zone filled by an app that has landed, in azure and
inset from its zone. The kit below is built from it; the mark is unchanged from the exploration. Read
[BRIEF.md](BRIEF.md) for what the brand must say.

## The kit

| Folder or file | What is in it | Made by |
|----------------|---------------|---------|
| `logo/` | `icon.svg` (master: the mark on a graphite tile) and `icon-{1024,512,256,192,180,128,64}.png`; `icon-small.svg` (the mark on its native 16 grid) and `icon-{48,32,16}.png`; `favicon.ico` (16, 32, 48); `glyph.svg` and `glyph-light.svg` (transparent, for dark and light grounds) with 512 PNGs; `stencil.svg` and `stencil-white.svg` (one colour) with 512 PNGs | `tools/logo.py` |
| `logo/` | `wordmark.svg` and `lockup.svg` (transparent, for dark grounds), `wordmark-light.svg` and `lockup-light.svg` (transparent, for light grounds), `wordmark-on-dark.svg`, `wordmark-on-paper.svg`, `lockup-on-dark.svg`, `lockup-on-paper.svg` (with their ground), and a PNG of each | `tools/kit.py` |
| `social/` | `github-social-preview.png` (1280 by 640), `banner-dark.png` and `banner-light.png` (1600 by 400, README banner), `card-wide.png` and `card-wide-light.png` (1200 by 630), `card-square.png` (1080), `card-x.png` (1600 by 900), `card-linkedin.png` (1200 by 627), `avatar-400.png` | `tools/social.py` |
| `../preview.png` | Marketplace preview, 1280 by 640 like omagnet's and omahop's: lockup, tagline and the settings window (from `docs/media/desktops-page.png`, a clean crop with no private content) | `tools/social.py` |
| `terminal/` | `banner.txt` (plain half-block "omaplace" and the tagline), `banner.ansi` (the same in azure), and the `lettering.svg`/`.png` they are traced from | `tools/terminal.py` |
| `brand-sheet.html`, `brand-sheet.png` | Palette with computed WCAG contrast ratios, type, spacing, do and do not | `tools/sheet.py` |

Tagline: **Every app in its zone.** Sub line: Placement rules, desktop plans, named scenes and session restore for Omarchy.

Palette: graphite `#16181d`, near white `#f4f5f7` (the mark), azure `#5aa9ff` (the landed app, on dark), paper
`#f4f3f0` (light ground), and **azure deep `#1f5fae`** for light grounds, because azure is only 2.21:1 on paper.

| Pair | WCAG ratio |
|------|-----------:|
| Azure `#5aa9ff` on graphite | 7.23:1 |
| Azure deep `#1f5fae` on paper | 5.72:1 |
| Near white on graphite | 16.28:1 |
| Graphite on paper | 16.00:1 |
| Muted `#9a9eb0` on graphite | 6.67:1 |
| Muted light `#5b5f6e` on paper | 5.72:1 |
| Azure on paper | 2.21:1, do not use |

### Launcher icon

`omaplace.desktop` names `Icon=omaplace`, like OmaBar's `Icon=omabar`. The icon file is `logo/icon-256.png`, and it
must be installed under that name:

```
install -Dm644 branding/logo/icon-256.png ~/.local/share/icons/hicolor/256x256/apps/omaplace.png
```

### Rebuild

```
python3 -B branding/tools/logo.py      # logo set and favicon (rsvg-convert, ImageMagick)
python3 -B branding/tools/kit.py       # wordmark and lockups
python3 -B branding/tools/social.py    # social images and ../preview.png (headless Chromium)
python3 -B branding/tools/sheet.py     # brand sheet (headless Chromium)
python3 -B branding/tools/terminal.py  # terminal banners (Pillow)
```

`tools/wordmark.py` holds the shared parts: the mark geometry, the palette, contrast, the outlined JetBrains Mono Bold
lettering (fontTools, so no SVG needs the font) and the Chromium helper. `logo.py`, `kit.py`, `social.py` and
`sheet.py` were copied from OmaBar's kit and `terminal.py` from omadials', then adapted; each names its source in its
header. Social images and the brand sheet are headless Chromium screenshots with a throwaway profile in a temp folder.
Needs `rsvg-convert`, `magick`, `chromium`, Python with fontTools and Pillow, and JetBrains Mono Nerd Font installed.

## The three explorations (record)

Three logo directions made on 2026-11-21, kept as history. [board.png](board.png) shows them side by side.

| Folder | Idea |
|--------|------|
| [v1-plan](explorations/v1-plan/) | A monitor drawn as a desktop plan of unequal zones, one zone filled by a landed app. Azure. **Picked.** |
| [v2-pin](explorations/v2-pin/) | A map pin with a window cut into its head, landing on a slot. Lime. |
| [v3-drop](explorations/v3-drop/) | Three desktop slots, the middle app dropped into its own. Orchid. |

Rebuild them with `python3 -B branding/tools/build.py && python3 -B branding/tools/board.py`.

## Review

Every rendered image was checked by eye: the icon at 1024 down to 16 px (16, 32 and 48 enlarged without smoothing),
glyphs and stencils, all wordmarks and lockups, every social image, the preview and the brand sheet. The landed app
stays a separate block at 16 px in one colour. The GitHub social preview is under 1 MB. No text file under `branding/`
contains an em dash or en dash.

## Licence

Original artwork made for this project and released under the project's MIT licence unless the maintainer chooses
otherwise. omaplace is not affiliated with or endorsed by Omarchy. JetBrains Mono is an open-source typeface under the
SIL Open Font License; the wordmarks contain outlines only.
