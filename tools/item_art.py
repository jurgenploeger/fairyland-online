#!/usr/bin/env python3
"""Hand-drawn pixel art for every item, as code: writes art/sprites/item_<id>.png (32×32).

Each item is drawn in flat colours with a light and a dark shade, then gets the same dark
outline as the game's other sprites. No image libraries needed. Edit a drawing below and rerun:

    python3 tools/item_art.py            # all items
    python3 tools/item_art.py potion     # just these
    python3 tools/item_art.py --sheet out.png   # also a 4× contact sheet to look at
"""

import json
import math
import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"
SIZE = 32
OUTLINE = (35, 24, 52, 255)


def hexc(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


class Canvas:
    def __init__(self, size=SIZE):
        self.size = size
        self.px = [[None] * size for _ in range(size)]

    def set(self, x, y, color):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[y][x] = color

    def get(self, x, y):
        if 0 <= x < self.size and 0 <= y < self.size:
            return self.px[y][x]
        return None

    def rect(self, x0, y0, x1, y1, color):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, color)

    def line(self, x0, y0, x1, y1, color, width=1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) * 2 + 1
        for i in range(steps + 1):
            t = i / steps
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            if width == 1:
                self.set(x, y, color)
            else:
                self.disc(x, y, width / 2, color)

    def disc(self, cx, cy, r, color):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.set(x, y, color)

    def ellipse(self, cx, cy, rx, ry, color):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
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

    def ring(self, cx, cy, r_out, r_in, color, ry_scale=1.0):
        for y in range(int(cy - r_out - 1), int(cy + r_out + 2)):
            for x in range(int(cx - r_out - 1), int(cx + r_out + 2)):
                d = (x - cx) ** 2 + ((y - cy) / ry_scale) ** 2
                if r_in * r_in < d <= r_out * r_out:
                    self.set(x, y, color)

    def shade(self, test, color):
        """Recolour the filled pixels where test(x, y, current) is true."""
        for y in range(self.size):
            for x in range(self.size):
                c = self.px[y][x]
                if c is not None and test(x, y, c):
                    self.px[y][x] = color

    def outline(self, color=OUTLINE):
        grow = []
        for y in range(self.size):
            for x in range(self.size):
                if self.px[y][x] is None and any(
                    self.get(x + dx, y + dy) not in (None, color) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ):
                    grow.append((x, y))
        for x, y in grow:
            self.px[y][x] = color

    def png(self, scale=1):
        size = self.size * scale
        rows = []
        for y in range(size):
            row = bytearray([0])
            for x in range(size):
                c = self.px[y // scale][x // scale] or (0, 0, 0, 0)
                row += bytes(c)
            rows.append(bytes(row))
        return encode_png(size, size, b"".join(rows))


def encode_png(width, height, raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


# ---------------------------------------------------------------- shared shapes

WOOD = [hexc("8a5a2b"), hexc("b67a3c"), hexc("d9a05a")]          # dark, mid, light
STEEL = [hexc("7b8798"), hexc("b9c4d2"), hexc("eef3f8")]
GOLD = [hexc("b07a12"), hexc("e8b62c"), hexc("fff09a")]
WHITE = hexc("ffffff")


def light_top_left(c, colors, cx, cy, r):
    """Three-tone ball shading: light up-left, dark down-right."""
    dark, mid, light = colors
    for y in range(SIZE):
        for x in range(SIZE):
            if c.px[y][x] == mid:
                d = (x - cx) + (y - cy)
                if d > r * 0.55:
                    c.px[y][x] = dark
                elif d < -r * 0.75:
                    c.px[y][x] = light




def sword(c, blade, guard, grip, gem=None, long=True):
    tip, base = ((26, 5), (11, 20)) if long else ((23, 8), (11, 20))
    c.line(base[0], base[1], tip[0], tip[1], blade[1], width=4)
    c.line(base[0] + 1, base[1] - 1, tip[0] - 1, tip[1] + 1, blade[2], width=1)   # edge shine
    c.line(base[0] + 1, base[1] + 1, tip[0], tip[1] + 2, blade[0], width=1)       # shadow side
    c.line(7, 17, 14, 24, guard[1], width=3)                                      # crossguard
    c.line(7, 16, 13, 22, guard[2], width=1)
    c.line(9, 22, 5, 26, grip[1], width=3)                                        # grip
    c.line(9, 23, 5, 27, grip[0], width=1)
    c.disc(4.5, 27.5, 1.8, guard[1])                                              # pommel
    if gem:
        c.disc(10.5, 20.5, 1.3, gem)


def staff(c, shaft, top):
    c.line(7, 28, 21, 9, shaft[1], width=3)
    c.line(8, 28, 22, 10, shaft[0], width=1)
    c.line(6, 27, 20, 8, shaft[2], width=1)
    top(c)


def axe(c, head, handle, double=False):
    c.line(8, 28, 21, 7, handle[1], width=3)
    c.line(9, 28, 22, 8, handle[0], width=1)
    c.poly([(18, 6), (27, 3), (29, 13), (22, 15)], head[1])
    c.shade(lambda x, y, col: col == head[1] and x + y > 36, head[0])
    c.line(27, 4, 29, 12, head[2])
    if double:
        c.poly([(19, 7), (10, 3), (8, 12), (16, 14)], head[1])
        c.shade(lambda x, y, col: col == head[1] and x < 13 and y > 9, head[0])
        c.line(10, 4, 8, 11, head[2])
    c.rect(19, 7, 22, 12, handle[0])


def shirt(c, cloth, sleeves=True, collar=None):
    dark, mid, light = cloth
    c.poly([(9, 7), (23, 7), (25, 28), (7, 28)], mid)
    if sleeves:
        c.poly([(9, 7), (3, 13), (6, 17), (10, 13)], mid)
        c.poly([(23, 7), (29, 13), (26, 17), (22, 13)], mid)
    c.shade(lambda x, y, col: col == mid and x > 19, dark)
    c.shade(lambda x, y, col: col == mid and x < 11 and y > 8, light)
    c.ellipse(16, 7, 4, 2.2, collar or dark)
    c.rect(7, 27, 25, 28, dark)


def robe(c, cloth, trim, star=None):
    dark, mid, light = cloth
    c.poly([(11, 5), (21, 5), (28, 29), (4, 29)], mid)
    c.poly([(11, 6), (3, 15), (6, 18), (11, 12)], mid)
    c.poly([(21, 6), (29, 15), (26, 18), (21, 12)], mid)
    c.shade(lambda x, y, col: col == mid and x > 20, dark)
    c.shade(lambda x, y, col: col == mid and x < 10 and y > 7, light)
    c.line(16, 7, 16, 29, trim[1])
    c.rect(5, 28, 27, 29, trim[1])
    c.ellipse(16, 5.5, 4, 2, trim[0])
    if star:
        star_shape(c, 21, 19, 4.6, star, inner=0.5)


def cloak(c, cloth, clasp, fur=None, hood=False):
    dark, mid, light = cloth
    if hood:
        c.poly([(12, 6), (20, 6), (29, 29), (3, 29)], mid)
    else:   # rounded shoulders, so it reads as a cloak and not a tent
        c.poly([(10, 7), (22, 7), (27, 12), (29, 29), (3, 29), (5, 12)], mid)
    c.shade(lambda x, y, col: col == mid and x > 18, dark)
    c.shade(lambda x, y, col: col == mid and x < 11 and y > 9, light)
    c.line(16, 9, 12, 29, dark)
    c.line(16, 9, 20, 29, dark)
    if hood:
        c.ellipse(16, 7, 7, 5, mid)
        c.ellipse(16, 8, 4, 3, dark)
    if fur:
        c.ellipse(16, 8, 8, 2.8, fur[1])
        for x in range(9, 24, 3):
            c.set(x, 10, fur[0])
    c.disc(16, 11, 1.7, clasp)


def star_shape(c, cx, cy, r, color, inner=0.45, rotation=-math.pi / 2):
    points = []
    for i in range(10):
        radius = r if i % 2 == 0 else r * inner
        angle = rotation + i * math.pi / 5
        points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    c.poly(points, color)


def ring(c, band, gem=None, gem_color=None):
    dark, mid, light = band
    c.ring(16, 19, 9, 5.5, mid, ry_scale=0.85)
    c.shade(lambda x, y, col: col == mid and y > 21, dark)
    c.shade(lambda x, y, col: col == mid and y < 16 and x < 15, light)
    if gem:
        c.poly([(12, 9), (20, 9), (22, 12), (16, 17), (10, 12)], gem_color[1])
        c.shade(lambda x, y, col: col == gem_color[1] and x > 16, gem_color[0])
        c.poly([(13, 10), (16, 10), (15, 12), (12, 12)], gem_color[2])


def whip(c, leather, grip, tassel=None):
    # A braided lash: the coil alternates light and dark every few steps.
    for i in range(0, 60):
        t = i / 60 * math.pi * 3.2
        r = 3 + i * 0.13
        c.disc(17 + r * math.cos(t), 14 + r * math.sin(t) * 0.8, 1.1, leather[2] if i % 6 < 2 else leather[1])
    c.line(6, 28, 11, 21, grip[1], width=3)
    c.line(7, 28, 12, 22, grip[0], width=1)
    for (x, y) in ((7, 26), (9, 24)):                       # wrapped handle
        c.line(x - 1, y - 1, x + 1, y + 1, grip[2])
    c.rect(10, 20, 13, 22, GOLD[1])
    c.set(10, 20, GOLD[2])
    if tassel:
        tassel(c)


# ---------------------------------------------------------------- the items

RED = [hexc("a8202e"), hexc("e0384a"), hexc("ff8a8a")]
PINK = [hexc("b0205e"), hexc("ee4c8c"), hexc("ffa4c8")]
BLUE = [hexc("1c4fa8"), hexc("3a86e8"), hexc("9ccaff")]
VIOLET = [hexc("4a2aa0"), hexc("7a5ae6"), hexc("c0aaff")]
GREEN = [hexc("2a7a2e"), hexc("46b848"), hexc("9ee88a")]
TEAL = [hexc("137a78"), hexc("2cc0b5"), hexc("a4f2e6")]
LEATHER = [hexc("6a4020"), hexc("9a6232"), hexc("c88a4e")]
CLOTH = [hexc("9a8a62"), hexc("d8c89a"), hexc("f4ead0")]
ORANGE = [hexc("b0501a"), hexc("ee8a2a"), hexc("ffc070")]
NAVY = [hexc("1a2a6a"), hexc("2e4aa8"), hexc("6a8ae0")]
SNOW = [hexc("5f88b8"), hexc("a9cdef"), hexc("e4f2ff")]
DRAGON = [hexc("8a1a1a"), hexc("d03a2a"), hexc("ff8a5a")]
LILAC = [hexc("8a5ab0"), hexc("c49ae8"), hexc("eedcff")]
COPPER = [hexc("8a4a22"), hexc("c8783a"), hexc("f0b07a")]






def draw_seal_stone(c):
    c.poly([(16, 4), (26, 11), (24, 25), (16, 29), (8, 25), (6, 11)], TEAL[1])
    c.shade(lambda x, y, col: col == TEAL[1] and x > 17 and y > 14, TEAL[0])
    c.poly([(16, 5), (8, 11), (12, 14), (16, 9)], TEAL[2])
    for i in range(0, 40):       # the sealing spiral
        t = i / 40 * math.pi * 3
        r = 0.6 + i * 0.14
        c.set(16 + r * math.cos(t), 17 + r * math.sin(t), WHITE)


def draw_pet_egg(c):
    shell = [hexc("d8c8a4"), hexc("fbf2dc"), WHITE]
    c.ellipse(16, 17.5, 9, 11.5, shell[1])
    light_top_left(c, shell, 16, 17.5, 10)
    for (x, y, r, col) in ((12, 14, 2.2, hexc("f08aa8")), (20, 19, 2.6, hexc("7ac0f0")), (13, 23, 1.8, hexc("9ad86a")), (19, 11, 1.5, hexc("f6c33b"))):
        c.disc(x, y, r, col)
    c.line(3, 10, 5, 12, OUTLINE)     # wiggle marks
    c.line(28, 10, 26, 12, OUTLINE)


def draw_wooden_sword(c):
    # A practice sword: pale ash blade with grain, a dark guard and a leather-wrapped grip.
    blade = [hexc("a8743c"), hexc("deb070"), hexc("f6dca4")]
    sword(c, blade, [hexc("4a2a14"), hexc("6a3e1e"), hexc("8a5a30")], [hexc("3a2410"), hexc("5a3a1a"), hexc("7a5228")], long=True)
    for (x, y) in ((16, 15), (19, 12), (22, 9)):          # wood grain
        c.set(x, y, blade[0])
    for (x, y) in ((8, 24), (6, 26)):                      # leather wraps
        c.set(x, y, hexc("c89a5a"))


def draw_steel_sword(c):
    sword(c, STEEL, GOLD, [hexc("4a2a6a"), hexc("6a44a0"), hexc("9a7ad0")], gem=hexc("e0384a"))
    c.line(13, 17, 23, 7, STEEL[0])                        # the fuller, a groove down the blade
    c.set(24, 6, STEEL[2]); c.set(25, 5, WHITE)             # glint at the tip
    for (x, y) in ((7, 24), (6, 25)):                       # wrapped grip
        c.set(x, y, hexc("c0a8f0"))


def draw_oak_staff(c):
    def top(c):
        # A leafy crown cradling a small green spirit orb.
        for (cx, cy, r) in ((22, 5.5, 3.2), (25.5, 8.5, 3), (19.5, 8.5, 2.8)):
            c.disc(cx, cy, r, GREEN[1])
        c.shade(lambda x, y, col: col == GREEN[1] and x + y > 31, GREEN[0])
        c.disc(21, 4.5, 1.3, GREEN[2]); c.disc(25, 7.5, 1, GREEN[2])
        c.disc(22.5, 7.5, 1.6, hexc("d8ffb0"))
        c.set(22, 7, WHITE)
    staff(c, WOOD, top)
    c.disc(13.5, 19.5, 1.2, WOOD[0])                       # a knot in the shaft
    for (x, y) in ((17, 15), (15, 18), (11, 22), (9, 25)):  # a vine curling down the shaft
        c.set(x, y, GREEN[1]); c.set(x + 1, y, GREEN[0])


def draw_elder_staff(c):
    def top(c):
        c.ring(22.5, 7.5, 5.2, 3.2, WOOD[1])
        c.shade(lambda x, y, col: col == WOOD[1] and x + y > 31, WOOD[0])
        c.disc(22.5, 7.5, 3, hexc("7af0ff"))
        c.shade(lambda x, y, col: col == hexc("7af0ff") and x + y > 31, hexc("2cb8d8"))
        c.disc(21.5, 6.5, 1.2, WHITE)
    staff(c, [hexc("5a3a1a"), hexc("7a4e24"), hexc("a07040")], top)
    for (x, y) in ((14, 18), (11, 22)):                     # carved bands
        c.line(x - 1, y - 1, x + 1, y + 1, GOLD[1])
    c.set(13, 19, GREEN[1]); c.set(12, 19, GREEN[2]); c.set(16, 15, GREEN[1])


def draw_iron_axe(c):
    axe(c, STEEL, WOOD)
    # A broader blade, with a bright cutting edge and a rivet.
    c.poly([(18, 5), (28, 1), (30, 15), (21, 16)], STEEL[1])
    c.shade(lambda x, y, col: col == STEEL[1] and x + y > 37, STEEL[0])
    c.line(28, 2, 30, 14, STEEL[2])
    c.line(27, 3, 29, 13, WHITE)
    c.rect(19, 7, 22, 13, WOOD[0])
    c.disc(20.5, 10, 1, GOLD[1])


def draw_battle_axe(c):
    steel = [hexc("5a6474"), hexc("8e9aac"), hexc("dde6f0")]
    axe(c, steel, [hexc("4a2a1a"), hexc("6a3e22"), hexc("8a5a34")], double=True)
    # Gold rims along both blades, an engraved line, and a gold cap.
    c.line(27, 3, 29, 13, GOLD[1]); c.line(10, 3, 8, 12, GOLD[1])
    c.line(26, 5, 27, 11, steel[2]); c.line(11, 5, 10, 10, steel[2])
    c.line(23, 8, 26, 11, steel[0]); c.line(15, 8, 12, 11, steel[0])
    c.disc(20.5, 9.5, 1.6, GOLD[1]); c.set(20, 9, GOLD[2])
    c.disc(8.5, 28.5, 1.3, GOLD[1])


def draw_crystal_wand(c):
    c.line(6, 28, 17, 14, WOOD[1], width=3)
    c.line(7, 28, 18, 15, WOOD[0])
    c.line(5, 27, 16, 13, WOOD[2])
    crystal = [hexc("1e98c0"), hexc("62dcf4"), hexc("d4fbff")]
    c.poly([(21, 1), (28, 9), (22, 18), (14, 10)], crystal[1])
    c.shade(lambda x, y, col: col == crystal[1] and x > 21, crystal[0])
    c.poly([(20, 4), (16, 10), (19, 11), (22, 5)], crystal[2])
    c.set(18, 7, WHITE); c.set(26, 2, WHITE); c.set(29, 15, WHITE)
    c.rect(15, 13, 19, 15, GOLD[1])
    c.line(15, 13, 19, 13, GOLD[2])


def draw_star_wand(c):
    c.line(7, 27, 17, 15, GOLD[1], width=2)
    c.line(8, 27, 18, 16, GOLD[0])
    star_shape(c, 20.5, 10.5, 8, hexc("ffd84a"))
    star_shape(c, 19.5, 9.5, 4, hexc("fff4b0"))
    c.set(28, 21, WHITE); c.set(4, 12, WHITE); c.set(27, 3, WHITE)


def draw_tamer_whip(c):
    whip(c, LEATHER, WOOD)


def draw_beast_whip(c):
    def tassel(c):
        c.disc(24, 25, 3, hexc("f6c33b"))                 # paw pad
        for (x, y) in ((21, 21), (24, 20), (27, 21)):
            c.disc(x, y, 1.2, hexc("f6c33b"))
    whip(c, [hexc("7a1a1a"), hexc("b8302a"), hexc("e8604a")], [hexc("3a2a1a"), hexc("5a4028"), hexc("7a5a38")], tassel)


def draw_wild_horn(c):
    horn = [hexc("a07a4a"), hexc("e6cfa0"), hexc("fff4dc")]
    path = []
    for i in range(0, 48):
        t = i / 47
        x = 5 + t * 19
        y = 26 - math.sin(t * math.pi / 2) * 15
        r = 1 + t * 4.2
        path.append((x, y, r))
        c.disc(x, y, r, horn[1])
    # Shade across the curve: the side facing down-right is in shadow, up-left catches light.
    for py in range(SIZE):
        for px in range(SIZE):
            if c.px[py][px] != horn[1]:
                continue
            x, y, r = min(path, key=lambda p: (p[0] - px) ** 2 + (p[1] - py) ** 2)
            across = ((px - x) + (py - y)) / math.sqrt(2)
            if across > 0.35 * r:
                c.px[py][px] = horn[0]
            elif across < -0.45 * r:
                c.px[py][px] = horn[2]
    for t in (0.4, 0.7):                                                      # carved bands
        x, y, r = path[int(t * 47)]
        c.ring(x, y, r + 0.3, r - 1.3, LEATHER[0])
    x, y, r = path[-1]
    c.ellipse(x + 1, y - 0.5, r * 0.55, r * 0.8, hexc("5a3a1a"))           # the bell's opening
    c.disc(6, 25.5, 1.2, GOLD[1])                                             # mouthpiece


def draw_cloth_tunic(c):
    shirt(c, CLOTH, collar=hexc("8a7a52"))
    c.line(16, 8, 16, 14, CLOTH[0])                        # laced neck
    for y in (9, 11, 13):
        c.set(15, y, WOOD[0]); c.set(17, y, WOOD[0])
    c.rect(8, 21, 24, 22, WOOD[1])                         # belt
    c.rect(15, 20, 17, 23, GOLD[1])
    c.set(15, 20, GOLD[2])
    for x in range(9, 24, 3):                              # stitched hem
        c.set(x, 26, CLOTH[0])


def draw_leather_vest(c):
    shirt(c, LEATHER, sleeves=False, collar=hexc("4a2a14"))
    c.poly([(14, 8), (18, 8), (17, 27), (15, 27)], CLOTH[2])   # the shirt underneath
    c.line(14, 8, 15, 27, LEATHER[0]); c.line(18, 8, 17, 27, LEATHER[0])
    for y in (12, 17, 22):                                 # buttons
        c.set(13, y, GOLD[1]); c.set(19, y, GOLD[1])
    c.rect(9, 18, 12, 21, LEATHER[0]); c.rect(20, 18, 23, 21, LEATHER[0])   # pockets
    c.line(9, 18, 12, 18, LEATHER[2]); c.line(20, 18, 23, 18, LEATHER[2])
    for y in range(9, 27, 3):                              # stitching
        c.set(9, y, LEATHER[2])


def draw_chain_mail(c):
    shirt(c, STEEL, collar=hexc("5a6474"))
    c.shade(lambda x, y, col: col in STEEL and (x + y) % 3 == 0 and 8 < y < 27, STEEL[0])


def draw_iron_plate(c):
    plate = [hexc("6a7688"), hexc("aab6c6"), hexc("f0f6ff")]
    c.poly([(8, 6), (24, 6), (26, 12), (23, 28), (9, 28), (6, 12)], plate[1])
    c.disc(6, 9, 3.5, plate[1]); c.disc(26, 9, 3.5, plate[1])
    c.shade(lambda x, y, col: col == plate[1] and x > 18, plate[0])
    c.shade(lambda x, y, col: col == plate[1] and x < 12 and y > 8, plate[2])
    c.line(16, 8, 16, 27, plate[0])
    c.line(9, 17, 23, 17, plate[0])
    c.ellipse(16, 6, 4, 1.8, plate[0])


def draw_dragon_mail(c):
    shirt(c, DRAGON, collar=GOLD[0])
    for y in range(10, 27, 3):
        for x in range(8 + (y // 3) % 2 * 2, 25, 4):
            c.set(x, y, DRAGON[0]); c.set(x + 1, y + 1, DRAGON[0])
    c.line(8, 9, 11, 7, GOLD[1]); c.line(24, 9, 21, 7, GOLD[1])


def draw_silk_robe(c):
    robe(c, LILAC, [hexc("b89ad8"), WHITE, WHITE], star=GOLD[1])


def draw_mage_robe(c):
    robe(c, NAVY, [GOLD[0], GOLD[1], GOLD[2]])
    for (x, y) in ((10, 20), (22, 24), (12, 26), (20, 14)):
        c.set(x, y, GOLD[2])


def draw_snow_cloak(c):
    cloak(c, SNOW, hexc("3a86e8"), fur=[hexc("b8c8dc"), WHITE])
    c.rect(4, 27, 28, 28, WHITE)                     # fur hem
    for (x, y) in ((9, 20), (22, 18), (14, 24), (19, 15)):   # snowflakes
        c.set(x, y, WHITE); c.set(x - 1, y, WHITE); c.set(x + 1, y, WHITE); c.set(x, y - 1, WHITE); c.set(x, y + 1, WHITE)


def draw_ranger_cloak(c):
    cloak(c, GREEN, GOLD[1], hood=True)


def draw_tamer_jacket(c):
    shirt(c, ORANGE, collar=hexc("7a3a10"))
    c.rect(9, 19, 13, 23, ORANGE[0]); c.rect(19, 19, 23, 23, ORANGE[0])   # pockets
    c.rect(10, 20, 12, 20, ORANGE[2]); c.rect(20, 20, 22, 20, ORANGE[2])
    c.line(16, 9, 16, 28, hexc("7a3a10"))


def draw_lucky_clover(c):
    for (cx, cy) in ((11, 10), (21, 10), (11, 20), (21, 20)):
        c.disc(cx, cy, 5.2, GREEN[1])
    c.shade(lambda x, y, col: col == GREEN[1] and (x - 16) + (y - 15) > 6, GREEN[0])
    c.shade(lambda x, y, col: col == GREEN[1] and (x - 16) + (y - 15) < -9, GREEN[2])
    c.line(16, 15, 23, 29, hexc("2a6a2e"), width=2)
    c.set(16, 15, GREEN[0])


def draw_ruby_ring(c):
    ring(c, GOLD, gem=True, gem_color=RED)


def draw_novice_ring(c):
    ring(c, COPPER)
    c.disc(16, 11, 1.8, hexc("9ccaff"))


def draw_star_charm(c):
    c.line(5, 3, 16, 12, GOLD[0])
    c.line(27, 3, 16, 12, GOLD[0])
    c.disc(16, 12, 1.5, GOLD[1])
    star_shape(c, 16, 21, 9, GOLD[1])
    star_shape(c, 15, 20, 4.5, GOLD[2])
    c.set(27, 25, WHITE); c.set(6, 18, WHITE)


def draw_power_band(c):
    band = [hexc("8a1a2a"), hexc("d83a4a"), hexc("ff8a8a")]
    c.ring(16, 16, 11, 6.5, band[1], ry_scale=0.62)
    c.shade(lambda x, y, col: col == band[1] and y > 17, band[0])
    c.shade(lambda x, y, col: col == band[1] and y < 13, band[2])
    for x in (8, 16, 24):
        c.disc(x, 21 if x == 16 else 19, 1.3, STEEL[2])


def draw_speed_boots(c):
    boot = [hexc("1c4fa8"), hexc("3a86e8"), hexc("9ccaff")]
    c.poly([(9, 6), (17, 6), (17, 21), (26, 23), (27, 28), (8, 28)], boot[1])
    c.shade(lambda x, y, col: col == boot[1] and x > 15 and y < 21, boot[0])
    c.shade(lambda x, y, col: col == boot[1] and x < 12, boot[2])
    c.rect(8, 26, 27, 28, hexc("f4ead0"))
    c.rect(9, 6, 17, 8, hexc("f4ead0"))
    for i, (x, y) in enumerate(((5, 10), (4, 14), (5, 18))):   # the wing: three feathers
        c.ellipse(x + 2, y, 3.2, 1.6, WHITE)
        c.line(x, y + 1, x + 4, y + 1, hexc("9ccaff"))
    c.set(21, 25, GOLD[1])


DRAWINGS = {name[5:]: fn for name, fn in globals().items() if name.startswith("draw_")}
# Not drawn here: the Potion is a Retro Diffusion sprite (rd_pro__fantasy) and the Hi-Potion,
# Ether and Hi-Ether are palette swaps of it (`derive` in art/assets.json).

PROMPTS = {  # for a later Retro Diffusion upgrade (python3 tools/rd.py generate item_<id>)
    "potion": "round red healing potion bottle with a cork",
    "hi_potion": "big pink healing potion bottle with a gold star label",
    "ether": "blue mana potion in a cone flask with a cork",
    "hi_ether": "violet mana potion in a cone flask with a gold star",
    "seal_stone": "teal crystal sealing stone with a white spiral rune",
    "pet_egg": "cream pet egg with colourful spots, wiggling",
    "wooden_sword": "small wooden practice sword",
    "steel_sword": "steel sword with a gold crossguard and a red gem",
    "oak_staff": "oak staff topped with green leaves",
    "elder_staff": "gnarled elder staff holding a glowing cyan orb",
    "iron_axe": "iron axe with a wooden handle",
    "battle_axe": "double-headed dwarven battle axe",
    "crystal_wand": "short wand with a cyan crystal tip",
    "star_wand": "golden wand with a big shining star",
    "tamer_whip": "coiled leather whip",
    "beast_whip": "red coiled whip with a paw-shaped tassel",
    "wild_horn": "curved hunting horn with a leather strap",
    "cloth_tunic": "simple beige cloth tunic with a belt",
    "leather_vest": "brown leather vest",
    "chain_mail": "chain mail shirt",
    "iron_plate": "shiny iron breastplate",
    "dragon_mail": "red dragon scale armor",
    "silk_robe": "lilac silk robe with a gold star",
    "mage_robe": "navy mage robe with gold trim",
    "snow_cloak": "white snow cloak with a fur collar",
    "ranger_cloak": "green hooded ranger cloak",
    "tamer_jacket": "orange jacket with big pockets",
    "lucky_clover": "four-leaf lucky clover",
    "ruby_ring": "gold ring with a red ruby",
    "novice_ring": "simple copper ring with a small blue stone",
    "star_charm": "gold star charm on a necklace",
    "power_band": "red wristband with steel studs",
    "speed_boots": "blue winged speed boots",
}


# Magic weapons (items.json `glow` + `glowAt`): a small soft halo around the tip, added after the
# outline. The game adds the same glow, gently pulsing, when the weapon is held.
def _glows():
    items = json.loads((pathlib.Path(__file__).resolve().parent.parent / "content" / "items.json").read_text())["items"]
    return {i["id"]: (i["glowAt"][0], i["glowAt"][1], 10, hexc(i["glow"].lstrip("#")))
            for i in items if i.get("glow") and i.get("glowAt")}


GLOWS = _glows()


def halo(c, cx, cy, radius, color):
    """Fills empty pixels near the tip with the glow colour, fading out with distance."""
    r, g, b = color[:3]
    for y in range(SIZE):
        for x in range(SIZE):
            if c.px[y][x] is not None:
                continue
            d = math.hypot(x - cx, y - cy) / radius
            if d < 1:
                alpha = int(185 * (1 - d) ** 1.3)
                if alpha > 12:
                    c.px[y][x] = (r, g, b, alpha)


def render(item_id):
    canvas = Canvas()
    DRAWINGS[item_id](canvas)
    canvas.outline()
    if item_id in GLOWS:
        halo(canvas, *GLOWS[item_id])
    return canvas


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    ids = argv or sorted(DRAWINGS)
    for item_id in ids:
        (SPRITES / f"item_{item_id}.png").write_bytes(render(item_id).png())
    print(f"wrote {len(ids)} item sprites to art/sprites/")
    if sheet_path:
        columns, scale, pad = 6, 4, 4
        rows = math.ceil(len(ids) / columns)
        cell = SIZE * scale + pad
        width, height = columns * cell + pad, rows * cell + pad
        pixels = [[(238, 245, 251, 255)] * width for _ in range(height)]
        for n, item_id in enumerate(ids):
            art = render(item_id)
            ox, oy = pad + (n % columns) * cell, pad + (n // columns) * cell
            for y in range(SIZE * scale):
                for x in range(SIZE * scale):
                    c = art.px[y // scale][x // scale]
                    if c:   # blend, so soft glows show as they will in the game
                        a = c[3] / 255
                        bg = pixels[oy + y][ox + x]
                        pixels[oy + y][ox + x] = tuple(int(c[i] * a + bg[i] * (1 - a)) for i in range(3)) + (255,)
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path} (order: {', '.join(ids)})")


if __name__ == "__main__":
    main(sys.argv[1:])
