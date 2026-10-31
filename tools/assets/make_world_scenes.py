"""RoPlague: pictures of the game's own world for the shop's and the Evolve screen's backgrounds.

Renders crops of the World map the way the game draws it (Map/MapSurface: the terrain colours, each
country's colour over it at TERRITORY_ALPHA, a darker border line, and the plague's crimson flush in soft
patches over the infected countries, the same value noise as MapSurface.plague_mix), then softens the
edges. No text in any image.

    .bin/lune.exe run tools/assets/dump_country_colors.luau > build/country_colors.json
    .venv/Scripts/python.exe tools/assets/make_world_scenes.py   ->  build/world_scenes/<name>.png
"""

import base64
import json
import math
import os
import re

import numpy as np
import zstandard
from PIL import Image, ImageFilter

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(REPO, "build", "world_scenes")
W, H = 2000, 1000

OCEAN = (0x47, 0x85, 0xB5)
SAND = (0xCC, 0xCB, 0x9E)
PLAINS = (0xBE, 0xDC, 0x8A)
HIGHLAND = (0xDC, 0xCB, 0x9E)
MOUNTAIN = (0xE6, 0xE6, 0xE6)
ALPHA = 150 / 255
BORDER_DARKEN = 0.125
CRIMSON = np.array([214, 28, 40], dtype=np.float32)

# name: (countries the picture is framed around, {infected country: share 0..1})
SCENES = {
    "europe": (["fr", "de", "it", "pl", "es", "gr"], {"fr": 0.9, "es": 0.6, "de": 0.35, "it": 0.5}),
    "africa": (["ng", "cd", "et", "ao", "td", "ke"], {"ng": 0.9, "cd": 0.7, "cm": 0.6, "td": 0.3}),
    "asia": (["in", "cn", "th", "bd", "mm"], {"in": 0.9, "cn": 0.45, "np": 0.8, "bd": 0.7, "pk": 0.35}),
    "america": (["us", "mx", "gt", "cu"], {"us": 0.55, "mx": 0.85, "cu": 0.5}),
}


def decode(path, key):
    s = open(path, encoding="utf-8").read()
    m = re.search(key + r' = "([A-Za-z0-9+/=]+)"', s)
    raw = zstandard.ZstdDecompressor().decompress(base64.b64decode(m.group(1)), max_output_size=W * H * 2)
    return np.frombuffer(raw, dtype=np.uint8).reshape(H, W)


def isos(path):
    """iso -> (country id, label tile)."""
    s = open(path, encoding="utf-8").read()
    out = {}
    for i, m in enumerate(re.finditer(r'iso = "([a-z0-9-]+)".*?label = (\d+)', s), start=1):
        out[m.group(1)] = (i, int(m.group(2)))
    return out


def terrain_rgb(tb):
    land = tb >= 128
    shore = (tb & 64) != 0
    mag = (tb & 31).astype(np.int32)
    rgb = np.zeros(tb.shape + (3,), dtype=np.float32)
    rgb[:] = OCEAN
    shallow = (~land) & shore
    rgb[shallow] = np.array(OCEAN) * 0.7 + 76.5
    plains = land & (~shore) & (mag < 10)
    rgb[plains] = np.stack([np.full(mag.shape, PLAINS[0]), PLAINS[1] - 2 * mag, np.full(mag.shape, PLAINS[2])], -1)[plains]
    high = land & (~shore) & (mag >= 10) & (mag < 20)
    m = (mag - 10) * 2
    rgb[high] = np.stack([HIGHLAND[0] + m, HIGHLAND[1] + m, HIGHLAND[2] + m], -1)[high]
    mount = land & (~shore) & (mag >= 20) & (mag < 31)
    m2 = mag // 2
    rgb[mount] = np.stack([MOUNTAIN[0] + m2, MOUNTAIN[1] + m2, MOUNTAIN[2] + m2], -1)[mount]
    rgb[land & shore] = SAND
    return np.clip(rgb, 0, 255)


def hash2(x, y):
    return np.mod(np.sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)


def vnoise(x, y):
    xi, yi = np.floor(x), np.floor(y)
    fx, fy = x - xi, y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = hash2(xi, yi)
    b = hash2(xi + 1, yi)
    c = hash2(xi, yi + 1)
    d = hash2(xi + 1, yi + 1)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy


def patches(x, y):
    """0..1, smooth across neighbouring tiles (MapSurface's `patches`)."""
    return vnoise(x / 7, y / 7) * 0.65 + vnoise(x / 2.5 + 17, y / 2.5 + 31) * 0.35


def main():
    os.makedirs(OUT, exist_ok=True)
    terrain = decode(os.path.join(REPO, "src", "shared", "Data", "Maps", "World.luau"), "terrain")
    grid = decode(os.path.join(REPO, "src", "shared", "Data", "Maps", "WorldCountries.luau"), "grid")
    colors = json.load(open(os.path.join(REPO, "build", "country_colors.json")))
    iso = isos(os.path.join(REPO, "src", "shared", "Data", "Maps", "WorldCountries.luau"))
    pal = np.zeros((256, 3), dtype=np.float32)
    for k, v in colors.items():
        pal[int(k)] = v
    base = terrain_rgb(terrain)
    # territory over the terrain, borders darker and opaque
    owned = grid > 0
    fill = pal[grid]
    up = np.roll(grid, 1, 0)
    dn = np.roll(grid, -1, 0)
    lf = np.roll(grid, 1, 1)
    rt = np.roll(grid, -1, 1)
    border = owned & ((up != grid) | (dn != grid) | (lf != grid) | (rt != grid))
    img = base.copy()
    img[owned] = base[owned] * (1 - ALPHA) + fill[owned] * ALPHA
    img[border] = fill[border] * (1 - BORDER_DARKEN)
    gy, gx = np.mgrid[0:H, 0:W].astype(np.float64)
    nz = patches(gx, gy)
    for name, (frame, inf) in SCENES.items():
        # the frame: around the listed countries' label points (overseas bits don't count), 2:1
        pts = [iso[c][1] for c in frame if c in iso]
        xs = np.array([t % W for t in pts])
        ys = np.array([t // W for t in pts])
        cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
        hw = max((xs.max() - xs.min()) / 2 + 70, (ys.max() - ys.min()) / 2 * 2 + 140)
        hh = hw / 2
        x0, x1 = int(max(0, cx - hw)), int(min(W, cx + hw))
        y0, y1 = int(max(0, cy - hh)), int(min(H, cy + hh))
        out = img.copy()
        # the plague: a crimson flush in patches over part of each infected country (from its middle)
        for code, share in inf.items():
            if code not in iso:
                continue
            cid = iso[code][0]
            mask = grid == cid
            mask[:, : max(0, x0 - 40)] = False
            mask[:, x1 + 40 :] = False
            ys, xs = np.nonzero(mask)
            if len(xs) == 0:
                continue
            cy, cx = ys.mean(), xs.mean()
            d = np.hypot(ys - cy, xs - cx)
            # (a ragged front, not a circle: the distance is bent by big slow patches)
            cell = max(3.0, math.sqrt(len(xs)) / 5.0)
            d = d + (patches(xs * 7.0 / cell, ys * 7.0 / cell) - 0.5) * (d.max() + 1) * 0.9
            cut = np.quantile(d, share)
            near = d <= cut
            yy, xx = ys[near], xs[near]
            k = np.where(border[yy, xx], 0.35, 0.32 + 0.4 * nz[yy, xx])[:, None]
            out[yy, xx] = out[yy, xx] * (1 - k) + CRIMSON * k
        crop = out[y0:y1, x0:x1].astype(np.uint8)
        im = Image.fromarray(crop, "RGB")
        # pixel-crisp like the game, then to a 2:1 card
        scale = 3
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        tw, th = 768, 384
        r = max(tw / im.width, th / im.height)
        im = im.resize((int(im.width * r), int(im.height * r)), Image.LANCZOS)
        left = (im.width - tw) // 2
        top = (im.height - th) // 2
        im = im.crop((left, top, left + tw, top + th))
        # a soft vignette so the scene sits in its card
        v = Image.new("L", (tw, th), 0)
        vx = np.linspace(-1, 1, tw)[None, :]
        vy = np.linspace(-1, 1, th)[:, None]
        vig = np.clip(1 - 0.45 * (vx ** 2 + vy ** 2), 0.45, 1)
        arr = np.asarray(im).astype(np.float32) * vig[..., None]
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"))
        print("wrote", name, x0, y0, x1, y1)


if __name__ == "__main__":
    main()
