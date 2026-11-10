#!/usr/bin/env python3
"""Generate DriveSpeed icon concepts: full-size speedometer moved up, external drive below.

Mirrors network-speed-monitor/design/gen_concepts.py (which put an Ethernet glyph
under the same gauge), so the two app icons read as a family.

The drive comes from GenericDrive.jpeg: it is cut out of its white background (the
soft floor shadow is dropped), recoloured to suit the blue tile, and embedded in the
SVG as a PNG. One concept instead redraws the drive as a flat vector glyph.

Usage:  python3 gen_concepts.py [outdir]          (default: ./concepts)
Needs:  Pillow, numpy, scipy  (pip install pillow numpy scipy) and rsvg-convert.
Writes one SVG + PNG per concept and contact_sheet.png.
"""
import base64, io, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage as nd

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "GenericDrive.jpeg")

# ---------------------------------------------------------------- gauge (same geometry as gen_icon.py)
CX = 512.0
R, BAND = 262.0, 50.0
START, END, NEEDLE = 150.0, 390.0, 325.0
GAUGE_UP, GAUGE_DOWN = 287.0, 156.0     # gauge extent above / below its centre

def fmt(p):
    return f"{p[0]:.2f},{p[1]:.2f}"

def gauge_markup(cy):
    def P(r, deg):
        a = math.radians(deg)
        return (CX + r * math.cos(a), cy + r * math.sin(a))
    bg_s, bg_e, fill_e = P(R, START), P(R, END), P(R, NEEDLE)
    ticks, d = [], START
    while d <= END + 0.1:
        po, pi = P(232, d), P(208, d)
        ticks.append(f'<line x1="{po[0]:.2f}" y1="{po[1]:.2f}" x2="{pi[0]:.2f}" y2="{pi[1]:.2f}"/>')
        d += 40.0
    nd_ = math.radians(NEEDLE)
    dx, dy, px, py = math.cos(nd_), math.sin(nd_), -math.sin(nd_), math.cos(nd_)
    pts = [(CX + 250 * dx, cy + 250 * dy), (CX + 22 * px, cy + 22 * py),
           (CX - 60 * dx, cy - 60 * dy), (CX - 22 * px, cy - 22 * py)]
    return f'''
  <path d="M {fmt(bg_s)} A {R} {R} 0 1 1 {fmt(bg_e)}" fill="none" stroke="#ffffff" stroke-opacity="0.20" stroke-width="{BAND}" stroke-linecap="round"/>
  <path d="M {fmt(bg_s)} A {R} {R} 0 0 1 {fmt(fill_e)}" fill="none" stroke="#ffffff" stroke-opacity="0.96" stroke-width="{BAND}" stroke-linecap="round"/>
  <g stroke="#ffffff" stroke-opacity="0.55" stroke-width="7" stroke-linecap="round">{"".join(ticks)}</g>
  <polygon points="{" ".join(fmt(p) for p in pts)}" fill="url(#needle)"/>
  <circle cx="{CX}" cy="{cy:.2f}" r="32" fill="#ffffff"/>
  <circle cx="{CX}" cy="{cy:.2f}" r="13" fill="#0B4FBF"/>'''

# ---------------------------------------------------------------- drive cut-out
def cut_out_drive():
    """Return the drive as an RGBA image cropped to its silhouette (no floor shadow)."""
    rgb = Image.open(SRC).convert("RGB")
    L = np.asarray(rgb.convert("L")).astype(float)
    m = nd.binary_fill_holes(L < 215)              # side shadows are lighter than 215
    lab, n = nd.label(m)
    m = lab == (np.argmax(nd.sum(m, lab, range(1, n + 1))) + 1)
    # The floor shadow under the drive is darker than 215; the drive's bottom edge is a
    # near-black rubber foot (< 75), so cut each column just below its last foot pixel.
    y0 = int(L.shape[0] * 0.73)
    for x in range(L.shape[1]):
        dark = np.where(L[y0:, x] < 75)[0]
        m[y0 + (dark.max() + 1 if len(dark) else 0):, x] = False
    m = nd.binary_opening(m, iterations=3)
    lab, n = nd.label(m)
    m = lab == (np.argmax(nd.sum(m, lab, range(1, n + 1))) + 1)
    m = nd.binary_erosion(m, iterations=2)         # stay clear of the white fringe
    alpha = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.copy()
    out.putalpha(alpha)
    return out.crop(alpha.getbbox())

LIP = 0.83      # fraction of the cut-out's height where the top face meets the front lip

def foreshorten(drive, k):
    """Squash only the top face vertically by k, as if seen from a lower angle; the
    front lip keeps its height. Makes the drive wider-than-tall like a Finder drive icon."""
    if k == 1:
        return drive
    y = round(drive.height * LIP)
    top = drive.crop((0, 0, drive.width, y)).resize((drive.width, round(y * k)), Image.LANCZOS)
    lip = drive.crop((0, y, drive.width, drive.height))
    out = Image.new("RGBA", (drive.width, top.height + lip.height))
    out.paste(top, (0, 0)); out.paste(lip, (0, top.height))
    return out

def recolour(drive, stops, gamma=1.0, lo=18.0, hi=228.0):
    """Map the drive's luminance through a colour ramp. stops: [(t, '#rrggbb'), ...]."""
    a = np.asarray(drive).astype(float)
    lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2])
    t = np.clip((lum - lo) / (hi - lo), 0, 1) ** gamma
    ts = np.array([s[0] for s in stops])
    cols = np.array([[int(s[1][i:i + 2], 16) for i in (1, 3, 5)] for s in stops], float)
    out = np.stack([np.interp(t, ts, cols[:, c]) for c in range(3)], -1)
    return Image.fromarray(np.dstack([out, a[..., 3]]).astype(np.uint8), "RGBA")

# Colour treatments. Each is a luminance ramp, so the brushed-metal shading survives.
TREATMENTS = {
    # cool silver: neutral metal nudged toward the tile's blue so it doesn't look grey/dirty
    "silver": [(0, "#1E2836"), (0.45, "#8E9CB0"), (0.8, "#D9E3F0"), (1, "#F7FAFF")],
    # frosted white: reads as white like the gauge band, keeps the 3-D shading
    "frost":  [(0, "#7FAEEA"), (0.35, "#CFE3FF"), (0.75, "#F2F8FF"), (1, "#FFFFFF")],
    # blue metal: monochrome in the tile's own blues
    "blue":   [(0, "#06265C"), (0.4, "#2F7BE8"), (0.8, "#A9D2FF"), (1, "#EEF6FF")],
}

def png_data_uri(img, width):
    h = round(img.height * width / img.width)
    buf = io.BytesIO()
    img.resize((width, h), Image.LANCZOS).save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

# ---------------------------------------------------------------- flat vector drive
# Same proportions as the foreshortened photo: a top face that narrows toward the back,
# a gap, then the front lip. Native box 1000 x 720.
FLAT_W, FLAT_H = 1000.0, 720.0

def rounded_path(pts, r):
    """Closed path through pts with each corner rounded (quadratic) by radius r."""
    n, d = len(pts), []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        def toward(a, b):
            L = math.hypot(b[0] - a[0], b[1] - a[1]); t = min(r, L / 2) / L
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        a, b = toward(p1, p0), toward(p1, p2)
        d.append(("M" if i == 0 else "L") + f" {fmt(a)} Q {fmt(p1)} {fmt(b)}")
    return " ".join(d) + " Z"

def flat_drive():
    top = rounded_path([(70, 0), (930, 0), (1000, 520), (0, 520)], 70)
    front = rounded_path([(0, 548), (1000, 548), (1000, FLAT_H), (0, FLAT_H)], 60)
    return (f'<path d="{top}" fill="#ffffff" fill-opacity="0.96"/>'
            f'<path d="{front}" fill="#ffffff" fill-opacity="0.66"/>'
            '<rect x="445" y="44" width="110" height="28" rx="14" fill="#0B4FBF" fill-opacity="0.85"/>')

# ---------------------------------------------------------------- tile
TILE = '<rect x="100" y="100" width="824" height="824" rx="185" ry="185"'
DEFS = '''
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3A9DFF"/><stop offset="1" stop-color="#005FE0"/>
    </linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/><stop offset="0.45" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="needle" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FF4B3E"/><stop offset="1" stop-color="#DC0A00"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#001634" flood-opacity="0.34"/>
    </filter>
    <filter id="lift" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="8" stdDeviation="9" flood-color="#001634" flood-opacity="0.40"/>
    </filter>
    <clipPath id="tileclip">''' + TILE + '''/></clipPath>
  </defs>'''

def layout(offset, height):
    """(gauge_cy, drive_top) centring the gauge + drive group on the tile (y = 512)."""
    bottom_from_cy = max(GAUGE_DOWN, offset + height)
    cy = 512 - (bottom_from_cy - GAUGE_UP) / 2
    return cy, cy + offset

def icon(drive_markup):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" viewBox="0 0 1024 1024">{DEFS}
  {TILE} fill="url(#tile)" filter="url(#shadow)"/>
  {TILE} fill="url(#gloss)" clip-path="url(#tileclip)"/>
  {{GAUGE}}
  {drive_markup}
</svg>
'''

# Each concept: (treatment, top-face squash k, drive top offset below the gauge hub,
# drive width). The gauge (full size) + drive group is centred vertically on the tile.
CONCEPTS = {
    "1_silver":         ("silver", 0.6, 175, 310),  # natural metal, cooled to the tile
    "2_frost":          ("frost",  0.6, 175, 310),  # frosted white, matches the gauge band
    "3_blue_metal":     ("blue",   0.6, 175, 310),  # monochrome blue metal
    "4_frost_nestled":  ("frost",  1.0, 108, 262),  # photo's own proportions, tucked up between the arc ends
    "5_flat_glyph":     ("flat",   1.0, 180, 310),  # flat vector drive, like NetSpeed's glyph
}

def build(outdir):
    os.makedirs(outdir, exist_ok=True)
    drive = cut_out_drive()
    uris = {}
    rendered = []
    for name, (treat, k, offset, w) in CONCEPTS.items():
        img = None if treat == "flat" else foreshorten(drive, k)
        h = w * (FLAT_H / FLAT_W if treat == "flat" else img.height / img.width)
        cy, top = layout(offset, h)
        x = CX - w / 2
        if treat == "flat":
            s = w / FLAT_W
            markup = f'<g transform="translate({x:.2f},{top:.2f}) scale({s:.4f})">{flat_drive()}</g>'
        else:
            if (treat, k) not in uris:
                uris[treat, k] = png_data_uri(recolour(img, TREATMENTS[treat]), 640)
            markup = (f'<image x="{x:.2f}" y="{top:.2f}" width="{w}" height="{h:.2f}" '
                      f'filter="url(#lift)" xlink:href="{uris[treat, k]}"/>')
        svg = icon(markup).replace("{GAUGE}", gauge_markup(cy))
        sp, pp = os.path.join(outdir, name + ".svg"), os.path.join(outdir, name + ".png")
        with open(sp, "w") as f:
            f.write(svg)
        subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", sp, "-o", pp], check=True)
        print(f"{name}: gauge {cy - GAUGE_UP:.0f}-{cy + GAUGE_DOWN:.0f}, drive {top:.0f}-{top + h:.0f}")
        rendered.append((name, pp))
    contact_sheet(rendered, os.path.join(outdir, "contact_sheet.png"))

def contact_sheet(items, path):
    """Big icon plus 128/64/32 px previews on light and dark backgrounds."""
    cols, cell_w, cell_h = 2, 560, 360
    rows = math.ceil(len(items) / cols)
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (236, 238, 243))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
    except OSError:
        font = ImageFont.load_default()
    for i, (name, pp) in enumerate(items):
        ox, oy = (i % cols) * cell_w, (i // cols) * cell_h
        im = Image.open(pp).convert("RGBA")
        sheet.paste(big := im.resize((280, 280), Image.LANCZOS), (ox + 20, oy + 10), big)
        y = oy + 30
        for s in (96, 48, 24):              # shown at 1x of each size; stand-ins for 128/64/32
            sm = im.resize((s, s), Image.LANCZOS)
            sheet.paste(sm, (ox + 320, y), sm)
            dark = Image.new("RGB", (s + 12, s + 12), (30, 30, 34))
            sheet.paste(dark, (ox + 320 + s + 10, y - 6))
            sheet.paste(sm, (ox + 320 + s + 16, y), sm)
            y += s + 18
        d.text((ox + 30, oy + 305), name, fill=(30, 30, 30), font=font)
    sheet.save(path)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "concepts"))
