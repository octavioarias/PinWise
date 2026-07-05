#!/usr/bin/env python3
"""Simple 'PW' in one clean font (Futura Bold). The ONLY unique element is the base of the P,
which continues into a syringe needle. White (or gradient) glyph on Apple-style grounds."""
import subprocess, os, io, base64
from PIL import Image, ImageDraw, ImageFont
SP = os.path.dirname(os.path.abspath(__file__))
FONT, WEIGHT, SIZE = "Futura", "bold", 390
BX, BY, LSP = 190, 690, "4"

def render(name, svg, size=1024):
    p=os.path.join(SP,name+".svg"); png=p+".png"; open(p,"w").write(svg)
    if os.path.exists(png): os.remove(png)
    subprocess.run(["qlmanage","-t","-s",str(size),"-o",SP,p],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    return png

def probe(text):
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<rect width="1024" height="1024" fill="#000"/>'
            f'<text x="{BX}" y="{BY}" font-family="{FONT}" font-weight="{WEIGHT}" font-size="{SIZE}" letter-spacing="{LSP}" fill="#fff">{text}</text></svg>')

def wbbox(png,thr=110):
    im=Image.open(png).convert("L").point(lambda v:255 if v>thr else 0); return im, im.getbbox()

imP,bbP = wbbox(render("p2_P",probe("P")))
imPW,bbPW = wbbox(render("p2_PW",probe("PW")))
lP,tP,rP,bP = bbP
row = imP.crop((0,int(tP+0.80*(bP-tP)),1024,int(tP+0.80*(bP-tP))+2)).getbbox()
stem_cx=(row[0]+row[2])/2.0; stem_w=row[2]-row[0]; baseline=bP

# syringe needle at the base of the P (the only unique element)
nw=round(stem_w*0.26); sh=round(stem_w*0.36); collar_w=round(nw*1.95); collar_h=round(stem_w*0.11)
shaft_len=round(stem_w*1.35); bevel=round(stem_w*0.66); hs,hn=stem_w/2.0,nw/2.0
y_sh=baseline+sh; y_shaft=y_sh+collar_h; y_sbot=y_shaft+shaft_len; tip_y=y_sbot+bevel
def needle(F):
    return (f'<path fill="{F}" d="M{stem_cx-hs:.1f},{baseline} L{stem_cx+hs:.1f},{baseline} L{stem_cx+hn:.1f},{y_sh} L{stem_cx-hn:.1f},{y_sh} Z"/>'
            f'<rect x="{stem_cx-collar_w/2:.1f}" y="{y_sh}" width="{collar_w}" height="{collar_h}" fill="{F}"/>'
            f'<rect x="{stem_cx-hn:.1f}" y="{y_shaft}" width="{nw}" height="{shaft_len}" fill="{F}"/>'
            f'<path fill="{F}" d="M{stem_cx-hn:.1f},{y_sbot} L{stem_cx+hn:.1f},{y_sbot} L{stem_cx-hn:.1f},{tip_y} Z"/>')

# center the LETTERS block; needle hangs below
cx=(bbPW[0]+bbPW[2])/2.0; cy=(bbPW[1]+bbPW[3])/2.0
dx,dy = 512-cx, 512-cy
def glyphgroup(F):
    return (f'<g transform="translate({dx:.1f},{dy:.1f})">'
            f'<text x="{BX}" y="{BY}" font-family="{FONT}" font-weight="{WEIGHT}" font-size="{SIZE}" letter-spacing="{LSP}" fill="{F}">PW</text>'
            f'{needle(F)}</g>')

def tile(defs,bg,F):
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{bg}{glyphgroup(F)}</svg>')

def vgrad(i,a,b): return f'<linearGradient id="{i}" x1="0" y1="0" x2="0" y2="1024" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>'
def dgrad(i,a,b): return f'<linearGradient id="{i}" x1="190" y1="395" x2="906" y2="690" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>'
SHEEN='<radialGradient id="sh" cx="512" cy="150" r="760" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#fff" stop-opacity="0.13"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/></radialGradient>'
def fb(g): return f'<rect width="1024" height="1024" fill="url(#{g})"/>'
def sh_(): return '<rect width="1024" height="1024" fill="url(#sh)"/>'
M=dgrad("m","#3a5bef","#18e39a")

VARIANTS=[
 ("green","Vital green",   vgrad("b","#3fe37f","#12b45a")+SHEEN, fb("b")+sh_(), "#ffffff"),
 ("white","Clinic white",  vgrad("b","#ffffff","#eef1f7")+M,     fb("b"),       "url(#m)"),
 ("blue","Brand blue",     vgrad("b","#4f7bff","#2536E6")+SHEEN, fb("b")+sh_(), "#ffffff"),
 ("brand","Brand gradient",dgrad("b","#3a5bef","#18e39a")+SHEEN, fb("b")+sh_(), "#ffffff"),
 ("teal","Kinetic teal",   vgrad("b","#22c9c2","#0f9d8a")+SHEEN, fb("b")+sh_(), "#ffffff"),
 ("dark","Midnight",       vgrad("b","#1b1e29","#080910")+M+SHEEN,fb("b")+sh_(),"url(#m)"),
]
pngs=[(k,lbl,render("pw2_"+k,tile(d,bg,F))) for k,lbl,d,bg,F in VARIANTS]

def rounded(im,rf=0.225):
    im=im.convert("RGBA"); w,h=im.size; r=int(w*rf); m=Image.new("L",(w,h),0)
    ImageDraw.Draw(m).rounded_rectangle([0,0,w-1,h-1],radius=r,fill=255); im.putalpha(m); return im
cols,rows,cell,pad,lab=3,2,360,40,44
W=cols*cell+(cols+1)*pad; H=rows*(cell+lab)+(rows+1)*pad
sheet=Image.new("RGB",(W,H),(12,13,18)); dr=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf",26)
except: font=ImageFont.load_default()
for i,(k,lbl,png) in enumerate(pngs):
    c,r=i%cols,i//cols; x=pad+c*(cell+pad); y=pad+r*(cell+lab+pad)
    ic=rounded(Image.open(png).resize((cell,cell),Image.LANCZOS)); sheet.paste(ic,(x,y),ic)
    tb=dr.textbbox((0,0),lbl,font=font); dr.text((x+(cell-(tb[2]-tb[0]))//2,y+cell+8),lbl,font=font,fill=(200,208,224))
sheet.save(f"{SP}/pw2_sheet.png"); print("stem_w",stem_w,"tip_y",tip_y,"sheet",W,H)

# shipping companions for Midnight: full-bleed dark default + grayscale tinted
MONO='<linearGradient id="m" x1="190" y1="395" x2="500" y2="820" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#f2f5fb"/><stop offset="1" stop-color="#aab4c8"/></linearGradient>'
render("ship_dark",   tile(vgrad("b","#1b1e29","#080910")+M+SHEEN, fb("b")+sh_(), "url(#m)"))
render("ship_tinted", tile(vgrad("b","#0a0b10","#0a0b10")+MONO,     fb("b"),        "url(#m)"))
print("shipping renders done")
