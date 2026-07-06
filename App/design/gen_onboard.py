#!/usr/bin/env python3
"""Faithful mockups of the three pipeline screens for onboarding. Matches PinWiseTheme, shows the
bottom tab bar (correct tab highlighted) + the Protocols 'My Protocols/My Inventory' segments, and
uses one coherent example throughout: a WOLVERINE vial (BPC-157 + TB-500) -> protocol -> log."""
import subprocess, os
SP = os.path.dirname(os.path.abspath(__file__))
CANVAS = 1080
W_PT, H_PT = 390.0, 520.0
S = CANVAS / H_PT
SCREEN_PX = W_PT * S
OFF = (CANVAS - SCREEN_PX) / 2
M = 16
CW = W_PT - 2 * M

INK, SUB, ACC, ACCT, MINT = "#FFFFFF", "#9AA3B8", "#2536E6", "#8A97FF", "#18E39A"
ELEV, STROKE, SURF = "#171A2C", "#2A2F45", "#0F1120"

def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;")
def txt(x, y, s, size, fill=INK, w=600, anchor="start", italic=False):
    st = ' font-style="italic"' if italic else ''
    return (f'<text x="{x}" y="{y}" font-family="-apple-system,Helvetica,Arial,sans-serif" '
            f'font-size="{size}" font-weight="{w}" fill="{fill}"{st} text-anchor="{anchor}">{esc(s)}</text>')
def card(x, y, w, h):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="18" fill="url(#cardg)"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="18" fill="none" stroke="{STROKE}" stroke-width="1.2"/>')
def seg(x, y, w, h, left, right, leftActive):
    half = w / 2
    tx = x + 2 + (0 if leftActive else half - 2)
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{ELEV}" stroke="{STROKE}" stroke-width="1"/>'
            f'<rect x="{tx}" y="{y+2}" width="{half-2}" height="{h-4}" rx="6" fill="#3A3F52"/>'
            + txt(x + half/2, y + h/2 + 5, left, 14, INK if leftActive else SUB, 700, "middle")
            + txt(x + half + half/2, y + h/2 + 5, right, 14, SUB if leftActive else INK, 700, "middle"))
def chip(x, y, w, h, label, active):
    if active:
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{ACC}"/>' + txt(x+w/2, y+h/2+5, label, 14, "#fff", 700, "middle")
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{ELEV}" stroke="{STROKE}" stroke-width="1"/>'
            + txt(x+w/2, y+h/2+5, label, 14, INK, 700, "middle"))
def tag(x, y, label, color):
    w = 8 + len(label) * 7.2
    return (f'<rect x="{x}" y="{y}" width="{w}" height="22" rx="7" fill="{color}" fill-opacity="0.16" stroke="{color}" stroke-width="1"/>'
            + txt(x + w/2, y + 15, label, 11, color, 700, "middle"))
def button(x, y, w, h, label):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="url(#btn)"/>' + txt(x+w/2, y+h/2+6, label.upper(), 15, "#fff", 800, "middle")
def title(t): return txt(M, 48, t, 34, INK, 900)

# --- bottom tab bar ---
def icon(kind, cx, iy, c):
    if kind == "home":
        return f'<path d="M{cx-8},{iy+2} L{cx},{iy-8} L{cx+8},{iy+2} Z" fill="{c}"/><rect x="{cx-6}" y="{iy+1}" width="12" height="8" rx="1" fill="{c}"/>'
    if kind == "tools":
        return txt(cx, iy+8, "ƒ", 24, c, 700, "middle", italic=True)
    if kind == "log":
        return (f'<circle cx="{cx}" cy="{iy}" r="13" fill="{ACC}"/>'
                f'<rect x="{cx-6}" y="{iy-1.6}" width="12" height="3.2" rx="1.5" fill="#fff"/>'
                f'<rect x="{cx-1.6}" y="{iy-6}" width="3.2" height="12" rx="1.5" fill="#fff"/>')
    if kind == "protocols":  # "Stack" tab — three stacked plates
        s = ""
        for dy in (-7, -1, 5):
            s += f'<rect x="{cx-8}" y="{iy+dy}" width="16" height="4" rx="2" fill="{c}"/>'
        return s
    if kind == "news":
        s = f'<rect x="{cx-9}" y="{iy-8}" width="18" height="16" rx="2" fill="{c}"/>'
        for dy in (-3, 1, 5):
            s += f'<rect x="{cx-5}" y="{iy+dy}" width="10" height="1.6" fill="{SURF}"/>'
        return s
    return ""

def tabbar(active):
    barY = H_PT - 52
    tabs = [("home", "Home"), ("tools", "Tools"), ("log", "Log"), ("protocols", "Stack"), ("news", "News")]
    out = [f'<rect x="0" y="{barY}" width="{W_PT}" height="{H_PT-barY}" fill="{SURF}"/>',
           f'<rect x="0" y="{barY}" width="{W_PT}" height="0.6" fill="{STROKE}"/>']
    colw = W_PT / 5
    for i, (kind, label) in enumerate(tabs):
        cx = colw * (i + 0.5)
        sel = (kind == active) or (kind == "log" and active == "log")
        c = ACCT if (sel or kind == "log") else SUB
        out.append(icon(kind, cx, barY + 20, c))
        out.append(txt(cx, barY + 42, label, 9, ACCT if (sel or kind == "log") else SUB, 600 if sel else 500, "middle"))
    return "".join(out)

def frame(content, active):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <defs>
    <linearGradient id="cardg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#16182c"/><stop offset="1" stop-color="#0f1120"/></linearGradient>
    <linearGradient id="btn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{ACC}"/><stop offset="1" stop-color="#1f2ec0"/></linearGradient>
    <radialGradient id="mesh" cx="540" cy="30" r="640" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{ACC}" stop-opacity="0.5"/><stop offset="0.42" stop-color="#0C1A66" stop-opacity="0.32"/>
      <stop offset="0.8" stop-color="#04050B" stop-opacity="0"/></radialGradient>
    <clipPath id="screen"><rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" rx="60"/></clipPath>
  </defs>
  <rect width="{CANVAS}" height="{CANVAS}" fill="#04050B"/>
  <rect x="{OFF-9}" y="-10" width="{SCREEN_PX+18}" height="{CANVAS+20}" rx="70" fill="#05060d"/>
  <g clip-path="url(#screen)">
    <rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" fill="#04050B"/>
    <rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" fill="url(#mesh)"/>
    <g transform="translate({OFF},0) scale({S})">{content}{tabbar(active)}</g>
  </g>
  <rect x="{OFF}" y="0" width="{SCREEN_PX}" height="{CANVAS}" rx="60" fill="none" stroke="#2c3350" stroke-width="2"/>
</svg>'''

# Screen 1 — Protocols ▸ My Inventory (add a vial). Example: Wolverine (BPC-157 + TB-500).
vial = "".join([
    title("Stack"),
    seg(M, 66, CW, 32, "My Protocols", "My Inventory", False),
    button(M, 110, CW, 42, "Add vial"),
    card(M, 166, CW, 150),
    txt(M+16, 196, "Wolverine", 16, INK, 700),
    tag(M+CW-70, 182, "BLEND", MINT),
    txt(M+16, 222, "BPC-157 + TB-500", 13, SUB, 500),
    txt(M+16, 246, "10 mg + 10 mg · 2 mL", 13, SUB, 500),
    f'<rect x="{M+16}" y="266" width="{CW-32}" height="6" rx="3" fill="{ELEV}"/>',
    f'<rect x="{M+16}" y="266" width="{(CW-32)*0.15}" height="6" rx="3" fill="{ACC}"/>',
    txt(M+16, 296, "6 of 40 doses left · ~3 wks", 12, SUB, 500),
])

# Screen 2 — Protocols ▸ My Protocols (build a protocol from a vial).
protocol = "".join([
    title("Stack"),
    seg(M, 66, CW, 32, "My Protocols", "My Inventory", True),
    button(M, 110, CW, 42, "New protocol"),
    card(M, 166, CW, 150),
    txt(M+16, 196, "Wolverine recovery", 16, INK, 700),
    txt(M+16, 224, "BPC-157", 14, SUB, 500), txt(M+CW-16, 224, "250 mcg", 14, ACCT, 700, "end"),
    txt(M+16, 250, "TB-500", 14, SUB, 500), txt(M+CW-16, 250, "250 mcg", 14, ACCT, 700, "end"),
    txt(M+16, 284, "Linked to Wolverine · every 3 days", 13, MINT, 700),
])

# Screen 3 — Log tab (log the Wolverine protocol).
log = "".join([
    title("Log a dose"),
    seg(M, 66, CW, 32, "Protocol", "One-time", True),
    card(M, 110, CW, 150),
    txt(M+16, 140, "Wolverine recovery", 16, INK, 700),
    txt(M+16, 172, "BPC-157", 15, SUB, 500), txt(M+CW-16, 172, "250 mcg", 15, ACCT, 700, "end"),
    txt(M+16, 200, "TB-500", 15, SUB, 500), txt(M+CW-16, 200, "250 mcg", 15, ACCT, 700, "end"),
    txt(M+16, 232, "Logs both at once.", 12, SUB, 500),
    txt(M, 292, "Where did you inject?", 16, INK, 700),
    chip(M, 306, 108, 32, "Abdomen", False), chip(M+118, 306, 108, 32, "Thigh", True), chip(M+236, 306, 108, 32, "Glute", False),
    button(M, 372, CW, 44, "Log dose"),
])

def render(name, svg):
    p = os.path.join(SP, name + ".svg"); png = p + ".png"; open(p, "w").write(svg)
    if os.path.exists(png): os.remove(png)
    subprocess.run(["qlmanage", "-t", "-s", str(CANVAS), "-o", SP, p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("ok" if os.path.exists(png) else "FAIL", name)

render("onboard-vial", frame(vial, "protocols"))
render("onboard-protocol", frame(protocol, "protocols"))
render("onboard-log", frame(log, "log"))
