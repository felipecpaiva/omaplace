#!/usr/bin/env python3
"""Build the comparison board: branding/board.html and branding/board.png (headless Chromium).
Copied from omadials/branding/tools/board.py (2026-11-21) and adapted for omaplace: 512, 64 and 16 px on dark and
light grounds, accent hex and contrast per concept, a strip of family accents. Chromium uses a throwaway profile in a
temp folder, so nothing lands in the repo. No librsvg fallback: if Chromium fails, the script says so and stops.
Usage: python3 -B branding/tools/board.py (run build.py first)"""
from wordmark import *
import os, tempfile
H=2300
css='''*{box-sizing:border-box}body{margin:32px;background:#f4f3f0;color:#16181d;font:16px/1.5 'JetBrains Mono',monospace}
h1{margin:0}main{display:grid;grid-template-columns:repeat(3,584px);gap:22px}article{background:white;border-radius:14px;padding:20px}
h2{font-size:24px;margin:0}figure{margin:16px 0;padding:16px;border-radius:10px}img{display:block}.px{image-rendering:pixelated}
.dark{background:#16181d;color:#f4f5f7}.light{background:#f4f3f0;border:1px solid #e3e1db}.row{display:flex;align-items:flex-end;gap:28px}
.swatch{width:96px;height:36px;border-radius:5px}small{font-size:13px}.fam{display:flex;gap:18px;margin:8px 0 24px}'''
parts=[f'<!doctype html><html lang="en"><meta charset="utf-8"><title>omaplace / three explorations</title><style>{css}</style>',
       f'<h1>{NAME} / three explorations</h1><p>Apps land in their place. Original vectors on a 16 px grid. Pick one; the full kit is built from it.</p>',
       '<div class="fam">'+''.join(f'<div><div class="swatch" style="background:{c}"></div><small>{n} {c} (taken)</small></div>' for n,c in FAMILY)+'</div><main>']
for v in DIRECTIONS:
    p='explorations/'+v['folder']; a,b=contrast(v['accent'],BG),contrast(v['deep'],PAPER)
    parts.append(f'<article><h2>{v["folder"]}</h2><p><b>{v["title"]}.</b> {v["idea"]}</p>')
    for bg,icon in (('dark','icon'),('light','icon-light')):
        parts.append(f'<figure class="{bg}"><img src="{p}/{icon}.svg" width="512" height="512"><div class="row" style="margin-top:12px">')
        parts.append(f'<div><img src="{p}/{icon}-64.png" width="64" height="64"><small>64 px</small></div>')
        parts.append(f'<div><img src="{p}/{icon}-16.png" width="16" height="16"><small>16 px</small></div>')
        parts.append(f'<div><img class="px" src="{p}/{icon}-16.png" width="64" height="64"><small>16 px, 4x</small></div>')
        parts.append(f'<div><img src="{p}/icon-mono{"-dark" if bg=="dark" else ""}.svg" width="64" height="64"><small>one colour</small></div>')
        parts.append(f'</div><small>{bg} ground / 512 px vector above</small></figure>')
    parts.append('<div class="row" style="gap:10px">')
    for c in (v['accent'],v['deep']): parts.append(f'<div><div class="swatch" style="background:{c}"></div><small>{c}</small></div>')
    parts.append(f'</div><p>Accent {v["accent"]} on graphite {BG}: <b>{a:.2f}:1</b><br>Deep {v["deep"]} on paper {PAPER}: <b>{b:.2f}:1</b></p>')
    parts.append(f'<img src="{p}/lockup.svg" style="background:#16181d;padding:10px;border-radius:8px;width:100%"><img src="{p}/lockup-light.svg" style="padding:10px;width:100%"></article>')
parts.append('</main><p>Independent project. Not affiliated with or endorsed by Omarchy.</p></html>')
(ROOT/'board.html').write_text('\n'.join(parts))
with tempfile.TemporaryDirectory() as tmp:
    env=dict(os.environ,XDG_CACHE_HOME=tmp,XDG_CONFIG_HOME=tmp)
    r=subprocess.run(['chromium','--headless','--disable-gpu','--no-sandbox','--disable-crash-reporter','--hide-scrollbars',
        f'--user-data-dir={tmp}/profile',f'--window-size=1860,{H}',f'--screenshot={ROOT}/board.png','file://'+str(ROOT/'board.html')],
        capture_output=True,timeout=60,env=env)
if r.returncode: raise SystemExit('Chromium failed:\n'+r.stderr.decode()[-2000:])
print('board.html and board.png written')
