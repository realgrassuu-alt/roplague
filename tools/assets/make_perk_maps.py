"""RoPlague: the shop's live map frames. Each plague perk's preview plays over a real piece of the game's
world (the country grid, its colours, the same soft crimson patches as the match) whose infection moves
frame by frame with what the perk does: Super Spreader's first country floods, Sea Legs' far coast
catches it when the ship lands, and so on.

Frames are FRAME_W x FRAME_H px (one px about a map tile, drawn pixel-crisp like RoWorld's Arsenal
maps), packed 4 x 8 in 1024 x 1024 atlases. Writes build/perk_maps/atlas_<n>.png and
build/perk_maps/perk_maps.json (scene -> atlas, frame offsets, points as fractions of the frame).
No text in any image.

    .venv/Scripts/python.exe tools/assets/make_perk_maps.py
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_world_scenes as ws  # noqa: E402

OUT = os.path.join(ws.REPO, "build", "perk_maps")
FRAME_W, FRAME_H = 256, 128
FRAMES = 8
COLS, ROWS = 4, 8
CRIMSON = ws.CRIMSON

# scene: centre countries (framed around their label points), the zoom (crop width in tiles), and per
# country its infected share at each of the 8 frames
SCENES = {
    "super_spreader": {
        "frame": ["in"], "width": 300,
        "inf": {"in": [0.004, 0.06, 0.16, 0.28, 0.4, 0.5, 0.58, 0.62], "np": [0, 0, 0, 0, 0.1, 0.3, 0.5, 0.6],
                "bd": [0, 0, 0, 0.05, 0.2, 0.35, 0.5, 0.55], "pk": [0, 0, 0, 0, 0, 0.06, 0.15, 0.22]},
        "points": {"zero": "in"},
    },
    "sea_legs": {
        "frame": ["br", "ng"], "width": 520,
        "inf": {"br": [0.55] * 8, "ng": [0, 0, 0, 0, 0, 0.05, 0.2, 0.38], "bj": [0, 0, 0, 0, 0, 0, 0.04, 0.15]},
        "points": {"home": ("coast", "br", "e"), "far": ("coast", "ng", "w")},
    },
    "bubble_magnet": {
        "frame": ["ng", "cd", "td"], "width": 330,
        "inf": {"ng": [0.4, 0.44, 0.48, 0.52, 0.56, 0.6, 0.63, 0.66], "cm": [0.2, 0.25, 0.3, 0.34, 0.38, 0.42, 0.45, 0.48],
                "td": [0.1, 0.13, 0.17, 0.2, 0.24, 0.27, 0.3, 0.33], "cf": [0, 0, 0.05, 0.1, 0.15, 0.2, 0.24, 0.28]},
        "points": {"b1": "ng", "b2": "cm", "b3": "td", "b4": "cf", "b5": "ne"},
    },
    "head_start": {
        "frame": ["fr", "de", "es"], "width": 280,
        "inf": {"fr": [0.05, 0.14, 0.25, 0.36, 0.46, 0.55, 0.62, 0.68], "es": [0, 0, 0.05, 0.12, 0.2, 0.28, 0.35, 0.4],
                "be": [0, 0, 0, 0.1, 0.25, 0.4, 0.5, 0.55], "de": [0, 0, 0, 0, 0.05, 0.12, 0.2, 0.28]},
        "points": {"zero": "fr"},
    },
    "gene_bank": {
        "frame": ["cn", "mn", "th"], "width": 420,
        "inf": {"cn": [0.2, 0.26, 0.32, 0.38, 0.44, 0.5, 0.55, 0.6], "mn": [0, 0, 0.05, 0.1, 0.16, 0.22, 0.28, 0.33],
                "vn": [0.1, 0.16, 0.22, 0.28, 0.34, 0.4, 0.45, 0.5], "la": [0, 0.05, 0.1, 0.16, 0.22, 0.28, 0.33, 0.38]},
        "points": {},
    },
    "slow_science": {
        "frame": ["us", "mx"], "width": 460,
        "inf": {"us": [0.1, 0.16, 0.22, 0.28, 0.34, 0.4, 0.46, 0.52], "mx": [0.3, 0.36, 0.42, 0.48, 0.54, 0.6, 0.65, 0.7],
                "gt": [0, 0.05, 0.12, 0.2, 0.28, 0.35, 0.42, 0.48], "ca": [0, 0, 0, 0.03, 0.06, 0.1, 0.14, 0.18]},
        "points": {},
    },
    "mutagen": {
        "frame": ["et", "ke", "so"], "width": 300,
        "inf": {"et": [0.2, 0.2, 0.2, 0.26, 0.36, 0.46, 0.54, 0.6], "ke": [0, 0, 0, 0.06, 0.16, 0.26, 0.34, 0.4],
                "so": [0, 0, 0, 0.04, 0.1, 0.18, 0.25, 0.3], "ss": [0, 0, 0, 0, 0.06, 0.12, 0.18, 0.24]},
        "points": {"hex": "et"},
    },
}


def main():
    os.makedirs(OUT, exist_ok=True)
    W, H = ws.W, ws.H
    terrain = ws.decode(os.path.join(ws.REPO, "src", "shared", "Data", "Maps", "World.luau"), "terrain")
    grid = ws.decode(os.path.join(ws.REPO, "src", "shared", "Data", "Maps", "WorldCountries.luau"), "grid")
    colors = json.load(open(os.path.join(ws.REPO, "build", "country_colors.json")))
    iso = ws.isos(os.path.join(ws.REPO, "src", "shared", "Data", "Maps", "WorldCountries.luau"))
    pal = np.zeros((256, 3), dtype=np.float32)
    for k, v in colors.items():
        pal[int(k)] = v
    base = ws.terrain_rgb(terrain)
    owned = grid > 0
    fill = pal[grid]
    up, dn = np.roll(grid, 1, 0), np.roll(grid, -1, 0)
    lf, rt = np.roll(grid, 1, 1), np.roll(grid, -1, 1)
    border = owned & ((up != grid) | (dn != grid) | (lf != grid) | (rt != grid))
    img = base.copy()
    img[owned] = base[owned] * (1 - ws.ALPHA) + fill[owned] * ws.ALPHA
    img[border] = fill[border] * (1 - ws.BORDER_DARKEN)
    gy, gx = np.mgrid[0:H, 0:W].astype(np.float64)
    nz = ws.patches(gx, gy)

    def order_of(cid, x0, x1):
        """Each tile of country cid (inside the crop's columns, with a margin): its infection order 0..1."""
        mask = grid == cid
        mask[:, : max(0, x0 - 40)] = False
        mask[:, x1 + 40 :] = False
        ys, xs = np.nonzero(mask)
        if len(xs) == 0:
            return None
        cy, cx = ys.mean(), xs.mean()
        d = np.hypot(ys - cy, xs - cx)
        cell = max(3.0, math.sqrt(len(xs)) / 5.0)
        d = d + (ws.patches(xs * 7.0 / cell, ys * 7.0 / cell) - 0.5) * (d.max() + 1) * 0.9
        rank = np.argsort(np.argsort(d)) / max(1, len(d) - 1)
        return ys, xs, rank

    atlases = []
    manifest = {"frame": [FRAME_W, FRAME_H], "scenes": {}}
    slot = 0
    for name, sc in SCENES.items():
        pts = [iso[c][1] for c in sc["frame"] if c in iso]
        cx = sum(t % W for t in pts) / len(pts)
        cy = sum(t // W for t in pts) / len(pts)
        cw = sc["width"]
        ch = cw // 2
        x0 = int(min(max(0, cx - cw / 2), W - cw))
        y0 = int(min(max(0, cy - ch / 2), H - ch))
        x1, y1 = x0 + cw, y0 + ch
        orders = {}
        for code in sc["inf"]:
            if code in iso:
                o = order_of(iso[code][0], x0, x1)
                if o is not None:
                    orders[code] = o
        offsets = []
        for f in range(FRAMES):
            out = img.copy()
            for code, (ys, xs, rank) in orders.items():
                share = sc["inf"][code][f]
                if share <= 0:
                    continue
                near = rank <= share
                yy, xx = ys[near], xs[near]
                k = np.where(border[yy, xx], 0.4, 0.38 + 0.42 * nz[yy, xx])[:, None]
                out[yy, xx] = out[yy, xx] * (1 - k) + CRIMSON * k
            crop = Image.fromarray(np.clip(out[y0:y1, x0:x1], 0, 255).astype(np.uint8), "RGB")
            crop = crop.resize((FRAME_W, FRAME_H), Image.BOX)
            a = slot // (COLS * ROWS)
            while len(atlases) <= a:
                atlases.append(Image.new("RGB", (COLS * FRAME_W, ROWS * FRAME_H), (10, 14, 28)))
            r = slot % (COLS * ROWS)
            ox, oy = (r % COLS) * FRAME_W, (r // COLS) * FRAME_H
            atlases[a].paste(crop, (ox, oy))
            offsets.append([a, ox, oy])
            slot += 1
        # points the overlay needs, as fractions of the frame
        points = {}
        for key, spec in sc["points"].items():
            if isinstance(spec, tuple):
                _, code, side = spec
                cid = iso[code][0]
                ys, xs = np.nonzero((grid == cid) & ((terrain & 64) != 0))
                inside = (xs >= x0) & (xs < x1) & (ys >= y0) & (ys < y1)
                ys, xs = ys[inside], xs[inside]
                if side == "e":
                    j = np.argmax(xs - np.abs(ys - ys.mean()) * 0.3)
                else:
                    j = np.argmin(xs + np.abs(ys - ys.mean()) * 0.3)
                tx, ty = xs[j], ys[j]
            else:
                t = iso[spec][1]
                tx, ty = t % W, t // W
            points[key] = [round((tx - x0) / cw, 4), round((ty - y0) / ch, 4)]
        manifest["scenes"][name] = {"frames": offsets, "points": points}
        print("scene", name, "crop", x0, y0, x1, y1, points)
    for i, a in enumerate(atlases):
        a.save(os.path.join(OUT, "atlas_%d.png" % i))
    json.dump(manifest, open(os.path.join(OUT, "perk_maps.json"), "w"), indent=1)
    print("atlases", len(atlases))


if __name__ == "__main__":
    main()
