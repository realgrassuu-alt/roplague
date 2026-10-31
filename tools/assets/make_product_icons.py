"""RoPlague: the store icons of our developer products and gamepasses (Roblox shows them in the purchase
prompt and on the experience's store page). Each is a 512 px rounded tile in the item's colour with its
own glyph from build/plague_icons or build/trait_icons, or, for an infection colour, a hex of that
colour in the map's soft patches. No text in any of them.

    .venv/Scripts/python.exe tools/assets/make_product_icons.py   ->  build/product_icons/<key>.png
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(REPO, "build", "product_icons")
S = 512
sys.path.insert(0, os.path.join(REPO, "src", "shared", "Data"))

# key: (tile colour, glyph file or a drawn shape)
GLYPHS = {
    "unlock_head_start": ((255, 150, 60), "plague_icons/dna.png"),
    "unlock_bubble_magnet": ((235, 70, 50), "plague_icons/infect.png"),
    "unlock_super_spreader": ((226, 72, 58), "trait_icons/carrier.png"),
    "unlock_sea_legs": ((60, 180, 255), "trait_icons/water2.png"),
    "unlock_gene_bank": ((70, 190, 100), "plague_icons/evolve.png"),
    "unlock_slow_science": ((90, 170, 255), "plague_icons/cure.png"),
    "unlock_mutagen": ((170, 90, 240), "trait_icons/hardy.png"),
    "unlock_stars2x": ((255, 200, 61), "@star2"),
    "starter_pack": ((232, 46, 56), "@gift"),
    "crate": ((200, 120, 50), "@crate"),
    "crate_first": ((230, 150, 60), "@crate"),
    "crate3": ((210, 110, 40), "@crate3"),
    "crate10": ((240, 170, 40), "@crate10"),
    "takeover": ((120, 140, 255), "plague_icons/world.png"),
    "rename": ((255, 90, 80), "plague_icons/pencil.png"),
    "auto_pop": ((70, 150, 255), "@autopop"),
}


def tile(col):
    """A rounded square: the colour at the top deepening to night at the bottom, a soft inner glow."""
    y = np.linspace(0, 1, S)[:, None]
    top = np.array(col, dtype=np.float32) * 0.85 + 30
    bot = np.array((14, 18, 38), dtype=np.float32)
    grad = top[None, None, :] * (1 - y[..., None] * 0.85) + bot[None, None, :] * (y[..., None] * 0.85)
    grad = np.broadcast_to(grad, (S, S, 3))
    im = Image.fromarray(np.clip(grad, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([8, 8, S - 8, S - 8], radius=96, fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([96, 80, S - 96, S - 112], fill=tuple(int(c) for c in col) + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(48))
    out.alpha_composite(Image.composite(glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([10, 10, S - 10, S - 10], radius=94, outline=(255, 255, 255, 90), width=8)
    out.alpha_composite(rim)
    return out


def star(d, cx, cy, r, fill):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=(30, 18, 8, 255))
    pts2 = [(cx + (x - cx) * 0.86, cy + (y - cy) * 0.86) for x, y in pts]
    d.polygon(pts2, fill=fill)


def crate(d, x, y, w, col):
    h = w * 0.78
    d.rounded_rectangle([x, y, x + w, y + h], radius=w * 0.08, fill=(40, 22, 10, 255))
    d.rounded_rectangle([x + 10, y + 10, x + w - 10, y + h - 10], radius=w * 0.06, fill=col)
    d.rectangle([x + 10, y + h * 0.36, x + w - 10, y + h * 0.46], fill=(40, 22, 10, 255))
    d.rounded_rectangle([x + w * 0.42, y + h * 0.3, x + w * 0.58, y + h * 0.56], radius=8, fill=(255, 214, 90, 255),
                        outline=(40, 22, 10, 255), width=6)


def shape(kind):
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    if kind == "@star2":
        star(d, S * 0.42, S * 0.52, 150, (255, 214, 80, 255))
        star(d, S * 0.7, S * 0.36, 82, (255, 236, 150, 255))
    elif kind == "@gift":
        d.rounded_rectangle([140, 200, 372, 400], radius=20, fill=(40, 10, 14, 255))
        d.rounded_rectangle([150, 210, 362, 390], radius=16, fill=(255, 220, 110, 255))
        d.rectangle([236, 200, 276, 400], fill=(232, 46, 56, 255))
        d.rounded_rectangle([124, 160, 388, 220], radius=16, fill=(40, 10, 14, 255))
        d.rounded_rectangle([132, 168, 380, 212], radius=12, fill=(255, 236, 160, 255))
        d.rectangle([236, 160, 276, 220], fill=(232, 46, 56, 255))
        d.ellipse([186, 104, 256, 170], outline=(232, 46, 56, 255), width=18)
        d.ellipse([256, 104, 326, 170], outline=(232, 46, 56, 255), width=18)
    elif kind == "@crate":
        crate(d, 116, 150, 280, (196, 128, 64, 255))
    elif kind == "@crate3":
        crate(d, 70, 210, 190, (176, 112, 54, 255))
        crate(d, 250, 210, 190, (176, 112, 54, 255))
        crate(d, 160, 110, 190, (206, 138, 70, 255))
    elif kind == "@autopop":
        return auto_pop()
    elif kind == "@crate10":
        for i, (x, y) in enumerate(((60, 250), (190, 250), (320, 250), (125, 160), (255, 160), (190, 80))):
            crate(d, x, y, 130, (186 + i * 6, 122, 58, 255))
    return g


def bubble(out, cx, cy, r, top, bot, icon, popping=False):
    """A bubble the way the match draws it: a gradient core, a white rim, its glyph; popping: burst rays."""
    b = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(b)
    if popping:
        for i in range(10):
            a = i * math.pi / 5 + 0.3
            r0, r1 = r * 1.22, r * 1.62
            d.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * r1, cy + math.sin(a) * r1)],
                   fill=(255, 255, 255, 235), width=max(6, int(r * 0.13)))
    yy, xx = np.mgrid[0:S, 0:S]
    k = np.clip((yy - (cy - r)) / (2 * r), 0, 1)[..., None]
    col = np.array(top, np.float32) * (1 - k) + np.array(bot, np.float32) * k
    inside = ((xx - cx) ** 2 + (yy - cy) ** 2) <= r * r
    core = np.zeros((S, S, 4), np.uint8)
    core[..., :3] = np.clip(col, 0, 255).astype(np.uint8)
    core[..., 3] = inside * 255
    b.alpha_composite(Image.fromarray(core, "RGBA"))
    d = ImageDraw.Draw(b)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 245), width=max(5, int(r * 0.1)))
    # (the shine on its own layer: drawing a translucent fill straight onto the core would cut a hole)
    hi = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hi).ellipse([cx - r * 0.55, cy - r * 0.72, cx - r * 0.12, cy - r * 0.42], fill=(255, 255, 255, 150))
    b.alpha_composite(hi)
    g = Image.open(os.path.join(REPO, "build", icon)).convert("RGBA")
    box = g.split()[3].getbbox()
    if box:
        g = g.crop(box)
    kk = r * 1.1 / max(g.width, g.height)
    g = g.resize((max(1, int(g.width * kk)), max(1, int(g.height * kk))), Image.LANCZOS)
    b.alpha_composite(g, (int(cx - g.width / 2), int(cy - g.height / 2)))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(b.split()[3].point(lambda v: int(v * 0.5)))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(9)), (6, 12))
    out.alpha_composite(b)


def auto_pop():
    """Auto Pop Bubbles: a DNA, a cure and a hotspot bubble, the big one bursting by itself."""
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bubble(g, 190, 280, 112, (255, 156, 66), (226, 52, 30), "plague_icons/dna.png", popping=True)
    bubble(g, 368, 160, 70, (120, 196, 255), (34, 98, 222), "plague_icons/cure.png")
    bubble(g, 372, 372, 64, (255, 96, 96), (196, 18, 30), "plague_icons/infect.png")
    return g


def glyph(path, size=300):
    im = Image.open(os.path.join(REPO, "build", path)).convert("RGBA")
    box = im.split()[3].getbbox()
    if box:
        im = im.crop(box)
    k = size / max(im.width, im.height)
    im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    a = im.split()[3]
    shadow.putalpha(a.point(lambda v: int(v * 0.55)))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    x, y = (S - im.width) // 2, (S - im.height) // 2
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)), (x + 8, y + 14))
    out.alpha_composite(im, (x, y))
    return out


def hash2(x, y):
    return np.mod(np.sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)


def vnoise(x, y):
    xi, yi = np.floor(x), np.floor(y)
    fx, fy = x - xi, y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a, b, c, d = hash2(xi, yi), hash2(xi + 1, yi), hash2(xi, yi + 1), hash2(xi + 1, yi + 1)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy


def swatch(a, b, rainbow=False):
    """A flat-top hex filled with the colour in the map's soft patches (a -> b by the noise)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    n = vnoise(xx / 46, yy / 46) * 0.65 + vnoise(xx / 18 + 17, yy / 18 + 31) * 0.35
    if rainbow:
        import colorsys
        rgb = np.zeros((S, S, 3))
        hs = (n * 1.4 + xx / S * 0.4) % 1.0
        for i in range(0, S, 4):
            for j in range(0, S, 4):
                r, g, bb = colorsys.hsv_to_rgb(hs[i, j], 0.75, 1.0)
                rgb[i:i + 4, j:j + 4] = (r * 255, g * 255, bb * 255)
    else:
        A, B = np.array(a, dtype=np.float64), np.array(b, dtype=np.float64)
        rgb = A[None, None, :] * (1 - n[..., None]) + B[None, None, :] * n[..., None]
    im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    mask = Image.new("L", (S, S), 0)
    r = 180
    cx, cy = S / 2, S / 2 + 6
    pts = [(cx + r * math.cos(math.pi / 3 * i), cy + r * 0.92 * math.sin(math.pi / 3 * i)) for i in range(6)]
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    edge = Image.new("L", (S, S), 0)
    big = [(cx + (r + 14) * math.cos(math.pi / 3 * i), cy + (r + 14) * 0.92 * math.sin(math.pi / 3 * i)) for i in range(6)]
    ImageDraw.Draw(edge).polygon(big, fill=255)
    out.paste((250, 250, 255, 255), (0, 0), edge)
    out.paste(im, (0, 0), mask)
    gl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([150, 120, 300, 200], fill=(255, 255, 255, 70))
    out.alpha_composite(Image.composite(gl.filter(ImageFilter.GaussianBlur(14)), Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))
    return out


def colours():
    """The infection colours, read from src/shared/Data/Strains.luau (the one list)."""
    import re
    src = open(os.path.join(REPO, "src", "shared", "Data", "Strains.luau"), encoding="utf-8").read()
    out = []
    for m in re.finditer(r'\{\s*key = "(\w+)",\s*name = "([^"]+)",\s*rarity = "(\w+)",\s*a = \{ (\d+), (\d+), (\d+) \},'
                         r'\s*b = \{ (\d+), (\d+), (\d+) \}(,\s*rainbow = true)?', src):
        k, name, rarity = m.group(1), m.group(2), m.group(3)
        a = tuple(int(m.group(i)) for i in (4, 5, 6))
        b = tuple(int(m.group(i)) for i in (7, 8, 9))
        out.append((k, a, b, m.group(10) is not None))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, (col, g) in GLYPHS.items():
        im = tile(col)
        im.alpha_composite(shape(g) if g.startswith("@") else glyph(g))
        im.save(os.path.join(OUT, key + ".png"))
    n = 0
    if os.path.exists(os.path.join(REPO, "src", "shared", "Data", "Strains.luau")):
        for k, a, b, rb in colours():
            im = tile(((a[0] + b[0]) // 2, (a[1] + b[1]) // 2, (a[2] + b[2]) // 2))
            im.alpha_composite(swatch(a, b, rb))
            im.save(os.path.join(OUT, "strain_" + k + ".png"))
            n += 1
    # (Auto Pop's bubbles alone, for the shop's own icon: Assets/PlagueIcons auto_pop)
    auto_pop().save(os.path.join(REPO, "build", "plague_icons", "auto_pop.png"))
    print("icons", len(GLYPHS), "+ strains", n)


if __name__ == "__main__":
    main()
