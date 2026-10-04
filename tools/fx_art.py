#!/usr/bin/env python3
"""Pixel art for the elemental spell effects, drawn in code like tools/item_art.py (free):
writes art/sprites/fx_<name>.png, which Fairyland/Battle/ElementEffects.swift animates.

    python3 tools/fx_art.py                  # every sprite
    python3 tools/fx_art.py --sheet out.png  # also a 4x contact sheet to look at

Stone: rock spikes in four cuts (tall, mid, low, thin) with three faces and soil at the foot, rock
chunks, a dust puff that billows and thins (4 frames), the ground cracking open. Fire: a fireball
that flickers (4 frames), a blast that blooms and burns out into smoke (6 frames), a flame tongue
(4 frames), a scorch mark. Wood: leaves in three colours, a petal, a wind streak. Water: a droplet,
an orb that wobbles (2 frames), a splash crown (4 frames), a bubble. Everything has a dark outline
except light, smoke, wind and the marks on the ground.
"""

import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from item_art import OUTLINE, SPRITES, encode_png, hexc  # noqa: E402

STONE = [hexc("2e2630"), hexc("564a50"), hexc("7c6e6a"), hexc("a39484"), hexc("c8b8a0"), hexc("efe4cc")]
# deepest shadow, shadow face, shadow face lit, lit face, lit face bright, highlight
DIRT = [hexc("2a1c14"), hexc("5a3c24"), hexc("86603a"), hexc("ad8456")]   # crack, dark, mid, lit
DUST = [hexc("9a8668"), hexc("bba886"), hexc("d8c8a6"), hexc("f0e6cc")]
FIRE = [hexc("8a1a0a"), hexc("d03a14"), hexc("ff7e1c"), hexc("ffc93c"), hexc("fff4c0")]   # deep red … white-hot
SMOKE = [hexc("4a4048"), hexc("6e6470"), hexc("9a909a"), hexc("c4bcc4")]
LEAF = [hexc("1e5a24"), hexc("3e9a34"), hexc("7ed04a"), hexc("c8f080")]
LEAF_LIGHT = [hexc("2e7a2a"), hexc("5cb83c"), hexc("a6e65e"), hexc("e4ffb0")]
LEAF_GOLD = [hexc("6a6a14"), hexc("a8b42a"), hexc("dce85a"), hexc("fbffa8")]
PETAL = [hexc("c0507a"), hexc("f08aac"), hexc("ffd4e4")]
WATER = [hexc("0e3c74"), hexc("1c6ab0"), hexc("48a8f0"), hexc("a8dcff"), hexc("ffffff")]
FIRE_LINE = hexc("5a1006")
LEAF_LINE = hexc("143a18")
WATER_LINE = hexc("0a2a54")


class Canvas:
    """A width × height pixel canvas (item_art's Canvas is square)."""

    def __init__(self, width, height):
        self.w, self.h = width, height
        self.px = [[None] * width for _ in range(height)]

    def set(self, x, y, color):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def disc(self, cx, cy, r, color, ry=None):
        ry = ry or r
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if ((x - cx) / r) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    self.set(x, y, color)

    def poly(self, points, color):
        ys = [p[1] for p in points]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]):
                if (y0 <= y + 0.5 < y1) or (y1 <= y + 0.5 < y0):
                    xs.append(x0 + (y + 0.5 - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(int(math.ceil(a - 0.5)), int(math.floor(b - 0.5)) + 1):
                    self.set(x, y, color)

    def line(self, x0, y0, x1, y1, color):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
        for i in range(steps + 1):
            t = i / steps
            self.set(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, color)

    def recolour(self, test, color):
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None and test(x, y, self.px[y][x]):
                    self.px[y][x] = color

    def outline(self, color=OUTLINE):
        grow = [(x, y) for y in range(self.h) for x in range(self.w)
                if self.px[y][x] is None and any(self.get(x + dx, y + dy) not in (None, color)
                                                 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        for x, y in grow:
            self.px[y][x] = color

    def png(self, scale=1):
        rows = []
        for y in range(self.h * scale):
            row = bytearray([0])
            for x in range(self.w * scale):
                row += bytes(self.px[y // scale][x // scale] or (0, 0, 0, 0))
            rows.append(bytes(row))
        return encode_png(self.w * scale, self.h * scale, b"".join(rows))


# ---------------------------------------------------------------- stone

def spike(width, height, lean, seed):
    """A rock spike: a sharp shard cut in three faces (bright on the left, plain in the middle, in
    shadow on the right) with bright edges between them, a chip out of one side, flecks and nicks,
    and clods of soil heaved up round its foot. Its foot is the canvas's third row from the
    bottom (ElementEffects anchors it there)."""
    rnd = random.Random(seed)
    w, h = width + 6, height + 3
    c = Canvas(w, h)
    base_y = height
    cx = w / 2
    tip_x = cx + lean
    left_foot, right_foot = cx - width / 2, cx + width / 2

    def along(t, foot):
        return (tip_x + (foot - tip_x) * t, 0.5 + (base_y - 0.5) * t)

    chip, step = rnd.uniform(0.35, 0.5), rnd.uniform(0.6, 0.75)
    notch_x, notch_y = along(chip, right_foot)
    bump_x, bump_y = along(step, left_foot)
    c.poly([(tip_x, 0), along(chip - 0.07, right_foot), (notch_x - 1.5, notch_y), along(chip + 0.09, right_foot),
            (right_foot, base_y + 0.5), (left_foot, base_y + 0.5),
            along(step + 0.05, left_foot), (bump_x - 1, bump_y), along(step - 0.05, left_foot)], STONE[3])
    # Two edges run from the tip to the foot and split it into faces.
    edge_a = left_foot + width * rnd.uniform(0.22, 0.3)
    edge_b = left_foot + width * rnd.uniform(0.48, 0.55)
    for y in range(h):
        row = [x for x in range(w) if c.px[y][x] is not None]
        if not row:
            continue
        t = max(0.0, (y - 0.5) / (base_y - 0.5))
        a = int(math.floor(tip_x + (edge_a - tip_x) * t + 0.5))
        b = int(math.floor(tip_x + (edge_b - tip_x) * t + 0.5))
        for x in row:
            if x < a:
                c.px[y][x] = STONE[4]
            elif x == a:
                c.px[y][x] = STONE[5]
            elif x < b:
                c.px[y][x] = STONE[3]
            elif x == b:
                c.px[y][x] = STONE[2]
            else:
                c.px[y][x] = STONE[1]
        if row[-1] > b + 1:
            c.px[y][row[-1]] = STONE[0]
        if t > 0.2 and row[0] < a - 1:
            c.px[y][row[0]] = STONE[5] if t < 0.6 else STONE[4]
    # Nicks in the shadow, flecks on the bright face.
    for _ in range(max(3, height // 7)):
        y = int(rnd.uniform(height * 0.25, height * 0.95))
        row = [x for x in range(w) if c.px[y][x] is not None]
        if len(row) < 4:
            continue
        x = rnd.choice(row[len(row) // 2:-1])
        c.px[y][x] = STONE[0]
        if c.get(x + 1, y + 1) not in (None,):
            c.px[y + 1][x + 1] = STONE[0]
    for _ in range(max(2, height // 10)):
        y = int(rnd.uniform(height * 0.3, height * 0.9))
        row = [x for x in range(w) if c.px[y][x] is not None]
        if len(row) >= 4:
            c.px[y][row[1]] = STONE[3]
    c.outline()
    # Clods of soil heaved up around its foot.
    for _ in range(4 + width // 4):
        x = rnd.uniform(left_foot - 1.5, right_foot + 1.5)
        r = rnd.uniform(1.0, 1.9)
        c.disc(x, base_y, r, DIRT[2], r * 0.7)
        c.set(x - 0.4, base_y - r * 0.5, DIRT[3])
    c.outline()
    return c


def rock(size, seed):
    """A chunk of rock flying off: an irregular, faceted lump, lit top left."""
    rnd = random.Random(seed)
    c = Canvas(size + 3, size + 3)
    cx = cy = (size + 3) / 2
    pts = []
    for i in range(6):
        a = i / 6 * math.tau + rnd.uniform(-0.3, 0.3)
        r = size / 2 * rnd.uniform(0.75, 1.05)
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.85))
    c.poly(pts, STONE[3])
    c.recolour(lambda x, y, _: (x - cx) * 0.6 + (y - cy) > size * 0.1, STONE[1])
    c.recolour(lambda x, y, _: (x - cx) + (y - cy) < -size * 0.3, STONE[4])
    c.set(cx - size * 0.2, cy - size * 0.28, STONE[5])
    c.outline()
    return c


def dust(frame):
    """A puff of dust: billows out (0-1), spreads and pales (2), breaks into wisps (3)."""
    c = Canvas(30, 20)
    lobes = [(-7, 1, 4.2), (-2, -1.5, 5), (4, -0.5, 4.6), (8.5, 1.5, 3.4), (0, 2.5, 4), (-11, 3, 2.6), (12, 3.2, 2.3)]
    grow = (0.42, 0.62, 0.78, 0.86)[frame]
    shade, body, light, shine = (DUST[0], DUST[1], DUST[2], DUST[3]) if frame < 2 else (DUST[1], DUST[2], DUST[3], DUST[3])
    kept = [lobe for i, lobe in enumerate(lobes) if not (frame == 3 and i in (1, 4))]
    spots = [(15 + dx * grow * (1.2 if frame == 3 else 1), 13 + dy * grow - frame, r * grow * (0.72 if frame == 3 else 1))
             for dx, dy, r in kept]
    for x, y, r in spots:
        c.disc(x + 0.5, y + 0.8, r, shade)
    for x, y, r in spots:
        c.disc(x, y, r, body)
    for x, y, r in spots:
        c.disc(x - r * 0.28, y - r * 0.35, r * 0.55, light)
        c.set(x - r * 0.4, y - r * 0.55, shine)
    c.outline(hexc("7a6850"))
    return c


def crack():
    """The ground split open, seen at a slant: a dark hole with its far wall showing and a rim of
    heaved-up earth, cracks running out from it (wide near it, thin at the ends, some forking)
    with lit near lips, loose pebbles, and a shadow that darkens whatever ground it lands on."""
    c = Canvas(44, 16)
    rnd = random.Random(3)
    cx, cy = 22, 8
    c.disc(cx, cy, 20, hexc("28180c", 70), 7)

    def run(x, y, a, length, wide_until):
        for step in range(int(length)):
            a += rnd.uniform(-0.4, 0.4)
            x, y = x + math.cos(a), y + math.sin(a) * 0.45
            wide = step < wide_until
            c.set(x, y, DIRT[0])
            if wide:
                c.set(x, y + 1, DIRT[0])
            if abs(math.sin(a)) < 0.7:
                c.set(x, y + (2 if wide else 1), DIRT[3])
            if step == int(length * 0.5) and length > 13:
                run(x, y, a + rnd.choice((-0.9, 0.9)), length * 0.4, 0)

    for i in range(7):
        length = rnd.uniform(11, 19)
        run(cx, cy, i / 7 * math.tau + rnd.uniform(-0.25, 0.25), length, length * 0.45)
    c.disc(cx, cy, 6.2, DIRT[2], 3.2)
    c.disc(cx, cy + 0.3, 4.6, DIRT[0], 2.2)
    for x in range(c.w):
        hole = [y for y in range(c.h) if c.px[y][x] == DIRT[0] and abs(x - cx) < 5 and abs(y - cy) < 3]
        if hole:
            c.px[hole[0]][x] = DIRT[1]
            below = hole[-1] + 1
            if c.get(x, below) == DIRT[2]:
                c.px[below][x] = DIRT[3]
    for _ in range(7):
        x, y = cx + rnd.uniform(-18, 18), cy + rnd.uniform(-5, 5)
        if abs(x - cx) > 6:
            c.set(x, y, DIRT[3])
            c.set(x + 1, y, DIRT[2])
            c.set(x, y + 1, DIRT[1])
    return c


# ---------------------------------------------------------------- fire

def fireball(frame):
    """A fireball flying right: a white-hot head and a flickering tail of flame tongues."""
    c = Canvas(30, 18)
    rnd = random.Random(11 + frame)
    head = (21, 9)
    # Tail tongues, each a little different per frame.
    for i in range(4):
        y = 9 + (i - 1.5) * 2.6 + rnd.uniform(-0.8, 0.8)
        length = 13 + rnd.uniform(-2, 3) - abs(i - 1.5) * 2
        c.poly([(head[0] - 2, y - 2.6), (head[0] - length, y + rnd.uniform(-1, 1)), (head[0] - 2, y + 2.6)], FIRE[1])
    c.disc(head[0], head[1], 6.2, FIRE[1])
    for i in range(3):
        y = 9 + (i - 1) * 2.2 + rnd.uniform(-0.6, 0.6)
        length = 9 + rnd.uniform(-1.5, 2) - abs(i - 1) * 2
        c.poly([(head[0] - 1, y - 2), (head[0] - length, y + rnd.uniform(-0.7, 0.7)), (head[0] - 1, y + 2)], FIRE[2])
    c.disc(head[0], head[1], 4.8, FIRE[2])
    c.poly([(head[0] + 1, 6.5), (head[0] - 7, 9 + rnd.uniform(-0.6, 0.6)), (head[0] + 1, 11.5)], FIRE[3])
    c.disc(head[0] + 0.5, head[1], 3.4, FIRE[3])
    c.disc(head[0] + 1.2, head[1] - 0.4, 1.9, FIRE[4])
    c.outline(FIRE_LINE)
    return c


def blast(frame):
    """An explosion: a white flash (0), a bloom of fire with jagged tongues (1-2), a ring of
    flame breaking up (3-4), smoke drifting off (5)."""
    c = Canvas(48, 48)
    rnd = random.Random(21 + frame)
    cx = cy = 24
    if frame == 0:
        c.disc(cx, cy, 8, FIRE[3])
        c.disc(cx, cy, 5.5, FIRE[4])
        for i in range(8):
            a = i / 8 * math.tau
            c.line(cx + math.cos(a) * 6, cy + math.sin(a) * 6, cx + math.cos(a) * 11, cy + math.sin(a) * 11, FIRE[3])
        c.outline(FIRE_LINE)
        return c
    if frame in (1, 2):
        r = 12 if frame == 1 else 17
        for i in range(14):
            a = i / 14 * math.tau + rnd.uniform(-0.15, 0.15)
            tongue = r * rnd.uniform(1.15, 1.45)
            c.poly([(cx + math.cos(a - 0.25) * r * 0.8, cy + math.sin(a - 0.25) * r * 0.8),
                    (cx + math.cos(a) * tongue, cy + math.sin(a) * tongue),
                    (cx + math.cos(a + 0.25) * r * 0.8, cy + math.sin(a + 0.25) * r * 0.8)], FIRE[1])
        c.disc(cx, cy, r, FIRE[1])
        c.disc(cx, cy, r * 0.8, FIRE[2])
        c.disc(cx - r * 0.1, cy - r * 0.1, r * 0.55, FIRE[3])
        c.disc(cx - r * 0.15, cy - r * 0.15, r * 0.3, FIRE[4])
        c.outline(FIRE_LINE)
        return c
    if frame in (3, 4):
        # The middle burns out into smoke while flames still lick round its edge.
        smoke_r = 11 if frame == 3 else 15
        lobes = 11 if frame == 3 else 8
        flames = []
        for i in range(lobes):
            a = i / lobes * math.tau + rnd.uniform(-0.25, 0.25)
            d = rnd.uniform(14, 18) if frame == 3 else rnd.uniform(15, 18.5)
            flames.append((cx + math.cos(a) * d, cy + math.sin(a) * d * 0.95, rnd.uniform(4, 6.5) if frame == 3 else rnd.uniform(2.5, 4.5)))
        for x, y, r in flames:
            c.disc(x, y, r, FIRE[1])
        puffs = [(cx + math.cos(a) * smoke_r * 0.5, cy + math.sin(a) * smoke_r * 0.45 - 1, smoke_r * rnd.uniform(0.5, 0.7))
                 for a in (rnd.uniform(0, math.tau) + k * math.tau / 5 for k in range(5))]
        puffs.append((cx, cy, smoke_r * 0.7))
        for x, y, r in puffs:
            c.disc(x + 0.6, y + 0.8, r, SMOKE[0])
        for x, y, r in puffs:
            c.disc(x, y, r, SMOKE[1])
        for x, y, r in puffs:
            c.disc(x - r * 0.3, y - r * 0.35, r * 0.5, SMOKE[2])
        for x, y, r in flames:
            c.disc(x - 0.4, y - 0.6, r * 0.62, FIRE[2] if frame == 3 else FIRE[1])
            if frame == 3:
                c.disc(x - 0.6, y - 1, r * 0.3, FIRE[3])
        c.outline(FIRE_LINE)
        return c
    # 5: smoke rising off in a lumpy cloud.
    puffs = [(cx + rnd.uniform(-12, 12), cy + rnd.uniform(-9, 5) - 4, rnd.uniform(3.5, 6.5)) for _ in range(9)]
    for x, y, r in puffs:
        c.disc(x + 0.6, y + 0.8, r, SMOKE[0])
    for x, y, r in puffs:
        c.disc(x, y, r, SMOKE[1])
    for x, y, r in puffs:
        c.disc(x - r * 0.3, y - r * 0.35, r * 0.5, SMOKE[2])
        c.set(x - r * 0.45, y - r * 0.5, SMOKE[3])
    c.outline(hexc("2e2830"))
    return c


def scorch():
    """A burn mark left on the ground: soot with a few embers still glowing in it."""
    c = Canvas(36, 12)
    rnd = random.Random(9)
    for _ in range(14):
        a, d = rnd.uniform(0, math.tau), rnd.uniform(0, 11)
        c.disc(18 + math.cos(a) * d, 6 + math.sin(a) * d * 0.33, rnd.uniform(2.5, 4.5), hexc("2a1e1a", 140), rnd.uniform(1.2, 2))
    c.disc(18, 6, 9, hexc("1e1412", 200), 3)
    for _ in range(6):
        c.set(18 + rnd.uniform(-9, 9), 6 + rnd.uniform(-2, 2), rnd.choice((FIRE[2], FIRE[3], FIRE[1])))
    return c


def flame(frame):
    """A tongue of flame, its tip swaying: frames 0-3."""
    c = Canvas(14, 24)
    sway = (0, 1.5, 0.5, -1)[frame]
    c.poly([(7 + sway, 1), (12, 13), (11, 20), (7, 23), (3, 20), (2, 13)], FIRE[1])
    c.poly([(7 + sway * 0.7, 6), (10.5, 15), (9.5, 20), (7, 21.5), (4.5, 20), (3.5, 15)], FIRE[2])
    c.poly([(7 + sway * 0.4, 11), (9, 17), (7, 20.5), (5, 17)], FIRE[3])
    c.disc(7, 19, 1.6, FIRE[4])
    c.outline(FIRE_LINE)
    return c


# ---------------------------------------------------------------- wood

def pixels(rows, palette):
    """A canvas from rows of characters, each a key of `palette` ('.' is empty)."""
    c = Canvas(len(rows[0]), len(rows))
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            if key != ".":
                c.px[y][x] = palette[key]
    return c


BROAD_LEAF = [
    ".....oooo....",
    "...ooLLHLoo..",
    "..oLLLLLLLLo.",
    "ssoDDDDDDDDDo",
    "..oMMMMMMMMo.",
    "...ooMMMMoo..",
    ".....oooo....",
]
SLENDER_LEAF = [
    "....oooo...",
    "..ooLLHLoo.",
    "ssoDDDDDDDo",
    "..ooMMMMoo.",
    "....oooo...",
]


def leaf_sprite(colors, rows=BROAD_LEAF):
    """A leaf pointing right: lit upper half, shaded lower half, the midrib between, a stem."""
    return pixels(rows, {"o": LEAF_LINE, "s": LEAF_LINE, "D": colors[0], "M": colors[1], "L": colors[2], "H": colors[3]})


def petal():
    c = Canvas(8, 7)
    c.poly([(1, 3.5), (3, 1), (6, 1.2), (7, 3.5), (6, 6), (3, 6)], PETAL[1])
    c.set(4, 2, PETAL[2])
    c.set(5, 2, PETAL[2])
    c.set(2, 4, PETAL[0])
    c.outline(hexc("7a2848"))
    return c


def wind():
    """A curved streak of wind, thick in the middle and tapering away, mint at the edges."""
    c = Canvas(44, 14)
    for i in range(80):
        t = i / 79
        x = 2 + t * 40
        y = 10 - math.sin(t * math.pi) * 7
        width = math.sin(t * math.pi) * 2.2
        if width < 0.5:
            c.set(x, y, hexc("bff5d0", 170))
            continue
        c.disc(x, y, width, hexc("bff5d0", 200))
        c.disc(x, y - 0.4, width * 0.5, hexc("ffffff", 240))
    return c


# ---------------------------------------------------------------- water

def droplet():
    c = Canvas(7, 10)
    c.poly([(3.5, 0.5), (5.8, 5), (5.5, 7.5), (3.5, 8.8), (1.5, 7.5), (1.2, 5)], WATER[2])
    c.recolour(lambda x, y, _: x >= 4 and y >= 5, WATER[1])
    c.set(2.5, 5, WATER[4])
    c.set(2.5, 6, WATER[3])
    c.outline(WATER_LINE)
    return c


def orb(frame):
    """A wobbling ball of water with a bright window highlight."""
    c = Canvas(18, 18)
    rx, ry = (7, 6.4) if frame == 0 else (6.4, 7)
    c.disc(9, 9, rx, WATER[1], ry)
    c.disc(8.4, 8.4, rx * 0.8, WATER[2], ry * 0.8)
    c.disc(7, 6.6, 2.4, WATER[3], 1.8)
    c.set(6, 6, WATER[4])
    c.set(7, 5.5, WATER[4])
    c.set(12, 12, WATER[3])
    c.outline(WATER_LINE)
    return c


def splash(frame):
    """Water hitting: a dome (0), a crown thrown up with drops (1), drops falling (2), a ripple (3)."""
    c = Canvas(40, 30)
    rnd = random.Random(5)
    cx, base = 20, 26
    if frame == 0:
        c.disc(cx, base, 9, WATER[2], 6)
        c.disc(cx - 2, base - 2, 5, WATER[3], 3)
    elif frame == 1:
        for i in range(7):
            x = cx - 12 + i * 4
            h = 10 + 8 * math.sin((i + 0.5) / 7 * math.pi) + rnd.uniform(-2, 2)
            c.poly([(x - 2, base), (x - 0.5, base - h), (x + 1, base - h + 1), (x + 2, base)], WATER[2])
            c.set(x - 0.5, base - h + 2, WATER[4])
        c.disc(cx, base, 13, WATER[1], 3)
        for i in range(6):
            c.disc(cx - 14 + i * 5.6, base - 20 - rnd.uniform(0, 4), 1.4, WATER[3])
    elif frame == 2:
        c.disc(cx, base, 14, WATER[1], 3.4)
        c.disc(cx, base - 1, 10, WATER[2], 2)
        for i in range(8):
            c.disc(cx - 16 + i * 4.6, base - rnd.uniform(5, 15), 1.5, WATER[3])
    else:
        for r_out, color in ((16, WATER[2]), (10, WATER[3])):
            for i in range(90):
                a = i / 90 * math.tau
                c.set(cx + math.cos(a) * r_out, base - 2 + math.sin(a) * r_out * 0.28, color)
    c.outline(WATER_LINE)
    return c


def bubble():
    c = Canvas(9, 9)
    for i in range(48):
        a = i / 48 * math.tau
        c.set(4 + math.cos(a) * 3.4, 4 + math.sin(a) * 3.4, WATER[3])
    c.set(3, 2, WATER[4])
    c.set(2, 3, WATER[4])
    return c


# ---------------------------------------------------------------- all of it

def sprites():
    out = {
        "fx_spike_tall": spike(13, 46, 1.0, 1),
        "fx_spike_mid": spike(11, 32, -1.5, 2),
        "fx_spike_low": spike(14, 20, 0.8, 3),
        "fx_spike_thin": spike(7, 28, 2.5, 4),
        "fx_rock_a": rock(7, 1),
        "fx_rock_b": rock(5, 2),
        "fx_rock_c": rock(9, 3),
        "fx_crack": crack(),
        "fx_leaf_green": leaf_sprite(LEAF),
        "fx_leaf_light": leaf_sprite(LEAF_LIGHT, SLENDER_LEAF),
        "fx_leaf_gold": leaf_sprite(LEAF_GOLD),
        "fx_scorch": scorch(),
        "fx_petal": petal(),
        "fx_wind": wind(),
        "fx_drop": droplet(),
        "fx_bubble": bubble(),
    }
    for frame in range(4):
        out[f"fx_dust_{frame}"] = dust(frame)
        out[f"fx_fireball_{frame}"] = fireball(frame)
        out[f"fx_flame_{frame}"] = flame(frame)
        out[f"fx_splash_{frame}"] = splash(frame)
    for frame in range(6):
        out[f"fx_blast_{frame}"] = blast(frame)
    for frame in range(2):
        out[f"fx_orb_{frame}"] = orb(frame)
    return out


def contact_sheet(art, path, zoom=4):
    from PIL import Image
    names = sorted(art)
    cell = 48 * zoom + 8
    cols = 8
    sheet = Image.new("RGB", (cols * cell, ((len(names) + cols - 1) // cols) * (cell + 14)), (88, 140, 88))
    import io
    for i, name in enumerate(names):
        img = Image.open(io.BytesIO(art[name].png(zoom)))
        x = (i % cols) * cell + (cell - img.width) // 2
        y = (i // cols) * (cell + 14) + 12 + (cell - img.height) // 2
        sheet.paste(img, (x, y), img)
        from PIL import ImageDraw
        ImageDraw.Draw(sheet).text(((i % cols) * cell + 4, (i // cols) * (cell + 14)), name[3:], fill=(255, 255, 255))
    sheet.save(path)


def main():
    art = sprites()
    for name, canvas in art.items():
        (SPRITES / f"{name}.png").write_bytes(canvas.png())
    print(f"wrote {len(art)} sprites to art/sprites/fx_*.png")
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        contact_sheet(art, path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
