"""RoPlague: our own sound effects, made from scratch (oscillators, filtered noise, bells, a small reverb).
No samples from anyone else.

Writes build/plague_sfx/<name>.wav (one per effect) and build/plague_sfx/sprite.wav, every effect in
one file with SPRITE_GAP s of silence between them (one audio upload instead of seventy), plus
build/plague_sfx/sprite.json {name: [start, stop, length]}. tools/assets/upload_plague_sfx.py uploads
the sprite and writes src/shared/Assets/AudioPlague.luau.

    .venv/Scripts/python.exe tools/assets/make_plague_sfx.py
"""

import json
import os
import wave

import numpy as np
from scipy.signal import lfilter

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(REPO, "build", "plague_sfx")
SR = 44100
SPRITE_GAP = 0.5
RNG = np.random.default_rng(7)


# ---------------------------------------------------------------------------------------------
# building blocks
# ---------------------------------------------------------------------------------------------

def n_of(d):
    return max(1, int(round(SR * d)))


def tt(d):
    return np.arange(n_of(d)) / SR


def osc(freq, d, kind="sine", phase=0.0):
    """freq: a number or an array as long as the sound (a sweep)."""
    n = n_of(d)
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, dtype=np.float64)[:n]
    ph = phase + np.cumsum(2 * np.pi * f / SR)
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if kind == "square":
        return np.tanh(np.sin(ph) * 4)
    raise ValueError(kind)


def sweep(f0, f1, d, curve="exp"):
    k = np.linspace(0, 1, n_of(d))
    if curve == "exp":
        return f0 * (f1 / f0) ** k
    return f0 + (f1 - f0) * k


def noise(d):
    return RNG.uniform(-1, 1, n_of(d))


def env(d, a=0.004, decay=None, hold=0.0, curve=5.0):
    """Attack `a`, hold, then an exponential-ish fall to silence by the end."""
    n = n_of(d)
    x = np.arange(n) / SR
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    start = a + hold
    rest = np.clip((x - start) / max(1e-4, d - start), 0, 1)
    e = e * np.where(x > start, np.exp(-curve * rest) * (1 - rest), 1.0)
    return e


def adsr(d, a, dcy, s, r):
    n = n_of(d)
    x = np.arange(n) / SR
    e = np.interp(x, [0, a, a + dcy, max(a + dcy, d - r), d], [0, 1, s, s, 0])
    return e


def onepole_lp(x, fc):
    fc = np.full(len(x), float(fc)) if np.isscalar(fc) else np.asarray(fc)[: len(x)]
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def biquad(x, kind, f, q=0.707):
    w = 2 * np.pi * f / SR
    cw, sw = np.cos(w), np.sin(w)
    al = sw / (2 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    elif kind == "bp":
        b = [al, 0, -al]
    else:
        raise ValueError(kind)
    a = [1 + al, -2 * cw, 1 - al]
    return lfilter(np.array(b) / a[0], np.array(a) / a[0], x)


def bell(f, d, bright=1.0, decay=4.0):
    """An FM-free bell: a few inharmonic partials, the high ones dying first."""
    out = np.zeros(n_of(d))
    for mult, amp, dk in ((1.0, 1.0, 1.0), (2.0, 0.45 * bright, 1.6), (2.76, 0.35 * bright, 2.4),
                          (5.4, 0.18 * bright, 3.6), (8.93, 0.08 * bright, 5.0)):
        out += amp * osc(f * mult, d) * env(d, 0.002, curve=decay * dk)
    return out


def pluck(f, d, kind="tri", cut=3000):
    return onepole_lp(osc(f, d, kind), cut) * env(d, 0.002, curve=6)


def whoosh(d, f0=400, f1=2500, q=1.2):
    x = noise(d)
    out = np.zeros_like(x)
    fs = sweep(f0, f1, d)
    seg = 512
    for i in range(0, len(x), seg):
        out[i : i + seg] = biquad(x[max(0, i - 64) : i + seg], "bp", fs[i], q)[-len(x[i : i + seg]) :]
    return out * adsr(d, d * 0.45, d * 0.1, 0.8, d * 0.45)


def thud(d=0.35, f=70):
    body = osc(sweep(f * 2.2, f, d), d) * env(d, 0.002, curve=7)
    click = biquad(noise(d), "lp", 1800) * env(d, 0.001, curve=40)
    return body + 0.5 * click


def boom(d=3.0, f=48):
    sub = osc(sweep(f * 1.6, f * 0.6, d), d) * env(d, 0.004, curve=3.5)
    rumble = onepole_lp(noise(d), sweep(2400, 120, d)) * env(d, 0.003, curve=2.6) * 2.5
    crack = biquad(noise(d), "hp", 1500) * env(d, 0.001, curve=30) * 0.6
    return np.tanh((sub + rumble + crack) * 1.4)


def chord(freqs, d, kind="tri", spread=0.0, cut=2600, a=0.01):
    out = np.zeros(n_of(d))
    for i, f in enumerate(freqs):
        out += onepole_lp(osc(f * (1 + 0.002 * (i - len(freqs) / 2)), d, kind), cut)
    return out / len(freqs) * adsr(d, a, d * 0.3, 0.65, d * 0.55)


def seq(parts, d=None):
    """parts: [(offset s, signal)] mixed into one buffer."""
    end = max(off + len(sig) / SR for off, sig in parts)
    n = n_of(d if d is not None else end)
    out = np.zeros(n)
    for off, sig in parts:
        i = int(off * SR)
        j = min(n, i + len(sig))
        out[i:j] += sig[: j - i]
    return out


def reverb(x, mix=0.25, size=1.0, tail=1.2):
    """A small Schroeder room (4 combs, 2 allpasses) with `tail` s added for the decay."""
    x = np.concatenate([x, np.zeros(n_of(tail))])
    wet = np.zeros_like(x)
    for dl, g in ((1557, 0.80), (1617, 0.79), (1491, 0.81), (1422, 0.82)):
        D = int(dl * size)
        a = np.zeros(D + 1)
        a[0], a[D] = 1, -g
        wet += lfilter([1], a, x)
    wet /= 4
    for dl, g in ((225, 0.5), (556, 0.5)):
        D = int(dl * size)
        b = np.zeros(D + 1)
        b[0], b[D] = -g, 1
        a = np.zeros(D + 1)
        a[0], a[D] = 1, -g
        wet = lfilter(b, a, wet)
    wet = biquad(wet, "lp", 5000)
    return x * (1 - mix) + wet * mix


def note(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    base = names[name[0]]
    i = 1
    if len(name) > 2 and name[1] in "#b":
        base += 1 if name[1] == "#" else -1
        i = 2
    octave = int(name[i:])
    return 440.0 * 2 ** ((base + (octave - 4) * 12) / 12)


def arp(notes, step, each, kind="bell", **kw):
    parts = []
    for i, nm in enumerate(notes):
        f = note(nm) if isinstance(nm, str) else nm
        sig = bell(f, each, **kw) if kind == "bell" else pluck(f, each, kind)
        parts.append((i * step, sig))
    return seq(parts)


def finish(x, peak=0.8):
    """Fade the very end (no click), remove DC, normalise to `peak`."""
    x = x - np.mean(x)
    f = min(len(x), n_of(0.01))
    x[-f:] *= np.linspace(1, 0, f)
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


# ---------------------------------------------------------------------------------------------
# the sounds
# ---------------------------------------------------------------------------------------------

def wet_pop(f0=300, f1=1100, d=0.09):
    """A bubble's pop: a quick upward sine chirp with a soft attack."""
    return osc(sweep(f0, f1, d), d) * env(d, 0.003, curve=6)


def S():
    s = {}
    # interface
    s["ui_hover"] = (osc(2600, 0.045) * env(0.045, 0.002, curve=9), 0.18)
    s["ui_click"] = (osc(sweep(1700, 900, 0.07), 0.07) * env(0.07, 0.001, curve=9)
                     + 0.3 * biquad(noise(0.07), "bp", 3500, 2) * env(0.07, 0.001, curve=30), 0.45)
    s["ui_tab"] = (pluck(1300, 0.08, "tri", 4000) + 0.2 * biquad(noise(0.08), "bp", 2500, 3) * env(0.08, 0.001, curve=30), 0.4)
    s["ui_open"] = (reverb(seq([(0, whoosh(0.22, 500, 3000) * 0.5), (0.03, bell(note("E6"), 0.25) * 0.6),
                                (0.1, bell(note("B6"), 0.3) * 0.45)]), 0.2, tail=0.3), 0.5)
    s["ui_back"] = (seq([(0, osc(sweep(900, 520, 0.12), 0.12, "tri") * env(0.12, 0.002, curve=6)),
                         (0, whoosh(0.15, 2400, 600) * 0.3)]), 0.45)
    s["ui_error"] = (seq([(0, onepole_lp(osc(196, 0.09, "square"), 1400) * env(0.09, 0.003, curve=4)),
                          (0.11, onepole_lp(osc(165, 0.12, "square"), 1200) * env(0.12, 0.003, curve=4))]), 0.42)
    s["ui_confirm"] = (reverb(seq([(0, bell(note("C6"), 0.35)), (0.09, bell(note("G6"), 0.5) * 0.8)]), 0.22, tail=0.4), 0.5)
    s["ui_locked"] = (seq([(0, thud(0.12, 120) * 0.7), (0.0, osc(260, 0.1, "square") * env(0.1, 0.002, curve=8) * 0.3)]), 0.42)
    s["order_ack"] = (seq([(0, pluck(880, 0.07)), (0.08, pluck(1320, 0.09))]), 0.4)
    s["countdown_tick"] = (osc(1050, 0.08) * env(0.08, 0.001, curve=10), 0.4)
    for i, nm in enumerate(["A4", "B4", "C#5", "E5", "F#5"]):
        s["countdown_tick_%d" % (5 - i)] = (reverb(bell(note(nm), 0.6, 0.7), 0.15, tail=0.3), 0.5)
    s["countdown_gamestart"] = (reverb(seq([(0, chord([note(x) for x in ("A3", "E4", "A4", "C#5", "E5")], 1.6, "saw", cut=2200)),
                                            (0, whoosh(0.8, 300, 4000) * 0.4),
                                            (0, thud(0.5, 60))]), 0.3, tail=1.0), 0.75)
    s["queue_start"] = (reverb(seq([(0, whoosh(0.9, 300, 3500) * 0.6), (0.6, bell(note("E6"), 0.6))]), 0.25, tail=0.5), 0.5)
    s["spectate_switch"] = (whoosh(0.22, 1200, 3000), 0.35)
    # crates and reveals
    s["crate_drop"] = (seq([(0, osc(sweep(1800, 300, 0.9), 0.9, "tri") * adsr(0.9, 0.05, 0.3, 0.6, 0.2) * 0.3),
                            (0.9, thud(0.45, 60))]), 0.7)
    s["crate_land"] = (thud(0.5, 55), 0.75)
    rat = np.zeros(n_of(0.6))
    for k in range(9):
        b = biquad(noise(0.04), "bp", 2500 + 700 * RNG.random(), 4) * env(0.04, 0.001, curve=12)
        i = int((k * 0.06 + RNG.random() * 0.02) * SR)
        rat[i : i + len(b)] += b[: len(rat) - i]
    s["crate_rattle"] = (rat, 0.5)
    for rarity, notes in (("common", ["C5", "E5", "G5"]), ("rare", ["D5", "F#5", "A5", "D6"]),
                          ("epic", ["E5", "G#5", "B5", "E6", "G#6"]), ("legendary", ["F5", "A5", "C6", "F6", "A6", "C7"])):
        s["crate_preview_" + rarity] = (reverb(arp(notes, 0.12, 0.8, bright=0.8), 0.3, tail=0.8), 0.5)
        s["reveal_" + rarity] = (reverb(seq([(0, chord([note(n) for n in notes], 2.0, "tri", cut=3500)),
                                             (0, arp(notes + notes[-1:], 0.07, 0.9, bright=1.1) * 0.6),
                                             (0, whoosh(0.5, 400, 5000) * 0.3)]), 0.3, tail=1.0), 0.7)
    s["crate_open"] = (reverb(seq([(0, boom(0.8, 90) * 0.5), (0.02, arp(["C6", "E6", "G6", "C7"], 0.04, 0.7) * 0.6)]), 0.3, tail=0.6), 0.7)
    sh = np.zeros(n_of(3.0))
    for k in range(26):
        f = note(RNG.choice(["C6", "E6", "G6", "A6", "C7", "E7"]))
        b = bell(f, 0.6, 0.6) * (0.4 + 0.6 * RNG.random())
        i = int(RNG.random() * 2.4 * SR)
        sh[i : i + len(b)] += b[: len(sh) - i]
    s["crate_shimmer"] = (reverb(sh * adsr(3.0, 0.4, 0.5, 0.8, 1.2), 0.35, tail=0.6), 0.4)
    s["card_whoosh"] = (whoosh(0.4, 600, 3500), 0.45)
    s["card_flip"] = (seq([(0, biquad(noise(0.05), "bp", 1800, 1.5) * env(0.05, 0.001, curve=10)),
                           (0.06, biquad(noise(0.05), "bp", 2400, 1.5) * env(0.05, 0.001, curve=10))]), 0.45)
    # war mode (multiplayer keeps RoWorld's war)
    s["expand"] = (wet_pop(260, 700, 0.12), 0.4)
    s["expand_pop"] = (wet_pop(380, 980, 0.06), 0.35)
    s["attack_launch"] = (seq([(0, whoosh(0.9, 250, 1600) * 0.8), (0, thud(0.3, 80) * 0.4)]), 0.6)
    horn = onepole_lp(osc(110, 1.4, "saw") + 0.5 * osc(165, 1.4, "saw"), 900) * adsr(1.4, 0.12, 0.2, 0.8, 0.5)
    s["boat_launch"] = (reverb(horn, 0.25, tail=0.6), 0.55)
    s["warship"] = (reverb(onepole_lp(osc(73, 1.6, "saw") + 0.6 * osc(110, 1.6, "saw"), 700) * adsr(1.6, 0.15, 0.2, 0.85, 0.6), 0.3, tail=0.8), 0.6)
    s["build"] = (seq([(0, thud(0.2, 140)), (0.22, thud(0.25, 110))]), 0.55)
    s["nuke_launch"] = (onepole_lp(noise(2.6), sweep(300, 3000, 2.6)) * adsr(2.6, 0.3, 0.4, 0.9, 0.8) * 2, 0.6)
    siren = osc(440 + 220 * np.sin(2 * np.pi * 0.9 * tt(2.4)), 2.4, "tri") * adsr(2.4, 0.1, 0.1, 0.9, 0.3)
    s["nuke_alarm"] = (onepole_lp(siren, 2500), 0.5)
    s["nuke_explosion"] = (reverb(boom(4.0, 40), 0.3, size=1.3, tail=1.0), 0.9)
    s["sam_launch"] = (whoosh(0.7, 500, 4000), 0.5)
    s["sam_intercept"] = (reverb(boom(0.9, 120), 0.25, tail=0.5), 0.6)
    s["shell_fire"] = (seq([(0, boom(0.25, 160) * 0.8)]), 0.5)
    s["shell_hit"] = (thud(0.35, 90), 0.55)
    s["shell_splash"] = (biquad(noise(0.4), "bp", 1200, 0.8) * env(0.4, 0.005, curve=5), 0.45)
    sink = np.zeros(n_of(2.0))
    for k in range(18):
        b = wet_pop(200 + 300 * RNG.random(), 500 + 500 * RNG.random(), 0.07) * (1 - k / 18)
        i = int((k * 0.1 + RNG.random() * 0.05) * SR)
        sink[i : i + len(b)] += b[: len(sink) - i]
    s["ship_sink"] = (seq([(0, sink), (0, onepole_lp(noise(2.0), 400) * env(2.0, 0.1, curve=2) * 0.8)]), 0.5)
    s["under_attack"] = (seq([(0, onepole_lp(osc(660, 0.25, "square"), 2500) * adsr(0.25, 0.01, 0.05, 0.8, 0.05)),
                              (0.3, onepole_lp(osc(520, 0.25, "square"), 2500) * adsr(0.25, 0.01, 0.05, 0.8, 0.05)),
                              (0.6, onepole_lp(osc(660, 0.25, "square"), 2500) * adsr(0.25, 0.01, 0.05, 0.8, 0.05))]), 0.45)
    s["ally_request"] = (reverb(seq([(0, bell(note("G5"), 0.4)), (0.15, bell(note("D6"), 0.6))]), 0.25, tail=0.4), 0.5)
    s["alliance"] = (reverb(seq([(0, chord([note(n) for n in ("C4", "G4", "C5", "E5")], 2.0, "tri", cut=2500)),
                                 (0, arp(["C5", "E5", "G5", "C6"], 0.12, 1.0) * 0.5)]), 0.3, tail=1.0), 0.6)
    s["betrayal"] = (reverb(seq([(0, chord([note(n) for n in ("C4", "F#4", "B4")], 2.2, "saw", cut=1400)),
                                 (0, osc(sweep(note("E5"), note("A4"), 1.8), 1.8, "tri") * adsr(1.8, 0.05, 0.3, 0.6, 0.6) * 0.4)]), 0.3, tail=1.0), 0.6)
    s["conquer"] = (reverb(seq([(0, arp(["C5", "G5", "C6"], 0.1, 0.8)), (0.3, chord([note(n) for n in ("C4", "G4", "C5", "E5", "G5")], 1.6, "saw", cut=2600))]), 0.3, tail=1.0), 0.65)
    # match moments
    s["game_start"] = (reverb(seq([(0, chord([note(n) for n in ("A3", "E4", "A4")], 1.2, "saw", cut=1500, a=0.6) * 0.7),
                                   (1.0, chord([note(n) for n in ("D4", "A4", "D5", "F#5")], 1.6, "saw", cut=2800)),
                                   (1.0, thud(0.6, 55) * 0.8)]), 0.3, tail=1.2), 0.75)
    s["victory"] = (reverb(seq([(0, arp(["C5", "E5", "G5", "C6"], 0.14, 0.9)),
                                (0.6, chord([note(n) for n in ("C4", "G4", "C5", "E5", "G5")], 1.0, "saw", cut=3000)),
                                (1.5, chord([note(n) for n in ("F4", "C5", "F5", "A5")], 0.9, "saw", cut=3000)),
                                (2.3, chord([note(n) for n in ("G4", "D5", "G5", "B5")], 0.7, "saw", cut=3000)),
                                (2.9, chord([note(n) for n in ("C4", "G4", "C5", "E5", "G5", "C6")], 1.8, "saw", cut=3200)),
                                (2.9, arp(["C6", "E6", "G6", "C7"], 0.06, 1.2) * 0.5)]), 0.32, tail=1.5), 0.75)
    s["defeat"] = (reverb(seq([(0, chord([note(n) for n in ("A3", "E4", "A4", "C5")], 1.3, "tri", cut=1800)),
                               (1.1, chord([note(n) for n in ("F3", "C4", "F4", "A4")], 1.3, "tri", cut=1500)),
                               (2.2, chord([note(n) for n in ("E3", "B3", "E4", "G#4")], 1.6, "tri", cut=1200))]), 0.35, tail=1.5), 0.65)
    s["spawn_confirm"] = (reverb(seq([(0, wet_pop(150, 420, 0.25) * 0.9), (0.08, bell(note("E5"), 0.6, 0.6) * 0.6),
                                      (0.08, onepole_lp(noise(0.5), 600) * env(0.5, 0.02, curve=4) * 0.5)]), 0.3, tail=0.6), 0.6)
    s["eliminate"] = (reverb(seq([(0, thud(0.3, 90) * 0.7), (0.02, bell(note("G6"), 0.5) * 0.6)]), 0.2, tail=0.3), 0.55)
    s["star_tick"] = (bell(note("E7"), 0.08, 0.4, decay=8), 0.3)
    s["star_get"] = (reverb(arp(["E6", "G6", "B6", "E7"], 0.06, 0.6), 0.3, tail=0.6), 0.5)
    coins = np.zeros(n_of(1.2))
    for k in range(7):
        b = bell(note(["E6", "G6", "B6", "D7"][k % 4]) * (1 + 0.01 * k), 0.4, 0.9, decay=6) * (1 - k / 9)
        i = int(k * 0.09 * SR)
        coins[i : i + len(b)] += b[: len(coins) - i]
    s["buy_spend"] = (reverb(coins, 0.25, tail=0.4), 0.5)
    s["unlock"] = (reverb(seq([(0, whoosh(1.0, 300, 4500) * 0.4), (0.2, arp(["C5", "E5", "G5", "C6", "E6", "G6"], 0.09, 1.1)),
                               (0.75, chord([note(n) for n in ("C4", "G4", "C5", "E5")], 1.6, "tri", cut=3000) * 0.8)]), 0.32, tail=1.0), 0.65)
    # RoPlague's own
    s["plague_pop"] = (reverb(seq([(0, wet_pop(320, 1250, 0.08)), (0.03, bell(note("A6"), 0.35, 0.6) * 0.5),
                                   (0.0, biquad(noise(0.05), "bp", 3000, 2) * env(0.05, 0.001, curve=20) * 0.3)]), 0.18, tail=0.3), 0.55)
    s["plague_hotspot"] = (reverb(seq([(0, wet_pop(180, 700, 0.14)), (0.04, thud(0.3, 75) * 0.6),
                                       (0.06, arp(["E5", "B5", "E6"], 0.05, 0.5) * 0.5)]), 0.25, tail=0.5), 0.65)
    goo = onepole_lp(noise(0.7), sweep(300, 1400, 0.7)) * adsr(0.7, 0.05, 0.2, 0.6, 0.3)
    s["plague_infect"] = (reverb(seq([(0, goo * 1.6), (0.05, wet_pop(120, 300, 0.3) * 0.6),
                                      (0.12, bell(note("D5"), 0.7, 0.5) * 0.35)]), 0.3, tail=0.6), 0.55)
    s["plague_send"] = (seq([(0, whoosh(0.35, 300, 1400) * 0.7), (0.0, pluck(330, 0.12) * 0.5),
                             (0.08, pluck(440, 0.12) * 0.5)]), 0.45)
    s["plague_cure"] = (reverb(seq([(0, bell(note("C6"), 0.5)), (0.1, bell(note("A5"), 0.6) * 0.7)]), 0.3, tail=0.5), 0.45)
    s["plague_evolve"] = (reverb(seq([(0, wet_pop(200, 800, 0.15)), (0.05, arp(["A4", "E5", "A5", "C#6"], 0.06, 0.7)),
                                      (0.05, onepole_lp(noise(0.6), sweep(500, 3000, 0.6)) * adsr(0.6, 0.1, 0.1, 0.6, 0.3) * 0.4)]), 0.3, tail=0.6), 0.6)
    return s


def write_wav(path, x):
    pcm = np.clip(x * 32767, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    sounds = S()
    sprite_parts, index, cur = [], {}, 0.0
    for name in sorted(sounds):
        sig, peak = sounds[name]
        x = finish(np.asarray(sig, dtype=np.float64), peak)
        write_wav(os.path.join(OUT, name + ".wav"), x)
        length = len(x) / SR
        index[name] = [round(cur, 4), round(cur + length, 4), round(length, 4)]
        sprite_parts.append(x)
        sprite_parts.append(np.zeros(n_of(SPRITE_GAP)))
        cur += length + SPRITE_GAP
    sprite = np.concatenate(sprite_parts)
    write_wav(os.path.join(OUT, "sprite.wav"), sprite)
    json.dump(index, open(os.path.join(OUT, "sprite.json"), "w"), indent=1, sort_keys=True)
    print("%d sounds, sprite %.1f s" % (len(index), len(sprite) / SR))


if __name__ == "__main__":
    main()
