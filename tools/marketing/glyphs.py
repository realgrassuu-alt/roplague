"""White glyphs the game's icon set has no picture for (the cure's buildings), drawn as simple
silhouettes at 256 px with transparency: hospital, lab, research (a building with a dish), city."""

import os

from PIL import Image, ImageDraw

OUT = os.path.join(r"C:\Users\PC\Desktop\RoPlague_Artwork", "_glyphs")
S = 256 * 4


def _save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def hospital():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    W = (255, 255, 255, 255)
    d.rounded_rectangle((170, 300, 854, 900), 40, fill=W)
    d.rounded_rectangle((300, 140, 724, 360), 30, fill=W)
    # the cross, cut out
    d.rectangle((462, 400, 562, 700), fill=(0, 0, 0, 0))
    d.rectangle((362, 500, 662, 600), fill=(0, 0, 0, 0))
    d.rectangle((452, 760, 572, 900), fill=(0, 0, 0, 0))
    return im


def lab():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    W = (255, 255, 255, 255)
    d.rounded_rectangle((400, 110, 624, 170), 20, fill=W)
    d.rectangle((432, 150, 592, 440), fill=W)
    d.polygon([(432, 430), (592, 430), (860, 860), (164, 860)], fill=W)
    d.rounded_rectangle((164, 800, 860, 900), 40, fill=W)
    # the liquid line and two bubbles, cut out
    d.polygon([(340, 640), (684, 640), (650, 590), (374, 590)], fill=(0, 0, 0, 0))
    d.ellipse((470, 690, 530, 750), fill=(0, 0, 0, 0))
    d.ellipse((560, 730, 600, 770), fill=(0, 0, 0, 0))
    return im


def research():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    W = (255, 255, 255, 255)
    d.rounded_rectangle((180, 520, 844, 900), 30, fill=W)
    d.pieslice((260, 200, 760, 700), 180, 360, fill=W)
    d.rectangle((500, 100, 524, 260), fill=W)
    d.ellipse((470, 80, 554, 164), fill=W)
    for x in (260, 440, 620):
        d.rectangle((x, 620, x + 120, 760), fill=(0, 0, 0, 0))
    return im


def city():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    W = (255, 255, 255, 255)
    d.rectangle((150, 420, 390, 900), fill=W)
    d.rectangle((410, 180, 630, 900), fill=W)
    d.rectangle((650, 340, 874, 900), fill=W)
    for x0, x1, y0 in ((150, 390, 420), (410, 630, 180), (650, 874, 340)):
        y = y0 + 60
        while y < 820:
            for xx in range(x0 + 40, x1 - 60, 90):
                d.rectangle((xx, y, xx + 44, y + 56), fill=(0, 0, 0, 0))
            y += 110
    return im


def main():
    for f in (hospital, lab, research, city):
        _save(f(), f.__name__)
    print("glyphs in", OUT)


if __name__ == "__main__":
    main()
