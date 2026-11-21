#!/usr/bin/env python3
"""Shared omaplace vector geometry, palette, contrast and outlined JetBrains Mono Bold lettering.
Copied from omadials/branding/tools/wordmark.py (2026-11-21) and adapted for omaplace: new marks and accents."""
from pathlib import Path
import subprocess, sys
sys.dont_write_bytecode = True
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
ROOT = Path(__file__).resolve().parents[1]
FONT = Path('/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf')
BG, WHITE, PAPER = '#16181d', '#f4f5f7', '#f4f3f0'
NAME = 'omaplace'
# Accents already used by the family; the board shows them so a new accent can be judged against them.
FAMILY = [('omagnet', '#8b7bff'), ('OmaBar', '#5cdbc0'), ('omahop', '#ffc83d'), ('omadials', '#ff8c78')]
font = TTFont(FONT)
glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
def svg(body,w,h,view=None):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{view or f"0 0 {w} {h}"}">{body}</svg>\n'
def lettering(text,x,baseline,size,fill):
    scale=size/font['head'].unitsPerEm
    paths=[]
    for ch in text:
        g=glyphs[cmap[ord(ch)]]; pen=SVGPathPen(glyphs); g.draw(pen)
        paths.append(f'<path d="{pen.getCommands()}" transform="translate({x:g} {baseline:g}) scale({scale:g} {-scale:g})"/>')
        x+=g.width*scale
    return f'<g fill="{fill}">'+''.join(paths)+'</g>'
def rect(x,y,w,h,r,c):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{c}"/>'
def path(d,c,width):
    return f'<path d="{d}" fill="none" stroke="{c}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>'
def mark(kind,main,accent):
    if kind=='plan':
        # A monitor holding a desktop plan: one tall zone, two stacked zones, the lower one landed (accent, inset
        # so it differs by shape too), and a stand.
        return (rect(1,2,7,10,1,main)+rect(9,2,6,4,1,main)+rect(10,8,4,3,0.75,accent)
          +rect(5,13,6,2,1,main))
    if kind=='pin':
        # A map pin with a window cut into its head, landing on a slot.
        return (f'<path fill="{accent}" fill-rule="evenodd" d="M8 12L4.8 9.35A5 5 0 1 1 11.2 9.35ZM5 4H11V7H5Z"/>'
          +rect(3,13,10,2,1,main))
    # drop: three desktop slots; the middle app has dropped into its slot, lower than its neighbours, with a chevron.
    return (rect(1,4,4,10,1,main)+rect(11,4,4,10,1,main)+rect(6,8,4,6,1,accent)
       +path('M6.5 3L8 4.5L9.5 3',accent,1.4))
def png(src,out,w=None,h=None):
    subprocess.run(['rsvg-convert']+(['-w',str(w)] if w else [])+(['-h',str(h)] if h else [])+['-o',str(out),str(src)],check=True)
def luminance(h):
    rgb=[int(h[i:i+2],16)/255 for i in (1,3,5)]
    return sum(c*w for c,w in zip([v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb],[.2126,.7152,.0722]))
def contrast(a,b):
    x,y=sorted([luminance(a),luminance(b)])
    return (y+.05)/(x+.05)
DIRECTIONS=[
 dict(folder='v1-plan',kind='plan',accent='#5aa9ff',deep='#1f5fae',title='The desktop plan',tag='Every app in its zone.',
  idea='A monitor drawn as a desktop plan: one tall zone and two stacked zones, on a short stand. The lower right zone is filled by an app that has landed, in azure and inset from its zone.',
  differs='Unequal zones on a monitor stand, not a square ring of four equal quarters (omagnet), two tiles under an arc (omahop), pills on a rail (OmaBar) or a corner frame with arcs (omadials).',
  small='All shapes sit on whole units with 1 unit gaps. The landed zone is inset by 1 unit on every side, so it reads as a separate block even in one colour.'),
 dict(folder='v2-pin',kind='pin',accent='#a6e05a',deep='#4a7a12',title='Lands here',tag='Pinned to its place.',
  idea='A map pin with a small window cut into its head, its point landing on a slot. The pin is the app and the slot is where it goes. Lime pin, near white slot.',
  differs='A single teardrop pin above a bar. No grid, no tiles, no arcs, no corner frame. Nothing in the family uses a pin or a cut-out window.',
  small='The head is 10 units wide and the window hole is 6 by 3, so the cut-out stays open at 16 px. A 1 unit gap separates the pin point from the slot.'),
 dict(folder='v3-drop',kind='drop',accent='#f27fd8',deep='#a02b88',title='Drop into the slot',tag='Back where it belongs.',
  idea='Three desktop slots side by side. The middle app has dropped into its slot, sitting lower than its neighbours, with a small chevron above that shows the motion. Orchid accent.',
  differs='Three upright columns with one lowered, not horizontal pills (OmaBar), a square ring (omagnet), two square tiles (omahop) or arcs (omadials).',
  small='Columns are 4 units wide with 1 unit gaps. The lowered middle column changes the silhouette, so the idea survives in one colour. The chevron is a 1.4 unit stroke.')]
