#!/usr/bin/env python3
"""Generate the DriveSpeed app icon as SVG (1024x1024, macOS tile).

A speedometer gauge, raised toward the top of the tile, with a silver external drive
centred below it. The gauge sits exactly where it does in NetSpeed's icon
(network-speed-monitor/design/gen_icon.py), so the two apps read as a family and differ
only in the badge below: an Ethernet glyph there, a drive here.

The drive is concept 1_silver from gen_concepts.py: GenericDrive.jpeg cut out of its
white background, its top face foreshortened so it is wider than tall, and its metal
cooled slightly toward the tile's blue. Silver was chosen because Mac users already
read a silver/grey drive as storage (the internal boot drive's Finder icon).
The drive is embedded in the SVG as a PNG, so icon.svg is self-contained.

Usage:  python3 gen_icon.py [out.svg]      (default: icon.svg)
Needs:  Pillow, numpy, scipy  (pip install pillow numpy scipy)
Render each app-icon size with rsvg-convert, e.g.
    rsvg-convert -w 1024 -h 1024 icon.svg -o icon_512x512@2x.png
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_concepts import (CX, DEFS, TILE, TREATMENTS, cut_out_drive, foreshorten,
                          gauge_markup, png_data_uri, recolour)

# Gauge centre: identical to NetSpeed's (its gauge + glyph group, centred on the tile).
CY = 472.83
DRIVE_WIDTH = 310.0             # drive width on the 1024 canvas
DRIVE_OFFSET = 155.0            # drive top, measured down from the gauge hub;
                                # chosen so the margins above the gauge and below
                                # the drive match
SQUASH = 0.6                    # top-face foreshortening (see gen_concepts.foreshorten)

drive = foreshorten(cut_out_drive(), SQUASH)
h = DRIVE_WIDTH * drive.height / drive.width
top = CY + DRIVE_OFFSET
uri = png_data_uri(recolour(drive, TREATMENTS["silver"]), 640)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" viewBox="0 0 1024 1024">{DEFS}

  <!-- tile + gloss -->
  {TILE} fill="url(#tile)" filter="url(#shadow)"/>
  {TILE} fill="url(#gloss)" clip-path="url(#tileclip)"/>

  <!-- gauge + needle + hub -->{gauge_markup(CY)}

  <!-- silver drive -->
  <image x="{CX - DRIVE_WIDTH / 2:.2f}" y="{top:.2f}" width="{DRIVE_WIDTH:.0f}" height="{h:.2f}" filter="url(#lift)" xlink:href="{uri}"/>
</svg>
'''

out = sys.argv[1] if len(sys.argv) > 1 else "icon.svg"
with open(out, "w") as f:
    f.write(svg)
print(f"wrote {out}: gauge {CY - 287:.0f}-{CY + 156:.0f}, drive {top:.0f}-{top + h:.0f} (tile 100-924)")
