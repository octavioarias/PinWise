#!/usr/bin/env python3
"""Build the PinWise icon: 'PW' in one consistent typeface (Futura Bold), with the ONLY
modification being the base of the P growing into a syringe needle. Measures the P's real
stem from a WebKit render so the needle matches its width, then centers the whole mark."""
import subprocess, os
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "Futura"
WEIGHT = "bold"
SIZE = 390
BX, BY = 190, 690          # text start x, baseline y (probe space, viewBox 1024)
LSP = "4"                  # letter-spacing

def render(name, svg, size=1024):
    p = os.path.join(OUT, name + ".svg"); png = p + ".png"
    open(p, "w").write(svg)
    if os.path.exists(png): os.remove(png)
    subprocess.run(["qlmanage","-t","-s",str(size),"-o",OUT,p],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return png

def probe(text):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#000"/>
  <text x="{BX}" y="{BY}" font-family="{FONT}" font-weight="{WEIGHT}" font-size="{SIZE}"
        letter-spacing="{LSP}" fill="#fff">{text}</text>
</svg>'''

def white_bbox(png, thr=110):
    im = Image.open(png).convert("L").point(lambda v: 255 if v > thr else 0)
    return im, im.getbbox()   # (l,t,r,b) or None

# --- measure P alone (stem + baseline) and full PW bbox ---
imP, bbP = white_bbox(render("probeP", probe("P")))
imPW, bbPW = white_bbox(render("probePW", probe("PW")))
lP, tP, rP, bP = bbP
# stem x-range: sample a row 78% down the P (below the bowl -> only stem present)
row_y = int(tP + 0.80 * (bP - tP))
row = imP.crop((0, row_y, 1024, row_y + 2)).getbbox()
sx0, sx1 = row[0], row[2]
stem_w = sx1 - sx0
stem_cx = (sx0 + sx1) / 2.0
baseline = bP
print(f"P bbox={bbP}  stem x=({sx0},{sx1}) w={stem_w} cx={stem_cx:.1f} baseline={baseline}")
print(f"PW bbox={bbPW}")

# --- needle geometry (grows from the stem base), sized to the stem ---
shaft_w   = round(stem_w * 0.34)
guard_w   = round(stem_w * 1.02)
guard_h   = round(stem_w * 0.16)
shaft_len = round(stem_w * 1.15)   # baseline -> crossguard
tip_len   = round(stem_w * 1.15)   # crossguard -> point
gx0 = round(stem_cx - guard_w/2); gx1 = round(stem_cx + guard_w/2)
sxa = round(stem_cx - shaft_w/2); sxb = round(stem_cx + shaft_w/2)
guard_y = baseline + shaft_len
tip_y   = guard_y + tip_len
needle = f'''
    <rect x="{sxa}" y="{baseline-4}" width="{shaft_w}" height="{shaft_len+8}" fill="{{FILL}}"/>
    <rect x="{gx0}" y="{guard_y}" width="{guard_w}" height="{guard_h}" fill="{{FILL}}"/>
    <path d="M{sxa},{guard_y+guard_h} L{sxb},{guard_y+guard_h} L{stem_cx:.1f},{tip_y} Z" fill="{{FILL}}"/>'''

# --- union bbox (text + needle) -> translate to center in 1024 ---
lU, tU = bbPW[0], bbPW[1]
rU, bU = bbPW[2], tip_y
cx = (lU + rU) / 2.0; cy = (tU + bU) / 2.0
dx = 512 - cx; dy = 512 - cy
print(f"union=({lU},{tU},{rU},{bU}) center=({cx:.0f},{cy:.0f}) translate=({dx:.0f},{dy:.0f})")

def compose(name, bg_defs, bg_layers, fill):
    body = f'''
    <text x="{BX}" y="{BY}" font-family="{FONT}" font-weight="{WEIGHT}" font-size="{SIZE}"
          letter-spacing="{LSP}" fill="{fill}">PW</text>{needle.replace("{FILL}", fill)}'''
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>{bg_defs}</defs>
  {bg_layers}
  <g transform="translate({dx:.1f},{dy:.1f})">{body}</g>
</svg>'''

BRAND = '''<linearGradient id="m" x1="230" y1="330" x2="800" y2="820" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#3a5bef"/><stop offset="0.5" stop-color="#22b8e6"/><stop offset="1" stop-color="#18e39a"/></linearGradient>'''
DARK_BG = '''<linearGradient id="bv" x1="0" y1="0" x2="0" y2="1024" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#1b1e29"/><stop offset="1" stop-color="#080910"/></linearGradient>
    <radialGradient id="sheen" cx="512" cy="200" r="650" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fff" stop-opacity="0.06"/><stop offset="0.55" stop-color="#fff" stop-opacity="0"/></radialGradient>'''
dark_layers = '<rect width="1024" height="1024" fill="#12141c"/><rect width="1024" height="1024" fill="url(#bv)"/><rect width="1024" height="1024" fill="url(#sheen)"/>'

render("icon_v2_dark", compose("dark", DARK_BG + BRAND, dark_layers, "url(#m)"))

# tinted: grayscale mark on near-black (system re-colors it)
MONO = '''<linearGradient id="m" x1="240" y1="380" x2="500" y2="760" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#f2f5fb"/><stop offset="1" stop-color="#aab4c8"/></linearGradient>'''
render("icon_v2_tinted", compose("tinted", MONO, '<rect width="1024" height="1024" fill="#0a0b10"/>', "url(#m)"))

# light: deeper brand gradient on a light ground (optional light-mode variant)
BRAND_LIGHT = '''<linearGradient id="m" x1="230" y1="330" x2="800" y2="820" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#2f45d8"/><stop offset="0.5" stop-color="#0f9fd0"/><stop offset="1" stop-color="#0fbf86"/></linearGradient>'''
LIGHT_BG = '''<linearGradient id="bv" x1="0" y1="0" x2="0" y2="1024" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#f6f8fd"/><stop offset="1" stop-color="#dfe4f1"/></linearGradient>'''
render("icon_v2_light", compose("light", LIGHT_BG + BRAND_LIGHT,
       '<rect width="1024" height="1024" fill="#eef1f8"/><rect width="1024" height="1024" fill="url(#bv)"/>', "url(#m)"))

# framed preview matching the reference tile look (squircle floating on darker canvas)
def framed():
    body = f'''<text x="{BX}" y="{BY}" font-family="{FONT}" font-weight="{WEIGHT}" font-size="{SIZE}"
          letter-spacing="{LSP}" fill="url(#m)">PW</text>{needle.replace("{FILL}", "url(#m)")}'''
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>{BRAND}
    <linearGradient id="tl" x1="0" y1="168" x2="0" y2="856" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#20232e"/><stop offset="1" stop-color="#070810"/></linearGradient>
    <radialGradient id="sh" cx="512" cy="208" r="520" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity=".07"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="1024" height="1024" fill="#0c0d12"/>
  <rect x="168" y="168" width="688" height="688" rx="154" fill="url(#tl)"/>
  <rect x="168" y="168" width="688" height="688" rx="154" fill="url(#sh)"/>
  <rect x="169" y="169" width="686" height="686" rx="153" fill="none" stroke="#fff" stroke-opacity=".10" stroke-width="2"/>
  <g transform="translate(512 512) scale(0.62) translate(-512 -512) translate({dx:.1f},{dy:.1f})">{body}</g>
</svg>'''
render("preview_v2_dark", framed())
print("composed dark / tinted / light / preview")
