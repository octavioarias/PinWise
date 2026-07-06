#!/usr/bin/env python3
"""Faithful on-brand mockups of the three pipeline screens, matching PinWiseTheme tokens:
accent #2536E6 (solid CTA, UPPERCASE), gradient cards, hero-mesh top, native segmented, chips.
Authored in POINTS (390pt-wide screen) then scaled into a 1080 square device frame."""
import subprocess, os
SP = os.path.dirname(os.path.abspath(__file__))
CANVAS = 1080
SCREEN_W_PT, SCREEN_H_PT = 390.0, 480.0
S = CANVAS / SCREEN_H_PT                     # 2.25
SCREEN_PX = SCREEN_W_PT * S                  # 877.5
OFF = (CANVAS - SCREEN_PX) / 2               # 101.25
M = 16
CW = SCREEN_W_PT - 2 * M                     # content width 358

INK, SUB, ACC, ACCT, MINT = "#FFFFFF", "#9AA3B8", "#2536E6", "#8A97FF", "#18E39A"
ELEV, STROKE = "#171A2C", "#2A2F45"

def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;")
def txt(x, y, s, size, fill=INK, w=600, anchor="start"):
    return (f'<text x="{x}" y="{y}" font-family="-apple-system,Helvetica,Arial,sans-serif" '
            f'font-size="{size}" font-weight="{w}" fill="{fill}" text-anchor="{anchor}">{esc(s)}</text>')
def card(x, y, w, h):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="18" fill="url(#cardg)"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="18" fill="none" stroke="{STROKE}" stroke-width="1.2"/>')
def fieldbox(x, y, w, h, left, right=None):
    out = (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{ELEV}" stroke="{STROKE}" stroke-width="1"/>'
           + txt(x + 12, y + h/2 + 5, left, 15, SUB, 500))
    if right: out += txt(x + w - 12, y + h/2 + 5, right, 15, INK, 700, "end")
    return out
def seg(x, y, w, h, left, right, leftActive):
    half = w / 2
    thumb_x = x + 2 + (0 if leftActive else half - 2)
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{ELEV}" stroke="{STROKE}" stroke-width="1"/>'
            f'<rect x="{thumb_x}" y="{y+2}" width="{half-2}" height="{h-4}" rx="6" fill="#3A3F52"/>'
            + txt(x + half/2, y + h/2 + 5, left, 14, INK if leftActive else SUB, 700, "middle")
            + txt(x + half + half/2, y + h/2 + 5, right, 14, SUB if leftActive else INK, 700, "middle"))
def chip(x, y, w, h, label, active):
    if active:
        return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{ACC}"/>'
                + txt(x + w/2, y + h/2 + 5, label, 14, "#fff", 700, "middle"))
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{ELEV}" stroke="{STROKE}" stroke-width="1"/>'
            + txt(x + w/2, y + h/2 + 5, label, 14, INK, 700, "middle"))
def button(x, y, w, h, label):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="url(#btn)"/>'
            + txt(x + w/2, y + h/2 + 6, label.upper(), 16, "#fff", 800, "middle"))
def title(t): return txt(M, 50, t, 34, INK, 900)

def frame(content):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <linearGradient id="cardg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16182c"/><stop offset="1" stop-color="#0f1120"/></linearGradient>
    <linearGradient id="btn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{ACC}"/><stop offset="1" stop-color="#1f2ec0"/></linearGradient>
    <radialGradient id="mesh" cx="540" cy="30" r="640" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{ACC}" stop-opacity="0.55"/><stop offset="0.42" stop-color="#0C1A66" stop-opacity="0.35"/>
      <stop offset="0.8" stop-color="#04050B" stop-opacity="0"/></radialGradient>
    <clipPath id="screen"><rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" rx="62"/></clipPath>
  </defs>
  <rect width="{CANVAS}" height="{CANVAS}" fill="#04050B"/>
  <rect x="{OFF-9}" y="-10" width="{SCREEN_PX+18}" height="{CANVAS+20}" rx="72" fill="#05060d"/>
  <g clip-path="url(#screen)">
    <rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" fill="#04050B"/>
    <rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" fill="url(#mesh)"/>
    <g transform="translate({OFF},0) scale({S})">{content}</g>
  </g>
  <rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" rx="62" fill="none" stroke="#2c3350" stroke-width="2"/>
</svg>'''

vial = "".join([
    title("New vial"),
    seg(M, 68, CW, 32, "Pre-mixed", "Powder", False),
    card(M, 118, CW, 158),
    txt(M+16, 146, "What's in the vial?", 16, INK, 700),
    fieldbox(M+16, 158, CW-32, 42, "Semaglutide", "5 mg"),
    txt(M+16, 236, "＋ Add ingredient", 13, ACCT, 700),
    txt(M+CW-16, 236, "Use a blend preset", 13, ACCT, 700, "end"),
    card(M, 292, CW, 66),
    txt(M+16, 316, "Nickname (optional)", 13, SUB, 600),
    txt(M+16, 340, "GLOW", 16, INK, 700),
    button(M, 392, CW, 46, "Add vial"),
])

protocol = "".join([
    title("New protocol"),
    card(M, 68, CW, 58),
    txt(M+16, 90, "Name this protocol", 13, SUB, 600),
    txt(M+16, 112, "Weekly stack", 16, INK, 700),
    card(M, 140, CW, 196),
    txt(M+16, 166, "What's in this protocol?", 16, INK, 700),
    chip(M+16, 178, 214, 30, "＋ Use one of your vials", True),
    fieldbox(M+16, 220, CW-32, 42, "Semaglutide", "2.5 mg"),
    txt(M+16, 300, "Linked to GLOW", 13, MINT, 700),
    card(M, 350, CW, 54),
    txt(M+16, 372, "How often?", 13, SUB, 600),
    txt(M+CW-16, 380, "Every few days", 16, INK, 700, "end"),
    button(M, 420, CW, 46, "Save protocol"),
])

log = "".join([
    title("Log a dose"),
    seg(M, 68, CW, 32, "Protocol", "One-time", True),
    card(M, 118, CW, 150),
    txt(M+16, 146, "Weekly stack", 16, INK, 700),
    txt(M+16, 178, "Semaglutide", 15, SUB, 500), txt(M+CW-16, 178, "2.5 mg", 15, ACCT, 700, "end"),
    txt(M+16, 206, "BPC-157", 15, SUB, 500), txt(M+CW-16, 206, "250 mcg", 15, ACCT, 700, "end"),
    txt(M+16, 236, "Logs both at once.", 12, SUB, 500),
    txt(M, 296, "Where did you inject?", 16, INK, 700),
    chip(M, 310, 110, 32, "Upper L", False), chip(M+120, 310, 110, 32, "Upper R", True), chip(M+240, 310, 110, 32, "Lower L", False),
    button(M, 392, CW, 46, "Log dose"),
])

def render(name, svg):
    p = os.path.join(SP, name + ".svg"); png = p + ".png"; open(p, "w").write(svg)
    if os.path.exists(png): os.remove(png)
    subprocess.run(["qlmanage", "-t", "-s", str(CANVAS), "-o", SP, p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("ok" if os.path.exists(png) else "FAIL", name)

render("onboard-vial", frame(vial))
render("onboard-protocol", frame(protocol))
render("onboard-log", frame(log))
