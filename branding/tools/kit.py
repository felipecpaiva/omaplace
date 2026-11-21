#!/usr/bin/env python3
"""Build the wordmark and lockups (SVG and PNG) into branding/logo/: transparent for dark grounds, transparent for light
grounds (-light), and on their own ground (-on-dark, -on-paper). Same geometry as explorations/v1-plan.
Copied from OmaBarConfigurator/branding/tools/kit.py (2026-11-21), with the -on-dark and -on-paper files from
omadials/branding/tools/kit.py. Usage: python3 -B branding/tools/kit.py (run logo.py first)"""
from wordmark import *
LOGO.mkdir(exist_ok=True)
W=round(len(NAME)*50.4+16)  # JetBrains Mono advance is 0.6 em at 84 px
def word(ink): return lettering(NAME,8,74,84,ink)
def lock(ink,accent): return f'<g transform="scale(6)">{plan(ink,accent)}</g>'+lettering(NAME,116,74,84,ink)
parts={'wordmark':(W,word(WHITE),word(BG)),'lockup':(W+108,lock(WHITE,ACCENT),lock(BG,DEEP))}
for kind,(w,dark,light) in parts.items():
    files={f'{kind}.svg':svg(dark,w,96),                         # transparent, for dark grounds
           f'{kind}-light.svg':svg(light,w,96),                  # transparent, for light grounds
           f'{kind}-on-dark.svg':svg(rect(0,0,w+48,144,0,BG)+f'<g transform="translate(24 24)">{dark}</g>',w+48,144),
           f'{kind}-on-paper.svg':svg(rect(0,0,w+48,144,0,PAPER)+f'<g transform="translate(24 24)">{light}</g>',w+48,144)}
    for name,text in files.items():
        (LOGO/name).write_text(text)
        png(LOGO/name,LOGO/(name[:-4]+'.png'),h=256 if 'lockup' in name else 192)
print('wordmark and lockups written to logo/')
