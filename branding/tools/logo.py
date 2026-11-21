#!/usr/bin/env python3
"""Build the omaplace logo set (the v1-plan mark) into branding/logo/: app icon on a graphite tile, a small-size icon,
transparent glyphs for dark and light grounds, one-colour stencils, PNG exports and favicon.ico.
Copied from OmaBarConfigurator/branding/tools/logo.py (2026-11-21) and adapted for omaplace: v1-plan mark, azure.
Usage: python3 -B branding/tools/logo.py   (needs rsvg-convert, ImageMagick and fontTools)"""
from wordmark import *
LOGO.mkdir(exist_ok=True)
def write(name,text): (LOGO/name).write_text(text)
tile=rect(0,0,16,16,3.5,BG)

# large icon: the mark inset to 75% so it breathes inside the tile
write('icon.svg',svg(tile+f'<g transform="translate(2 2) scale(0.75)">{plan(WHITE,ACCENT)}</g>',512,512,'0 0 16 16'))
# small icon: the mark on its native 16 grid, so every edge lands on a pixel at 16, 32 and 48 px
write('icon-small.svg',svg(tile+plan(WHITE,ACCENT),512,512,'0 0 16 16'))
write('glyph.svg',svg(plan(WHITE,ACCENT),512,512,'0 0 16 16'))       # on dark grounds
write('glyph-light.svg',svg(plan(BG,DEEP),512,512,'0 0 16 16'))      # on light grounds
write('stencil.svg',svg(plan(BG,BG),512,512,'0 0 16 16'))            # one colour, for light grounds
write('stencil-white.svg',svg(plan(WHITE,WHITE),512,512,'0 0 16 16'))  # one colour, for dark grounds

for s in (1024,512,256,192,180,128,64): png(LOGO/'icon.svg',LOGO/f'icon-{s}.png',s,s)
for s in (48,32,16): png(LOGO/'icon-small.svg',LOGO/f'icon-{s}.png',s,s)
for n in ('glyph','glyph-light','stencil','stencil-white'): png(LOGO/f'{n}.svg',LOGO/f'{n}-512.png',512,512)
subprocess.run(['magick',*(str(LOGO/f'icon-{s}.png') for s in (16,32,48)),str(LOGO/'favicon.ico')],check=True)
print('logo set written to logo/')
