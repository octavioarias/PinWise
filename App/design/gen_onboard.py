#!/usr/bin/env python3
"""Representative on-brand mockup 'screenshots' of the three pipeline screens for onboarding."""
import subprocess, os
SP = os.path.dirname(os.path.abspath(__file__))
W, H, M = 1080, 1080, 64
BLUE, MINT, ACC = "#3a5bef", "#18e39a", "#3f7bff"
INK, SUB, CARD, LINE, ELEV = "#e9edf7", "#8b96b4", "#14161f", "#2a2f40", "#1b1f2b"

def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;")
def txt(x, y, s, size=30, fill=INK, w=600, anchor="start"):
    return (f'<text x="{x}" y="{y}" font-family="-apple-system,Helvetica,Arial,sans-serif" '
            f'font-size="{size}" font-weight="{w}" fill="{fill}" text-anchor="{anchor}">{esc(s)}</text>')
def card(x, y, w, h, r=28):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{CARD}" stroke="{LINE}" stroke-width="2"/>'
def field(x, y, w, s):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="66" rx="16" fill="{ELEV}" stroke="{LINE}" stroke-width="2"/>'
            + txt(x + 24, y + 44, s, 28, SUB, 500))
def chip(x, y, w, s, active=False, h=56):
    fill = ACC if active else ELEV
    fg = "#ffffff" if active else INK
    stroke_attr = "" if active else f' stroke="{LINE}" stroke-width="2"'
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2}" fill="{fill}"{stroke_attr}/>'
            + txt(x + w/2, y + h/2 + 10, s, 26, fg, 700, "middle"))
def segmented(x, y, w, left, right, leftActive=True):
    half = w/2
    return (f'<rect x="{x}" y="{y}" width="{w}" height="70" rx="18" fill="{ELEV}" stroke="{LINE}" stroke-width="2"/>'
            f'<rect x="{x+6}" y="{y+6}" width="{half-9}" height="58" rx="14" fill="{ACC if leftActive else "none"}"/>'
            f'<rect x="{x+half+3}" y="{y+6}" width="{half-9}" height="58" rx="14" fill="{"none" if leftActive else ACC}"/>'
            + txt(x + half/2, y + 46, left, 26, "#fff" if leftActive else SUB, 700, "middle")
            + txt(x + half + half/2, y + 46, right, 26, SUB if leftActive else "#fff", 700, "middle"))
def button(x, y, w, s):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="78" rx="20" fill="url(#g)"/>'
            + txt(x + w/2, y + 51, s, 30, "#fff", 800, "middle"))

def screen(title, body):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="{W}" y2="78" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{BLUE}"/><stop offset="1" stop-color="{MINT}"/></linearGradient>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="{H}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#12141c"/><stop offset="1" stop-color="#0a0b10"/></linearGradient>
  </defs>
  <rect width="{W}" height="{H}" fill="url(#bg)"/>
  {txt(M, 78, "9:41", 26, INK, 700)}
  <rect x="{W-150}" y="58" width="60" height="26" rx="8" fill="{SUB}" opacity="0.5"/>
  {txt(M, 190, title, 56, INK, 800)}
  {body}
</svg>'''

# --- Screen 1: Add a vial ---
s1 = "".join([
    segmented(M, 236, W-2*M, "Pre-mixed", "Powder", False),
    card(M, 340, W-2*M, 300),
    txt(M+36, 400, "What's in the vial?", 30, INK, 700),
    field(M+36, 430, W-2*M-72, "Semaglutide            5 mg"),
    txt(M+36, 560, "+ Add ingredient", 26, ACC, 700),
    txt(W-M-36, 560, "Use a blend preset", 26, ACC, 700, "end"),
    card(M, 668, W-2*M, 120),
    txt(M+36, 726, "Nickname (optional)", 28, SUB, 600),
    txt(M+36, 762, "GLOW", 30, INK, 700),
    button(M, 955, W-2*M, "Add vial"),
])

# --- Screen 2: Build a protocol ---
s2 = "".join([
    card(M, 236, W-2*M, 118),
    txt(M+36, 294, "Name this protocol", 28, SUB, 600),
    txt(M+36, 332, "Weekly stack", 30, INK, 700),
    card(M, 382, W-2*M, 330),
    txt(M+36, 442, "What's in this protocol?", 30, INK, 700),
    chip(M+36, 470, 300, "＋ Use one of your vials", True, 56),
    field(M+36, 548, W-2*M-72, "Semaglutide            2.5 mg"),
    txt(M+36, 672, "Linked to GLOW", 26, MINT, 700),
    card(M, 740, W-2*M, 150),
    txt(M+36, 800, "How often?", 28, SUB, 600),
    chip(M+36, 826, 240, "Every few days", False, 56),
    button(M, 955, W-2*M, "Save protocol"),
])

# --- Screen 3: Log a dose ---
s3 = "".join([
    segmented(M, 236, W-2*M, "Protocol", "One-time", True),
    card(M, 340, W-2*M, 250),
    txt(M+36, 400, "Weekly stack", 30, INK, 700),
    txt(M+36, 452, "Semaglutide", 28, SUB, 600), txt(W-M-36, 452, "2.5 mg", 28, ACC, 700, "end"),
    txt(M+36, 506, "BPC-157", 28, SUB, 600), txt(W-M-36, 506, "250 mcg", 28, ACC, 700, "end"),
    txt(M+36, 558, "Logs both at once.", 24, SUB, 500),
    txt(M, 660, "Where did you inject?", 30, INK, 700),
    chip(M, 700, 150, "Upper L", False), chip(M+166, 700, 150, "Upper R", True), chip(M+332, 700, 150, "Lower L", False),
    button(M, 955, W-2*M, "Log dose"),
])

def render(name, svg):
    p = os.path.join(SP, name + ".svg"); png = p + ".png"; open(p, "w").write(svg)
    if os.path.exists(png): os.remove(png)
    subprocess.run(["qlmanage", "-t", "-s", str(H), "-o", SP, p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("ok" if os.path.exists(png) else "FAIL", name)

render("onboard-vial", screen("New vial", s1))
render("onboard-protocol", screen("New protocol", s2))
render("onboard-log", screen("Log a dose", s3))
