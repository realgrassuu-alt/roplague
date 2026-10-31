"""RoPlague trailer from REAL GAMEPLAY (2026-10-30): cuts recorded Studio Play footage into a trailer.

    .venv/Scripts/python.exe tools/marketing/make_trailer.py [main|long|both]
        -> RoPlague_Artwork/trailer/RoPlague_Trailer.mp4 (30 s) and RoPlague_Trailer_Long.mp4 (~70 s)

The footage is build/trailer_rec/*.mp4: the Studio Play viewport (1104x792) grabbed with ffmpeg gdigrab
while the game was played with Studio's virtual mouse (rec.sh in that folder). Nothing in a shot is
rendered by this script except the captions and the end card; the clips are only trimmed, sped up,
cropped to 16:9 (Roblox's own logo button cropped away) and upscaled.

Audio: our own synthesized SFX (build/plague_sfx) on the cuts, over a music bed synthesized here.
RoWorld's soundtrack is NOT used: its files may not be downloaded.
"""

import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy.io import wavfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art  # noqa: E402

import imageio_ffmpeg  # noqa: E402

FF = imageio_ffmpeg.get_ffmpeg_exe()
REC = os.path.join(art.REPO, "build", "trailer_rec")
SFX = os.path.join(art.REPO, "build", "plague_sfx")
OUT = os.path.join(art.ART, "trailer")
FPS = 30
W, H = 1920, 1080
SR = 44100

HUD = (0, 171, 1104, 621)  # keeps the bottom HUD bar
MID = (0, 100, 1104, 621)  # panels in the middle (Evolve, the end screens)
TOP = (0, 60, 1104, 621)  # keeps the top (race board, country card)
TOPL = (64, 40, 1040, 585)  # the very top (banners) without Roblox's logo button

# (clip, from, to, speed, crop, caption, sub, sfx [(t in output seconds, name, volume)])
MAIN = [
    dict(clip="race1", a=6.9, b=8.8, crop=TOP, sfx=[(0.0, "game_start", 0.55)]),
    dict(clip="solo1", a=53.6, b=56.6, crop=HUD, cap="PICK PATIENT ZERO", sfx=[(1.0, "plague_infect", 0.9)]),
    dict(clip="solo2", a=31.2, b=34.5, crop=HUD, cap="SPREAD ACROSS THE REAL WORLD", sfx=[(1.2, "plague_pop", 0.7), (2.4, "plague_pop", 0.6)]),
    dict(clip="solo2", a=5.0, b=19.0, speed=4.0, crop=MID, cap="EVOLVE YOUR PLAGUE", sfx=[(0.6, "plague_evolve", 0.7), (2.2, "plague_evolve", 0.6)]),
    dict(clip="solo3", a=216.0, b=238.0, speed=7.33, crop=HUD, cap="WIPE OUT HUMANITY"),
    dict(clip="solo3", a=240.6, b=242.6, crop=MID, sfx=[(0.0, "victory", 0.6)]),
    dict(clip="race1", a=305.0, b=308.0, crop=TOP, cap="PLAGUE RACE", sub="INVADE YOUR RIVALS", sfx=[(0.9, "attack_launch", 0.9)]),
    dict(clip="race1", a=309.0, b=329.4, speed=12.0, crop=TOP),
    dict(clip="race1", a=357.6, b=360.6, crop=TOPL, sfx=[(1.6, "conquer", 0.8)]),
    dict(clip="cure1", a=186.5, b=195.5, speed=3.0, crop=HUD, cap="1V1: PLAY THE CURE", sub="BUILD LABS AND HOSPITALS",
         sfx=[(1.2, "build", 0.8), (2.4, "build", 0.7)]),
    dict(end=True, clip="solo3", a=228.0, b=230.6),
]

LONG = [
    dict(clip="race1", a=6.0, b=10.0, crop=TOP, sfx=[(0.0, "game_start", 0.55)]),
    dict(clip="solo1", a=53.0, b=58.0, crop=HUD, cap="PICK PATIENT ZERO", sfx=[(1.6, "plague_infect", 0.9)]),
    dict(clip="solo2", a=29.0, b=37.0, crop=HUD, cap="SPREAD ACROSS THE REAL WORLD", sub="POP BUBBLES FOR DNA",
         sfx=[(3.4, "plague_pop", 0.7), (4.6, "plague_pop", 0.6), (6.0, "plague_pop", 0.6)]),
    dict(clip="solo2", a=4.0, b=20.0, speed=2.5, crop=MID, cap="EVOLVE YOUR PLAGUE",
         sfx=[(0.8, "plague_evolve", 0.7), (2.4, "plague_evolve", 0.6), (4.2, "plague_evolve", 0.6)]),
    dict(clip="solo3", a=152.0, b=200.0, speed=8.0, crop=HUD, cap="INFECT EVERY CONTINENT"),
    dict(clip="solo3", a=212.0, b=238.0, speed=5.2, crop=HUD, cap="WIPE OUT HUMANITY"),
    dict(clip="solo3", a=240.5, b=244.0, crop=MID, sfx=[(0.0, "victory", 0.6)]),
    dict(clip="race1", a=302.5, b=308.5, crop=TOP, cap="PLAGUE RACE", sub="EVERY PLAGUE ON ONE MAP", sfx=[(3.4, "attack_launch", 0.9)]),
    dict(clip="race1", a=309.0, b=333.0, speed=6.0, crop=TOP, cap="INVADE YOUR RIVALS"),
    dict(clip="race1", a=357.0, b=361.5, crop=TOPL, sfx=[(2.2, "conquer", 0.8)]),
    dict(clip="cure1", a=1.0, b=4.5, crop=HUD, cap="1V1: PLAGUE VS CURE", sfx=[(2.0, "ui_click", 0.8)]),
    dict(clip="cure1", a=136.0, b=160.0, speed=3.0, crop=HUD, cap="BUILD TO STOP THE PLAGUE", sub="LABS, HOSPITALS, CAMPS",
         sfx=[(1.4, "build", 0.8), (6.0, "build", 0.7)]),
    dict(clip="cure1", a=186.0, b=198.0, speed=2.0, crop=HUD, sfx=[(2.0, "build", 0.8), (4.5, "build", 0.7)]),
    dict(clip="cure1", a=289.6, b=293.6, crop=MID, sfx=[(0.0, "victory", 0.6)]),
    dict(end=True, clip="solo3", a=228.0, b=232.0),
]


# ---------------------------------------------------------------------------------------------
# Captions
# ---------------------------------------------------------------------------------------------

def _layer(draw):
    """Renders with `draw(im)` on a big transparent canvas, cropped to what was drawn."""
    im = Image.new("RGBA", (W, 520), (0, 0, 0, 0))
    draw(im)
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def caption_layer(cap, sub):
    def draw(im):
        art.gradient_text(im, (W // 2, 140), cap, 118, top=(255, 255, 255), bottom=(255, 210, 120))
        if sub:
            art.pill(im, (W // 2, 262), sub, 46, fill=art.PLAGUE["crimson"])
    return _layer(draw)


def pop(t, dur=0.32):
    """0 -> 1 with an overshoot (a pop-in), t in seconds."""
    if t <= 0:
        return 0.0
    x = min(1.0, t / dur)
    return 1 + 2.4 * (x - 1) ** 3 + 1.4 * (x - 1) ** 2


def paste_scaled(frame, layer, k, alpha, cx, top):
    if k <= 0.02 or alpha <= 0.01:
        return
    w, h = max(1, int(layer.width * k)), max(1, int(layer.height * k))
    lay = layer.resize((w, h), Image.BILINEAR) if (w, h) != layer.size else layer
    if alpha < 1:
        a = np.asarray(lay).copy()
        a[..., 3] = (a[..., 3] * alpha).astype(np.uint8)
        lay = Image.fromarray(a, "RGBA")
    frame.alpha_composite(lay, (int(cx - w / 2), int(top + (layer.height - h) / 2)))


# ---------------------------------------------------------------------------------------------
# Footage
# ---------------------------------------------------------------------------------------------

def frames_of(seg):
    """The segment's frames (1920x1080 RGB uint8), decoded, sped up, cropped and upscaled by ffmpeg."""
    x, y, w, h = seg.get("crop", HUD)
    speed = seg.get("speed", 1.0)
    n = int(round((seg["b"] - seg["a"]) / speed * FPS))
    vf = "setpts=PTS/{s},fps={f},crop={w}:{h}:{x}:{y},scale={W}:{H}:flags=lanczos,unsharp=5:5:0.55:5:5:0".format(
        s=speed, f=FPS, w=w, h=h, x=x, y=y, W=W, H=H)
    p = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-ss", "%.3f" % seg["a"], "-i",
                          os.path.join(REC, seg["clip"] + ".mp4"), "-t", "%.3f" % (seg["b"] - seg["a"]), "-vf", vf,
                          "-frames:v", str(n),
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    size = W * H * 3
    out = []
    while len(out) < n:
        buf = p.stdout.read(size)
        if len(buf) < size:
            break
        out.append(np.frombuffer(buf, np.uint8).reshape(H, W, 3))
    p.stdout.close()
    p.wait()
    while len(out) < n:  # (a short read: hold the last frame)
        out.append(out[-1])
    return out


def end_card(frames):
    """The last shot: the dying world, dimmed and blurred, under the logo and the modes."""
    logo = _layer(lambda im: art.gradient_text(im, (W // 2, 200), "ROPLAGUE", 250, top=(255, 255, 255), bottom=(255, 196, 96)))
    tag = _layer(lambda im: art.pill(im, (W // 2, 200), "INFECT THE REAL WORLD", 54, fill=art.PLAGUE["crimson"]))
    modes = _layer(lambda im: art.text(im, (W // 2, 200), "SOLO  ·  1V1  ·  PLAGUE RACE  ·  TEAM PLAGUE", 46))
    play = _layer(lambda im: art.pill(im, (W // 2, 200), "PLAY NOW", 80, fill=art.PLAGUE["toxic"]))
    out = []
    for i, f in enumerate(frames):
        t = i / FPS
        bg = Image.fromarray(f).filter(ImageFilter.GaussianBlur(6 * min(1.0, t / 0.4)))
        arr = np.asarray(bg, np.float32) * (1.0 - 0.5 * min(1.0, t / 0.4))
        im = Image.fromarray(arr.astype(np.uint8)).convert("RGBA")
        paste_scaled(im, logo, pop(t - 0.1, 0.4), min(1.0, (t - 0.1) / 0.15), W // 2, 300)
        paste_scaled(im, tag, pop(t - 0.45), min(1.0, (t - 0.45) / 0.15), W // 2, 560)
        paste_scaled(im, modes, pop(t - 0.7), min(1.0, (t - 0.7) / 0.15), W // 2, 680)
        paste_scaled(im, play, pop(t - 1.0, 0.4), min(1.0, (t - 1.0) / 0.15), W // 2, 790)
        out.append(np.asarray(im.convert("RGB")))
    return out


# ---------------------------------------------------------------------------------------------
# Audio: a music bed of our own, and our SFX
# ---------------------------------------------------------------------------------------------

def _env(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-t / d)


def _note(f):
    return 440.0 * 2 ** ((f - 69) / 12)


def music(total, drop):
    """A driving 124 BPM bed in A minor (kick, clap, hats, bass, arp); quiet pad before `drop`."""
    n = int(total * SR) + SR
    mix = np.zeros(n, np.float32)
    beat = 60.0 / 124
    rng = np.random.default_rng(7)
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]  # Am F C G
    bar = beat * 4

    def add(sig, at):
        i = int(at * SR)
        if i >= n:
            return
        j = min(n, i + len(sig))
        mix[i:j] += sig[: j - i]

    # pad (under everything, alone before the drop)
    t = 0.0
    while t < total:
        c = chords[int(t / bar) % 4]
        m = int(bar * SR)
        tt = np.arange(m) / SR
        pad = sum(np.sin(2 * np.pi * _note(k) * tt) + 0.5 * np.sin(2 * np.pi * _note(k) * 2.003 * tt) for k in c)
        pad *= np.minimum(1, tt / 0.3) * np.minimum(1, (bar - tt) / 0.3) * 0.035
        add(pad.astype(np.float32), t)
        t += bar
    # the beat, from the drop
    k = 0
    t = drop
    kick_n = int(0.32 * SR)
    tk = np.arange(kick_n) / SR
    kick = np.sin(2 * np.pi * (45 * tk + (120 - 45) * 0.04 * (1 - np.exp(-tk / 0.04)))) * np.exp(-tk / 0.13) * 0.85
    clap = rng.standard_normal(int(0.18 * SR)) * _env(int(0.18 * SR), 0.002, 0.05) * 0.28
    hat = np.diff(rng.standard_normal(int(0.05 * SR) + 1)) * _env(int(0.05 * SR), 0.001, 0.012) * 0.10
    while t < total - 0.4:
        add(kick.astype(np.float32), t)
        if k % 2 == 1:
            add(clap.astype(np.float32), t)
        add(hat.astype(np.float32), t + beat / 2)
        # bass: eighths on the chord's root
        c = chords[int((t - drop) / bar) % 4]
        for e in range(2):
            m = int(beat / 2 * SR)
            tt = np.arange(m) / SR
            f = _note(c[0] - 24)
            b = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * 2 * f * tt) + 0.15 * np.sign(np.sin(2 * np.pi * f * tt)))
            add((b * _env(m, 0.004, 0.16) * 0.22).astype(np.float32), t + e * beat / 2)
        # arp: sixteenths over the chord
        for s in range(4):
            m = int(beat / 4 * SR)
            tt = np.arange(m) / SR
            f = _note(c[(k * 4 + s) % 3] + 12)
            a = np.sign(np.sin(2 * np.pi * f * tt)) * 0.5 + np.sin(2 * np.pi * f * tt) * 0.5
            add((a * _env(m, 0.002, 0.05) * 0.045).astype(np.float32), t + s * beat / 4)
        t += beat
        k += 1
    # a riser into the drop
    rn = int(min(drop, 1.6) * SR)
    if rn > 0:
        tt = np.arange(rn) / SR
        r = rng.standard_normal(rn) * (tt / tt[-1]) ** 2 * 0.12
        add(r.astype(np.float32), drop - rn / SR)
    return mix


def sfx(name):
    sr, a = wavfile.read(os.path.join(SFX, name + ".wav"))
    a = a.astype(np.float32) / 32768.0
    if a.ndim == 2:
        a = a.mean(1)
    return a


def soundtrack(cuts, total, path):
    drop = cuts[1][0] if len(cuts) > 1 else 0.0
    mix = music(total, drop) * 0.9
    whoosh = sfx("card_whoosh")
    for start, seg in cuts:
        if seg.get("cap"):
            i = int(start * SR)
            mix[i:i + len(whoosh)] += whoosh[: len(mix) - i] * 0.5
        for t, name, vol in seg.get("sfx", []):
            s = sfx(name)
            i = int((start + t) * SR)
            if i < len(mix):
                j = min(len(mix), i + len(s))
                mix[i:j] += s[: j - i] * vol
    mix = mix[: int(total * SR)]
    # fade out over the last second, then normalise to -1 dBFS
    fo = int(1.0 * SR)
    mix[-fo:] *= np.linspace(1, 0, fo)
    mix *= 0.89 / max(1e-6, np.abs(mix).max())
    st = np.stack([mix, mix], 1)
    wavfile.write(path, SR, (st * 32767).astype(np.int16))


# ---------------------------------------------------------------------------------------------

def build(segs, name):
    os.makedirs(OUT, exist_ok=True)
    silent = os.path.join(REC, "_" + name + "_v.mp4")
    enc = subprocess.Popen([FF, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                            "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow",
                            "-crf", "17", "-pix_fmt", "yuv420p", silent], stdin=subprocess.PIPE)
    cuts = []
    t_out = 0.0
    nseg = len(segs)
    for si, seg in enumerate(segs):
        fr = frames_of(seg)
        if seg.get("end"):
            fr = end_card(fr)
        layer = caption_layer(seg["cap"], seg.get("sub")) if seg.get("cap") else None
        dur = len(fr) / FPS
        cuts.append((t_out, seg))
        for i, f in enumerate(fr):
            t = i / FPS
            if layer is not None:
                im = Image.fromarray(f).convert("RGBA")
                a = min(1.0, t / 0.12) * min(1.0, max(0.0, (dur - t) / 0.18))
                paste_scaled(im, layer, pop(t), a, W // 2, 40)
                f = np.asarray(im.convert("RGB"))
            g = None
            if si > 0 and i < 3:  # a quick white flash on every cut
                g = (0.45, 0.22, 0.08)[i]
            if si == 0 and t < 0.5:  # fade in from black
                f = (f.astype(np.float32) * (t / 0.5)).astype(np.uint8)
            if si == nseg - 1 and dur - t < 0.6:  # fade out to black
                f = (f.astype(np.float32) * max(0.0, (dur - t) / 0.6)).astype(np.uint8)
            if g is not None:
                f = (f.astype(np.float32) * (1 - g) + 255 * g).astype(np.uint8)
            enc.stdin.write(np.ascontiguousarray(f).tobytes())
        t_out += dur
        print("%s: shot %d/%d (%.2f s) at %.2f s" % (name, si + 1, nseg, dur, t_out), flush=True)
    enc.stdin.close()
    enc.wait()
    wav = os.path.join(REC, "_" + name + ".wav")
    soundtrack(cuts, t_out, wav)
    out = os.path.join(OUT, name + ".mp4")
    subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", silent, "-i", wav, "-c:v", "copy", "-c:a", "aac",
                    "-b:a", "192k", "-shortest", "-movflags", "+faststart", out], check=True)
    os.remove(silent)
    os.remove(wav)
    print("wrote", out, "%.2f s" % t_out)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "both"
    if which in ("main", "both"):
        build(MAIN, "RoPlague_Trailer")
    if which in ("long", "both"):
        build(LONG, "RoPlague_Trailer_Long")


if __name__ == "__main__":
    main()
