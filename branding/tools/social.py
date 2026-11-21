#!/usr/bin/env python3
"""Render the social images into branding/social/ and the marketplace preview.png at the repo root, with headless Chromium.
Copied from OmaBarConfigurator/branding/tools/social.py (2026-11-21) and adapted for omaplace: a strip of desktop plans
in place of the pill bar, and a preview that shows the settings window (docs/media/desktops-page.png, a clean crop with
no private content) like omahop's. Run logo.py and kit.py first. Usage: python3 -B branding/tools/social.py"""
from wordmark import *
import base64
S=ROOT/'social'
THEMES={
  'dark': dict(bg=BG,fg=WHITE,mute=MUTE,lockup='lockup.svg',desk=PANEL,zone='#3a3e48',app=ACCENT,stand='#3a3e48'),
  'light':dict(bg=PAPER,fg=BG,mute=MUTE_LIGHT,lockup='lockup-light.svg',desk=CHIP_LIGHT,zone='#c9c6bf',app=DEEP,stand='#c9c6bf'),
}

def plans(t):
    """Three desktops, each drawn as a plan of zones on a stand. One app (accent) has landed in each, inset in its zone."""
    def desk(x0,zones,landed):
        out=rect(x0,0,192,120,10,t['desk'])
        for i,(x,y,w,h) in enumerate(zones):
            out+=rect(x0+x,y,w,h,6,t['app'] if i==landed else t['zone'])
        return out+rect(x0+66,130,60,12,6,t['stand'])
    body=(desk(0,[(10,10,84,100),(102,10,80,100)],1)
          +desk(224,[(10,10,84,100),(102,10,80,44),(108,62,68,42)],2)   # the mark's own plan
          +desk(448,[(10,10,172,100)],0))
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 142">{body}</svg>'

def page(w,h,th,layout):
    t=THEMES[th]; lk=(LOGO/t['lockup']).read_text()
    k={'wide':(0.20,0.068,0.034),'square':(0.13,0.05,0.028),'banner':(0.24,0.085,0.05)}[layout]
    art=f'<div class="art">{plans(t)}</div>'
    url='' if layout=='banner' else f'<div class="url">{URL}</div>'
    # the banner puts the plans beside the text, so the wide strip has no empty right half
    banner_css=('<style>body{flex-direction:row!important;align-items:center;justify-content:space-between}'
                '.art{margin:0!important} .art svg{width:440px!important} .sub{max-width:none!important;white-space:nowrap;font-size:19px!important}</style>')
    return f"""<!doctype html><meta charset="utf-8"><style>
*{{box-sizing:border-box;margin:0}}
body{{width:{w}px;height:{h}px;background:{t['bg']};color:{t['fg']};font-family:'JetBrainsMono Nerd Font','JetBrains Mono',monospace;
 display:flex;flex-direction:column;justify-content:center;padding:0 {int(w*0.08)}px;gap:{int(h*0.035)}px;overflow:hidden;position:relative}}
.lk svg{{height:{int(h*k[0])}px;width:auto;display:block;margin-bottom:{int(h*0.015)}px}}
.tag{{font-size:{int(h*k[1])}px;font-weight:700;line-height:1.2}}
.sub{{font-size:{int(h*k[2])}px;color:{t['mute']};line-height:1.4;max-width:{int(w*0.84)}px;text-wrap:balance}}
.col{{display:flex;flex-direction:column;gap:{int(h*0.035)}px}} .art{{margin-top:{int(h*0.03)}px}} .art svg{{width:{int(min(w*0.6,640))}px;display:block}}
.url{{position:absolute;right:{int(w*0.04)}px;bottom:{int(h*0.05)}px;font-size:{max(16,int(h*0.026))}px;color:{t['mute']}}}
</style>{banner_css if layout=='banner' else ''}<div class="col"><div class="lk">{lk}</div><div class="tag">{TAG}</div><div class="sub">{SUB}</div></div>{art}{url}"""

def make(name,w,h,th,layout='wide'):
    shot(page(w,h,th,layout),S/name,w,h); print(name)

def preview(w=1280,h=640):
    """Marketplace preview, 1280 by 640 like omagnet's and omahop's: lockup and tagline beside the
    settings window, cropped to its top (the rest of the page is empty)."""
    t=THEMES['dark']; lk=(LOGO/t['lockup']).read_text()
    shotb64=base64.b64encode((ROOT.parent/'docs/media/desktops-page.png').read_bytes()).decode()
    html=f"""<!doctype html><meta charset="utf-8"><style>*{{box-sizing:border-box;margin:0}}
body{{width:{w}px;height:{h}px;background:{t['bg']};color:{t['fg']};font-family:'JetBrainsMono Nerd Font',monospace;
 display:flex;align-items:center;justify-content:space-between;padding:0 64px;overflow:hidden}}
.col{{display:flex;flex-direction:column;gap:22px;width:520px}} .lk svg{{height:64px;width:auto;display:block;margin-bottom:28px}}
.tag{{font-size:38px;font-weight:700;line-height:1.25}} .sub{{font-size:19px;color:{t['mute']};line-height:1.5}}
.win{{width:620px;height:372px;border-radius:12px;border:2px solid {ACCENT}55;overflow:hidden}} .win img{{width:100%;display:block}}</style>
<div class="col"><div class="lk">{lk}</div><div class="tag">{TAG}</div><div class="sub">{SUB}</div></div>
<div class="win"><img src="data:image/png;base64,{shotb64}"></div>"""
    shot(html,ROOT.parent/'preview.png',w,h); print('preview.png (repo root)')

if __name__=='__main__':
    S.mkdir(exist_ok=True)
    make('github-social-preview.png',1280,640,'dark')
    make('card-wide.png',1200,630,'dark')
    make('card-wide-light.png',1200,630,'light')
    make('card-square.png',1080,1080,'dark','square')
    make('card-linkedin.png',1200,627,'dark')
    make('card-x.png',1600,900,'dark')
    make('banner-dark.png',1600,400,'dark','banner')
    make('banner-light.png',1600,400,'light','banner')
    png(LOGO/'icon.svg',S/'avatar-400.png',400,400); print('avatar-400.png')
    preview()
