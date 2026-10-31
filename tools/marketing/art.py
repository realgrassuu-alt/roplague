"""RoPlague marketing art: the game's own World map, painted (2026-10-30).

A stylized take on the map the game draws (Data/Maps/World + WorldCountries): navy ocean with a shallow
halo, smooth coasts and borders, muted neutral countries, and bright plague territories with a glowing
rim, a white front where two plagues meet, the plague's mottled flush, virus specks; then the badges
(game icons in dark discs), curved arrows, outlined numbers and the title.

Used by make_art.py (icons + thumbnails) and make_trailer.py (the trailer's frames).
"""

import base64
import json
import math
import os
import re

import numpy as np
import zstandard
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ART = r"C:\Users\PC\Desktop\RoPlague_Artwork"
FONTS = os.path.join(ART, "_fonts")
ICONS = os.path.join(REPO, "build", "plague_icons")
MW, MH = 2000, 1000

PLAGUE = {
    "crimson": (255, 58, 64),
    "toxic": (72, 226, 92),
    "violet": (168, 92, 255),
    "orange": (255, 152, 40),
    "cure": (78, 172, 255),
    "gold": (255, 208, 50),
}


# ---------------------------------------------------------------------------------------------
# The map data
# ---------------------------------------------------------------------------------------------

def _decode(path, key):
    s = open(path, encoding="utf-8").read()
    m = re.search(key + r' = "([A-Za-z0-9+/=]+)"', s)
    raw = zstandard.ZstdDecompressor().decompress(base64.b64decode(m.group(1)), max_output_size=MW * MH * 2)
    return np.frombuffer(raw, dtype=np.uint8).reshape(MH, MW)


class World:
    def __init__(self):
        maps = os.path.join(REPO, "src", "shared", "Data", "Maps")
        self.terrain = _decode(os.path.join(maps, "World.luau"), "terrain")
        self.grid = _decode(os.path.join(maps, "WorldCountries.luau"), "grid")
        s = open(os.path.join(maps, "WorldCountries.luau"), encoding="utf-8").read()
        self.iso = {}
        self.name = {}
        for i, m in enumerate(re.finditer(r'iso = "([a-z0-9-]+)".*?label = (\d+)', s), start=1):
            self.iso[m.group(1)] = (i, int(m.group(2)))
        for i, m in enumerate(re.finditer(r'name = "([^"]+)"', s), start=1):
            self.name[i] = m.group(1)
        self.land = (self.terrain >= 128).astype(np.float32)
        g = self.grid
        b = np.zeros_like(g, dtype=bool)
        for ax, sh in ((0, 1), (0, -1), (1, 1), (1, -1)):
            r = np.roll(g, sh, ax)
            b |= (r != g) & (g > 0) & (r > 0)
        self.border = b.astype(np.float32)
        # neutral land: muted dark greens / teals / slates, one per country
        rng = np.random.default_rng(7)
        tones = np.array([[56, 142, 92], [70, 156, 98], [56, 130, 116], [94, 152, 84], [68, 122, 146], [112, 152, 92]], np.float32)
        pal = np.zeros((256, 3), np.float32)
        pal[1:] = tones[rng.integers(0, len(tones), 255)] * rng.uniform(0.9, 1.1, (255, 1))
        self.pal = pal
        # terrain relief for shading the land
        mag = (self.terrain & 31).astype(np.float32)
        self.relief = np.where(self.terrain >= 128, mag / 31.0, 0).astype(np.float32)

    def cid(self, iso):
        return self.iso[iso][0]

    def label(self, iso):
        t = self.iso[iso][1]
        return t % MW, t // MW

    def mask(self, isos):
        ids = [self.cid(c) for c in isos if c in self.iso]
        return np.isin(self.grid, ids).astype(np.float32)

    def centre(self, isos):
        pts = [self.label(c) for c in isos if c in self.iso]
        return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)


# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------

def _view(arr, box, size, resample=Image.BILINEAR):
    im = Image.fromarray(arr.astype(np.float32), "F")
    return np.asarray(im.transform(size, Image.EXTENT, box, resample=resample), dtype=np.float32)


def _view_rgb(arr, box, size):
    chans = [_view(arr[..., k], box, size, Image.NEAREST) for k in range(3)]
    return np.stack(chans, -1)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _noise(size, scale, seed):
    rng = np.random.default_rng(seed)
    w, h = size
    small = rng.random((max(2, h // scale + 2), max(2, w // scale + 2))).astype(np.float32)
    im = Image.fromarray(small, "F").resize((w, h), Image.BICUBIC)
    return np.asarray(im, np.float32)


def render_map(world, centre, span, size=(1920, 1080), territories=(), seams=True, specks=False, seed=1, dim=1.0):
    """The painted map around `centre` (tile x, y), `span` tiles wide, `size` px.

    territories: list of dicts {mask: tile-res float array, color: rgb, glow: 0..1}
    Returns an RGB float array (0..255) and the box (x0, y0, x1, y1) in tile coords.
    """
    W, H = size
    cx, cy = centre
    sh = span * H / W
    box = (cx - span / 2, cy - sh / 2, cx + span / 2, cy + sh / 2)
    ppt = W / span  # px per tile
    land_raw = _view(world.land, box, size)
    land = ndimage.gaussian_filter(land_raw, max(1.0, ppt * 0.55))
    coast = smoothstep(0.45, 0.55, land)
    # ocean: deep navy, lighter in the shallows, a little grain
    yy = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    ocean = np.empty((H, W, 3), np.float32)
    top, bot = np.array([26, 68, 134], np.float32), np.array([16, 46, 100], np.float32)
    ocean[:] = top * (1 - yy[..., None]) + bot * yy[..., None]
    halo = ndimage.gaussian_filter(land_raw, ppt * 4.0)
    ocean += (np.array([50, 110, 180], np.float32) * np.clip(halo * 1.3, 0, 1)[..., None]) * 0.5
    ocean *= (0.94 + 0.08 * _noise(size, 90, seed))[..., None]
    # land: each country its muted tone, relief shading, soft borders
    fill = _view_rgb(world.pal[world.grid], box, size)
    fill = np.stack([ndimage.gaussian_filter(fill[..., k], max(0.8, ppt * 0.35)) for k in range(3)], -1)
    relief = _view(world.relief, box, size)
    relief = ndimage.gaussian_filter(relief, max(1.0, ppt * 0.6))
    landc = fill * (0.86 + 0.32 * relief[..., None])
    landc *= (0.95 + 0.1 * _noise(size, 40, seed + 1))[..., None]
    border = _view(world.border, box, size)
    border = np.clip(ndimage.gaussian_filter(border, max(0.7, ppt * 0.25)) * 2.2, 0, 1) * coast
    landc = landc * (1 - 0.32 * border[..., None])
    # territories (the plagues)
    alphas = []
    for t in territories:
        m = _view(t["mask"], box, size)
        m = smoothstep(0.44, 0.56, ndimage.gaussian_filter(m, max(0.9, ppt * 0.38))) * coast
        alphas.append(m)
        col = np.array(t["color"], np.float32)
        inner = ndimage.gaussian_filter(m, max(6.0, ppt * 4.0))
        # (lit from above, as RoWorld's art is: a touch lighter at the top of the frame)
        shade = (0.9 + 0.16 * np.clip(inner, 0, 1)) * (1.08 - 0.14 * yy)
        mott = 0.94 + 0.09 * _noise(size, int(max(18, ppt * 6)), seed + 3)
        tc = col[None, None, :] * (shade * mott)[..., None]
        # the game's darker patches of the dead / densest infection
        if t.get("patches", True):
            p = _noise(size, int(max(30, ppt * 10)), seed + 5)
            tc *= (1 - 0.1 * smoothstep(0.62, 0.9, p))[..., None]
        landc = landc * (1 - m[..., None]) + tc * m[..., None]
        # rim: a light line just inside the edge, and the plague's glow outside it
        edge = np.clip(m - ndimage.gaussian_filter(m, max(1.2, ppt * 0.45)), 0, 1) * 2.4
        landc = landc + (np.array([255, 255, 255], np.float32) - landc) * (np.clip(edge, 0, 1) * 0.7)[..., None]
        t["_alpha"] = m
    img = ocean * (1 - coast[..., None]) + landc * coast[..., None]
    for t in territories:
        m = t["_alpha"]
        glow = ndimage.gaussian_filter(m, max(4.0, ppt * 1.8)) * (1 - m)
        img = img + np.array(t["color"], np.float32)[None, None, :] * (glow * 0.55 * t.get("glow", 1.0))[..., None]
    # the front: a bright jagged seam where two plagues meet
    if seams and len(alphas) >= 2:
        sw = max(1.6, ppt * 0.5)
        for i in range(len(alphas)):
            for j in range(i + 1, len(alphas)):
                a = ndimage.gaussian_filter(alphas[i], sw)
                b = ndimage.gaussian_filter(alphas[j], sw)
                seam = np.clip(a * b * 4.0, 0, 1)
                core = smoothstep(0.35, 0.8, seam)
                glow = ndimage.gaussian_filter(seam, sw * 3)
                img = img + (np.array([255, 255, 255], np.float32) - img) * np.clip(core * 0.95 + glow * 0.35, 0, 1)[..., None]
    if specks and territories:
        # virus specks drifting over the plagues
        rng = np.random.default_rng(seed + 9)
        sp = np.zeros((H, W), np.float32)
        n = int(W * H / 2500)
        xs, ys = rng.integers(0, W, n), rng.integers(0, H, n)
        any_m = np.max(np.stack([t["_alpha"] for t in territories]), 0)
        keep = any_m[ys, xs] > 0.5
        sp[ys[keep], xs[keep]] = rng.uniform(0.6, 1.0, keep.sum())
        sp = ndimage.gaussian_filter(sp, 1.6) * 9
        img = img + 255 * np.clip(sp, 0, 1)[..., None] * 0.35
    # vignette
    vx = np.linspace(-1, 1, W, dtype=np.float32)[None, :]
    vy = np.linspace(-1, 1, H, dtype=np.float32)[:, None]
    vig = np.clip(1 - 0.18 * (vx ** 2 + vy ** 2), 0.7, 1)
    img = img * vig[..., None] * dim
    # a little more colour (RoWorld's art is saturated)
    g = img.mean(-1, keepdims=True)
    img = g + (img - g) * 1.18
    return np.clip(img, 0, 255), box


def tile_to_px(box, size, x, y):
    x0, y0, x1, y1 = box
    return (x - x0) / (x1 - x0) * size[0], (y - y0) / (y1 - y0) * size[1]


# ---------------------------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------------------------

_font_cache = {}


def font(kind, px):
    key = (kind, px)
    if key not in _font_cache:
        if kind in ("title", "num"):
            f = ImageFont.truetype(os.path.join(FONTS, "LilitaOne-Regular.ttf"), px)
        else:
            f = ImageFont.truetype(os.path.join(FONTS, "Fredoka.ttf"), px)
            try:
                f.set_variation_by_axes([100, 700])
            except Exception:
                pass
        _font_cache[key] = f
    return _font_cache[key]


def to_image(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def text(im, xy, s, px, fill=(255, 255, 255), stroke=(14, 22, 44), kind="title", anchor="mm", shadow=True, sw=None):
    """Chunky outlined text with a soft drop shadow (RoWorld's thumbnail style)."""
    f = font(kind, px)
    sw = sw if sw is not None else max(3, px // 9)
    if shadow:
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(sh)
        d.text((xy[0] + px * 0.04, xy[1] + px * 0.07), s, font=f, fill=(0, 0, 0, 170), anchor=anchor, stroke_width=sw, stroke_fill=(0, 0, 0, 170))
        sh = sh.filter(ImageFilter.GaussianBlur(px * 0.05))
        im.alpha_composite(sh)
    d = ImageDraw.Draw(im)
    d.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=sw, stroke_fill=stroke)


def gradient_text(im, xy, s, px, top=(255, 255, 255), bottom=(255, 214, 150), stroke=(14, 22, 44), kind="title", anchor="mm"):
    """Outlined text whose fill runs from `top` to `bottom` (the title)."""
    f = font(kind, px)
    sw = max(4, px // 8)
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.text((xy[0] + px * 0.03, xy[1] + px * 0.08), s, font=f, fill=(0, 0, 0, 190), anchor=anchor, stroke_width=sw, stroke_fill=(0, 0, 0, 190))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(px * 0.06)))
    d = ImageDraw.Draw(im)
    d.text(xy, s, font=f, fill=(0, 0, 0, 0), anchor=anchor, stroke_width=sw, stroke_fill=stroke)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).text(xy, s, font=f, fill=255, anchor=anchor)
    bb = mask.getbbox()
    if bb is None:
        return
    grad = Image.new("RGBA", im.size, (0, 0, 0, 0))
    g = np.zeros((im.size[1], im.size[0], 4), np.uint8)
    t = np.clip((np.arange(im.size[1]) - bb[1]) / max(1, bb[3] - bb[1]), 0, 1)[:, None]
    for k in range(3):
        g[..., k] = (top[k] * (1 - t) + bottom[k] * t).astype(np.uint8)
    g[..., 3] = 255
    grad = Image.fromarray(g, "RGBA")
    im.paste(grad, (0, 0), mask)


_icon_cache = {}


def icon(name, px, color=(255, 255, 255)):
    key = (name, px, color)
    if key not in _icon_cache:
        path = None
        for base in (ICONS, os.path.join(REPO, "build", "trait_icons"), os.path.join(ART, "_glyphs")):
            if os.path.exists(os.path.join(base, name + ".png")):
                path = os.path.join(base, name + ".png")
                break
        src = Image.open(path).convert("RGBA")
        src = src.resize((px, px), Image.LANCZOS)
        a = np.asarray(src).copy()
        a[..., 0], a[..., 1], a[..., 2] = color
        _icon_cache[key] = Image.fromarray(a, "RGBA")
    return _icon_cache[key]


def badge(im, xy, name, px=64, ring=(255, 255, 255), fill=(24, 22, 40), glyph=(255, 255, 255)):
    """A game icon in a dark disc with a light rim (RoWorld's structure badges)."""
    r = px // 2
    s = 4
    big = Image.new("RGBA", (px * s + 8 * s, px * s + 8 * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = big.width // 2
    d.ellipse((c - r * s - 3 * s, c - r * s - 3 * s + 3 * s, c + r * s + 3 * s, c + r * s + 3 * s + 3 * s), fill=(0, 0, 0, 120))
    d.ellipse((c - r * s - 3 * s, c - r * s - 3 * s, c + r * s + 3 * s, c + r * s + 3 * s), fill=ring + (255,))
    d.ellipse((c - r * s, c - r * s, c + r * s, c + r * s), fill=fill + (255,))
    big = big.resize((big.width // s, big.height // s), Image.LANCZOS)
    g = icon(name, int(px * 0.62), glyph)
    big.alpha_composite(g, (big.width // 2 - g.width // 2, big.height // 2 - g.height // 2))
    im.alpha_composite(big, (int(xy[0] - big.width / 2), int(xy[1] - big.height / 2)))


def arrow(im, p0, p1, color, width=46, bend=0.25, outline=(255, 255, 255)):
    """A fat curved arrow from p0 to p1: a body that thickens from the tail, a big head, a white rim
    and a soft shadow (RoWorld's attack arrows)."""
    s = 3
    W, H = im.size
    (x0, y0), (x1, y1) = p0, p1
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    nx, ny = -(y1 - y0), (x1 - x0)
    c = (mx + nx * bend, my + ny * bend)
    n = 80
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(((1 - t) ** 2 * x0 + 2 * (1 - t) * t * c[0] + t * t * x1, (1 - t) ** 2 * y0 + 2 * (1 - t) * t * c[1] + t * t * y1))
    seg = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(n)]
    total = sum(seg)
    head = width * 1.35
    acc, cut = 0.0, n
    for i in range(n):
        acc += seg[i]
        if acc >= total - head:
            cut = i
            break

    def shape(grow):
        left, right = [], []
        for i in range(cut + 1):
            x, y = pts[i]
            j = min(i + 1, n)
            dx, dy = pts[j][0] - x, pts[j][1] - y
            l = math.hypot(dx, dy) or 1
            ux, uy = -dy / l, dx / l
            t = i / max(cut, 1)
            w = (width * (0.42 + 0.58 * t)) / 2 + grow
            left.append(((x + ux * w) * s, (y + uy * w) * s))
            right.append(((x - ux * w) * s, (y - uy * w) * s))
        bx, by = pts[cut]
        dx, dy = x1 - bx, y1 - by
        l = math.hypot(dx, dy) or 1
        ux, uy = dx / l, dy / l
        hw = width * 1.0 + grow * 1.4
        tip = ((x1 + ux * grow * 1.6) * s, (y1 + uy * grow * 1.6) * s)
        bl = ((bx - uy * hw - ux * grow) * s, (by + ux * hw - uy * grow) * s)
        br = ((bx + uy * hw - ux * grow) * s, (by - ux * hw - uy * grow) * s)
        return left + [bl, tip, br] + right[::-1]

    layer = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon(shape(width * 0.14), fill=outline + (255,))
    d.polygon(shape(0), fill=color + (255,))
    # a lighter stripe along the body: the arrow reads as rounded
    hi = tuple(min(255, int(v + (255 - v) * 0.45)) for v in color)
    d.line([(x * s, y * s) for x, y in pts[2:cut]], fill=hi + (150,), width=int(width * 0.18 * s))
    layer = layer.resize((W, H), Image.LANCZOS)
    a = np.asarray(layer).copy()
    sh = np.zeros_like(a)
    sh[..., 3] = (a[..., 3] * 0.55).astype(np.uint8)
    shadow = Image.fromarray(sh, "RGBA").filter(ImageFilter.GaussianBlur(9))
    im.alpha_composite(shadow, (5, 9))
    im.alpha_composite(layer)


def pill(im, xy, s, px, fill=(232, 42, 52), fg=(255, 255, 255), anchor="mm"):
    """A rounded banner with text on it."""
    f = font("title", px)
    d = ImageDraw.Draw(im)
    bb = d.textbbox((0, 0), s, font=f)
    w, h = bb[2] - bb[0] + px * 1.2, px * 1.45
    x, y = xy
    if anchor == "mm":
        x0, y0 = x - w / 2, y - h / 2
    else:
        x0, y0 = x, y
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x0 + 4, y0 + 8, x0 + w + 4, y0 + h + 8), h / 2, fill=(0, 0, 0, 140))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8)))
    d.rounded_rectangle((x0 - 4, y0 - 4, x0 + w + 4, y0 + h + 4), h / 2 + 4, fill=(255, 255, 255, 255))
    d.rounded_rectangle((x0, y0, x0 + w, y0 + h), h / 2, fill=fill + (255,))
    d.text((x0 + w / 2, y0 + h / 2 + px * 0.04), s, font=f, fill=fg, anchor="mm", stroke_width=max(2, px // 14), stroke_fill=(14, 22, 44))


def number(im, xy, s, px):
    """A big troop-count style number: dark navy letters, thick white rim, soft shadow."""
    text(im, xy, s, px, fill=(18, 24, 48), stroke=(255, 255, 255), kind="num", sw=max(4, px // 11))


def save(im, path):
    """Saves (to a temporary name first, so a picture open in a viewer does not stop the run)."""
    tmp = path + ".tmp.png"
    im.convert("RGB").save(tmp, optimize=True)
    for _ in range(20):
        try:
            os.replace(tmp, path)
            return path
        except OSError:
            import time

            time.sleep(0.25)
    alt = path.replace(".png", "_new.png")
    os.replace(tmp, alt)
    return alt


def fmt(n):
    if n >= 1e9:
        return ("%.1fB" % (n / 1e9)).replace(".0B", "B")
    if n >= 1e6:
        return "%dM" % round(n / 1e6)
    if n >= 1e3:
        return "%dK" % round(n / 1e3)
    return str(int(n))
