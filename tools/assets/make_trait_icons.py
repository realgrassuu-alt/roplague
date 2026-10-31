"""RoPlague's trait and pathogen icons, drawn from scratch (no third-party art, no text).

Same recipe as make_plague_icons.py: white shapes on a transparent 512x512 canvas, cut-outs drawn
transparent, then LANCZOS-resized to 128x128 white-on-transparent masks (tinted in game with
ImageColor3). Writes build/trait_icons/<key>.png and a contact sheet build/trait_icons/_sheet.png.

    .venv/Scripts/python.exe tools/assets/make_trait_icons.py

There are no letters, digits or numerals anywhere: tiers are shown with bars, badges or doubled shapes.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

S = 512  # drawn at 4x, saved at 128
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "build", "trait_icons")
W = (255, 255, 255, 255)
T = (0, 0, 0, 0)
TAU = math.tau
C = S / 2


# ----------------------------------------------------------------------------------------------- basics


def canvas():
    img = Image.new("RGBA", (S, S), T)
    return img, ImageDraw.Draw(img)


def disc(d, cx, cy, r, fill=W):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def ring(d, cx, cy, r, w, fill=W):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=fill, width=int(round(w)))


def line(d, a, b, w, fill=W):
    d.line((a, b), fill=fill, width=int(round(w)))
    disc(d, a[0], a[1], w / 2, fill)
    disc(d, b[0], b[1], w / 2, fill)


def poly(d, pts, w, fill=W):
    """Thick polyline with round joins and caps."""
    for i in range(len(pts) - 1):
        d.line((pts[i], pts[i + 1]), fill=fill, width=int(round(w)))
    for p in pts:
        disc(d, p[0], p[1], w / 2, fill)


def spline(pts, n=16, closed=False):
    """Catmull-Rom through tuples of any length (x, y) or (x, y, r)."""
    P = list(pts)
    P = [P[-1]] + P + [P[0], P[1]] if closed else [P[0]] + P + [P[-1]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - e) * t2 + (-a + 3 * b - 3 * c + e) * t3)
                for a, b, c, e in zip(p0, p1, p2, p3)
            ))
    if not closed:
        out.append(tuple(P[-2]))
    return out


def ellipse_pts(cx, cy, rx, ry, ang=0.0, n=96):
    a = math.radians(ang)
    co, si = math.cos(a), math.sin(a)
    pts = []
    for i in range(n):
        t = i * TAU / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + co * x - si * y, cy + si * x + co * y))
    return pts


def ngon(cx, cy, r, n, rot=0.0):
    return [(cx + math.cos(math.radians(rot) + k * TAU / n) * r, cy + math.sin(math.radians(rot) + k * TAU / n) * r)
            for k in range(n)]


def arc_pts(cx, cy, r, a0, a1, n=40):
    """Degrees, 0 = right, increasing clockwise on screen (y down)."""
    return [(cx + math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r,
             cy + math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r) for i in range(n + 1)]


def bez(p0, p1, p2, n):
    out = []
    for i in range(1, n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    return out


# ----------------------------------------------------------------------------------------------- layers


def alpha(img):
    return np.asarray(img.getchannel("A"), dtype=np.float32) / 255.0


def set_alpha(img, a):
    img.putalpha(Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)))


def stamp(dst, src, halo=16):
    """Composite src onto dst, first clearing a gap of `halo` px around it so the two read apart."""
    if halo > 0:
        dist = ndimage.distance_transform_edt(alpha(src) < 0.5)
        set_alpha(dst, alpha(dst) * (dist > halo))
    dst.alpha_composite(src)


def clip(src, mask):
    out = src.copy()
    set_alpha(out, alpha(src) * alpha(mask))
    return out


def place(src, cx, cy, s=1.0, ang=0.0):
    """Move a layer drawn around the canvas centre to (cx, cy), scaled by s, rotated ang degrees clockwise."""
    a = math.radians(ang)
    co, si = math.cos(a), math.sin(a)
    coeffs = (co / s, si / s, C - (co * cx + si * cy) / s, -si / s, co / s, C - (-si * cx + co * cy) / s)
    return src.transform((S, S), Image.AFFINE, coeffs, resample=Image.BICUBIC)


def split(lay, crack):
    """Cut a layer in two along a polyline running from y=0 to y=S."""
    ml, dl = canvas()
    dl.polygon(crack + [(0, S), (0, 0)], fill=W)
    mr, dr = canvas()
    dr.polygon(crack + [(S, S), (S, 0)], fill=W)
    return clip(lay, ml), clip(lay, mr)


def fit(img, margin=22):
    """Centre the drawing on its bounding box and shrink it if it runs into the margin."""
    bb = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if not bb:
        return img
    x0, y0, x1, y1 = bb
    lim = S - 2 * margin
    s = min(1.0, lim / (x1 - x0), lim / (y1 - y0))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if s < 1.0:
        coeffs = (1 / s, 0, cx - C / s, 0, 1 / s, cy - C / s)
        return img.transform((S, S), Image.AFFINE, coeffs, resample=Image.BICUBIC)
    out, _ = canvas()
    out.paste(img, (int(round(C - cx)), int(round(C - cy))))
    return out


def finish(img):
    """Pure white RGB, the drawing lives in alpha only (rotations leave grey fringes otherwise)."""
    out = Image.new("RGBA", img.size, W)
    out.putalpha(img.getchannel("A"))
    return out


# ----------------------------------------------------------------------------------------------- shared shapes


def drop(d, cx, cy, r, ang=0.0, fill=W):
    """Teardrop; ang is the direction the tip points (0 = up, clockwise)."""
    disc(d, cx, cy, r, fill)
    a = math.radians(ang)
    tip = (cx + math.sin(a) * 2 * r, cy - math.cos(a) * 2 * r)
    p1 = (cx + math.sin(a + math.pi / 3) * r, cy - math.cos(a + math.pi / 3) * r)
    p2 = (cx + math.sin(a - math.pi / 3) * r, cy - math.cos(a - math.pi / 3) * r)
    d.polygon((p1, tip, p2), fill=fill)


def bug(d, cx, cy, r, n=8, fill=W, rot=0.3):
    """A small chunky virus (body + knobbed spikes). Reaches about 1.68 r."""
    for k in range(n):
        a = rot + k * TAU / n
        p1 = (cx + math.cos(a) * r * 1.38, cy + math.sin(a) * r * 1.38)
        line(d, (cx, cy), p1, r * 0.36, fill)
        disc(d, p1[0], p1[1], r * 0.31, fill)
    disc(d, cx, cy, r, fill)


def shield_pts(cx, top, w, h):
    hw = w / 2
    r = [(cx, top), (cx + hw, top + 0.14 * h), (cx + hw * 0.97, top + 0.5 * h)]
    r += bez((cx + hw * 0.97, top + 0.5 * h), (cx + hw * 0.9, top + 0.84 * h), (cx, top + h), 16)
    left = [(2 * cx - x, y) for (x, y) in reversed(r[1:-1])]
    return r + left


def badge_shield(img, cx, top, w, h, halo=18):
    lay, d = canvas()
    d.polygon(shield_pts(cx, top, w, h), fill=W)
    t = w * 0.16
    d.polygon(shield_pts(cx, top + t * 1.1, w - 2 * t, h - t * 2.9), fill=T)
    stamp(img, lay, halo)


def lens_pts(cx, cy, w, h, n=60):
    """Almond eye outline: two circular arcs meeting at the corners."""
    hw, hh = w / 2, h / 2
    R = (hw * hw + hh * hh) / (2 * hh)
    k = R - hh
    top = []
    for i in range(n + 1):
        x = -hw + w * i / n
        y = math.sqrt(max(R * R - x * x, 0.0)) - k
        top.append((cx + x, cy - y))
    bot = [(x, 2 * cy - y) for (x, y) in reversed(top)]
    return top + bot


def eye(img, cx, cy, w, h, t, iris_r, iris_dx=0.0, pupil_r=0.0):
    d = ImageDraw.Draw(img)
    d.polygon(lens_pts(cx, cy, w, h), fill=W)
    inner = lens_pts(cx, cy, w - 3.2 * t, h - 2 * t)
    d.polygon(inner, fill=T)
    lay, ld = canvas()
    disc(ld, cx + iris_dx, cy, iris_r)
    if pupil_r:
        disc(ld, cx + iris_dx, cy, pupil_r, T)
    m, md = canvas()
    md.polygon(inner, fill=W)
    img.alpha_composite(clip(lay, m))


def moon(img, cx, cy, r, halo=16):
    lay, d = canvas()
    disc(d, cx, cy, r)
    disc(d, cx + 0.44 * r, cy - 0.34 * r, 0.8 * r, T)
    stamp(img, lay, halo)


def padlock(d, cx, cy, bw, bh, sw, fill=W):
    """cy is the body's centre."""
    top = cy - bh / 2
    sr = bw * 0.30
    yc = top - bh * 0.24
    pts = [(cx - sr, top + 20), (cx - sr, yc)] + arc_pts(cx, yc, sr, 180, 360, 36) + [(cx + sr, top + 20)]
    poly(d, pts, sw, fill)
    d.rounded_rectangle((cx - bw / 2, top, cx + bw / 2, cy + bh / 2), radius=bw * 0.12, fill=fill)


def helix(d, a0, a1, c, amp, turns, w, rung_w, fill=W, vertical=True, rungs=7):
    n = 300
    pa, pb = [], []
    for i in range(n + 1):
        t = i / n
        u = a0 + (a1 - a0) * t
        o = math.sin(t * TAU * turns) * amp
        pa.append((c + o, u) if vertical else (u, c + o))
        pb.append((c - o, u) if vertical else (u, c - o))
    if rung_w:
        for i in range(1, rungs + 1):
            t = i / (rungs + 1)
            u = a0 + (a1 - a0) * t
            o = math.sin(t * TAU * turns) * amp
            if abs(o) > amp * 0.4:
                if vertical:
                    line(d, (c + o, u), (c - o, u), rung_w, fill)
                else:
                    line(d, (u, c + o), (u, c - o), rung_w, fill)
    for pts in (pa, pb):
        poly(d, pts, w, fill)


def snowflake(d, cx, cy, R, w, fill=W):
    for k in range(6):
        a = -math.pi / 2 + k * TAU / 6
        ux, uy = math.cos(a), math.sin(a)
        line(d, (cx, cy), (cx + ux * R, cy + uy * R), w, fill)
        for f, L in ((0.5, 0.36), (0.8, 0.24)):
            bx, by = cx + ux * R * f, cy + uy * R * f
            for s in (-1, 1):
                b = a + s * math.radians(52)
                line(d, (bx, by), (bx + math.cos(b) * R * L, by + math.sin(b) * R * L), w * 0.84, fill)
    disc(d, cx, cy, w * 1.1, fill)


def sun(d, cx, cy, r, R0, R1, w, n=8, fill=W):
    disc(d, cx, cy, r, fill)
    for k in range(n):
        a = k * TAU / n - math.pi / 2
        L = R1 if k % 2 == 0 else R0 + (R1 - R0) * 0.66
        line(d, (cx + math.cos(a) * R0, cy + math.sin(a) * R0), (cx + math.cos(a) * L, cy + math.sin(a) * L), w, fill)


def puff(d, cx, cy, s, fill=W):
    """Small cloud. Reaches x +-1.07 s, y -0.84 s .. +0.64 s."""
    disc(d, cx - 0.55 * s, cy + 0.12 * s, 0.52 * s, fill)
    disc(d, cx, cy - 0.18 * s, 0.66 * s, fill)
    disc(d, cx + 0.55 * s, cy + 0.12 * s, 0.48 * s, fill)
    d.rounded_rectangle((cx - 0.95 * s, cy + 0.05 * s, cx + 0.95 * s, cy + 0.64 * s), radius=0.29 * s, fill=fill)


def heart(d, cx, cy, s=1.0, fill=W):
    disc(d, cx - 95 * s, cy - 60 * s, 115 * s, fill)
    disc(d, cx + 95 * s, cy - 60 * s, 115 * s, fill)
    d.polygon(((cx - 205 * s, cy - 25 * s), (cx + 205 * s, cy - 25 * s), (cx, cy + 200 * s)), fill=fill)


def wave(d, x0, x1, y, amp, periods, w, fill=W):
    pts = [(x0 + (x1 - x0) * i / 120, y + amp * math.sin(i / 120 * TAU * periods)) for i in range(121)]
    poly(d, pts, w, fill)


def curl_line(d, x0, y, x1, R, up=True, w=34, sweep=290, fill=W):
    """A wind stroke: straight, then curling up (or down) and back on itself."""
    pts = [(x0, y)]
    cy0 = y - R if up else y + R
    for i in range(61):
        f = i / 60
        a = math.radians(90 - sweep * f) if up else math.radians(-90 + sweep * f)
        rr = R * (1 - 0.28 * f)
        pts.append((x1 + math.cos(a) * rr, cy0 + math.sin(a) * rr))
    poly(d, pts, w, fill)


def capsule_layer(L=380, H=150, t=30, solid=False):
    lay, d = canvas()
    x0, x1, y0, y1 = C - L / 2, C + L / 2, C - H / 2, C + H / 2
    d.rounded_rectangle((x0, y0, x1, y1), radius=H / 2, fill=W)
    if not solid:
        d.rounded_rectangle((x0 + t, y0 + t, x1 - t, y1 - t), radius=H / 2 - t, fill=T)
        disc(d, x0 + H / 2, C, H / 2)
        d.rectangle((x0 + H / 2, y0, C + t / 2, y1), fill=W)
    line(d, (x0 + H * 0.45, y0 + H * 0.27), (C - H * 0.32, y0 + H * 0.27), H * 0.13, T)  # shine
    if solid:
        line(d, (C + H * 0.32, y0 + H * 0.27), (x1 - H * 0.45, y0 + H * 0.27), H * 0.13, T)
    return lay


# ----------------------------------------------------------------------------------------------- creatures


def mosquito_layer(k=1.0, small=False):
    lay, d = canvas()
    for pts in (((214, 286), (154, 350), (112, 440)),
                ((242, 298), (252, 380), (214, 468)),
                ((272, 292), (350, 360), (410, 452))):
        poly(d, pts, 18 * k)
    line(d, (150, 272), (62, 358), 20 * k)  # proboscis
    d.polygon(ellipse_pts(372, 214, 118, 42 + (8 if small else 0), -22), fill=W)  # abdomen
    d.ellipse((178, 198, 302, 302), fill=W)  # thorax
    disc(d, 168, 258, 40 + (6 if small else 0))  # head
    if not small:
        line(d, (158, 226), (116, 176), 14 * k)  # antenna
        ax, ay = math.cos(math.radians(-22)), math.sin(math.radians(-22))
        px, py = -ay, ax
        for off in (-6, 38, 78):
            cx, cy = 372 + ax * off, 214 + ay * off
            line(d, (cx - px * 60, cy - py * 60), (cx + px * 60, cy + py * 60), 12 * k, T)
        disc(d, 156, 252, 12, T)  # eye
    wings, wd = canvas()
    wd.polygon(ellipse_pts(318, 138, 108, 38, -38), fill=W)
    wd.polygon(ellipse_pts(342, 162, 98, 32, -16), fill=W)
    stamp(lay, wings, 22 if small else 13)
    return lay


def rat_layer():
    lay, d = canvas()
    poly(d, [(406, 352), (450, 346), (474, 314), (470, 270), (442, 246)], 28)  # tail
    d.ellipse((168, 214, 432, 402), fill=W)  # body
    d.polygon(((214, 232), (64, 328), (88, 354), (226, 386)), fill=W)  # snout wedge
    disc(d, 186, 306, 78)  # head
    disc(d, 70, 336, 19)  # nose
    disc(d, 140, 290, 15, T)  # eye
    d.rounded_rectangle((196, 372, 252, 414), radius=16, fill=W)  # front foot
    d.rounded_rectangle((332, 376, 404, 416), radius=16, fill=W)  # back foot
    ear, ed = canvas()
    disc(ed, 200, 214, 50)
    disc(ed, 202, 216, 22, T)
    stamp(lay, ear, 12)
    return lay


def pig_layer():
    lay, d = canvas()
    for s in (-1, 1):
        def x(v, s=s):
            return C + s * (v - C)
        d.polygon(((x(108), 214), (x(96), 66), (x(226), 142)), fill=W)
        disc(d, x(108), 82, 20)
    disc(d, C, 292, 168)
    disc(d, 194, 246, 23, T)
    disc(d, 318, 246, 23, T)
    d.ellipse((C - 104, 352 - 78, C + 104, 352 + 78), fill=T)  # gap round the snout
    d.ellipse((C - 84, 352 - 60, C + 84, 352 + 60), fill=W)
    d.ellipse((222 - 17, 352 - 26, 222 + 17, 352 + 26), fill=T)
    d.ellipse((290 - 17, 352 - 26, 290 + 17, 352 + 26), fill=T)
    return lay


def cow_layer():
    lay, d = canvas()
    for s in (-1, 1):
        def x(v, s=s):
            return C + s * (v - C)
        poly(d, [(x(180), 150), (x(122), 120), (x(98), 58)], 40)  # horn
        d.polygon(ellipse_pts(x(102), 218, 74, 34, -22 * s), fill=W)  # ear
    d.rounded_rectangle((150, 112, 362, 340), radius=84, fill=W)  # skull
    disc(d, 206, 230, 21, T)
    disc(d, 306, 230, 21, T)
    d.ellipse((C - 136, 372 - 98, C + 136, 372 + 98), fill=T)  # gap round the muzzle
    d.ellipse((C - 118, 372 - 80, C + 118, 372 + 80), fill=W)
    d.ellipse((212 - 18, 384 - 26, 212 + 18, 384 + 26), fill=T)
    d.ellipse((300 - 18, 384 - 26, 300 + 18, 384 + 26), fill=T)
    return lay


# ----------------------------------------------------------------------------------------------- transmission


def air1():
    # breath cloud spraying droplets
    img, d = canvas()
    disc(d, 150, 375, 80)
    disc(d, 245, 325, 100)
    disc(d, 340, 375, 78)
    d.rounded_rectangle((72, 370, 418, 452), radius=41, fill=W)
    drop(d, 395, 190, 44, 225)
    drop(d, 285, 122, 28, 205)
    drop(d, 462, 292, 26, 250)
    return img


def air2():
    # wind strokes carrying droplets
    img, d = canvas()
    curl_line(d, 50, 180, 300, 60, True)
    line(d, (95, 276), (425, 276), 34)
    curl_line(d, 50, 362, 270, 46, False)
    drop(d, 175, 92, 30, 270)
    drop(d, 435, 385, 38, 270)
    return img


def water1():
    # a tap with a drop falling from it
    img, d = canvas()
    dx = 60
    d.rounded_rectangle((34 + dx, 118, 76 + dx, 252), radius=14, fill=W)  # wall plate
    d.rounded_rectangle((62 + dx, 148, 336 + dx, 218), radius=22, fill=W)  # pipe
    d.rounded_rectangle((262 + dx, 148, 336 + dx, 292), radius=26, fill=W)  # spout
    d.rounded_rectangle((248 + dx, 276, 350 + dx, 306), radius=12, fill=W)  # lip
    d.rectangle((168 + dx, 104, 206 + dx, 150), fill=W)  # stem
    d.rounded_rectangle((104 + dx, 70, 270 + dx, 108), radius=19, fill=W)  # handle
    drop(d, 299 + dx, 425, 50)
    return img


def water2():
    # a ship riding a wave, a drop of ballast water in its hull
    img, d = canvas()
    y = 20
    d.polygon(((52, 250 + y), (460, 250 + y), (402, 372 + y), (112, 372 + y)), fill=W)  # hull
    d.rounded_rectangle((170, 168 + y, 330, 262 + y), radius=14, fill=W)  # deckhouse
    d.rounded_rectangle((300, 112 + y, 344, 180 + y), radius=10, fill=W)  # funnel
    for x in (198, 248):
        d.rounded_rectangle((x, 192 + y, x + 32, 222 + y), radius=8, fill=T)
    drop(d, C, 334 + y, 27, 0, T)
    wave(d, 40, 472, 448, 18, 2.5, 30)
    return img


def insect1():
    img, _ = canvas()
    img.alpha_composite(mosquito_layer(1.3))
    return img


def insect2():
    img, _ = canvas()
    m = mosquito_layer(2.2, small=True)
    for (cx, cy, ang) in ((140, 145, -12), (370, 205, 10), (225, 375, -4)):
        stamp(img, place(m, cx, cy, 0.47, ang), 10)
    return img


def rodent1():
    img, d = canvas()
    img.alpha_composite(rat_layer())
    d = ImageDraw.Draw(img)
    for (x, y, r) in ((262, 146, 20), (332, 106, 17), (394, 156, 19)):
        disc(d, x, y, r)
    return img


def rodent2():
    img, d = canvas()
    d.rounded_rectangle((62, 352, 450, 470), radius=30, fill=W)  # drain grate
    for i in range(5):
        x = 104 + i * 66
        d.rounded_rectangle((x, 378, x + 36, 444), radius=14, fill=T)
    stamp(img, place(rat_layer(), C, 196, 0.8), 14)
    return img


def farm1():
    img, _ = canvas()
    img.alpha_composite(pig_layer())
    return img


def farm2():
    img, _ = canvas()
    img.alpha_composite(place(cow_layer(), 190, 200, 0.7))
    stamp(img, place(pig_layer(), 330, 330, 0.68), 16)
    return img


def band(d, p0, p1, hw, fill=W, ext=60):
    """A straight band of half width hw from p0 to p1, overshooting both ends by ext (clip it after)."""
    ux, uy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(ux, uy)
    ux, uy = ux / L, uy / L
    nx, ny = -uy, ux
    a = (p0[0] - ux * ext, p0[1] - uy * ext)
    b = (p1[0] + ux * ext, p1[1] + uy * ext)
    d.polygon(((a[0] + nx * hw, a[1] + ny * hw), (b[0] + nx * hw, b[1] + ny * hw),
               (b[0] - nx * hw, b[1] - ny * hw), (a[0] - nx * hw, a[1] - ny * hw)), fill=fill)


def stowaway():
    # a cross-braced wooden cargo crate with a virus riding on it
    img, d = canvas()
    x0, y0, x1, y1 = 52, 168, 364, 480
    t = 40
    d.rounded_rectangle((x0, y0, x1, y1), radius=18, fill=W)
    ix0, iy0, ix1, iy1 = x0 + t, y0 + t, x1 - t, y1 - t
    d.rectangle((ix0, iy0, ix1, iy1), fill=T)
    inner, idr = canvas()
    idr.rectangle((ix0, iy0, ix1, iy1), fill=W)
    brace, bd = canvas()
    band(bd, (ix0, iy1), (ix1, iy0), 24)
    band(bd, (ix0, iy0), (ix1, iy1), 24)
    img.alpha_composite(clip(brace, inner))
    lay, ld = canvas()
    bug(ld, 384, 144, 58)
    stamp(img, lay, 16)
    return img


def hardy():
    # a spiky spore inside a ring of armour plates
    img, d = canvas()
    for k in range(12):
        a = k * TAU / 12
        tip = (C + math.cos(a) * 168, C + math.sin(a) * 168)
        b1 = (C + math.cos(a - 0.2) * 96, C + math.sin(a - 0.2) * 96)
        b2 = (C + math.cos(a + 0.2) * 96, C + math.sin(a + 0.2) * 96)
        d.polygon((b1, tip, b2), fill=W)
    disc(d, C, C, 108)
    ring(d, C, C, 54, 20, T)
    ring(d, C, C, 232, 38)
    for k in range(6):
        a = math.radians(k * 60 + 30)
        line(d, (C + math.cos(a) * 186, C + math.sin(a) * 186), (C + math.cos(a) * 246, C + math.sin(a) * 246), 22, T)
    return img


# ----------------------------------------------------------------------------------------------- symptoms


def nausea():
    # a stomach with a swirl in it
    img, d = canvas()
    # gullet coming in at the top, fundus bulging up beside it, body curving down and round to the
    # pylorus, duodenum leaving downward: the classic J-shaped stomach
    pts = [(296, 28, 26), (294, 96, 28), (300, 150, 52), (338, 196, 92), (322, 280, 108),
           (252, 346, 98), (176, 356, 74), (124, 326, 50), (98, 290, 38), (78, 334, 32), (84, 406, 30),
           (88, 450, 28)]
    for (x, y, r) in spline(pts, 18):
        disc(d, x, y, r)
    sp = []
    for i in range(121):
        f = i / 120
        a = f * TAU * 1.75
        r = 8 + 58 * f
        sp.append((300 + math.cos(a) * r, 262 + math.sin(a) * r))
    poly(d, sp, 22, T)
    return img


def cough():
    img, d = canvas()
    disc(d, 180, 262, 150)
    poly(d, [(112, 206), (154, 232), (112, 258)], 26, T)
    poly(d, [(262, 206), (220, 232), (262, 258)], 26, T)
    d.ellipse((200, 302, 304, 386), fill=T)  # open mouth
    puff(d, 420, 300, 56)
    puff(d, 432, 172, 34)
    puff(d, 426, 414, 30)
    return img


def rash():
    # a hand covered in spots
    img, d = canvas()
    for (x0, y0) in ((128, 96), (198, 58), (268, 78), (338, 128)):
        d.rounded_rectangle((x0, y0, x0 + 60, 300), radius=30, fill=W)
    line(d, (162, 404), (66, 274), 68)  # thumb
    d.rounded_rectangle((128, 236, 398, 476), radius=78, fill=W)  # palm
    for (x, y, r) in ((214, 322, 26), (306, 300, 22), (332, 398, 28), (206, 418, 20), (270, 368, 16)):
        disc(d, x, y, r, T)
    return img


def insomnia():
    # wide open eye under a crescent moon
    img, _ = canvas()
    eye(img, 232, 300, 390, 250, 30, 78, 0, 30)
    moon(img, 412, 112, 72)
    return img


def vomit():
    img, d = canvas()
    disc(d, 200, 186, 158)
    disc(d, 146, 140, 22, T)
    disc(d, 258, 140, 22, T)
    d.ellipse((188, 226, 300, 300), fill=T)
    lay, ld = canvas()
    for (x, y, r) in spline([(244, 262, 34), (262, 330, 38), (292, 392, 44), (318, 440, 50)], 14):
        disc(ld, x, y, r)
    ld.ellipse((150, 430, 470, 482), fill=W)  # puddle
    stamp(img, lay, 16)
    return img


def sneeze():
    # a nose spraying droplets
    img, d = canvas()
    d.polygon(((228, 52), (284, 52), (318, 250), (194, 250)), fill=W)
    disc(d, C, 52, 28)
    disc(d, C, 268, 84)
    disc(d, 172, 288, 62)
    disc(d, 340, 288, 62)
    d.ellipse((178, 300, 238, 336), fill=T)
    d.ellipse((274, 300, 334, 336), fill=T)
    for (x, y, r) in ((196, 398, 20), (256, 404, 22), (316, 398, 20),
                      (140, 448, 18), (214, 460, 20), (298, 460, 20), (372, 448, 18)):
        disc(d, x, y, r)
    return img


def fever():
    # a thermometer, mercury high
    img, d = canvas()
    cx = 226
    d.rounded_rectangle((cx - 56, 40, cx + 56, 380), radius=56, fill=W)
    d.rounded_rectangle((cx - 28, 68, cx + 28, 380), radius=28, fill=T)
    d.rectangle((cx - 28, 168, cx + 28, 380), fill=W)
    disc(d, cx, 396, 86)
    for (y, L) in ((96, 62), (146, 40), (196, 62), (246, 40)):
        line(d, (cx + 84, y), (cx + 84 + L, y), 22)
    return img


def cysts():
    # lumps rising out of the skin
    # a lumpy blob with fluid sacs inside it
    img, d = canvas()
    disc(d, C, C, 150)
    for k, r in enumerate((62, 54, 66, 50, 60, 52, 58)):
        a = -math.pi / 2 + k * TAU / 7
        disc(d, C + math.cos(a) * 150, C + math.sin(a) * 150, r)
    ring(d, C - 40, C - 30, 52, 20, T)
    ring(d, C + 58, C + 34, 40, 18, T)
    ring(d, C - 20, C + 82, 30, 16, T)
    return img


def anaemia():
    # a blood drop running low, and a down arrow
    img, d = canvas()
    cx, cy, r, t = 180, 340, 116, 30
    drop(d, cx, cy, r)
    drop(d, cx, cy, r - t, 0, T)
    lay, ld = canvas()
    drop(ld, cx, cy, r - t)
    level, lvd = canvas()
    lvd.rectangle((0, cy - 10, S, S), fill=W)
    img.alpha_composite(clip(lay, level))
    line(d, (402, 96), (402, 330), 54)
    d.polygon(((330, 318), (474, 318), (402, 446)), fill=W)
    return img


def paranoia():
    # a narrowed eye glancing sideways, a raised brow, a bead of sweat
    img, d = canvas()
    eye(img, 266, 318, 370, 196, 30, 62, 80, 24)
    line(d, (150, 176), (400, 136), 34)
    drop(d, 76, 196, 36)
    return img


def pneumonia():
    img, d = canvas()
    left = [(206, 128), (150, 96), (98, 158), (66, 280), (60, 400), (96, 466), (172, 472),
            (232, 448), (238, 356), (222, 300), (232, 196)]
    right = [(S - x, y) for (x, y) in reversed(left)]
    for side in (left, right):
        d.polygon(spline(side, 10, closed=True), fill=W)
    for (x, y, r) in ((110, 392, 22), (170, 424, 14), (402, 384, 20), (346, 428, 15)):
        disc(d, x, y, r, T)
    air, ad = canvas()
    ad.rounded_rectangle((234, 28, 278, 214), radius=22, fill=W)
    for s in (-1, 1):
        def x(v, s=s):
            return C + s * (v - C)
        poly(ad, [(C, 200), (x(198), 252), (x(176), 318)], 30)
        poly(ad, [(x(198), 252), (x(142), 282)], 24)
    stamp(img, air, 14)
    return img


def bleeding():
    img, d = canvas()
    d.ellipse((60, 418, 452, 478), fill=W)  # pool
    disc(d, 96, 392, 14)
    disc(d, 420, 386, 16)
    lay, ld = canvas()
    drop(ld, 214, 268, 104)
    drop(ld, 386, 194, 50)
    drop(ld, 118, 150, 34)
    stamp(img, lay, 16)
    return img


def seizures():
    # a head, a lightning bolt over it, shake lines either side
    img, d = canvas()
    disc(d, C, 282, 90)
    d.pieslice((104, 396, 408, 576), 180, 360, fill=W)
    for (r, a) in ((140, 30), (182, 24)):
        poly(d, arc_pts(C, 282, r, 180 - a, 180 + a, 16), 24)
        poly(d, arc_pts(C, 282, r, -a, a, 16), 24)
    bolt, bd = canvas()
    bd.polygon(((300, 20), (346, 20), (298, 84), (342, 84), (238, 172), (266, 106), (222, 106)), fill=W)
    stamp(img, bolt, 14)
    return img


def paralysis():
    # a rigid standing figure with a padlock
    img, d = canvas()
    cx = 196
    disc(d, cx, 92, 58)
    d.rounded_rectangle((cx - 64, 166, cx + 64, 336), radius=28, fill=W)
    d.rounded_rectangle((cx - 116, 172, cx - 78, 330), radius=19, fill=W)
    d.rounded_rectangle((cx + 78, 172, cx + 116, 330), radius=19, fill=W)
    d.rounded_rectangle((cx - 58, 322, cx - 8, 480), radius=22, fill=W)
    d.rounded_rectangle((cx + 8, 322, cx + 58, 480), radius=22, fill=W)
    lay, ld = canvas()
    padlock(ld, 400, 404, 150, 124, 30)
    disc(ld, 400, 396, 17, T)
    ld.polygon(((392, 400), (408, 400), (414, 436), (386, 436)), fill=T)
    stamp(img, lay, 16)
    return img


def immune():
    # a shield cracked in two
    sh, d = canvas()
    d.polygon(shield_pts(C, 34, 380, 444), fill=W)
    crack = [(270, 0), (262, 34), (232, 128), (288, 208), (226, 300), (276, 380), (254, S)]
    left, right = split(sh, crack)
    img, _ = canvas()
    img.alpha_composite(place(left, 240, 262, 1, -5))
    img.alpha_composite(place(right, 272, 250, 1, 6))
    return img


def organs():
    # a heart broken in two
    hl, d = canvas()
    heart(d, C, 262)
    crack = [(250, 0), (256, 110), (220, 190), (284, 270), (232, 350), (262, S)]
    left, right = split(hl, crack)
    img, _ = canvas()
    img.alpha_composite(place(left, 236, 266, 1, -7))
    img.alpha_composite(place(right, 276, 262, 1, 7))
    return img


def coma():
    # a closed eye over a monitor trace that has gone almost flat
    img, d = canvas()
    arc = []
    for i in range(41):
        f = i / 40
        arc.append((70 + 372 * f, 120 + 90 * math.sin(math.pi * f)))
    poly(d, arc, 36)
    for f in (0.12, 0.31, 0.5, 0.69, 0.88):
        x, y = 70 + 372 * f, 120 + 90 * math.sin(math.pi * f)
        nx, ny = -90 * math.pi * math.cos(math.pi * f), 372.0
        L = math.hypot(nx, ny)
        nx, ny = nx / L, ny / L
        line(d, (x + nx * 22, y + ny * 22), (x + nx * 74, y + ny * 74), 26)
    poly(d, [(40, 392), (118, 392), (142, 338), (172, 446), (198, 392), (472, 392)], 28)
    return img


# ----------------------------------------------------------------------------------------------- abilities


def cold1():
    img, d = canvas()
    snowflake(d, C, C, 214, 38)
    return img


def cold2():
    img, d = canvas()
    snowflake(d, 216, 216, 180, 36)
    badge_shield(img, 382, 282, 190, 212)
    return img


def heat1():
    img, d = canvas()
    sun(d, C, C, 112, 160, 228, 46)
    return img


def heat2():
    img, d = canvas()
    sun(d, 220, 220, 92, 132, 190, 40)
    badge_shield(img, 382, 282, 190, 212)
    return img


def drug1():
    img, _ = canvas()
    img.alpha_composite(place(capsule_layer(), C, C, 1, -45))
    return img


def drug2():
    # a pill snapped in two by a virus
    cap = capsule_layer(340, 140, 28, solid=True)
    crack = [(262, 0), (262, 172), (238, 206), (278, 246), (240, 292), (262, 336), (262, S)]
    left, right = split(cap, crack)
    img, _ = canvas()
    ax, ay = math.cos(math.radians(-45)), math.sin(math.radians(-45))
    off = 84
    img.alpha_composite(place(left, C - ax * off, C - ay * off, 1, -53))
    img.alpha_composite(place(right, C + ax * off, C + ay * off, 1, -37))
    lay, ld = canvas()
    bug(ld, C, C, 40)
    stamp(img, lay, 14)
    return img


def gene_shield(n):
    # a solid shield with a DNA helix cut through it; the tier is the number of bars under it
    img, d = canvas()
    top, w, h = 24, 340, 384
    d.polygon(shield_pts(C, top, w, h), fill=W)
    helix(d, 92, 318, C, 62, 1.25, 26, 16, fill=T)
    bw, bh, gap = 84, 40, 24
    total = n * bw + (n - 1) * gap
    x = C - total / 2
    for _ in range(n):
        d.rounded_rectangle((x, 432, x + bw, 432 + bh), radius=bh / 2, fill=W)
        x += bw + gap
    return img


def shield1():
    return gene_shield(1)


def shield2():
    return gene_shield(2)


def shield3():
    return gene_shield(3)


def lock():
    # a padlock with a DNA helix running through the body
    img, d = canvas()
    padlock(d, C, 340, 316, 236, 50)
    helix(d, 128, 384, 340, 58, 1.25, 30, 18, fill=T, vertical=False)
    return img


# ----------------------------------------------------------------------------------------------- pathogens


def bacterium():
    # a fat rod with a tuft of wavy flagella at one end
    lay, d = canvas()
    x0, x1, y0, y1 = 176, 440, 172, 340
    d.rounded_rectangle((x0, y0, x1, y1), radius=84, fill=W)
    disc(d, 292, 310, 13, T)
    disc(d, 372, 204, 13, T)
    for (y, dy) in ((214, -1.0), (256, 0.0), (298, 1.0)):
        pts = []
        for i in range(61):
            f = i / 60
            pts.append((196 - 158 * f, y + dy * 58 * f + 17 * math.sin(f * TAU * 1.7)))
        poly(d, pts, 22)
    pts = [(238 + 150 * i / 40, C + 22 * math.sin(i / 40 * TAU * 1.5)) for i in range(41)]
    poly(d, pts, 22, T)
    return place(lay, C, C, 1, 22)


def virus():
    # a phage: faceted capsid, tail, base plate and legs
    img, d = canvas()
    head = ngon(C, 128, 106, 6, -90)
    d.polygon(head, fill=W)
    for k in (1, 3, 5):
        hx, hy = head[k]
        line(d, (C, 128), (C + (hx - C) * 0.72, 128 + (hy - 128) * 0.72), 16, T)
    d.rounded_rectangle((C - 46, 228, C + 46, 252), radius=10, fill=W)
    d.rectangle((C - 26, 246, C + 26, 356), fill=W)
    d.rounded_rectangle((C - 72, 350, C + 72, 376), radius=12, fill=W)
    for s in (-1, 1):
        poly(d, [(C + s * 58, 368), (C + s * 122, 402), (C + s * 150, 470)], 24)
        poly(d, [(C + s * 26, 372), (C + s * 62, 418), (C + s * 66, 478)], 24)
    return img


def fungus():
    img, d = canvas()
    d.rounded_rectangle((204, 236, 308, 452), radius=40, fill=W)
    d.ellipse((176, 420, 336, 476), fill=W)
    cap, cd = canvas()
    cd.pieslice((54, 66, 458, 400), 180, 360, fill=W)
    cd.ellipse((70, 204, 442, 262), fill=W)
    for (x, y, r) in ((168, 176, 30), (268, 122, 34), (356, 186, 26), (250, 206, 18)):
        disc(cd, x, y, r, T)
    stamp(img, cap, 16)
    for (x, y, r) in ((420, 340, 16), (96, 330, 14), (440, 420, 12)):
        disc(d, x, y, r)
    return img


def parasite():
    # a segmented worm
    img, d = canvas()
    n = 160
    path = []
    for i in range(n + 1):
        f = i / n
        x = 78 + 356 * f
        y = 262 - 118 * math.sin(f * TAU)
        r = 18 + 34 * min(1.0, f / 0.3) - 6 * max(0.0, (f - 0.8) / 0.2)
        path.append((x, y, r))
    for (x, y, r) in path:
        disc(d, x, y, r)
    f = 0.16
    while f < 0.92:
        i = int(f * n)
        x, y, r = path[i]
        x2, y2, _ = path[i + 1]
        tx, ty = x2 - x, y2 - y
        L = math.hypot(tx, ty)
        px, py = -ty / L, tx / L
        line(d, (x - px * r * 0.62, y - py * r * 0.62), (x + px * r * 0.62, y + py * r * 0.62), 12, T)
        f += 0.075
    hx, hy, _ = path[-1]
    disc(d, hx + 18, hy, 12, T)  # mouth
    return img


# ----------------------------------------------------------------------------------------------- extra


def carrier():
    # a sick person walking (map sprite): hunched, mid-stride, virus dots by the head
    img, d = canvas()
    poly(d, [(232, 318), (200, 400), (146, 456), (170, 478)], 54)  # back leg
    poly(d, [(248, 318), (316, 394), (320, 468), (366, 472)], 54)  # front leg
    poly(d, [(276, 214), (222, 262), (174, 300)], 40)  # back arm
    line(d, (292, 194), (242, 314), 94)  # torso
    poly(d, [(302, 210), (344, 266), (362, 326)], 40)  # front arm
    head, hd = canvas()
    disc(hd, 330, 108, 54)
    stamp(img, head, 12)
    lay, ld = canvas()
    bug(ld, 168, 92, 28)
    bug(ld, 232, 52, 17)
    bug(ld, 118, 168, 15)
    stamp(img, lay, 14)
    return img


ICONS = {
    # transmission
    "air1": air1, "air2": air2, "water1": water1, "water2": water2,
    "insect1": insect1, "insect2": insect2, "rodent1": rodent1, "rodent2": rodent2,
    "farm1": farm1, "farm2": farm2, "stowaway": stowaway, "hardy": hardy,
    # symptoms
    "nausea": nausea, "cough": cough, "rash": rash, "insomnia": insomnia, "vomit": vomit,
    "sneeze": sneeze, "fever": fever, "cysts": cysts, "anaemia": anaemia, "paranoia": paranoia,
    "pneumonia": pneumonia, "bleeding": bleeding, "seizures": seizures, "paralysis": paralysis,
    "immune": immune, "organs": organs, "coma": coma,
    # abilities
    "cold1": cold1, "cold2": cold2, "heat1": heat1, "heat2": heat2, "drug1": drug1, "drug2": drug2,
    "shield1": shield1, "shield2": shield2, "shield3": shield3, "lock": lock,
    # pathogens
    "bacterium": bacterium, "virus": virus, "fungus": fungus, "parasite": parasite,
    # extra
    "carrier": carrier,
}


def render(name):
    big = finish(fit(ICONS[name]()))
    return finish(big.resize((128, 128), Image.LANCZOS))


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for name in ICONS:
        img = render(name)
        img.save(os.path.join(OUT, name + ".png"))
        tiles.append(img)
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (128 * cols, 128 * rows), (30, 34, 54, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t, ((i % cols) * 128, (i // cols) * 128))
    sheet.save(os.path.join(OUT, "_sheet.png"))
    print("wrote", len(tiles), "icons to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
