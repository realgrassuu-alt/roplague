"""RoPlague: five "LVL 1 vs LVL 100" thumbnails for the home page and ads (2026-10-31).

    .venv/Scripts/python.exe tools/marketing/make_lvl.py [n ...]   ->  RoPlague_Artwork/lvl1curevslevel100

The clickbait format, told only with the game's own art (as make_art's thumbnails are): a level 1 plague is
one small badge and one red country, its Evolve tree bare; a level 100 plague is a huge gold-rimmed virus
badge, every trait hexagon owned, the whole world red. The map, the badges, the trait hexagons, the fonts and
the numbers are make_art's / art's. (A first pass drew cartoon virus characters; the user wants the game's
icons instead.) No links, no gore, no skulls.
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art  # noqa: E402
import make_art as ma  # noqa: E402

OUT = os.path.join(art.ART, "lvl1curevslevel100")
S = (1920, 1080)
INK = (14, 22, 44)  # the title's stroke
P = art.PLAGUE
RED_DISC = ma.RED_DISC
GOLD_RING = (255, 206, 60)

# the Evolve screen's traits, in their node colours (make_art's evolve thumbnail)
TRAITS = [("air1", (80, 160, 255)), ("water1", (60, 210, 240)), ("cough", (255, 160, 50)), ("fever", (255, 120, 70)),
          ("insect1", (120, 220, 100)), ("pneumonia", (250, 90, 100)), ("organs", (220, 70, 140)), ("shield1", (160, 130, 255))]
LOCKED = (64, 68, 86)
# the germ badges, less the skull (kept off ads)
GERMS = tuple(g for g in ma.GERMS if g != "death")

GOLD = ((255, 236, 120), (255, 150, 20))
GREY = ((206, 214, 224), (128, 140, 160))
GREEN = ((180, 245, 140), (70, 176, 70))
ORANGE = ((255, 190, 120), (230, 90, 30))


# =============================================================================================
# Pieces
# =============================================================================================

def place(im, sprite, xy):
    im.alpha_composite(sprite, (int(xy[0] - sprite.width / 2), int(xy[1] - sprite.height / 2)))


def glow(im, xy, r, col=(255, 40, 60), k=1.0):
    """A soft hot disc behind something (the level 100 burns)."""
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x, y = xy
    d.ellipse((x - r, y - r, x + r, y + r), fill=col + (int(210 * k),))
    im.alpha_composite(lay.filter(ImageFilter.GaussianBlur(r * 0.35)))


def big_virus(im, xy, px, gold=True):
    """The level 100: the game's virus badge, huge, gold-rimmed, glowing."""
    glow(im, xy, px * 0.85)
    if gold:
        # (a fat gold rim, outlined: the badge's own rim is a hairline at this size)
        d = ImageDraw.Draw(im)
        x, y = xy
        for r, col in ((px * 0.5 + px * 0.085, INK), (px * 0.5 + px * 0.065, GOLD_RING)):
            d.ellipse((x - r, y - r, x + r, y + r), fill=col + (255,))
    art.badge(im, xy, "virus", px, ring=GOLD_RING if gold else (255, 255, 255), fill=RED_DISC)


def small_virus(im, xy, px):
    art.badge(im, xy, "virus", px, ring=(255, 255, 255), fill=RED_DISC)


def hex_ring(im, centre, radius, size, n, start=-90, spread=360, owned=None):
    """`n` trait hexagons around `centre` (the Evolve tree's nodes), owned or locked."""
    for k in range(n):
        a = math.radians(start + (spread * (k + 0.5) / n if spread < 360 else spread * k / n))
        x, y = centre[0] + math.cos(a) * radius, centre[1] + math.sin(a) * radius
        g, col = TRAITS[k % len(TRAITS)]
        if owned is None or owned[k]:
            ma.hexagon(im, (x, y), size, col, glyph=g)
        else:
            ma.hexagon(im, (x, y), size, LOCKED, glyph="lock")


def honeycomb(im, centre, r, owned):
    """The Evolve tree as a block: two rows of four trait hexagons, the second row offset."""
    cx, cy = centre
    for j, (g, col) in enumerate(TRAITS):
        ci, row = j % 4, j // 4
        x = cx + (ci - 1.5) * r * 2.3 + (r * 1.15 if row == 1 else 0) - r * 0.575
        y = cy + (row - 0.5) * r * 1.95
        if owned[j]:
            ma.hexagon(im, (x, y), r, col, glyph=g)
        else:
            ma.hexagon(im, (x, y), r, LOCKED, glyph="lock")


def tag(im, xy, s, px, top, bottom, ring=(255, 255, 255), tilt=0.0):
    """A level tag: a fat rounded plate in a two-stop gradient, a white rim, outlined capitals."""
    f = art.font("title", px)
    bb = ImageDraw.Draw(Image.new("RGBA", (8, 8))).textbbox((0, 0), s, font=f)
    w, h = int(bb[2] - bb[0] + px * 0.95), int(px * 1.32)
    pad = int(px * 0.5)
    lay = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x0, y0 = pad, pad
    sh = Image.new("RGBA", lay.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x0 + 6, y0 + 12, x0 + w + 6, y0 + h + 12), h * 0.36, fill=(0, 0, 0, 150))
    lay.alpha_composite(sh.filter(ImageFilter.GaussianBlur(px * 0.12)))
    rw = max(5, px // 9)
    d.rounded_rectangle((x0 - rw - 3, y0 - rw - 3, x0 + w + rw + 3, y0 + h + rw + 3), h * 0.36 + rw, fill=INK + (255,))
    d.rounded_rectangle((x0 - rw, y0 - rw, x0 + w + rw, y0 + h + rw), h * 0.36 + rw, fill=ring + (255,))
    g = np.zeros((h, w, 4), np.uint8)
    t = np.linspace(0, 1, h)[:, None]
    for k in range(3):
        g[..., k] = (top[k] * (1 - t) + bottom[k] * t).astype(np.uint8)
    g[..., 3] = 255
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), h * 0.36, fill=255)
    lay.paste(Image.fromarray(g, "RGBA"), (x0, y0), m)
    gl = Image.new("RGBA", lay.size, (0, 0, 0, 0))
    ImageDraw.Draw(gl).rounded_rectangle((x0 + h * 0.18, y0 + h * 0.1, x0 + w - h * 0.18, y0 + h * 0.42), h * 0.16, fill=(255, 255, 255, 70))
    lay.alpha_composite(gl)
    d.text((x0 + w / 2, y0 + h / 2 + px * 0.05), s, font=f, fill=(255, 255, 255), anchor="mm", stroke_width=max(4, px // 9), stroke_fill=INK)
    if tilt:
        lay = lay.rotate(tilt, resample=Image.BICUBIC, expand=True)
    place(im, lay, xy)


def vs(im, xy, px=230):
    """VS on a red starburst."""
    x, y = xy
    n, r0, r1 = 14, px * 0.62, px * 0.95
    pts = []
    for k in range(n * 2):
        a = math.pi * k / n - math.pi / 2
        r = r1 if k % 2 == 0 else r0
        pts.append((x + math.cos(a) * r, y + math.sin(a) * r))
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(a + 8, b + 14) for a, b in pts], fill=(0, 0, 0, 150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(12)))
    d = ImageDraw.Draw(im)
    d.polygon([(x + (a - x) * 1.09, y + (b - y) * 1.09) for a, b in pts], fill=INK + (255,))
    d.polygon([(x + (a - x) * 1.04, y + (b - y) * 1.04) for a, b in pts], fill=(255, 255, 255, 255))
    d.polygon(pts, fill=(230, 30, 40, 255))
    d.polygon([(x + (a - x) * 0.72, y + (b - y) * 0.72) for a, b in pts], fill=(255, 70, 60, 255))
    art.gradient_text(im, (x, y + px * 0.02), "VS", int(px * 0.78), top=(255, 250, 200), bottom=(255, 196, 30), stroke=INK)


def split(left, right, x_top, x_bot, seed=3):
    """The left picture and the right one, cut along a jagged white seam from (x_top, 0) to (x_bot, H)."""
    W, H = left.size
    rng = np.random.default_rng(seed)
    pts = []
    k = 9
    for i in range(k + 1):
        t = i / k
        x = x_top + (x_bot - x_top) * t + (rng.uniform(-38, 38) if 0 < i < k else 0)
        pts.append((x, -20 + (H + 40) * t))
    mask = Image.new("L", left.size, 0)
    ImageDraw.Draw(mask).polygon([(-10, -20)] + pts + [(-10, H + 20)], fill=255)
    out = right.copy()
    out.paste(left, (0, 0), mask)
    g = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).line(pts, fill=(255, 240, 200, 255), width=44, joint="curve")
    out.alpha_composite(g.filter(ImageFilter.GaussianBlur(18)))
    d = ImageDraw.Draw(out)
    d.line(pts, fill=INK + (255,), width=26, joint="curve")
    d.line(pts, fill=(255, 255, 255, 255), width=16, joint="curve")
    return out


def map_tiny(world, isos, colour, at_iso, at_px, span, dim=0.74, seed=1):
    """The level 1 side: a dim, quiet map, one small country in `colour`, its label landing on `at_px`.
    Returns the picture and where that country is (px)."""
    ppt = S[0] / span
    lx, ly = world.label(at_iso)
    centre = (lx - (at_px[0] - S[0] / 2) / ppt, ly - (at_px[1] - S[1] / 2) / ppt)
    t = [{"mask": world.mask(isos), "color": colour, "glow": 1.6}]
    img, box = art.render_map(world, centre, span, size=S, territories=t, seed=seed, dim=dim)
    return art.to_image(img), art.tile_to_px(box, S, lx, ly)


def map_world(world, centre=(1000, 470), span=1700, seed=2, dim=1.0):
    """The level 100 side: everyone red."""
    every = [k for k in world.iso if k not in ("aq", "gl")]
    img, box = art.render_map(world, centre, span, size=S, territories=[{"mask": world.mask(every), "color": P["crimson"], "glow": 0.9}],
                              seed=seed, dim=dim, specks=True)
    return art.to_image(img), box


def ping(im, xy, r, col=(255, 70, 70)):
    """Rings around the one infected spot: look here."""
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x, y = xy
    for k, a in ((1.0, 255), (1.55, 150), (2.1, 70)):
        rr = r * k
        d.ellipse((x - rr, y - rr, x + rr, y + rr), outline=col + (a,), width=max(4, int(r * 0.12)))
    im.alpha_composite(lay)


def red_wash(im, strength=0.35):
    """A hot red vignette (the level 100 side burns)."""
    W, H = im.size
    vx = np.linspace(-1, 1, W, dtype=np.float32)[None, :]
    vy = np.linspace(-1, 1, H, dtype=np.float32)[:, None]
    v = np.clip((vx ** 2 + vy ** 2) * 0.55, 0, 1)[..., None] * strength
    a = np.asarray(im).astype(np.float32)
    a[..., :3] = a[..., :3] * (1 - v) + np.array([120, 0, 20], np.float32) * v
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def chevron(im, xy, h, col=(255, 214, 40)):
    x, y = xy
    pts = [(x - h * 0.35, y - h * 0.5), (x + h * 0.35, y), (x - h * 0.35, y + h * 0.5), (x - h * 0.05, y)]
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(a + 4, b + 7) for a, b in pts], fill=(0, 0, 0, 150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(5)))
    ImageDraw.Draw(im).polygon(pts, fill=col + (255,), outline=INK + (255,), width=max(4, int(h * 0.09)))


# =============================================================================================
# The five thumbnails
# =============================================================================================

def t1(world):
    """The classic: one small badge by its one red country; a huge gold virus ringed by every trait."""
    left, lk = map_tiny(world, ["lk"], P["crimson"], "lk", (300, 900), 300, seed=11)
    right, _ = map_world(world, seed=12)
    ping(left, lk, 34)
    im = split(left, red_wash(right, 0.4), 1010, 900, seed=4)
    small_virus(im, (480, 600), 170)
    tag(im, (470, 360), "LVL 1", 120, *GREY, tilt=4)
    big_virus(im, (1500, 610), 320)
    hex_ring(im, (1500, 610), 272, 60, 8, start=-90)
    tag(im, (1500, 110), "LVL 100", 140, *GOLD, tilt=-3)
    vs(im, (945, 560), 190)
    return im


def t2(world):
    """The numbers: 1 infected against the whole world, germ badges all over it."""
    left, lk = map_tiny(world, ["lk"], P["crimson"], "lk", (560, 700), 150, seed=21)
    right, box = map_world(world, seed=22)
    ping(left, lk, 60)
    for iso, g in zip(("cn", "in", "au", "ir", "kz", "id", "mn"), GERMS):
        x, y = ma.at(world, box, S, iso)
        if x > 1080 and 270 < y < 840:
            art.badge(right, (x, y), g, 100, ring=(255, 255, 255), fill=RED_DISC)
    im = split(left, red_wash(right, 0.35), 950, 1010, seed=8)
    art.arrow(im, (250, 470), (lk[0] - 75, lk[1] - 70), (255, 220, 60), 54, bend=0.22)
    small_virus(im, (250, 830), 150)
    art.number(im, (430, 340), "1 INFECTED", 118)
    tag(im, (430, 140), "LVL 1", 116, *GREY, tilt=3)
    art.number(im, (1450, 940), "8 BILLION", 160)
    tag(im, (1450, 120), "LVL 100", 140, *GOLD, tilt=-3)
    vs(im, (980, 540), 190)
    return im


def t3(world):
    """The evolution: the virus badge growing LVL 1 -> 10 -> 50 -> 100, its traits gathering round it."""
    bg, _ = map_world(world, (1000, 470), 1500, seed=31, dim=0.55)
    im = red_wash(bg, 0.3)
    ground = 830
    rungs = [
        (110, 1, 30, "LVL 1", GREY, 230, 70, False),
        (150, 3, 36, "LVL 10", GREEN, 640, 80, False),
        (200, 5, 40, "LVL 50", ORANGE, 1090, 88, False),
        (270, 8, 46, "LVL 100", GOLD, 1590, 104, True),
    ]
    centres = []
    for px, n, hr, label, cols, x, tpx, top in rungs:
        y = ground - px / 2 - 90 - (hr * 2.4 if n >= 8 else 0)
        centres.append((x, y, px))
    for (x0, y0, p0), (x1, y1, p1) in zip(centres, centres[1:]):
        mid = (x0 + p0 * 0.7 + x1 - p1 * 0.7) / 2
        chevron(im, (mid - 20, y1), 64)
        chevron(im, (mid + 22, y1), 64)
    for (px, n, hr, label, cols, x, tpx, top), (_, y, _) in zip(rungs, centres):
        if top:
            big_virus(im, (x, y), px)
        else:
            small_virus(im, (x, y), px)
        hex_ring(im, (x, y), px * 0.5 + hr * 1.35, hr, n, start=-90 - 22 * (n - 1) if n < 8 else -90,
                 spread=44 * n if n < 8 else 360)
        tag(im, (x, ground + 40), label, tpx, *cols)
    art.gradient_text(im, (960, 130), "EVOLVE TO LVL 100!", 160, top=(255, 255, 255), bottom=(255, 214, 120), stroke=INK)
    return im


ASIA = ["ru", "cn", "mn", "kz", "in", "pk", "af", "ir", "iq", "sa", "tr", "uz", "tm", "kg", "tj", "np", "bd", "mm",
        "th", "la", "vn", "kh", "my", "id", "kp", "kr", "bt", "sy", "jo", "ye", "om", "ae"]


def t4(world):
    """Two plagues on one map: a level 1 holding one small country, a level 100 holding a continent."""
    green = P["toxic"]
    terr = [{"mask": world.mask(ASIA), "color": P["crimson"], "glow": 1.0},
            {"mask": world.mask(["jp"]), "color": green, "glow": 1.6}]
    img, box = art.render_map(world, (1490, 330), 560, size=S, territories=terr, seed=41)
    im = red_wash(art.to_image(img), 0.25)
    jp = ma.at(world, box, S, "jp")
    rng = np.random.default_rng(41)
    for iso, g in zip(("ru", "in", "kz", "mn", "ir", "pk"), GERMS):
        x, y = ma.at(world, box, S, iso)
        if 120 < x < 1500 and 200 < y < 960 and math.hypot(x - 900, y - 560) > 260 and not (1050 < x < 1500 and 380 < y < 640):
            art.badge(im, (x + rng.uniform(-30, 30), y), g, 104, ring=(255, 255, 255), fill=RED_DISC)
    big_virus(im, (900, 560), 260)
    art.arrow(im, (1130, 520), (jp[0] - 70, jp[1] - 10), P["crimson"], 70, bend=-0.25)
    art.badge(im, (jp[0] + 40, jp[1] + 120), "virus", 110, ring=(255, 255, 255), fill=(18, 90, 34))
    tag(im, (jp[0] - 10, jp[1] + 290), "LVL 1", 104, *GREEN, tilt=4)
    tag(im, (900, 870), "LVL 100", 130, *GOLD, tilt=-3)
    art.number(im, (jp[0] + 30, jp[1] - 140), "125M", 120)
    art.number(im, (560, 300), "4.6B", 170)
    art.gradient_text(im, (520, 120), "LVL 1 VS LVL 100", 130, top=(255, 255, 255), bottom=(255, 214, 120), stroke=INK)
    return im


def t5(world):
    """The Evolve tree: bare at level 1 (one trait, the rest locked), full at level 100."""
    left, _ = map_tiny(world, ["lk"], P["crimson"], "in", (480, 540), 420, dim=0.55, seed=51)
    right, _ = map_world(world, seed=52, dim=0.75)
    im = split(left, red_wash(right, 0.45), 990, 930, seed=13)
    honeycomb(im, (440, 600), 62, [True] + [False] * 7)
    glow(im, (1490, 600), 360, k=0.7)
    honeycomb(im, (1490, 600), 62, [True] * 8)
    tag(im, (440, 250), "LVL 1", 130, *GREY, tilt=3)
    tag(im, (1490, 250), "LVL 100", 140, *GOLD, tilt=-3)
    vs(im, (965, 590), 170)
    art.pill(im, (440, 930), "1 / 8 TRAITS", 64, fill=(90, 98, 120))
    art.pill(im, (1490, 930), "MAXED OUT", 64, fill=(230, 40, 50))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    world = art.World()
    only = [int(a) for a in sys.argv[1:]] or [1, 2, 3, 4, 5]
    for i, fn in enumerate((t1, t2, t3, t4, t5), start=1):
        if i in only:
            print("thumbnail", i, art.save(fn(world), os.path.join(OUT, "thumbnail_%02d.png" % i)))


if __name__ == "__main__":
    main()
