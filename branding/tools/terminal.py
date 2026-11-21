#!/usr/bin/env python3
"""Write branding/terminal/banner.txt (plain half-block "omaplace" and the tagline) and banner.ansi (the same in azure).
Copied from omadials/branding/tools/terminal.py (2026-11-21) and adapted for omaplace: 16 px rows for the p descender.
The lettering is outlined JetBrains Mono Bold rasterised by librsvg, then encoded two pixel rows per text line.
Usage: python3 -B branding/tools/terminal.py   (needs Pillow)"""
from wordmark import *
from PIL import Image
out=ROOT/'terminal'; out.mkdir(exist_ok=True)
W,H=68,16
(out/'lettering.svg').write_text(svg(lettering(NAME,0,11,14,'#ffffff'),W,H))
png(out/'lettering.svg',out/'lettering.png')
im=Image.open(out/'lettering.png').convert('RGBA')
lines=[]
for y in range(0,H,2):
    a=lambda x,yy: im.getpixel((x,yy))[3]>=100
    lines.append(''.join(' ▀▄█'[int(a(x,y))+2*int(a(x,y+1))] for x in range(W)).rstrip())
while lines and not lines[-1]: lines.pop()
plain='\n'.join(lines)+f'\n\n{TAG}\n'
(out/'banner.txt').write_text(plain)
(out/'banner.ansi').write_text('\x1b[38;2;90;169;255m'+plain+'\x1b[0m\n')   # #5aa9ff as truecolor
print(plain)
