#!/usr/bin/env python3
"""Generate an original DriveSpeed speedometer app icon as SVG (1024x1024, macOS tile)."""
import math, sys

CX, CY = 512.0, 578.0          # gauge center (a touch below middle so the needle has headroom)
R = 262.0                       # gauge band centerline radius
BAND = 50.0                     # gauge band thickness
START, END = 150.0, 390.0       # arc sweep in screen degrees (opens at the bottom)
NEEDLE = 325.0                  # needle angle (upper-right => "fast")

def P(r, deg):
    a = math.radians(deg)
    return (CX + r * math.cos(a), CY + r * math.sin(a))

def fmt(p):
    return f"{p[0]:.2f},{p[1]:.2f}"

# --- gauge arcs ---
bg_s, bg_e = P(R, START), P(R, END)
fill_e = P(R, NEEDLE)
bg_arc   = f"M {fmt(bg_s)} A {R} {R} 0 1 1 {fmt(bg_e)}"       # 240deg, over the top
fill_arc = f"M {fmt(bg_s)} A {R} {R} 0 0 1 {fmt(fill_e)}"     # 150->needle

# --- ticks ---
ticks = []
d = START
while d <= END + 0.1:
    po, pi = P(232, d), P(208, d)
    ticks.append(f'<line x1="{po[0]:.2f}" y1="{po[1]:.2f}" x2="{pi[0]:.2f}" y2="{pi[1]:.2f}"/>')
    d += 40.0

# --- needle (kite: tip, two base corners, counterweight tail) ---
nd = math.radians(NEEDLE)
dx, dy = math.cos(nd), math.sin(nd)
px, py = -math.sin(nd), math.cos(nd)
T    = (CX + 250 * dx, CY + 250 * dy)
B1   = (CX + 22 * px,  CY + 22 * py)
B2   = (CX - 22 * px,  CY - 22 * py)
TAIL = (CX - 60 * dx,  CY - 60 * dy)
needle_pts = " ".join(fmt(p) for p in (T, B1, TAIL, B2))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3A9DFF"/>
      <stop offset="1" stop-color="#005FE0"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0"    stop-color="#ffffff" stop-opacity="0.22"/>
      <stop offset="0.45" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="needle" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FF4B3E"/>
      <stop offset="1" stop-color="#DC0A00"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#001634" flood-opacity="0.34"/>
    </filter>
    <clipPath id="tileclip"><rect x="100" y="100" width="824" height="824" rx="185" ry="185"/></clipPath>
  </defs>

  <!-- tile + gloss -->
  <rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="url(#tile)" filter="url(#shadow)"/>
  <rect x="100" y="100" width="824" height="824" rx="185" ry="185" fill="url(#gloss)" clip-path="url(#tileclip)"/>

  <!-- gauge -->
  <path d="{bg_arc}" fill="none" stroke="#ffffff" stroke-opacity="0.20" stroke-width="{BAND}" stroke-linecap="round"/>
  <path d="{fill_arc}" fill="none" stroke="#ffffff" stroke-opacity="0.96" stroke-width="{BAND}" stroke-linecap="round"/>
  <g stroke="#ffffff" stroke-opacity="0.55" stroke-width="7" stroke-linecap="round">
    {"".join(ticks)}
  </g>

  <!-- needle + hub -->
  <polygon points="{needle_pts}" fill="url(#needle)"/>
  <circle cx="{CX}" cy="{CY}" r="32" fill="#ffffff"/>
  <circle cx="{CX}" cy="{CY}" r="13" fill="#0B4FBF"/>
</svg>
'''

out = sys.argv[1] if len(sys.argv) > 1 else "icon.svg"
with open(out, "w") as f:
    f.write(svg)
print(f"wrote {out}")
