"""RoPlague: the infected traveller as a RoWorld unit sprite (the ships' recipe, Assets/MapSprites
`units_one`): pixel art, body pixels WHITE and rim pixels GREY in one image, so one ImageColor3 tint
paints it in the plague's colour with a darker rim. Two frames (a stride and feet together), CELL px
each, in one row; CarrierLayer flips between them as it walks and mirrors them for a walk to the left.
Upscaled nearest-neighbour by UP so the upload stays sharp (the label is Pixelated anyway). No text.

    .venv/Scripts/python.exe tools/assets/make_pixel_walker.py
"""

import os

from PIL import Image

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(REPO, "build", "walker")
UP = 8

# '.' clear, 'o' rim (grey), 'w' body (white). Facing right, 16 x 16.
FRAMES = [
    [
        "................",
        "......oooo......",
        ".....owwwwo.....",
        ".....owwwwo.....",
        ".....owwwwo.....",
        "......oooo......",
        ".....oooooo.....",
        "....owwwwwwo....",
        "...owowwwwowo...",
        "...owoowwoowo...",
        "...oo.owwo.oo...",
        ".....owwwwo.....",
        "....owwoowwo....",
        "...owwo..owwo...",
        "...oooo..oooo...",
        "................",
    ],
    [
        "................",
        "......oooo......",
        ".....owwwwo.....",
        ".....owwwwo.....",
        ".....owwwwo.....",
        "......oooo......",
        ".....oooooo.....",
        "....owwwwwwo....",
        "...owowwwwowo...",
        "...owoowwoowo...",
        "...oo.owwo.oo...",
        ".....owwwwo.....",
        "....owwoowwo....",
        "....owwoowwo....",
        "....oooooooo....",
        "................",
    ],
]
CELL = len(FRAMES[0])
WHITE = (255, 255, 255, 255)
GREY = (92, 92, 92, 255)


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in FRAMES:
        assert len(f) == CELL and all(len(r) == CELL for r in f), "every frame is CELL x CELL"
    img = Image.new("RGBA", (CELL * len(FRAMES), CELL), (0, 0, 0, 0))
    for i, f in enumerate(FRAMES):
        for y, row in enumerate(f):
            for x, ch in enumerate(row):
                if ch == "w":
                    img.putpixel((i * CELL + x, y), WHITE)
                elif ch == "o":
                    img.putpixel((i * CELL + x, y), GREY)
    big = img.resize((img.width * UP, img.height * UP), Image.NEAREST)
    big.save(os.path.join(OUT, "walker_pixel.png"))
    # a preview: tinted red on the map's sea, at a few sizes
    prev = Image.new("RGBA", (big.width + 40, big.height + 60), (24, 44, 74, 255))
    tint = Image.new("RGBA", big.size, (228, 52, 60, 255))
    r, g, b, a = big.split()
    lum = r.point(lambda v: v)
    col = Image.merge("RGBA", (
        lum.point(lambda v: v * 228 // 255),
        lum.point(lambda v: v * 52 // 255),
        lum.point(lambda v: v * 60 // 255),
        a,
    ))
    prev.alpha_composite(col, (20, 20))
    small = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
    sr, sg, sb, sa = small.split()
    scol = Image.merge("RGBA", (
        sr.point(lambda v: v * 228 // 255),
        sr.point(lambda v: v * 52 // 255),
        sr.point(lambda v: v * 60 // 255),
        sa,
    ))
    prev.alpha_composite(scol, (20, big.height + 24))
    prev.save(os.path.join(OUT, "walker_pixel_preview.png"))
    del tint, g, b, lum
    print("wrote", os.path.join(OUT, "walker_pixel.png"), big.size)


if __name__ == "__main__":
    main()
