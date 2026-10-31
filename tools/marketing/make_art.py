"""RoPlague: 5 experience icons and 20 thumbnails (v2, 2026-10-30), in the style of RoWorld's store art.

    .venv/Scripts/python.exe tools/marketing/glyphs.py      (once: the buildings' glyphs)
    .venv/Scripts/python.exe tools/marketing/make_art.py   ->  RoPlague_Artwork/icons, /thumbnails

The look is RoWorld's: the real map, bright; two territories meeting at a jagged white front; badges in
dark discs; fat arrows; big dark numbers with a white rim; a chunky title. Ours: a red PLAGUE holding
virus badges against a blue CURE holding its syringe and buildings (or plague against plague).
No links, no other game's names or art.
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art  # noqa: E402

P = art.PLAGUE
RED, BLUE = P["crimson"], P["cure"]
RED_DISC, BLUE_DISC = (110, 18, 28), (14, 38, 104)

# the territories (iso codes), in pairs that share a long land border, and where to centre
PAIRS = {
    "africa": (["ma", "dz", "eh", "mr", "ml", "tn"], ["ly", "eg", "ne", "td", "sd"], ["dz", "ly"]),
    "europe": (["fr", "es", "pt", "be", "nl", "lu", "ch", "gb", "ie"], ["de", "pl", "cz", "at", "dk", "it", "sk", "hu", "si", "hr"], ["fr", "de"]),
    "asia": (["in", "pk", "bd", "np", "lk", "bt"], ["cn", "mn", "mm", "kp", "la", "vn", "th", "kh"], ["in", "cn"]),
    "russia": (["ru", "by", "kz"], ["ua", "pl", "fi", "lt", "lv", "ee", "ro", "md", "sk", "hu"], ["ua", "by"]),
    "america": (["us", "mx"], ["ca"], ["us", "ca"]),
    "brazil": (["br", "py", "uy"], ["ar", "bo", "pe", "cl", "co", "ve", "ec", "gy", "sr"], ["br", "bo"]),
    "mideast": (["sa", "iq", "sy", "jo", "ye", "om", "ae", "kw", "qa"], ["ir", "af", "tm", "uz"], ["iq", "ir"]),
    "westafrica": (["ng", "ne", "ml", "bf", "gh", "ci", "gn", "sn", "bj", "tg"], ["td", "cf", "cm", "cd", "sd", "ss"], ["ng", "td"]),
    "southafrica": (["za", "na", "bw", "zw", "ls", "sz"], ["ao", "zm", "mz", "mw", "cd"], ["bw", "zm"]),
    "chinarussia": (["cn", "kp"], ["ru", "mn", "kz"], ["cn", "mn"]),
    "india": (["pk", "af", "ir"], ["in", "np", "bd"], ["pk", "in"]),
    "iberia": (["es", "pt"], ["fr", "be", "ch"], ["es", "fr"]),
}


# the plague's badges: several germs, not one (the virus, then a mix chosen per picture)
GERMS = ("virus", "bacterium", "death", "parasite", "fungus", "cysts", "infect", "pneumonia")


def germs(n, seed):
    rest = list(GERMS[1:])
    np.random.default_rng(seed).shuffle(rest)
    return tuple(["virus"] + rest)[:n]


def terr(world, isos, color, glow=1.0):
    return {"mask": world.mask(isos), "color": color, "glow": glow}


def at(world, box, size, iso, dx=0, dy=0):
    x, y = world.label(iso)
    px, py = art.tile_to_px(box, size, x, y)
    return px + dx, py + dy


def centroid(world, box, size, isos):
    m = world.mask(isos)
    x0, y0, x1, y1 = box
    ys, xs = np.nonzero(m)
    inside = (xs >= x0) & (xs <= x1) & (ys >= y0) & (ys <= y1)
    if inside.sum() > 10:
        xs, ys = xs[inside], ys[inside]
    return art.tile_to_px(box, size, xs.mean(), ys.mean())


def front(world, box, size, a, b):
    """Where two territories meet, in px (the middle of their shared border in view)."""
    from scipy import ndimage

    ma = world.mask(a) > 0
    mb = world.mask(b) > 0
    touch = ndimage.binary_dilation(ma, iterations=2) & ndimage.binary_dilation(mb, iterations=2)
    ys, xs = np.nonzero(touch)
    x0, y0, x1, y1 = box
    inside = (xs >= x0) & (xs <= x1) & (ys >= y0) & (ys <= y1)
    if inside.sum() == 0:
        return None
    return art.tile_to_px(box, size, xs[inside].mean(), ys[inside].mean())


def range_circle(im, xy, r, color=(120, 210, 255)):
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x, y = xy
    d.ellipse((x - r, y - r, x + r, y + r), fill=color + (44,), outline=color + (230,), width=max(3, int(r / 36)))
    im.alpha_composite(lay)


def hexagon(im, xy, r, fill, ring=(255, 255, 255), glyph=None, owned=True):
    s = 4
    big = Image.new("RGBA", (int(r * 2.6 * s), int(r * 2.6 * s)), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = big.width / 2

    def pts(rr, oy=0.0):
        return [(c + rr * math.cos(math.radians(60 * k)), c + oy + rr * math.sin(math.radians(60 * k))) for k in range(6)]

    d.polygon(pts(r * s * 1.12, r * s * 0.12), fill=(0, 0, 0, 120))
    d.polygon(pts(r * s * 1.1), fill=ring + (255,))
    d.polygon(pts(r * s), fill=fill + (255,))
    d.polygon(pts(r * s * 0.86), fill=tuple(min(255, int(v * 1.12)) for v in fill) + (255,))
    big = big.resize((big.width // s, big.height // s), Image.LANCZOS)
    if glyph is not None:
        g = art.icon(glyph, int(r * 1.05))
        big.alpha_composite(g, (big.width // 2 - g.width // 2, big.height // 2 - g.height // 2))
    if not owned:
        a = np.asarray(big).copy()
        a[..., :3] = (a[..., :3] * 0.45).astype(np.uint8)
        big = Image.fromarray(a, "RGBA")
    im.alpha_composite(big, (int(xy[0] - big.width / 2), int(xy[1] - big.height / 2)))


def cure_bar(im, xy, w, pct, label="CURE RESEARCH"):
    x, y = xy
    h = 118
    d = ImageDraw.Draw(im)
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x + 6, y + 10, x + w + 6, y + h + 10), 26, fill=(0, 0, 0, 150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)))
    d.rounded_rectangle((x - 4, y - 4, x + w + 4, y + h + 4), 30, fill=(255, 255, 255, 255))
    d.rounded_rectangle((x, y, x + w, y + h), 26, fill=(16, 30, 70, 255))
    f = art.font("num", 44)
    d.text((x + 30, y + 34), label, font=f, fill=(120, 210, 255), anchor="lm", stroke_width=3, stroke_fill=(10, 14, 30))
    d.text((x + w - 30, y + 34), "%d%%" % pct, font=f, fill=(255, 255, 255), anchor="rm", stroke_width=3, stroke_fill=(10, 14, 30))
    bx0, by0, bx1, by1 = x + 30, y + 70, x + w - 30, y + 96
    d.rounded_rectangle((bx0, by0, bx1, by1), 10, fill=(40, 56, 100))
    d.rounded_rectangle((bx0, by0, bx0 + (bx1 - bx0) * pct / 100, by1), 10, fill=(80, 200, 255))


def scene(world, size, centre, span, territories, dim=1.0, seed=1):
    img, box = art.render_map(world, centre, span, size=size, territories=territories, seed=seed, dim=dim)
    return art.to_image(img), box


def spread_badges(world, box, size, isos, n, rng, avoid=()):
    """`n` spots inside the territory and in view, apart from each other and from `avoid` (px)."""
    m = world.mask(isos)
    ys, xs = np.nonzero(m)
    pts = []
    W, H = size
    margin = 0.1 * min(W, H)
    r = 0.2 * min(W, H)
    for _ in range(6000):
        if len(pts) >= n:
            break
        k = rng.integers(0, len(xs))
        x, y = art.tile_to_px(box, size, xs[k] + 0.5, ys[k] + 0.5)
        if not (margin < x < W - margin and margin < y < H - margin):
            continue
        if all(math.hypot(x - a, y - b) > r for a, b in pts + list(avoid)):
            pts.append((x, y))
    return pts


def clash(world, size, pair, red=RED, blue=BLUE, span=None, shift=(0, 0), seed=1, red_icons=None,
          blue_icons=("cure", "hospital", "lab"), numbers=("102M", "329M"), arrows=True, ranges=False, blue_disc=None,
          red_disc=None, keep_clear=(), badge_k=1.0, num_k=1.0):
    """RoWorld's composition: two territories meeting, an arrow from each into the front, a number on
    each side, badges in each (the plague's viruses; the cure's syringe and buildings)."""
    a, b, mid = PAIRS[pair]
    red_icons = red_icons or germs(3, seed)
    blue_icons = blue_icons or germs(3, seed + 100)
    W, H = size
    cx, cy = world.centre(mid)
    im, box = scene(world, size, (cx + shift[0], cy + shift[1]), span or 360, [terr(world, a, red), terr(world, b, blue)], seed=seed)
    f = front(world, box, size, a, b) or (W / 2, H / 2)
    ca = centroid(world, box, size, a)
    cb = centroid(world, box, size, b)
    scale = min(W, H) / 1080
    # (each side's number well inside its own territory, and never on top of the other's)
    na = [ca[0] * 0.72 + f[0] * 0.28, ca[1] * 0.72 + f[1] * 0.28 + 120 * scale]
    nb = [cb[0] * 0.72 + f[0] * 0.28, cb[1] * 0.72 + f[1] * 0.28 + 120 * scale]
    need = 470 * scale * num_k
    dx, dy = nb[0] - na[0], nb[1] - na[1]
    dist = math.hypot(dx, dy) or 1
    if dist < need:
        push = (need - dist) / 2
        na = [na[0] - dx / dist * push, na[1] - dy / dist * push]
        nb = [nb[0] + dx / dist * push, nb[1] + dy / dist * push]
    for p in (na, nb):
        p[0] = min(max(p[0], 200 * scale * num_k), W - 200 * scale * num_k)
        p[1] = min(max(p[1], 120 * scale), H - 110 * scale)
    na, nb = tuple(na), tuple(nb)
    rng = np.random.default_rng(seed)
    avoid = [na, nb, f] + list(keep_clear)
    bp = spread_badges(world, box, size, a, len(red_icons), rng, avoid)
    bq = spread_badges(world, box, size, b, len(blue_icons), rng, avoid + bp)
    if ranges:
        for p in bq:
            range_circle(im, p, 160 * scale)
    if arrows:
        def toward(src, dst, colour, bend):
            dx, dy = dst[0] - src[0], dst[1] - src[1]
            l = math.hypot(dx, dy) or 1
            s0 = (dst[0] - dx / l * 430 * scale, dst[1] - dy / l * 430 * scale - 30 * scale)
            s1 = (dst[0] - dx / l * 45 * scale, dst[1] - dy / l * 45 * scale - 30 * scale)
            art.arrow(im, s0, s1, colour, int(66 * scale), bend=bend)

        toward(ca, f, red, 0.22)
        toward(cb, f, blue, -0.22)
    for p, icn in zip(bp, red_icons):
        art.badge(im, p, icn, int(112 * scale * badge_k), ring=(255, 255, 255), fill=red_disc or RED_DISC)
    for p, icn in zip(bq, blue_icons):
        art.badge(im, p, icn, int(112 * scale * badge_k), ring=(255, 255, 255), fill=blue_disc or BLUE_DISC)
    if numbers:
        art.number(im, na, numbers[0], int(150 * scale * num_k))
        art.number(im, nb, numbers[1], int(150 * scale * num_k))
    return im, box


def title(im, s="ROPLAGUE", xy=None, px=None):
    W, H = im.size
    px = px or int(H * 0.16)
    xy = xy or (int(W * 0.25), int(H * 0.12))
    art.gradient_text(im, xy, s, px, top=(255, 255, 255), bottom=(255, 236, 200))


def pill(im, s, y=0.25, fill=RED, px=54):
    art.pill(im, (im.size[0] // 2, int(im.size[1] * y)), s, px, fill=fill)


def thumbnails(world):
    S = (1920, 1080)
    out = []
    TL = [(480, 130)]  # (the title's corner: no badge under it)
    # the core: the plague against the cure, all over the world, as RoWorld's own thumbnail
    for i, (pair, nums, span, shift) in enumerate([
        ("africa", ("102M", "329M"), 380, (0, 30)),
        ("europe", ("214M", "391M"), 300, (10, 20)),
        ("asia", ("1.4B", "980M"), 360, (20, 30)),
        ("america", ("331M", "38M"), 600, (0, 10)),
        ("russia", ("146M", "212M"), 470, (30, 0)),
        ("brazil", ("214M", "96M"), 430, (10, 10)),
        ("mideast", ("86M", "120M"), 330, (0, 20)),
        ("westafrica", ("402M", "188M"), 420, (0, 20)),
    ], start=1):
        im, _ = clash(world, S, pair, span=span, shift=shift, seed=i, numbers=nums, keep_clear=TL)
        title(im)
        out.append(im)
    TOP = [(960, 130)]
    # the modes
    im, _ = clash(world, S, "asia", span=380, shift=(20, 40), seed=21, numbers=("1.2B", "640M"), ranges=True, keep_clear=TL + [(290, 290)])
    title(im, "1V1", (int(1920 * 0.12), int(1080 * 0.12)), 200)
    art.pill(im, (int(1920 * 0.15), int(1080 * 0.27)), "PLAGUE VS CURE", 54, fill=RED)
    out.append(im)
    im, _ = clash(world, S, "europe", red=RED, blue=P["toxic"], span=320, seed=22, numbers=("188M", "203M"),
                  blue_icons=None, blue_disc=(18, 90, 34), keep_clear=TOP)
    title(im, "PLAGUE RACE", (960, 130), 170)
    pill(im, "LAST PLAGUE STANDING WINS", 0.9, P["toxic"])
    out.append(im)
    im, _ = clash(world, S, "russia", red=P["orange"], blue=P["violet"], span=480, shift=(30, 0), seed=23, numbers=("180M", "214M"),
                  blue_icons=None, red_disc=(120, 60, 10), blue_disc=(64, 24, 110), keep_clear=TOP)
    title(im, "TEAM PLAGUE", (960, 130), 170)
    pill(im, "DUOS  ·  TRIOS  ·  QUADS", 0.9, P["violet"])
    out.append(im)
    im, _ = clash(world, S, "india", span=330, seed=24, numbers=("312M", "1.4B"), ranges=True,
                  blue_icons=("hospital", "lab", "research", "cure"), keep_clear=TOP)
    title(im, "BE THE CURE", (960, 130), 170)
    pill(im, "BUILD LABS & HOSPITALS", 0.9, BLUE)
    out.append(im)
    im, _ = clash(world, S, "southafrica", span=360, seed=25, numbers=("64M", "92M"), keep_clear=TOP)
    title(im, "CAPTURE COUNTRIES", (960, 130), 150)
    out.append(im)
    im, _ = clash(world, S, "chinarussia", span=520, seed=26, numbers=("1.4B", "170M"), keep_clear=TOP)
    title(im, "WHO WILL WIN?", (960, 130), 160)
    out.append(im)
    im, _ = clash(world, S, "iberia", span=240, shift=(0, 10), seed=27, numbers=("57M", "68M"), keep_clear=TL)
    title(im)
    out.append(im)
    # two more of the core
    im, _ = clash(world, S, "india", span=340, seed=31, numbers=("246M", "1.4B"), keep_clear=TL)
    title(im)
    out.append(im)
    im, _ = clash(world, S, "brazil", red=RED, blue=BLUE, span=430, shift=(10, 10), seed=32, numbers=("214M", "96M"), ranges=True, keep_clear=TOP)
    title(im, "STOP THE PLAGUE", (960, 130), 160)
    pill(im, "PLAY AS THE CURE", 0.9, BLUE)
    out.append(im)
    # evolve
    im, box = scene(world, S, world.centre(["in", "cn"]), 400, [terr(world, PAIRS["asia"][0], RED)], dim=0.6, seed=28)
    nodes = [("air1", (80, 160, 255)), ("water1", (60, 210, 240)), ("cough", (255, 160, 50)), ("fever", (255, 120, 70)),
             ("insect1", (120, 220, 100)), ("pneumonia", (250, 90, 100)), ("organs", (220, 70, 140)), ("shield1", (160, 130, 255))]
    for j, (g, col) in enumerate(nodes):
        col_i, row = j % 4, j // 4
        hexagon(im, (960 + (col_i - 1.5) * 330 + (165 if row == 1 else 0), 560 + row * 270), 140, col, glyph=g, owned=j < 6)
    title(im, "EVOLVE YOUR PLAGUE", (960, 130), 150)
    out.append(im)
    # infect the world
    every = [k for k in world.iso if k not in ("aq", "gl")]
    im, box = scene(world, S, (1000, 470), 1700, [terr(world, every, RED, 0.8)], seed=29)
    for iso, g in zip(("us", "br", "ru", "cn", "in", "cd", "au"), GERMS):
        if iso in world.iso:
            art.badge(im, at(world, box, S, iso), g, 96, ring=(255, 255, 255), fill=RED_DISC)
    title(im, "INFECT THE WORLD", (960, 130), 150)
    art.number(im, (960, 950), "7.9B", 150)
    out.append(im)
    # beat the cure
    im, _ = clash(world, S, "america", span=620, shift=(0, 40), seed=30, numbers=None, ranges=True, keep_clear=TOP + [(960, 910)])
    cure_bar(im, (960 - 420, 860), 840, 97)
    title(im, "BEAT THE CURE", (960, 130), 160)
    out.append(im)
    return out


def icons(world):
    """The brief: a red area held by three viruses, fighting a blue area held by the cure and its
    buildings, at RoWorld's front. Five takes: five regions and framings."""
    S = (512, 512)
    out = []
    specs = [
        ("africa", 170, (0, 25), ("102M", "329M")),
        ("europe", 140, (5, 15), ("214M", "391M")),
        ("asia", 180, (15, 30), ("1.4B", "980M")),
        ("america", 270, (-10, 5), None),
        ("westafrica", 200, (0, 15), None),
    ]
    for i, (pair, span, shift, nums) in enumerate(specs, start=1):
        im, box = clash(world, S, pair, span=span, shift=shift, seed=40 + i, numbers=nums,
                        red_icons=None, blue_icons=("cure", "hospital", "lab"), badge_k=1.55, num_k=0.85)
        out.append(im)
    return out


def main():
    world = art.World()
    os.makedirs(os.path.join(art.ART, "icons"), exist_ok=True)
    os.makedirs(os.path.join(art.ART, "thumbnails"), exist_ok=True)
    for i, im in enumerate(icons(world), start=1):
        print("icon", i, art.save(im, os.path.join(art.ART, "icons", "icon_%02d.png" % i)))
    for i, im in enumerate(thumbnails(world), start=1):
        print("thumbnail", i, art.save(im, os.path.join(art.ART, "thumbnails", "thumbnail_%02d.png" % i)))


if __name__ == "__main__":
    main()
