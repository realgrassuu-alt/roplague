"""RoPlague: the infected traveller's walk cycle, our own art. A sick little person seen from the side,
walking right: pale green skin, droopy eyes, a red runny nose, a hoodie, arms and legs swinging. FRAMES
frames of CELL px in one row (build/walker/walker_sheet.png); CarrierLayer steps through them and mirrors
them for a walk to the left. Drawn at SS x and downsampled, with a dark outline. No text.

    .venv/Scripts/python.exe tools/assets/make_walker.py
"""

import math
import os

from PIL import Image, ImageDraw

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(REPO, "build", "walker")
CELL = 128
FRAMES = 6
SS = 4

INK = (28, 10, 16, 255)
SKIN = (176, 214, 150, 255)
SKIN_D = (138, 182, 118, 255)
HOOD = (196, 44, 52, 255)
HOOD_D = (146, 26, 36, 255)
PANTS = (52, 58, 92, 255)
PANTS_D = (38, 42, 70, 255)
SHOE = (40, 34, 40, 255)
NOSE = (232, 70, 70, 255)
WHITE = (250, 250, 250, 255)
SPOT = (214, 74, 64, 255)
OL = 5 * SS


def limb(d, a, b, w, col, dark=None):
    """A rounded limb from a to b, outlined."""
    for width, c in ((w + OL, INK), (w, col)):
        d.line([a, b], fill=c, width=int(width))
        for p in (a, b):
            r = width / 2
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=c)
    if dark is not None:
        pass


def ell(d, box, col):
    x0, y0, x1, y1 = box
    o = OL / 2
    d.ellipse([x0 - o, y0 - o, x1 + o, y1 + o], fill=INK)
    d.ellipse(box, fill=col)


def rrect(d, box, r, col):
    x0, y0, x1, y1 = box
    o = OL / 2
    d.rounded_rectangle([x0 - o, y0 - o, x1 + o, y1 + o], radius=r + o, fill=INK)
    d.rounded_rectangle(box, radius=r, fill=col)


def at(cx, cy, ang, length):
    return (cx + math.sin(ang) * length, cy + math.cos(ang) * length)


def frame(i):
    S = CELL * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ph = i / FRAMES * 2 * math.pi
    swing = math.sin(ph)
    bob = abs(math.cos(ph)) * 3 * SS  # up at mid-stride
    cx = S * 0.5
    hip = (cx - 2 * SS, S * 0.64 - bob)
    shoulder = (cx + 2 * SS, S * 0.44 - bob)
    leg = 30 * SS
    arm = 24 * SS
    # the far leg and arm first (darker), then the body, then the near ones
    fa, na = -swing * 0.85, swing * 0.85
    for ang, col, shoe in ((fa, PANTS_D, True),):
        knee = at(hip[0], hip[1], ang, leg * 0.52)
        foot = at(knee[0], knee[1], ang + min(0.0, ang) * 1.1, leg * 0.5)
        limb(d, hip, knee, 13 * SS, col)
        limb(d, knee, foot, 12 * SS, col)
        if shoe:
            ell(d, [foot[0] - 7 * SS, foot[1] - 4 * SS, foot[0] + 9 * SS, foot[1] + 5 * SS], SHOE)
    elbow = at(shoulder[0], shoulder[1], na * 1.1, arm * 0.5)
    hand = at(elbow[0], elbow[1], na * 1.1 + 0.5, arm * 0.48)
    limb(d, shoulder, elbow, 11 * SS, HOOD_D)
    limb(d, elbow, hand, 10 * SS, HOOD_D)
    ell(d, [hand[0] - 5 * SS, hand[1] - 5 * SS, hand[0] + 5 * SS, hand[1] + 5 * SS], SKIN_D)
    # body: a hoodie, leaning forward a little (sick, hurrying)
    rrect(d, [cx - 15 * SS, S * 0.40 - bob, cx + 17 * SS, S * 0.68 - bob], 12 * SS, HOOD)
    d.rounded_rectangle([cx - 15 * SS, S * 0.60 - bob, cx + 17 * SS, S * 0.68 - bob], radius=8 * SS, fill=HOOD_D)
    # near leg
    knee = at(hip[0], hip[1], na, leg * 0.52)
    foot = at(knee[0], knee[1], na + min(0.0, na) * 1.1, leg * 0.5)
    limb(d, hip, knee, 13 * SS, PANTS)
    limb(d, knee, foot, 12 * SS, PANTS)
    ell(d, [foot[0] - 7 * SS, foot[1] - 4 * SS, foot[0] + 10 * SS, foot[1] + 5 * SS], SHOE)
    # head: big, pale green, droopy eyes, red nose, a sick spot
    hx, hy, hr = cx + 7 * SS, S * 0.28 - bob, 21 * SS
    ell(d, [hx - hr, hy - hr, hx + hr, hy + hr], SKIN)
    d.ellipse([hx - hr * 0.55, hy + hr * 0.2, hx - hr * 0.15, hy + hr * 0.55], fill=SPOT)
    # hood rim behind the face
    d.arc([hx - hr - 2 * SS, hy - hr - 2 * SS, hx + hr + 2 * SS, hy + hr + 2 * SS], 150, 300, fill=HOOD, width=8 * SS)
    # eyes: half closed
    for ex in (hx + hr * 0.22, hx + hr * 0.62):
        ey = hy - hr * 0.12
        d.ellipse([ex - 4.5 * SS, ey - 4.5 * SS, ex + 4.5 * SS, ey + 4.5 * SS], fill=WHITE)
        d.ellipse([ex - 2.5 * SS, ey - 1 * SS, ex + 2.5 * SS, ey + 4 * SS], fill=INK)
        d.line([ex - 5 * SS, ey - 2 * SS, ex + 5 * SS, ey - 1 * SS], fill=SKIN_D, width=3 * SS)
    d.ellipse([hx + hr * 0.82, hy + hr * 0.1, hx + hr * 1.15, hy + hr * 0.42], fill=NOSE, outline=INK, width=2 * SS)
    # a frown
    d.arc([hx + hr * 0.25, hy + hr * 0.42, hx + hr * 0.8, hy + hr * 0.8], 200, 340, fill=INK, width=3 * SS)
    # near arm last
    elbow = at(shoulder[0], shoulder[1], fa * 1.1, arm * 0.5)
    hand = at(elbow[0], elbow[1], fa * 1.1 + 0.5, arm * 0.48)
    limb(d, shoulder, elbow, 11 * SS, HOOD)
    limb(d, elbow, hand, 10 * SS, HOOD)
    ell(d, [hand[0] - 5 * SS, hand[1] - 5 * SS, hand[0] + 5 * SS, hand[1] + 5 * SS], SKIN)
    return im.resize((CELL, CELL), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
    for i in range(FRAMES):
        sheet.paste(frame(i), (i * CELL, 0))
    sheet.save(os.path.join(OUT, "walker_sheet.png"))
    big = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    bg = Image.new("RGBA", big.size, (70, 130, 180, 255))
    bg.alpha_composite(big)
    bg.save(os.path.join(OUT, "walker_preview.png"))
    print("ok")


if __name__ == "__main__":
    main()
