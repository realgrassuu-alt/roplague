#!/usr/bin/env python3
"""RoPlague: a map's country layer, airports and ports, from public-domain Natural Earth data.

Reads the terrain already built by make_maps.py (World: src/shared/Data/Maps/World.luau; a continent:
src/server/MapData/<Module>.luau; both left untouched) and writes src/shared/Data/Maps/<Module>Countries.luau
(replicated on purpose: clients draw the country layer too):

  grid       base64(zstd(W*H bytes)): the country id (1..N) of each land tile, 0 on water and Antarctica
  countries  one row per id: name, iso, flag, pop, wealth 1-5, climate, density, label tile, tile count,
             neighbours {id, shared border edges}, airports and ports (tile indices)

Sources, downloaded into build/worldsrc/ on the first run:
  - ne_50m_admin_0_countries.geojson   polygons, names, ISO codes, POP_EST, INCOME_GRP
  - ne_10m_populated_places_simple.geojson   cities (airports, ports)

The projection, the rasteriser and the name fixes are make_maps.py's own (imported), so the countries land on the
same tiles as the coastline.

A continent map (`--map europe`, ...) uses that map's own window from make_maps.MAPS. A country only partly
inside it keeps its inside tiles, and its population is scaled by the share of its area inside the window
(area on the sphere, its Natural Earth polygons clipped to the window's lon/lat box), so a sliver of Russia is
not 144M people. A country under CONT_MIN_TILES tiles folds into the neighbour it shares the most border with
(World: MIN_TILES); a sliver with no land neighbour is nobody's. Antarctica is only on World.
(--pop-share cities scales by the share of its cities' people inside instead: closer where the part inside
is its empty end, Siberia or French Guiana, or its crowded one, European Russia or the Maghreb's coast.)

Usage (repo root): .venv/Scripts/python.exe tools/maps/make_countries.py [--map world|africa|asia|europe|
    northamerica|southamerica|all] [--pop-share area|cities] [--preview build/countries.png]
"""
import argparse
import base64
import json
import math
import os
import re
import sys
import urllib.request

import numpy as np
import zstandard
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_maps as mm  # noqa: E402

REPO = mm.REPO
SRC = os.path.join(REPO, "build", "worldsrc")
OUT_DIR = os.path.join(REPO, "src", "shared", "Data", "Maps")
SOURCES = {
    "ne_50m_admin_0_countries.geojson": mm.NE + "ne_50m_admin_0_countries.geojson",
    "ne_10m_populated_places_simple.geojson": mm.NE + "ne_10m_populated_places_simple.geojson",
}
SS = mm.SS
# Folded into another country (ADM0_A3 -> ADM0_A3): breakaway regions and bases, as the UN maps them.
MERGE = {
    "SOL": "SOM",  # Somaliland
    "CYN": "CYP",  # Northern Cyprus
    "CNM": "CYP",  # UN buffer zone
    "ESB": "CYP",  # Dhekelia
    "WSB": "CYP",  # Akrotiri
    "KAB": "KAZ",  # Baikonur
    "KAS": "IND",  # Siachen
}
NAMES = dict(mm.NAMES)
NAMES.update({
    "Niger": "Republic of Niger",  # make_maps leaves it out (a text-filter risk); a plague game needs it
    "United States": "United States",
    "Bosnia and Herzegovina": "Bosnia",
    "Central African Republic": "Central African Rep.",
    "United Republic of Tanzania": "Tanzania",
    "Islamic Republic of Iran": "Iran",
})
MIN_TILES = 4  # a country under this folds into the neighbour it shares the most border with
# a continent's tiles are 5-9 times smaller than World's (a tile is 3-8 km, World's 20 km): a country under this
# (a microstate, a sliver at the window's edge) folds the same way; the same size as make_maps.MIN_ISLAND, the
# smallest island those maps keep
CONT_MIN_TILES = 21
CITY_SHARE_MIN = 3  # --pop-share cities: fewer places than this, the area share
MIN_POP = 50_000  # an island territory with fewer people is nobody's land (Falklands, South Georgia)
ANTARCTICA = {"ATA", "ATF"}
ANTARCTIC = [("West Antarctica", -110.0, 1200), ("Antarctica", 10.0, 1800), ("East Antarctica", 120.0, 2000)]


def fetch():
    os.makedirs(SRC, exist_ok=True)
    for name, url in SOURCES.items():
        path = os.path.join(SRC, name)
        if not os.path.exists(path):
            print("downloading", name)
            urllib.request.urlretrieve(url, path + ".part")
            os.replace(path + ".part", path)


def map_tiles(spec):
    s = open(mm.module_path(spec), encoding="utf-8").read()
    w = int(re.search(r"\bwidth = (\d+)", s).group(1))
    h = int(re.search(r"\bheight = (\d+)", s).group(1))
    b64 = re.search(r'\bterrain = "([^"]+)"', s).group(1)
    raw = zstandard.ZstdDecompressor().decompress(base64.b64decode(b64))
    assert len(raw) == w * h
    return w, h, np.frombuffer(raw, np.uint8).reshape(h, w)


def load_countries():
    with open(os.path.join(SRC, "ne_50m_admin_0_countries.geojson"), encoding="utf-8") as f:
        feats = json.load(f)["features"]
    rows = []
    for feat in feats:
        p = feat["properties"]
        a3 = p.get("ADM0_A3")
        if feat["geometry"] is None or not a3:
            continue
        rows.append((a3, p, feat["geometry"]))
    return rows


def rasterise(proj, rows):
    """(H, W) int32: index into rows + 1 under each tile centre (0 none)."""
    img = Image.new("I", (proj.w * SS, proj.h * SS), 0)
    draw = ImageDraw.Draw(img)
    polys = []
    for k, (_, _, geom) in enumerate(rows):
        parts = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        for rings in parts:
            polys.append((mm.ring_area(rings[0]), k + 1, rings))
    # biggest first: an enclave (Lesotho) is drawn after the hole its neighbour leaves for it
    for _, k, rings in sorted(polys, key=lambda t: -t[0]):
        mm.draw_rings(proj, draw, rings, k, 0)
    samples = np.array(img, dtype=np.int32).reshape(proj.h, SS, proj.w, SS)
    centre = samples[:, SS // 2, :, SS // 2]
    anyhit = samples.max(axis=(1, 3))
    return np.where(centre > 0, centre, anyhit)


def load_places():
    """ADM0_A3 -> its populated places (Natural Earth's), most populous first."""
    with open(os.path.join(SRC, "ne_10m_populated_places_simple.geojson"), encoding="utf-8") as f:
        places = [p["properties"] for p in json.load(f)["features"]]
    by_a3 = {}
    for p in places:
        by_a3.setdefault(p.get("adm0_a3"), []).append(p)
    for lst in by_a3.values():
        lst.sort(key=lambda p: -(p.get("pop_max") or 0))
    return by_a3


def clip_ring(ring, lon0, lon1, lat0, lat1):
    """Sutherland-Hodgman: a lon/lat ring clipped to the box lon0..lon1 x lat0..lat1 (a list, maybe empty)."""
    pts = [(float(p[0]), float(p[1])) for p in ring]
    for axis, bound, keep_above in ((0, lon0, True), (0, lon1, False), (1, lat0, True), (1, lat1, False)):
        if not pts:
            break

        def inside(q, axis=axis, bound=bound, keep_above=keep_above):
            return q[axis] >= bound if keep_above else q[axis] <= bound

        out = []
        prev = pts[-1]
        for cur in pts:
            if inside(cur):
                if not inside(prev):
                    out.append(cut(prev, cur, axis, bound))
                out.append(cur)
            elif inside(prev):
                out.append(cut(prev, cur, axis, bound))
            prev = cur
        pts = out
    return pts


def cut(a, b, axis, bound):
    t = (bound - a[axis]) / (b[axis] - a[axis])
    q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    return (bound, q[1]) if axis == 0 else (q[0], bound)


def sphere_area(ring):
    """Area of a lon/lat ring on the unit sphere (the integral of sin(lat) dlon: equal-area, not square degrees)."""
    if len(ring) < 3:
        return 0.0
    a = np.radians(np.asarray(ring, dtype=np.float64))
    lon, s = a[:, 0], np.sin(a[:, 1])
    return abs(float(np.sum((np.roll(lon, -1) - lon) * (s + np.roll(s, -1)) / 2)))


def area_in(geom, box):
    """(area inside box, whole area) of a (Multi)Polygon, holes taken out; box = (lon0, lon1, lat0, lat1)."""
    parts = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    inside = whole = 0.0
    for rings in parts:
        for i, ring in enumerate(rings):
            sign = 1.0 if i == 0 else -1.0
            whole += sign * sphere_area(ring)
            inside += sign * sphere_area(clip_ring(ring, *box))
    return max(inside, 0.0), max(whole, 0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="world", help="map id (make_maps.MAPS), or all")
    ap.add_argument("--preview", help="write a PNG of the countries (with --map all: a folder)")
    ap.add_argument("--pop-share", choices=("area", "cities"), default="area",
                    help="a continent: scale a cut country's people by its area inside the window (default), or by "
                         "its cities' people inside")
    args = ap.parse_args()
    fetch()
    ids = [m["id"] for m in mm.MAPS] if args.map == "all" else [args.map]
    for map_id in ids:
        spec = next((m for m in mm.MAPS if m["id"] == map_id), None)
        if spec is None:
            sys.exit("unknown map %r (one of: %s)" % (map_id, ", ".join(m["id"] for m in mm.MAPS)))
        preview = args.preview
        if preview and args.map == "all":
            preview = os.path.join(preview, map_id + ".png")
        build(spec, preview, args.pop_share)


def build(spec, preview, pop_share="area"):
    world = bool(spec.get("world"))
    out_path = os.path.join(OUT_DIR, spec["module"] + "Countries.luau")
    W, H, tb = map_tiles(spec)
    proj = mm.Proj(spec)
    assert proj.w == W and proj.h == H
    land = (tb & mm.LAND) != 0
    land &= tb != mm.IMPASSABLE
    rows = load_countries()
    a3_of = [r[0] for r in rows]
    raw = rasterise(proj, rows)  # 1-based row index
    # rows past the South Pole and every Antarctic polygon: nobody's
    ant_rows = {k + 1 for k, a3 in enumerate(a3_of) if a3 in ANTARCTICA}
    pole_y = int(proj.project(0.0, -60.0)[1])
    # nearest-country fill for land the 1:50m polygons miss (the coastline is 1:10m)
    assigned = land & (raw > 0)
    _, (iy, ix) = ndimage.distance_transform_edt(~assigned, return_indices=True)
    filled = np.where(land, raw[iy, ix], 0)
    for k in ant_rows:
        filled[filled == k] = 0
    filled[pole_y:, :] = np.where(filled[pole_y:, :] > 0, filled[pole_y:, :], 0)
    # merges (breakaway regions, bases)
    idx_of_a3 = {a3: k + 1 for k, a3 in enumerate(a3_of)}
    for a, b in MERGE.items():
        if a in idx_of_a3 and b in idx_of_a3:
            filled[filled == idx_of_a3[a]] = idx_of_a3[b]
    # a continent: the share of each country's area inside the window (its merged regions included)
    share = {}
    if not world:
        box = (spec["lon0"], spec["lon1"], spec["lat_bottom"], spec["lat_top"])
        acc = {}
        for k, (a3, _, geom) in enumerate(rows):
            target = idx_of_a3.get(MERGE.get(a3, a3), k + 1)
            i_, w_ = area_in(geom, box)
            a_, b_ = acc.get(target, (0.0, 0.0))
            acc[target] = (a_ + i_, b_ + w_)
        share = {k: min(1.0, a_ / b_) if b_ > 0 else 0.0 for k, (a_, b_) in acc.items()}
        if pop_share == "cities":
            # the share of its cities' people inside instead (pop_max, Natural Earth's places), where that says
            # something: at least CITY_SHARE_MIN places, some of them inside; else the area share
            places = load_places()
            for k in share:
                if share[k] >= 1.0:
                    continue
                a3 = a3_of[k - 1]
                cs = places.get(a3, []) + [q for m, t in MERGE.items() if t == a3 for q in places.get(m, [])]
                tot = sum(q.get("pop_max") or 0 for q in cs)
                ins = sum(q.get("pop_max") or 0 for q in cs
                          if box[0] <= q["longitude"] <= box[1] and box[2] <= q["latitude"] <= box[3])
                if len(cs) >= CITY_SHARE_MIN and ins > 0 and tot > 0:
                    share[k] = min(1.0, ins / tot)
    min_tiles = MIN_TILES if world else CONT_MIN_TILES
    # fold tiny countries into their biggest-border neighbour
    for _ in range(3):
        counts = np.bincount(filled.ravel(), minlength=len(rows) + 1)
        changed = False
        for k in np.nonzero((counts > 0) & (counts < min_tiles))[0]:
            if k == 0:
                continue
            mask = filled == k
            ring = ndimage.binary_dilation(mask, structure=mm.FOUR) & ~mask
            nb = filled[ring & land]
            nb = nb[nb > 0]
            if len(nb):
                filled[mask] = np.bincount(nb).argmax()
                changed = True
            elif not world and share.get(int(k), 1.0) < 1.0:
                filled[mask] = 0  # a sliver of a country cut by the window, alone: nobody's
                changed = True
        if not changed:
            break
    for k in range(1, len(rows) + 1):
        if (rows[k - 1][1].get("POP_EST") or 0) < MIN_POP:
            filled[filled == k] = 0
    counts = np.bincount(filled.ravel(), minlength=len(rows) + 1)
    keep = [k for k in range(1, len(rows) + 1) if counts[k] > 0]

    def pop_of(k):
        """POP_EST (a continent: times the share of the country inside the window)."""
        p = rows[k - 1][1].get("POP_EST") or 0
        return p if world else int(round(p * share.get(k, 1.0)))

    # renumber by population, biggest first (stable ids for a given data version)
    keep.sort(key=lambda k: (-pop_of(k), a3_of[k - 1]))
    new_id = np.zeros(len(rows) + 1, np.uint8)
    for i, k in enumerate(keep):
        new_id[k] = i + 1
    grid = new_id[filled]
    grid[~land] = 0
    # Antarctica as three countries, RoWorld's regions (name, the longitude it is centred on, people:
    # research stations), split by the nearest centre longitude (only World reaches it)
    antarctic = ANTARCTIC if pole_y < H else []
    ant_ys, ant_xs = np.nonzero(land & (grid == 0) & (np.arange(H)[:, None] >= pole_y))
    if antarctic:
        ant_lon, _ = proj.unproject(ant_xs + 0.5, ant_ys + 0.5)
        dists = []
        for _, lon0, _ in antarctic:
            d = np.abs(ant_lon - lon0) % 360.0
            dists.append(np.minimum(d, 360.0 - d))
        choice = np.argmin(np.stack(dists), axis=0)
        base = len(keep)
        for k in range(len(antarctic)):
            grid[ant_ys[choice == k], ant_xs[choice == k]] = base + 1 + k
    N = len(keep) + len(antarctic)
    # one byte per tile, and the sim keeps owner ids (countries, then the plague and the cure) in a byte
    assert N <= 254, "%s: %d countries, ids are one byte" % (spec["id"], N)

    # geometry per country
    ys, xs = np.nonzero(grid)
    ids = grid[ys, xs].astype(np.int64)
    tiles = np.bincount(ids, minlength=N + 1)
    sx = np.bincount(ids, weights=xs, minlength=N + 1)
    sy = np.bincount(ids, weights=ys, minlength=N + 1)
    mag = (tb & 0x1F).astype(np.float64)
    smag = np.bincount(ids, weights=mag[ys, xs], minlength=N + 1)
    # shared border edges, and one tile on each side of every border (where a land crossing lands)
    shared = {}
    edge_tile = {}  # (own id, other id) -> a tile of own id beside other id (the middle one along the border)
    edge_tiles = {}
    for (a, b), (dy, dx) in (((grid[:, :-1], grid[:, 1:]), (0, 1)), ((grid[:-1, :], grid[1:, :]), (1, 0))):
        m = (a != b) & (a > 0) & (b > 0)
        py, px = np.nonzero(m)
        for y, x, u, v in zip(py.tolist(), px.tolist(), a[m].tolist(), b[m].tolist()):
            key = (min(u, v), max(u, v))
            shared[key] = shared.get(key, 0) + 1
            edge_tiles.setdefault((u, v), []).append(y * W + x)
            edge_tiles.setdefault((v, u), []).append((y + dy) * W + (x + dx))
    for k, lst in edge_tiles.items():
        edge_tile[k] = lst[len(lst) // 2]
    # coastal tiles (land next to water) and the water byte they touch
    water = ~((tb & mm.LAND) != 0)
    coastal = np.zeros_like(land)
    ocean_side = np.zeros_like(land)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nwater = np.roll(water, (-dy, -dx), axis=(0, 1))
        nocean = np.roll(water & ((tb & mm.OCEAN) != 0), (-dy, -dx), axis=(0, 1))
        coastal |= land & nwater
        ocean_side |= land & nocean
    coastal[0, :] = coastal[-1, :] = coastal[:, 0] = coastal[:, -1] = False

    by_a3 = load_places()

    def tile_of(lon, lat, clamp=False):
        """World: the tile of a lon/lat (wrapped). A continent: None outside the window (clamp: its edge)."""
        x, y = proj.project(lon, lat)
        if world:
            x = int(x) % W
            y = int(min(max(y, 0), H - 1))
            return x, y
        if not (0 <= x < W and 0 <= y < H):
            if not clamp:
                return None
            x, y = min(max(x, 0), W - 1), min(max(y, 0), H - 1)
        return int(x), int(y)

    def nearest(mask, x, y, limit):
        y0, y1 = max(0, y - limit), min(H, y + limit + 1)
        x0, x1 = max(0, x - limit), min(W, x + limit + 1)
        sub = mask[y0:y1, x0:x1]
        py, px = np.nonzero(sub)
        if len(py) == 0:
            return None
        d = (py + y0 - y) ** 2 + (px + x0 - x) ** 2
        j = int(d.argmin())
        return int(px[j] + x0), int(py[j] + y0)

    # density classes by people per tile (log quantiles)
    pops = np.array([pop_of(k) for k in keep], np.float64)
    dens = np.log10(np.maximum(pops, 1) / np.maximum(tiles[1:len(keep) + 1], 1))
    lo, hi = np.quantile(dens, 0.3), np.quantile(dens, 0.7)
    flags = mm.flag_codes()
    out = []
    for i, k in enumerate(keep):
        cid = i + 1
        a3, p, _ = rows[k - 1]
        name = NAMES.get(p.get("NAME_LONG"), p.get("NAME_LONG") or p.get("NAME"))
        name = NAMES.get(name, name)
        iso = next((c for c in (p.get("ISO_A2_EH"), p.get("ISO_A2")) if c and len(c) == 2), "")
        pop = int(pop_of(k))
        inc = str(p.get("INCOME_GRP") or "4")[:1]
        wealth = {"1": 5, "2": 4, "3": 3, "4": 2, "5": 1}.get(inc, 2)
        cx, cy = sx[cid] / tiles[cid], sy[cid] / tiles[cid]
        _, clat = proj.unproject(cx, cy)
        clat = float(abs(clat))
        mean_mag = smag[cid] / tiles[cid]
        climate = "hot" if clat < 27 else ("cold" if clat > 50 or mean_mag >= 18 else "temperate")
        d = dens[i]
        density = "urban" if d >= hi else ("rural" if d <= lo else "normal")
        mine = grid == cid
        # label: Natural Earth's label point when it lands inside, else the tile nearest the centroid
        lt = tile_of(p["LABEL_X"], p["LABEL_Y"])
        lx, ly = lt if lt else (0, 0)
        if lt is None or grid[ly, lx] != cid:
            got = nearest(mine, int(cx), int(cy), max(W, H))
            lx, ly = got
        cities = by_a3.get(a3, []) + [q for m, t in MERGE.items() if t == a3 for q in by_a3.get(m, [])]
        cities.sort(key=lambda q: -(q.get("pop_max") or 0))

        def pick(n_max, mask, limit, gap):
            got = []
            for q in cities:
                if len(got) >= n_max:
                    break
                xy = tile_of(q["longitude"], q["latitude"])
                if xy is None:
                    continue  # a city outside the window
                x, y = xy
                t = nearest(mask, x, y, limit)
                if t is None or any((t[0] - a) ** 2 + (t[1] - b) ** 2 < gap * gap for a, b in got):
                    continue
                got.append(t)
            return got

        # every country with people can be reached: a port if it has a coast, an airport once it has
        # a city worth flying to
        n_air = 0 if pop < 200_000 else min(5, 1 + pop // 30_000_000)
        airports = pick(n_air, mine, 30, 22)
        if n_air and not airports:
            airports = [(lx, ly)]
        coast_mine = mine & coastal
        n_port = 0 if not coast_mine.any() else min(3, 1 + (pop > 30_000_000) + (pop > 100_000_000))
        ocean_mine = coast_mine & ocean_side
        ports = pick(n_port, ocean_mine if ocean_mine.any() else coast_mine, 14, 20)
        if n_port and not ports:
            # no city near the sea: the coastal tile nearest the biggest city (or the label)
            q = cities[0] if cities else None
            x, y = tile_of(q["longitude"], q["latitude"], True) if q else (lx, ly)
            t = nearest(ocean_mine if ocean_mine.any() else coast_mine, x, y, max(W, H))
            ports = [t] if t else []
        nbs = sorted(((b if a == cid else a, n) for (a, b), n in shared.items() if cid in (a, b)), key=lambda t: -t[1])
        nbs = [(o, n, edge_tile[(cid, o)]) for o, n in nbs]
        out.append(dict(
            name=name, iso=iso.lower(), flag=iso.lower() if iso.lower() in flags else "",
            pop=pop, wealth=wealth, climate=climate, density=density,
            label=ly * W + lx, tiles=int(tiles[cid]), neighbors=nbs,
            airports=[y * W + x for x, y in airports], ports=[y * W + x for x, y in ports],
        ))

    for k, (name, _, pop) in enumerate(antarctic):
        cid = len(keep) + 1 + k
        mine = grid == cid
        cx, cy = sx[cid] / max(tiles[cid], 1), sy[cid] / max(tiles[cid], 1)
        got = nearest(mine, int(cx), int(cy), max(W, H))
        lx, ly = got if got else (0, 0)
        nbs = sorted(((b if a == cid else a, n) for (a, b), n in shared.items() if cid in (a, b)), key=lambda t: -t[1])
        nbs = [(o, n, edge_tile[(cid, o)]) for o, n in nbs]
        coast_mine = mine & coastal
        port = nearest(coast_mine, lx, ly, max(W, H)) if coast_mine.any() else None
        out.append(dict(
            name=name, iso="aq", flag="aq" if "aq" in flags else "", pop=pop, wealth=5, climate="cold", density="rural",
            label=ly * W + lx, tiles=int(tiles[cid]), neighbors=nbs, airports=[],
            ports=[port[1] * W + port[0]] if port else [],
        ))

    z = zstandard.ZstdCompressor(level=19, write_content_size=True).compress(grid.tobytes())
    q = mm.lua_str
    lines = [
        "-- GENERATED by tools/maps/make_countries.py from public-domain Natural Earth data. Do not edit.",
        "-- grid = base64(zstd(width * height bytes)): the country id of each land tile (0: water, Antarctica).",
        "-- countries[id] = {name, iso, flag, pop, wealth 1-5, climate, density, label (tile), tiles,",
        "--   neighbors = {{id, shared border edges, a tile of this country on that border}}, airports = {tile},",
    "--   ports = {tile}}",
        "return {",
        "\tmap = %s," % q(spec["id"]),
        "\twidth = %d," % W,
        "\theight = %d," % H,
        '\tcodec = "zstd+base64",',
        '\tgrid = "%s",' % base64.b64encode(z).decode("ascii"),
        "\tcountries = {",
    ]
    for c in out:
        nb = ", ".join("{ %d, %d, %d }" % t for t in c["neighbors"])
        lines.append(
            "\t\t{ name = %s, iso = %s, flag = %s, pop = %d, wealth = %d, climate = %s, density = %s, label = %d, "
            "tiles = %d, neighbors = { %s }, airports = { %s }, ports = { %s } },"
            % (q(c["name"]), q(c["iso"]), q(c["flag"]), c["pop"], c["wealth"], q(c["climate"]), q(c["density"]),
               c["label"], c["tiles"], nb, ", ".join(map(str, c["airports"])), ", ".join(map(str, c["ports"]))))
    lines += ["\t},", "}", ""]
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    world_pop = sum(c["pop"] for c in out)
    print("%s: %d countries, %d land tiles assigned of %d, pop %.2fB, %d airports, %d ports, grid %d KB zstd, "
          "%s %d KB" % (spec["id"], N, int((grid > 0).sum()), int(land.sum()), world_pop / 1e9,
                        sum(len(c["airports"]) for c in out), sum(len(c["ports"]) for c in out), len(z) // 1024,
                        os.path.basename(out_path), os.path.getsize(out_path) // 1024))
    small_n = 10 * min_tiles // MIN_TILES
    print("under %d tiles:" % small_n, ", ".join(c["name"] for c in out if c["tiles"] < small_n))
    if not world:
        cut_rows = sorted((share[k], k) for k in keep if share.get(k, 1.0) < 1.0)
        print("partly inside (share of its %s inside: pop):" % ("area" if pop_share == "area" else "cities' people"),
              ", ".join(
            "%s %.1f%%: %s" % (out[keep.index(k)]["name"], s_ * 100, fmt_pop(pop_of(k))) for s_, k in cut_rows))
    if preview:
        rng = np.random.default_rng(7)
        pal = rng.integers(60, 230, size=(N + 1, 3)).astype(np.uint8)
        pal[0] = (20, 40, 80)
        img = pal[grid]
        img[land & (grid == 0)] = (235, 235, 240)
        im = Image.fromarray(img)
        d = ImageDraw.Draw(im)
        for c in out:
            for t in c["airports"]:
                x, y = t % W, t // W
                d.rectangle([x - 2, y - 2, x + 2, y + 2], fill=(255, 255, 255))
            for t in c["ports"]:
                x, y = t % W, t // W
                d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(0, 0, 0))
            x, y = c["label"] % W, c["label"] // W
            if c["tiles"] > 300:
                d.text((x - 10, y - 5), c["name"][:14], fill=(0, 0, 0))
        os.makedirs(os.path.dirname(os.path.abspath(preview)), exist_ok=True)
        im.save(preview)


def fmt_pop(n):
    return "%.1fM" % (n / 1e6) if n >= 1e6 else "%dk" % (n // 1000)


if __name__ == "__main__":
    main()
