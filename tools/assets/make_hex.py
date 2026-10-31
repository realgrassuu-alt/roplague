"""RoPlague's Evolve-tree hexes (flat-top), drawn from scratch: white masks tinted in game.

    .venv/Scripts/python.exe tools/assets/make_hex.py   ->  build/plague_icons/hex_{fill,ring,glow}.png
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "build", "plague_icons")


def hex_points(cx, cy, r):
    # flat-top: points at 0, 60, ... degrees
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in range(0, 360, 60)]


def main():
    os.makedirs(OUT, exist_ok=True)
    c = S / 2
    r = S * 0.48
    # fill: the hex with rounded corners (drawn big, then blurred and thresholded)
    fill = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(fill)
    d.polygon(hex_points(c, c, r), fill=255)
    fill = fill.filter(ImageFilter.GaussianBlur(14)).point(lambda v: 255 if v > 128 else 0)
    # a little top light: brighter top half (the tint multiplies it)
    shade = Image.new("L", (S, S), 0)
    for y in range(S):
        v = int(255 - 40 * (y / S))
        ImageDraw.Draw(shade).line([(0, y), (S, y)], fill=v)
    rgba = Image.merge("RGBA", (shade, shade, shade, fill))
    rgba.resize((256, 222 if False else 256), Image.LANCZOS).save(os.path.join(OUT, "hex_fill.png"))
    # ring: the outline only
    ring = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(ring)
    d.polygon(hex_points(c, c, r), fill=255)
    d.polygon(hex_points(c, c, r - S * 0.06), fill=0)
    ring = ring.filter(ImageFilter.GaussianBlur(5)).point(lambda v: 255 if v > 110 else 0)
    white = Image.new("L", (S, S), 255)
    Image.merge("RGBA", (white, white, white, ring)).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "hex_ring.png"))
    # glow: a soft halo around the hex
    glow = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(glow)
    d.polygon(hex_points(c, c, r * 0.9), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    Image.merge("RGBA", (white, white, white, glow)).resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "hex_glow.png"))
    sheet = Image.new("RGBA", (768, 256), (30, 34, 54, 255))
    for i, n in enumerate(["hex_fill", "hex_ring", "hex_glow"]):
        sheet.alpha_composite(Image.open(os.path.join(OUT, n + ".png")), (i * 256, 0))
    sheet.save(os.path.join(OUT, "_hex_sheet.png"))
    print("ok")


if __name__ == "__main__":
    main()
