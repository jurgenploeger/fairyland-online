#!/usr/bin/env python3
"""Synthesizes the game's sound effects into sound/*.wav (needs numpy).

Everything is made from the same ingredients as the music (sine partials with their own decay,
filtered noise, pitch sweeps), so the effects sit with the storybook soundtrack: bells and
plucks for rewards, soft thuds for hits, airy whooshes for movement. Nothing is sampled, so
there are no licences to track. Tweak a recipe below and rerun:

    python3 tools/make_sounds.py            # all sounds
    python3 tools/make_sounds.py coins hit  # just these
"""

import pathlib
import sys
import wave

import numpy as np

SR = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "sound"
rng = np.random.default_rng(3)


def t(seconds):
    return np.arange(int(seconds * SR)) / SR


def note(name):
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semis = names[name[0]] + (1 if "#" in name else -1 if name[1] == "b" else 0)
    octave = int(name[-1])
    return 440 * 2 ** ((12 * (octave + 1) + semis - 69) / 12)


def bell(freq, seconds=0.8, bright=1.0, decay=4.0):
    """A small bell or music-box tine: inharmonic partials that die away fast."""
    x = t(seconds)
    out = np.zeros_like(x)
    for ratio, amp, d in ((1, 1, 1), (2.76, 0.35 * bright, 2.2), (5.4, 0.18 * bright, 3.5), (8.93, 0.07 * bright, 5)):
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-decay * d * x)
    return out * np.minimum(1, x / 0.002)


def pluck(freq, seconds=0.5, decay=6.0):
    """A harp or pizzicato string."""
    x = t(seconds)
    out = sum(a * np.sin(2 * np.pi * freq * r * x) * np.exp(-decay * (1 + 0.6 * r) * x)
              for r, a in ((1, 1), (2, 0.45), (3, 0.2), (4, 0.08)))
    return out * np.minimum(1, x / 0.003)


def noise(seconds, lowpass=0.3, highpass=0.0):
    """Filtered white noise (one-pole filters; lowpass/highpass are 0..1 coefficients)."""
    n = rng.uniform(-1, 1, int(seconds * SR))
    if lowpass < 1:
        y = np.zeros_like(n)
        acc = 0.0
        for i, v in enumerate(n):
            acc += lowpass * (v - acc)
            y[i] = acc
        n = y
    if highpass > 0:
        y = np.zeros_like(n)
        acc = 0.0
        for i, v in enumerate(n):
            acc += highpass * (v - acc)
            y[i] = v - acc
        n = y
    return n


def env(x_len, attack=0.005, decay=0.2, seconds=None):
    x = np.arange(x_len) / SR
    return np.minimum(1, x / max(attack, 1e-4)) * np.exp(-x / decay)


def sweep(f0, f1, seconds, shape="exp"):
    """A sine gliding from f0 to f1."""
    x = t(seconds)
    k = x / seconds
    f = f0 * (f1 / f0) ** k if shape == "exp" else f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def at(parts, total=None):
    """Mixes (start_seconds, samples) pairs."""
    end = max(int(s * SR) + len(p) for s, p in parts)
    out = np.zeros(max(end, int((total or 0) * SR)))
    for s, p in parts:
        i = int(s * SR)
        out[i:i + len(p)] += p
    return out


def thud(freq=90, seconds=0.25, snap=0.5):
    """A soft hit: a falling sine body with a little noise snap on top."""
    body = sweep(freq * 2.2, freq, seconds) * env(int(seconds * SR), 0.001, 0.07)
    click = noise(0.04, 0.5) * env(int(0.04 * SR), 0.0005, 0.012) * snap
    return at([(0, body), (0, click)])


# ---------------------------------------------------------------- recipes

def tap():            # a soft wooden pop for buttons
    return sweep(900, 520, 0.05) * env(int(0.05 * SR), 0.001, 0.015) * 0.5

def close():          # a lower, softer pop
    return sweep(620, 360, 0.06) * env(int(0.06 * SR), 0.001, 0.018) * 0.45

def talk():           # a friendly two-note blip
    return at([(0, bell(note("A5"), 0.25, 0.3, 9)), (0.06, bell(note("E6"), 0.3, 0.3, 9) * 0.7)]) * 0.45

def step():           # a quiet footfall on grass
    return noise(0.06, 0.18) * env(int(0.06 * SR), 0.002, 0.018) * 0.5

def hit():
    return thud(95, 0.22, 0.6)

def crit():           # a heavier hit with a bright crack
    crack = noise(0.08, 0.9, 0.3) * env(int(0.08 * SR), 0.0005, 0.02)
    return at([(0, thud(75, 0.3, 0.8) * 1.2), (0, crack * 0.6), (0.01, bell(note("E6"), 0.3, 0.4, 8) * 0.25)])

def magic():          # a rising shimmer
    x = t(0.55)
    shimmer = sum(sweep(f, f * 2.2, 0.55) * (0.5 / (k + 1)) for k, f in enumerate((520, 780, 1170)))
    sparkle = at([(0.05 * i, bell(note(n), 0.35, 0.6, 7) * 0.25) for i, n in enumerate(("C6", "E6", "G6", "C7"))])
    return at([(0, shimmer * np.sin(np.pi * x / 0.55)), (0.05, sparkle)])

def heal():           # warm bells going up
    return at([(0.07 * i, bell(note(n), 0.6, 0.5, 3.5) * 0.4) for i, n in enumerate(("C5", "E5", "G5", "C6", "E6"))])

def potion():         # three little glugs
    glug = lambda f: sweep(f, f * 1.8, 0.07) * env(int(0.07 * SR), 0.004, 0.03)
    return at([(0, glug(300)), (0.1, glug(360)), (0.2, glug(420))]) * 0.6

def guard():          # a shield's ting
    return at([(0, bell(note("B5"), 0.5, 1.2, 5) * 0.5), (0, noise(0.03, 0.9, 0.4) * env(int(0.03 * SR), 0.0005, 0.008) * 0.3)])

def capture():        # a rising sparkle and a happy pop
    return at([(0, magic() * 0.7), (0.45, bell(note("G6"), 0.5, 0.8, 4) * 0.5), (0.5, bell(note("C7"), 0.6, 0.8, 4) * 0.45)])

def break_free():     # a boing downwards
    x = t(0.4)
    wobble = np.sin(2 * np.pi * np.cumsum(420 * 2 ** (-x * 2.5) * (1 + 0.06 * np.sin(2 * np.pi * 18 * x))) / SR)
    return wobble * env(len(x), 0.002, 0.15) * 0.5

def run():            # feet scampering off
    return at([(0.05 * i, step() * (1 - i * 0.12) * 3.5) for i in range(7)] + [(0, whoosh() * 0.8)])

def poof():           # a monster vanishing in a puff
    puff = noise(0.4, 0.12) * env(int(0.4 * SR), 0.01, 0.12)
    return at([(0, puff * 1.4), (0, sweep(500, 140, 0.25) * env(int(0.25 * SR), 0.002, 0.08) * 0.4)])

def faint():          # a friend going down
    return at([(0.12 * i, pluck(note(n), 0.5, 5) * 0.4) for i, n in enumerate(("E5", "C5", "A4"))])

def lose():           # the whole party fainting
    return at([(0.22 * i, bell(note(n), 0.9, 0.4, 2.5) * 0.35) for i, n in enumerate(("G4", "E4", "C4"))])

def level_up():       # a bright arpeggio and sparkles
    notes = ("C5", "E5", "G5", "C6", "E6", "G6")
    arp = at([(0.06 * i, pluck(note(n), 0.7, 4) * 0.35) for i, n in enumerate(notes)])
    return at([(0, arp), (0.36, bell(note("C7"), 1.0, 0.8, 2.2) * 0.35), (0.42, bell(note("G6"), 1.0, 0.6, 2.2) * 0.25)])

def coins():          # two coins clinking
    return at([(0, bell(note("B6"), 0.35, 1.2, 7) * 0.4), (0.08, bell(note("E7"), 0.4, 1.2, 6) * 0.35)])

def quest_accept():   # a hopeful two-note chime
    return at([(0, bell(note("G5"), 0.7, 0.6, 3) * 0.4), (0.12, bell(note("D6"), 0.9, 0.6, 3) * 0.4)])

def quest_done():     # a little music-box fanfare
    notes = (("C6", 0), ("E6", 0.1), ("G6", 0.2), ("C7", 0.34))
    return at([(s, bell(note(n), 1.0, 0.6, 2.6) * 0.38) for n, s in notes] + [(0.34, pluck(note("C5"), 0.8, 3) * 0.3)])

def chest():          # a creak, then a chime
    x = t(0.25)
    creak = np.sin(2 * np.pi * np.cumsum(180 + 60 * np.sin(2 * np.pi * 7 * x)) / SR) * env(len(x), 0.02, 0.1) * 0.25
    return at([(0, creak), (0.2, quest_accept())])

def hatch():          # a crack and a sparkle
    crack = noise(0.05, 0.8, 0.2) * env(int(0.05 * SR), 0.0005, 0.012)
    return at([(0, crack * 0.6), (0.12, crack * 0.5), (0.3, heal() * 0.8)])

def equip():          # a clink of armour
    return at([(0, noise(0.04, 0.9, 0.5) * env(int(0.04 * SR), 0.0005, 0.01) * 0.4), (0, bell(note("F#5"), 0.35, 1.3, 7) * 0.35)])

def learn():          # a quick sparkle
    return at([(0.045 * i, bell(note(n), 0.4, 0.5, 6) * 0.3) for i, n in enumerate(("E6", "G6", "B6", "E7"))])

def whoosh():         # travelling to a new place
    x = t(0.6)
    air = noise(0.6, 0.25, 0.05) * np.sin(np.pi * x / 0.6) ** 2
    return air * 0.6

def encounter():      # a monster jumps out: swoosh and a sting
    sting = at([(0, pluck(note("A4"), 0.4, 5) * 0.4), (0, pluck(note("D#5"), 0.4, 5) * 0.35)])
    return at([(0, whoosh() * 0.8), (0.28, sting)])


RECIPES = {name: fn for name, fn in globals().items() if callable(fn) and fn.__module__ == __name__
           and name not in {"t", "note", "bell", "pluck", "noise", "env", "sweep", "at", "thud", "write", "main"}}


def write(name, samples):
    peak = np.max(np.abs(samples)) or 1
    samples = samples / max(peak, 1) * 0.9 if peak > 0.9 else samples
    tail = int(0.01 * SR)
    if len(samples) > tail:
        samples[-tail:] *= np.linspace(1, 0, tail)
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def main():
    names = sys.argv[1:] or list(RECIPES)
    for name in names:
        write(name, RECIPES[name]())
    print(f"wrote {len(names)} sounds to {OUT}")


if __name__ == "__main__":
    main()
