"""RoPlague's UI glyphs, drawn from scratch (no third-party art, no text).

Writes 128x128 white-on-transparent masks (tinted in game with ImageColor3, like Assets/UiIcons) to
build/plague_icons/<name>.png and a contact sheet build/plague_icons/_sheet.png. Upload them, then put
the ids in src/shared/Assets/PlagueIcons.luau.

    .venv/Scripts/python.exe tools/assets/make_plague_icons.py
"""

import math
import os

from PIL import Image, ImageDraw

S = 512  # drawn at 4x, saved at 128
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "build", "plague_icons")
W = (255, 255, 255, 255)
T = (0, 0, 0, 0)


def canvas():
    img = Image.new("RGBA", (S, S), T)
    return img, ImageDraw.Draw(img)


def disc(d, cx, cy, r, fill=W):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def ring(d, cx, cy, r, w):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=W, width=w)


def line(d, a, b, w):
    d.line((a, b), fill=W, width=w)
    disc(d, a[0], a[1], w / 2)
    disc(d, b[0], b[1], w / 2)


def virus():
    img, d = canvas()
    c = S / 2
    # spikes with knobs
    for k in range(10):
        a = k * math.tau / 10 + 0.15
        p0 = (c + math.cos(a) * 120, c + math.sin(a) * 120)
        p1 = (c + math.cos(a) * 205, c + math.sin(a) * 205)
        line(d, p0, p1, 26)
        disc(d, p1[0], p1[1], 30)
    disc(d, c, c, 150)
    # holes in the body (cut out)
    for (x, y, r) in ((-48, -40, 30), (44, -18, 22), (-10, 52, 26), (58, 58, 14), (-66, 30, 12)):
        disc(d, c + x, c + y, r, T)
    return img


def dna():
    img, d = canvas()
    top, bot = 60, S - 60
    amp = 120
    n = 400
    pa, pb = [], []
    for i in range(n + 1):
        t = i / n
        y = top + (bot - top) * t
        ph = t * math.tau * 1.25
        pa.append((S / 2 + math.sin(ph) * amp, y))
        pb.append((S / 2 - math.sin(ph) * amp, y))
    # rungs
    for i in range(1, 10):
        t = i / 10
        y = top + (bot - top) * t
        ph = t * math.tau * 1.25
        x1 = S / 2 + math.sin(ph) * amp
        x2 = S / 2 - math.sin(ph) * amp
        if abs(x1 - x2) > 40:
            line(d, (x1, y), (x2, y), 18)
    for pts in (pa, pb):
        for i in range(len(pts) - 1):
            d.line((pts[i], pts[i + 1]), fill=W, width=34)
        for p in (pts[0], pts[-1]):
            disc(d, p[0], p[1], 17)
    return img


def evolve():
    # a cell splitting upward: two discs and a bold up arrow
    img, d = canvas()
    c = S / 2
    d.polygon(((c, 40), (c + 150, 210), (c + 60, 210), (c + 60, 300), (c - 60, 300), (c - 60, 210), (c - 150, 210)), fill=W)
    disc(d, c - 95, 395, 75)
    disc(d, c + 95, 395, 75)
    disc(d, c - 95, 395, 32, T)
    disc(d, c + 95, 395, 32, T)
    return img


def cure():
    # a syringe, diagonal
    img, d = canvas()
    body = Image.new("RGBA", (S, S), T)
    b = ImageDraw.Draw(body)
    c = S / 2
    b.rounded_rectangle((c - 60, 150, c + 60, 380), radius=20, fill=W)
    b.rectangle((c - 34, 180, c + 34, 300), fill=T)  # the window
    for y in (200, 240, 280):
        b.rectangle((c - 34, y, c + 6, y + 10), fill=W)  # marks
    b.rectangle((c - 22, 380, c + 22, 420), fill=W)  # neck
    b.polygon(((c - 9, 420), (c + 9, 420), (c, 500)), fill=W)  # needle
    b.rectangle((c - 16, 90, c + 16, 150), fill=W)  # plunger rod
    b.rounded_rectangle((c - 80, 60, c + 80, 96), radius=14, fill=W)  # thumb rest
    b.rounded_rectangle((c - 105, 140, c + 105, 168), radius=12, fill=W)  # finger grips
    body = body.rotate(-40, resample=Image.BICUBIC, center=(c, c))
    img.alpha_composite(body)
    return img


def pencil():
    img, d = canvas()
    p = Image.new("RGBA", (S, S), T)
    b = ImageDraw.Draw(p)
    c = S / 2
    b.rounded_rectangle((c - 50, 40, c + 50, 110), radius=18, fill=W)  # eraser
    b.rectangle((c - 50, 128, c + 50, 370), fill=W)  # body
    b.polygon(((c - 50, 388), (c + 50, 388), (c, 486)), fill=W)  # tip
    p = p.rotate(-45, resample=Image.BICUBIC, center=(c, c))
    img.alpha_composite(p)
    return img


def infect():
    # a target country being hit: a dot with radiating drops
    img, d = canvas()
    c = S / 2
    disc(d, c, c, 70)
    ring(d, c, c, 140, 26)
    for k in range(8):
        a = k * math.tau / 8
        x, y = c + math.cos(a) * 210, c + math.sin(a) * 210
        disc(d, x, y, 24)
    return img


def transmission():
    # droplets in the air: three drops of different size
    img, d = canvas()

    def drop(cx, cy, r):
        disc(d, cx, cy, r)
        d.polygon(((cx - r * 0.86, cy - r * 0.5), (cx + r * 0.86, cy - r * 0.5), (cx, cy - r * 2.1)), fill=W)

    drop(170, 330, 95)
    drop(355, 250, 70)
    drop(330, 440, 44)
    return img


def symptoms():
    # a heart with a pulse line cut through it
    img, d = canvas()
    c = S / 2
    disc(d, c - 95, 200, 115)
    disc(d, c + 95, 200, 115)
    d.polygon(((c - 205, 235), (c + 205, 235), (c, 460)), fill=W)
    pts = [(40, 270), (170, 270), (205, 190), (250, 350), (290, 230), (320, 270), (470, 270)]
    for i in range(len(pts) - 1):
        d.line((pts[i], pts[i + 1]), fill=T, width=30)
    return img


def abilities():
    # a shield with a cross-check
    img, d = canvas()
    c = S / 2
    d.polygon(((c, 40), (c + 190, 110), (c + 170, 300), (c, 470), (c - 170, 300), (c - 190, 110)), fill=W)
    d.polygon(((c, 100), (c + 130, 148), (c + 116, 285), (c, 405), (c - 116, 285), (c - 130, 148)), fill=T)
    line(d, (c - 70, 255), (c - 15, 315), 40)
    line(d, (c - 15, 315), (c + 85, 190), 40)
    return img


def skull():
    img, d = canvas()
    c = S / 2
    disc(d, c, 220, 170)
    d.rounded_rectangle((c - 110, 260, c + 110, 430), radius=40, fill=W)
    disc(d, c - 65, 240, 48, T)
    disc(d, c + 65, 240, 48, T)
    d.polygon(((c, 300), (c - 26, 345), (c + 26, 345)), fill=T)
    for x in (-60, -20, 20, 60):
        d.rectangle((c + x - 9, 385, c + x + 9, 430), fill=T)
    return img


def globe_sick():
    # the world, with a virus bite out of it
    img, d = canvas()
    c = S / 2
    disc(d, c, c, 200)
    disc(d, c, c, 170, T)
    d.ellipse((c - 80, c - 200, c + 80, c + 200), outline=W, width=24)
    line(d, (c - 190, c), (c + 190, c), 24)
    line(d, (c - 160, c - 100), (c + 160, c - 100), 20)
    line(d, (c - 160, c + 100), (c + 160, c + 100), 20)
    return img


ICONS = {
    "virus": virus,
    "dna": dna,
    "evolve": evolve,
    "cure": cure,
    "pencil": pencil,
    "infect": infect,
    "transmission": transmission,
    "symptoms": symptoms,
    "abilities": abilities,
    "death": skull,
    "world": globe_sick,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for name, fn in ICONS.items():
        img = fn().resize((128, 128), Image.LANCZOS)
        img.save(os.path.join(OUT, name + ".png"))
        tiles.append(img)
    sheet = Image.new("RGBA", (128 * len(tiles), 128), (30, 34, 54, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t, (i * 128, 0))
    sheet.save(os.path.join(OUT, "_sheet.png"))
    print("wrote", len(tiles), "icons to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
