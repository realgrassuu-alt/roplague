"""Edits a full-quality recording of the in-game trailer (src/client/Trailer/Director.luau, F6) into the
finished trailer (2026-10-31).

    .venv/Scripts/python.exe tools/marketing/edit_recording.py "<recording.mp4>" [out.mp4]
        -> RoPlague_Artwork/trailer/RoPlague_Trailer_Final.mp4 (60 fps, 1080p)
    ... --music <track.wav> --music-at <s>   (music only: the clean track, <s> s into it at the first frame)

The game plays the trailer on the music's clock, so every cut is at a known time from the first frame
(MUSIC_FROM in the Director; one bar is 2.47 s). This edit adds what a recording of the screen cannot:
  - a virtual camera per shot: the close shots are zoomed in on the action (the walkers, the ship, the
    Evolve panel, the front), which also drops the bottom HUD and Roblox's corner buttons out of frame;
  - the call-to-action pill stays crisp and where it is: on a zoomed shot the crop is placed so the
    game's own pill is outside it, and the pill is pasted back from the original frame, unscaled;
  - wide shots push in slowly about the pill's corner (so it never moves);
  - a short zoom punch on every cut, a white hit on the last beat, a light grade, the audio faded out.
Nothing is drawn that the game did not draw: it only frames it.
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FF = os.path.join(REPO, ".venv", "Lib", "site-packages", "imageio_ffmpeg", "binaries", "ffmpeg-win-x86_64-v7.1.exe")
OUT_DIR = r"C:\Users\PC\Desktop\RoPlague_Artwork\trailer"

W, H = 1920, 1080
FPS = 60
B = 2.47
DUR = 29.0
# the Director's beats (s from the first frame) and the end card
CUTS = [0.0, B, B * 2.5, B * 4, B * 5.5, B * 7, B * 9, B * 10, DUR]
# the pill (Director Overlay.layout at 1920x1080): left 49, top 145, 80 tall; its right edge follows the text
PILL_X, PILL_Y0, PILL_Y1 = 49, 145, 225
PILL_R = 13
GOLD_X = 62

# Per shot: zoom from..to, and either a crop centre (cx, cy) or a pivot that stays put (the pill's corner).
# A zoomed shot keeps its crop between y 225 (the game's pill out of frame) and y 985 (the bottom HUD and
# Roblox's corner buttons out of frame too): 540 / z <= (985 - 225) / 2, i.e. z >= 1.42, centre y 605.
SHOTS = [
    # (2026-10-31 v3: the game frames each action closely itself, so the edit only pushes in gently about
    # the pill's corner; the zoomed crops below are kept for footage that needs them)
    dict(name="outbreak", z=(1.00, 1.06), pivot=(PILL_X, PILL_Y0), pill=False),
    dict(name="borders", z=(1.00, 1.06), pivot=(PILL_X, PILL_Y0), pill=False),
    dict(name="seas", z=(1.00, 1.05), pivot=(PILL_X, PILL_Y0), pill=False),
    dict(name="evolve", z=(1.00, 1.07), pivot=(PILL_X, PILL_Y0), pill=False),
    dict(name="battle", z=(1.00, 1.06), pivot=(PILL_X, PILL_Y0), pill=False),
    dict(name="cure", z=(1.00, 1.045), pivot=(PILL_X, PILL_Y0), pill=False),
    dict(name="infect", z=(1.045, 1.09), pivot=(PILL_X, PILL_Y0), pill=False, flash=True),
    dict(name="card", z=(1.00, 1.05), c=(960, 520), pill=False),
]
# the zoomed close-up variant (v2's): keeps the game's pill out of the crop and pastes it back
ZOOMED = {
    "outbreak": dict(z=(1.42, 1.52), c=(800, 605), pill=True),
    "borders": dict(z=(1.42, 1.48), c=(840, 605), pill=True),
    "seas": dict(z=(1.48, 1.58), c=(960, 610), pill=True),
    "battle": dict(z=(1.42, 1.48), c=(960, 605), pill=True),
}
# Roblox's own corner buttons (its logo and menu; no game can hide them): measured on a 1080p recording
CORNER = (0, 0, 132, 66)


def find_start(video: str) -> float:
    """The first frame after the black (the cover lifts on the music's first note)."""
    w, h = 192, 108
    p = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-i", video, "-t", "90", "-vf",
                        f"fps=120,scale={w}:{h}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True)
    a = np.frombuffer(p.stdout, np.uint8).reshape(-1, h, w, 3).reshape(-1, w * h * 3).mean(1)
    dark_run = 0
    for i, m in enumerate(a):
        if m < 3:
            dark_run += 1
        elif m > 20 and dark_run >= 120:  # after at least a second of black
            return i / 120.0
        else:
            dark_run = 0
    raise SystemExit("could not find the trailer's first frame")


def frame_at(video: str, t: float) -> np.ndarray:
    p = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-ss", f"{t:.3f}", "-i", video, "-frames:v", "1",
                        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True)
    return np.frombuffer(p.stdout, np.uint8).reshape(H, W, 3)


def pill_right(img: np.ndarray) -> int:
    """The pill's right edge: its white text, scanned rightwards from the left edge until a wide gap."""
    band = img[171:200, 70:1300].astype(int)
    white = ((band[..., 0] > 235) & (band[..., 1] > 235) & (band[..., 2] > 235)).any(0)
    last, gap = -1, 0
    for x, on in enumerate(white):
        if on:
            last, gap = x, 0
        elif last >= 0:
            gap += 1
            if gap > 40:
                break
    return (last + 70 + 30) if last >= 0 else 540


# (2026-10-31: the first patch mirrored the strip below the buttons up over the whole box, and left a
# visible box seam on busy shots. Now only the buttons' own pixels are replaced, by the smooth fill that
# meets the map around them on every side (a Laplace solve, its matrix factored once: the mask is fixed))
LOGO = (37.5, 33.5, 22.0)  # Roblox's logo disc: centre x, y, radius (1080p recording, measured)
MENU = (68.0, 12.0, 119.0, 55.0)  # its menu capsule: left, top, right, bottom
BTN_PAD = 4.0  # their soft edge and shadow
_fill = {}


def _corner_solver():
    if "solve" in _fill:
        return _fill
    from scipy.sparse import lil_matrix
    from scipy.sparse.linalg import splu

    x0, y0, x1, y1 = CORNER
    h, w = y1 - y0, x1 - x0
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    lx, ly, lr = LOGO
    mx0, my0, mx1, my1 = MENU
    mr = (my1 - my0) / 2
    cy = (my0 + my1) / 2
    sx = np.clip(xx, mx0 + mr, mx1 - mr)
    mask = (np.hypot(xx - lx, yy - ly) <= lr + BTN_PAD) | (np.hypot(xx - sx, yy - cy) <= mr + BTN_PAD)
    mask[0, :] = mask[-1, :] = False
    mask[:, 0] = mask[:, -1] = False
    idx = -np.ones((h, w), np.int64)
    pts = np.argwhere(mask)
    idx[mask] = np.arange(len(pts))
    a = lil_matrix((len(pts), len(pts)))
    nbrs = []  # per unknown: its known neighbours (row, col)
    for k, (r, c) in enumerate(pts):
        a[k, k] = 4.0
        known = []
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            rr, cc = r + dr, c + dc
            if mask[rr, cc]:
                a[k, idx[rr, cc]] = -1.0
            else:
                known.append((rr, cc))
        nbrs.append(known)
    # the right-hand side as one sparse sum: b = S @ (the box's pixels, flattened)
    s = lil_matrix((len(pts), h * w))
    for k, known in enumerate(nbrs):
        for rr, cc in known:
            s[k, rr * w + cc] += 1.0
    _fill.update(solve=splu(a.tocsc()), s=s.tocsr(), pts=pts, h=h, w=w)
    return _fill


def patch_corner(src: np.ndarray) -> np.ndarray:
    """Roblox's corner buttons out: their pixels filled smoothly from the map around them."""
    f = _corner_solver()
    x0, y0, x1, y1 = CORNER
    box = src[y0:y1, x0:x1].astype(np.float64).reshape(-1, 3)
    vals = f["solve"].solve(f["s"] @ box)
    out = src.copy()
    sub = out[y0:y1, x0:x1]
    pts = f["pts"]
    sub[pts[:, 0], pts[:, 1]] = np.clip(vals, 0, 255).astype(np.uint8)
    return out


_masks = {}


def pill_mask(w: int) -> Image.Image:
    m = _masks.get(w)
    if m is None:
        big = Image.new("L", (w * 4, (PILL_Y1 - PILL_Y0) * 4), 0)
        ImageDraw.Draw(big).rounded_rectangle([0, 0, w * 4 - 1, (PILL_Y1 - PILL_Y0) * 4 - 1], PILL_R * 4, fill=255)
        m = big.resize((w, PILL_Y1 - PILL_Y0), Image.LANCZOS)
        _masks[w] = m
    return m


def ease(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def opt(name: str):
    """The value after --name, or None."""
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return None


def main():
    # (--music <wav> --music-at <s>: the trailer's audio is that file alone, from <s> s into it, instead of
    # the recording's own, so no game sound effect reaches the trailer; 2026-10-31, the user's call)
    music = opt("--music")
    music_at = float(opt("--music-at") or 0.0)
    skip = {music, opt("--music-at")}
    args = [a for a in sys.argv[1:] if not a.startswith("--") and a not in skip]
    if "--zoom" in sys.argv:
        for s in SHOTS:
            if s["name"] in ZOOMED:
                s.pop("pivot", None)
                s.update(ZOOMED[s["name"]])
    video = args[0]
    out = args[1] if len(args) > 1 else os.path.join(OUT_DIR, "RoPlague_Trailer_Final.mp4")
    t0 = find_start(video)
    print(f"trailer starts at {t0:.3f} s")
    rights = []
    for i, s in enumerate(SHOTS):
        r = pill_right(frame_at(video, t0 + (CUTS[i] + CUTS[i + 1]) / 2)) if s["pill"] else 0
        rights.append(r)
        print(f"  shot {s['name']}: {CUTS[i]:.2f}-{CUTS[i + 1]:.2f} s, pill right {r}")

    reader = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-ss", f"{t0:.3f}", "-i", video,
                               "-t", f"{DUR:.3f}", "-vf", f"fps={FPS}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                              stdout=subprocess.PIPE)
    audio_in = ["-ss", f"{music_at:.4f}", "-t", f"{DUR:.3f}", "-i", music] if music else \
        ["-ss", f"{t0:.3f}", "-t", f"{DUR:.3f}", "-i", video]
    writer = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-y",
                               "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                               *audio_in,
                               "-map", "0:v", "-map", "1:a",
                               "-vf", "eq=saturation=1.2:contrast=1.05,unsharp=5:5:0.45",
                               "-af", f"afade=t=in:d=0.03,afade=t=out:st={DUR - 1.4:.2f}:d=1.4",
                               "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-pix_fmt", "yuv420p",
                               "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", out],
                              stdin=subprocess.PIPE)
    n = int(DUR * FPS)
    size = W * H * 3
    for k in range(n):
        buf = reader.stdout.read(size)
        if len(buf) < size:
            break
        src = patch_corner(np.frombuffer(buf, np.uint8).reshape(H, W, 3))
        t = k / FPS
        i = max(j for j in range(len(SHOTS)) if CUTS[j] <= t + 1e-6)
        s = SHOTS[i]
        a, b = CUTS[i], CUTS[i + 1]
        u = ease((t - a) / (b - a))
        z = s["z"][0] + (s["z"][1] - s["z"][0]) * u
        # the punch on the cut
        dt = t - a
        z *= 1.0 + 0.055 * np.exp(-dt / 0.09) if i > 0 else 1.0
        if "pivot" in s:
            px, py = s["pivot"]
            x0, y0 = px * (1 - 1 / z), py * (1 - 1 / z)
        else:
            cx, cy = s["c"]
            x0, y0 = cx - W / 2 / z, cy - H / 2 / z
        x0 = min(max(x0, 0.0), W - W / z)
        y0 = min(max(y0, 0.0), H - H / z)
        img = Image.fromarray(src).resize((W, H), Image.BICUBIC, box=(x0, y0, x0 + W / z, y0 + H / z))
        if s["pill"]:
            # (the slide-in: the game's pill comes in from 32 px to the left over 0.22 s, Quart out)
            off = int(round(-32 * (1 - min(dt / 0.22, 1.0)) ** 4))
            x1 = rights[i]
            left = max(0, PILL_X + off)
            w = x1 + off - left
            if w > 20:
                patch = Image.fromarray(src[PILL_Y0:PILL_Y1, left:left + w])
                img.paste(patch, (left, PILL_Y0), pill_mask(w))
        if s.get("flash") and dt < 0.22:
            f = (1 - dt / 0.22) ** 2 * 0.55
            arr = np.asarray(img).astype(np.float32)
            img = Image.fromarray((arr + (255 - arr) * f).astype(np.uint8))
        writer.stdin.write(img.tobytes())
        if k % 120 == 0:
            print(f"  {t:5.1f} s  shot {s['name']}")
    writer.stdin.close()
    writer.wait()
    reader.wait()
    print("wrote", out)


if __name__ == "__main__":
    main()
