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


def draw_homeward_feather(c):
    """A soft white feather, gently curved, on a golden quill, with a homeward glint."""
    vane = [hexc("8fa8d0"), hexc("eef4ff"), WHITE]
    gold = [hexc("b07a1a"), hexc("f0c040"), hexc("fff0a0")]
    base, tip = (9, 24), (27, 3)                       # the shaft, bottom left to top right
    dx, dy = tip[0] - base[0], tip[1] - base[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length                  # along the shaft
    nx, ny = -uy, ux                                   # across it, towards the bottom right
    def spine(t):                                      # the shaft bows a little
        bend = 2.2 * math.sin(math.pi * t)
        return base[0] + dx * t - nx * bend, base[1] + dy * t - ny * bend
    def edge(side, widest):
        points = []
        for k in range(13):
            t = k / 12
            width = widest * math.sin(math.pi * t) ** 0.6 if t < 1 else 0
            x, y = spine(t)
            points.append((x + side * nx * width, y + side * ny * width))
        return points
    c.poly(edge(-1, 5.0) + edge(1, 7.5)[::-1], vane[1])
    for k in range(4, 11, 2):                          # barbs: soft grey splits slanting to the tip
        t = k / 12
        x, y = spine(t)
        c.line(x + nx * 1.5, y + ny * 1.5, x + nx * 6 + ux * 2.5, y + ny * 6 + uy * 2.5, vane[0])
        c.line(x - nx * 1.2, y - ny * 1.2, x - nx * 4 + ux * 2, y - ny * 4 + uy * 2, hexc("c8d6ee"))
    for k in range(2, 12):                             # light on the narrow upper side
        x, y = spine(k / 12)
        c.set(x - nx * 2.5, y - ny * 2.5, vane[2])
    for k in range(0, 25):                             # the golden quill along the spine
        x, y = spine(k / 24)
        c.set(x, y, gold[1] if k % 6 else gold[2])
    c.line(base[0], base[1], base[0] - 4, base[1] + 5, gold[0], width=2)
    for (x, y) in ((27, 19), (23, 24)):                # the homeward glint
        c.set(x, y, gold[2])
        for (ox, oy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c.set(x + ox, y + oy, gold[1])

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


# ---------------------------------------------------------------- companion toys
# Fairyland Online's Pet Toys: a companion who plays with one gains a stat for good.

SKIN = hexc("ffd6b4")
BEAR = [hexc("6e4224"), hexc("a06638"), hexc("d6a06a")]


def draw_toy_soldier(c):
    """A wind-up tin soldier: tall black shako with a gold badge and a red plume, red coat with gold
    buttons, blue trousers, black boots, and the gold key in his back."""
    c.rect(15, 1, 17, 2, RED[1])                       # plume
    c.rect(13, 3, 19, 9, hexc("2a2a3a"))               # shako
    c.rect(13, 3, 14, 9, hexc("4a4a62"))
    c.disc(16, 6, 1.3, GOLD[1])
    c.rect(13, 9, 19, 9, GOLD[0])                      # chin strap line
    c.rect(13, 10, 19, 13, SKIN)                       # face
    c.set(14, 11, OUTLINE); c.set(18, 11, OUTLINE)
    c.set(13, 12, hexc("f4a0a0")); c.set(19, 12, hexc("f4a0a0"))
    c.rect(12, 14, 20, 21, RED[1])                     # coat
    c.rect(19, 14, 20, 21, RED[0])
    c.rect(12, 14, 13, 17, RED[2])
    c.rect(10, 14, 11, 20, RED[1]); c.rect(21, 14, 22, 20, RED[0])   # arms
    c.rect(10, 21, 11, 21, SKIN); c.rect(21, 21, 22, 21, SKIN)
    c.rect(10, 14, 12, 15, GOLD[1]); c.rect(20, 14, 22, 15, GOLD[1])  # epaulettes
    for y in (15, 17, 19):
        c.set(16, y, GOLD[2])
    c.rect(12, 21, 20, 21, WHITE)                      # belt
    c.rect(13, 22, 19, 27, NAVY[1])                    # trousers
    c.rect(18, 22, 19, 27, NAVY[0])
    c.rect(16, 25, 16, 27, NAVY[0])
    c.rect(13, 28, 15, 29, hexc("2a2a3a")); c.rect(17, 28, 19, 29, hexc("2a2a3a"))   # boots
    c.line(9, 17, 6, 17, GOLD[0])                      # the wind-up key
    c.ring(4.5, 17, 2.4, 1.0, GOLD[1])


def draw_toy_blocks(c):
    """Three lettered wooden blocks, two on the floor and one on top: A in red, B in blue, C in yellow."""
    def block(x, y, colors, letter):
        dark, mid, light = colors
        c.poly([(x, y), (x + 3, y - 3), (x + 13, y - 3), (x + 10, y)], light)         # top
        c.poly([(x + 10, y), (x + 13, y - 3), (x + 13, y + 7), (x + 10, y + 10)], dark)  # side
        c.rect(x, y, x + 9, y + 9, mid)                                              # front
        rows = {"A": [" # ", "# #", "###", "# #", "# #"],
                "B": ["## ", "# #", "## ", "# #", "## "],
                "C": [" ##", "#  ", "#  ", "#  ", " ##"]}[letter]
        for dy, row in enumerate(rows):
            for dx, ch in enumerate(row):
                if ch == "#":
                    c.set(x + 3 + dx, y + 2 + dy, WHITE)
    block(1, 19, RED, "A")
    block(15, 19, BLUE, "B")
    block(8, 8, GOLD, "C")


def draw_toy_music_box(c):
    """An open wooden music box: velvet inside, a mirror in the raised lid, a gold keyhole and crank,
    and a note floating out."""
    wood = [hexc("6a3a1c"), hexc("a4602e"), hexc("d89058")]
    c.poly([(9, 14), (11, 4), (28, 4), (26, 14)], wood[1])              # the lid, raised
    c.poly([(11, 13), (12.5, 6), (26, 6), (24.5, 13)], hexc("bfe6ff"))   # its mirror
    c.line(14, 7, 13, 11, WHITE)
    c.poly([(5, 18), (9, 14), (26, 14), (22, 18)], hexc("8a1a3a"))      # velvet inside
    c.rect(5, 18, 22, 28, wood[1])                                       # front
    c.rect(5, 18, 22, 19, wood[2])
    c.poly([(22, 18), (26, 14), (26, 24), (22, 28)], wood[0])           # side
    c.rect(5, 20, 22, 20, GOLD[1])                                       # gold trim
    c.rect(13, 23, 14, 25, OUTLINE)                                      # keyhole
    c.set(13, 22, GOLD[1]); c.set(14, 22, GOLD[1])
    c.line(26, 20, 29, 20, GOLD[1])                                      # crank
    c.line(29, 20, 29, 17, GOLD[1])
    c.disc(29, 16, 1.2, GOLD[2])
    c.disc(4, 11, 1.6, GOLD[1])                                          # a note
    c.line(5.5, 4, 5.5, 11, GOLD[1])
    c.line(5.5, 4, 8, 6, GOLD[1])


def draw_toy_ball(c):
    """A red rubber ball with a yellow band and a white star, bouncing: two little marks below."""
    c.disc(16, 13, 9.6, RED[1])
    c.shade(lambda x, y, col: col == RED[1] and 11 <= y <= 15, GOLD[1])
    light_top_left(c, RED, 16, 13, 10)
    c.shade(lambda x, y, col: col == GOLD[1] and (x - 16) + (y - 13) > 6, GOLD[0])
    star_shape(c, 16, 13, 5, WHITE)
    c.disc(10, 7, 1.4, hexc("ffd0d0"))                                   # shine
    c.line(8, 28, 12, 26, hexc("9ccaff"))                                # bounce marks
    c.line(24, 28, 20, 26, hexc("9ccaff"))


def draw_toy_bear(c):
    """A sitting teddy bear: round ears, a tan muzzle and belly, button eyes and a red bow."""
    dark, mid, light = BEAR
    tan = hexc("eccb96")
    c.disc(9, 6, 3, mid); c.disc(23, 6, 3, mid)                          # ears
    c.disc(9, 6, 1.4, tan); c.disc(23, 6, 1.4, tan)
    c.ellipse(16, 23, 7.5, 6.5, mid)                                     # body
    c.ellipse(8, 21, 2.6, 4, mid); c.ellipse(24, 21, 2.6, 4, dark)       # arms
    c.ellipse(10, 28, 3.6, 2.6, mid); c.ellipse(22, 28, 3.6, 2.6, dark)  # feet
    c.disc(10, 28.5, 1.4, tan); c.disc(22, 28.5, 1.4, tan)
    c.ellipse(16, 24, 4, 3.6, tan)                                       # belly
    c.disc(16, 11, 7, mid)                                               # head
    c.shade(lambda x, y, col: col == mid and (x - 16) + (y - 11) > 7, dark)
    c.shade(lambda x, y, col: col == mid and (x - 16) + (y - 11) < -6, light)
    c.ellipse(16, 14, 3.4, 2.4, tan)                                     # muzzle
    c.rect(15, 13, 17, 13, OUTLINE)                                      # nose
    c.set(16, 14, OUTLINE)
    c.set(12, 10, OUTLINE); c.set(20, 10, OUTLINE)                       # button eyes
    c.poly([(11, 16), (16, 18), (11, 20)], RED[1])                       # bow
    c.poly([(21, 16), (16, 18), (21, 20)], RED[1])
    c.disc(16, 18, 1.2, RED[2])


def draw_toy_bubbles(c):
    """A bubble wand: a thin lilac stick with a knob, a small open ring at its tip, and a big bubble
    floating off it with two little ones, each with a white and a pink shine."""
    film = (205, 232, 255, 70)
    c.line(5, 29, 13, 18, LILAC[1], width=2)                             # the stick
    c.disc(5, 29, 1.8, LILAC[0])                                         # its knob
    c.ring(15, 15, 3.6, 2.2, LILAC[1])                                   # the ring
    c.disc(15, 15, 2.1, film)
    for (x, y, r) in ((23, 8, 6.2), (8, 9, 2.6), (28, 19, 2.2)):         # bubbles
        c.disc(x, y, r - 0.9, film)
        c.ring(x, y, r, r - 1, hexc("9ccaff"))
        c.set(x - r * 0.45, y - r * 0.45, WHITE)
        c.set(x + r * 0.4, y + r * 0.35, hexc("ffb4dc"))
    c.set(21, 6, WHITE); c.set(20, 7, WHITE)                             # the big one's bright shine



# ---------------------------------------------------------------- the staff line
# Fairyland Online's 棒類 (staffs): one every 5 levels. Each is a shaft plus a head.

def staff_line(c, shaft, head, band=None):
    c.line(7, 28, 20, 10, shaft[1], width=3)
    c.line(8, 28, 21, 11, shaft[0])
    c.line(6, 27, 19, 9, shaft[2])
    if band:
        c.line(9, 23, 11, 25, band, width=2)
        c.line(16, 14, 18, 16, band, width=2)
    head(c)


def knob(color):
    def draw(c):
        c.disc(21.5, 8.5, 3.4, color[1])
        c.disc(20.5, 7.5, 1.4, color[2])
    return draw


def gem_head(cap, gem):
    def draw(c):
        c.disc(21.5, 8.5, 4, cap[1])
        c.disc(21.5, 8.5, 2.6, gem[1])
        c.disc(20.8, 7.8, 1, gem[2])
    return draw


def star_head(color):
    def draw(c):
        star_shape(c, 22, 8, 6.5, color[1], inner=0.5)
        star_shape(c, 21.5, 7.5, 3, color[2], inner=0.5)
    return draw


def bamboo(c):
    for t in (0.3, 0.55, 0.8):   # the joints
        x, y = 7 + 13 * t, 28 - 18 * t
        c.line(x - 1.5, y - 1, x + 1.5, y + 1, GREEN[0], width=1)
    c.disc(21, 9, 2.2, GREEN[1])
    c.line(20, 8, 24, 5, GREEN[2])                         # a leaf


def blossom(c):
    for (x, y, col) in ((20, 9, hexc("f06292")), (23.5, 7, hexc("f48fb1")), (23, 11.5, hexc("f8bbd0"))):
        for dx, dy in ((0, -1.6), (1.6, 0), (0, 1.6), (-1.6, 0)):   # four petals
            c.disc(x + dx, y + dy, 1.2, col)
        c.set(x, y, GOLD[1])


def mace(color):
    def draw(c):
        c.disc(21.5, 8.5, 4.2, color[1])
        c.disc(20.5, 7.5, 1.6, color[2])
        for (x, y) in ((21.5, 3.5), (26.5, 8.5), (21.5, 13.5), (16.5, 8.5)):   # studs
            c.disc(x, y, 1.1, color[0])
    return draw


def cloud(c):
    puff = hexc("f4f8ff")
    for (x, y, r) in ((19.5, 9.5, 2.6), (22.5, 7.5, 3.2), (25, 10, 2.4), (22, 10.5, 2.6)):
        c.disc(x, y, r, puff)
    c.shade(lambda x, y, col: col == puff and y >= 11, hexc("b8d0ec"))    # shaded underside
    c.shade(lambda x, y, col: col == puff and y <= 5, WHITE)


def crown(c):
    c.poly([(16, 11), (17, 4), (19.5, 8), (21.5, 3), (23.5, 8), (26, 4), (27, 11)], GOLD[1])
    c.rect(16, 10, 27, 12, GOLD[0])
    c.disc(21.5, 9, 1.4, RED[1])


def aurora(c):
    c.disc(21.5, 8.5, 4.2, hexc("7af0ff"))
    c.shade(lambda x, y, col: col == hexc("7af0ff") and x > 22, hexc("b48cff"))
    c.shade(lambda x, y, col: col == hexc("7af0ff") and y > 10, hexc("8af0a0"))
    c.disc(20, 7, 1.2, WHITE)


def wisp(c):
    c.disc(21.5, 9.5, 3.4, hexc("b48cff"))
    c.poly([(19, 8), (22, 1), (25, 8)], hexc("b48cff"))
    c.disc(20.5, 9.5, 0.8, WHITE); c.disc(23, 9.5, 0.8, WHITE)


def lightning(c):
    c.disc(21.5, 8.5, 4, NAVY[1])
    c.poly([(22, 3), (19, 9), (22, 9), (20, 14), (25, 7), (22, 7)], hexc("ffd84a"))


def crescent(c):
    moon = hexc("fff4b0")
    c.disc(21, 9, 5.5, moon)
    for y in range(SIZE):          # bite out a second circle to leave a crescent
        for x in range(SIZE):
            if c.px[y][x] == moon and (x - 23.8) ** 2 + (y - 6.8) ** 2 <= 4.4 ** 2:
                c.px[y][x] = None
    c.shade(lambda x, y, col: col == moon and x + y > 30, hexc("e8c860"))
    c.set(26, 13, WHITE); c.set(27, 4, WHITE)


def dragon(c):
    c.disc(21.5, 8.5, 3.6, hexc("ff6a3a"))
    c.disc(20.5, 7.5, 1.3, hexc("ffd84a"))
    for (x0, y0, x1, y1) in ((17, 5, 15, 1), (26, 5, 28, 1)):   # horns
        c.line(x0, y0, x1, y1, GOLD[1], width=2)
    c.line(17, 12, 15, 15, GOLD[1], width=2); c.line(26, 12, 28, 15, GOLD[1], width=2)   # claws


BAMBOO = [hexc("3a8a3e"), hexc("6ac25a"), hexc("b8f08a")]
RATTAN = [hexc("9a7040"), hexc("d0a468"), hexc("f0d09a")]
PALE = [hexc("b09060"), hexc("e8cc9a"), hexc("fff0cc")]
BROWN = [hexc("5a3a1a"), hexc("8a5a2b"), hexc("b07a44")]
TEAK = [hexc("8a4a1a"), hexc("c0702a"), hexc("e8a050")]
DARKWOOD = [hexc("3a2616"), hexc("5e3e22"), hexc("86603a")]
REDWOOD = [hexc("8a2a1a"), hexc("c0482a"), hexc("e87a50")]
BLOODWOOD = [hexc("5a1010"), hexc("8e1f22"), hexc("c0443a")]
YEW = [hexc("4a2a5a"), hexc("7a4a8a"), hexc("aa7ac0")]
IRON = [hexc("4a5260"), hexc("7b8798"), hexc("b9c4d2")]
BRONZE = hexc("b0782a")

STAFFS = [  # id, level, name, shaft, head, band, description
    ("bamboo_staff", 1, "Green Bamboo Staff", BAMBOO, bamboo, None, "Cut fresh from the grove behind the village."),
    ("rattan_staff", 5, "Rattan Staff", RATTAN, knob(RATTAN), None, "Bends, but never breaks."),
    ("heavy_rattan_staff", 10, "Heavy Rattan Staff", RATTAN, knob(RATTAN), BRONZE, "Bound with bronze for a proper swing."),
    ("lightwood_staff", 15, "Lightwood Staff", PALE, knob(PALE), None, "Light as a feather, quick as a thought."),
    ("brownwood_staff", 20, "Brownwood Staff", BROWN, knob(BROWN), BRONZE, "Old wood that remembers every spell."),
    ("blossom_staff", 25, "Blossom Staff", BROWN, blossom, None, "Scatters petals with every cast."),
    ("teak_staff", 30, "Teak Staff", TEAK, gem_head(COPPER, TEAL), None, "Polished teak with a sea-green stone."),
    ("heavywood_staff", 35, "Heavywood Staff", DARKWOOD, mace(IRON), None, "Capped in iron. Mages don't only cast."),
    ("red_cypress_staff", 40, "Red Cypress Staff", REDWOOD, knob(REDWOOD), GOLD[1], "Smells of warm forests."),
    ("blood_cypress_staff", 45, "Dusk Cypress Staff", BLOODWOOD, gem_head(GOLD, RED), None, "Its ruby glows before a fight."),
    ("yew_staff", 50, "Yew Staff", YEW, gem_head(STEEL, VIOLET), None, "Purple yew, hard as stone."),
    ("purple_star_staff", 55, "Violet Comet Staff", YEW, star_head(LILAC), None, "A little star is caught at the tip."),
    ("armorbreaker_staff", 60, "Shellsplitter Staff", DARKWOOD, mace(STEEL), None, "Cracks shells and spells alike."),
    ("ironcrusher_staff", 65, "Anvil Staff", IRON, mace(IRON), None, "Heavy iron through and through."),
    ("red_cloud_staff", 70, "Crimson Mist Staff", REDWOOD, cloud, GOLD[1], "A cloud rests on it like a hat."),
    ("titanium_sceptre", 75, "Titanium Sceptre", STEEL, gem_head(STEEL, BLUE), None, "Cold, bright and nearly weightless."),
    ("emperor_sceptre", 80, "Emperor's Sceptre", GOLD, crown, None, "Once held by a fairy-tale king."),
    ("aurora_staff", 85, "Aurora Staff", SNOW, aurora, None, "Holds the northern lights."),
    ("ghost_staff", 90, "Wraithwood Staff", YEW, wisp, None, "Something friendly lives inside. Probably."),
    ("sky_ending_staff", 95, "Skyreach Staff", NAVY, lightning, GOLD[1], "Said to split the sky in two."),
    ("luna_staff", 100, "Luna Staff", STEEL, crescent, None, "Brightest under a full moon."),
    ("dragon_god_staff", 105, "Wyrmking Staff", BLOODWOOD, dragon, GOLD[1], "The staff of the Wyrmking himself."),
]

for _id, _level, _name, _shaft, _head, _band, _desc in STAFFS:
    globals()["draw_" + _id] = (lambda shaft, head, band: lambda c: staff_line(c, shaft, head, band))(_shaft, _head, _band)

# ---------------------------------------------------------------- the sword, axe and whip lines
# Also one every 5 levels, named after the original's 劍類, 斧類 and 鞭類 crafting tables where the
# names are known. Recipes live in content/items.json.

def sword_line(c, blade, guard, grip, length=13, width=4, wavy=False, gem=None, wings=False):
    bx, by = 11, 20
    tx, ty = bx + length, by - length
    if wavy:
        for i in range(0, 41):
            t = i / 40
            wobble = math.sin(t * math.pi * 3) * 1.3 * (1 - t * 0.6)
            c.disc(bx + (tx - bx) * t + wobble * 0.7, by + (ty - by) * t + wobble * 0.7, width / 2, blade[1])
    else:
        c.line(bx, by, tx, ty, blade[1], width=width)
    c.line(bx + 1, by - 1, tx - 1, ty + 1, blade[2])                  # edge shine
    c.line(bx + 1, by + 1, tx, ty + 2, blade[0])                      # shadow side
    if width >= 5:
        c.line(bx + 2, by, tx - 1, ty + 3, blade[0])
    c.line(7, 17, 14, 24, guard[1], width=3)                          # crossguard
    c.line(7, 16, 13, 22, guard[2])
    if wings:
        c.poly([(7, 17), (3, 12), (9, 15)], guard[1])
        c.poly([(14, 24), (19, 28), (16, 22)], guard[1])
    c.line(9, 22, 5, 26, grip[1], width=3)                            # grip
    c.line(9, 23, 5, 27, grip[0])
    c.disc(4.5, 27.5, 1.8, guard[1])                                  # pommel
    if gem:
        c.disc(10.5, 20.5, 1.4, gem[1])
        c.set(10, 20, gem[2])


def axe_line(c, head, handle, style="axe", gem=None):
    top = (23, 4) if style == "halberd" else (21, 7)
    c.line(8, 28, top[0], top[1], handle[1], width=3)
    c.line(9, 28, top[0] + 1, top[1] + 1, handle[0])
    if style == "hatchet":
        c.poly([(19, 6), (24, 2), (30, 6), (29, 14), (22, 12)], head[1])
        c.line(25, 3, 29, 7, head[2]); c.line(29, 8, 29, 13, head[2])
    elif style == "crescent":
        c.poly([(17, 6), (25, 1), (30, 6), (30, 13), (26, 18), (20, 14)], head[1])
        c.line(26, 2, 30, 7, head[2]); c.line(30, 8, 29, 13, head[2])
    else:
        c.poly([(18, 6), (27, 3), (29, 13), (22, 15)], head[1])
        c.line(27, 4, 29, 12, head[2])
    if style in ("double", "crescent"):
        c.poly([(19, 7), (10, 3), (8, 12), (16, 14)], head[1])
        c.line(10, 4, 8, 11, head[2])
    if style == "halberd":
        c.line(23, 4, 26, 0, head[2], width=2)                        # the spike
    edge = 39 if style == "hatchet" else 36
    c.shade(lambda x, y, col: col == head[1] and x + y > edge, head[0])
    c.shade(lambda x, y, col: col == head[1] and x < 13 and y > 9, head[0])
    c.rect(19, 7, 22, 12, handle[0])
    if gem:
        c.disc(20.5, 9.5, 1.5, gem[1])
        c.set(20, 9, gem[2])


def whip_line(c, leather, grip, turns=3.2, tip=None, gem=None, studs=None):
    points = 60
    for i in range(points):
        t = i / points * math.pi * turns
        r = 3 + i * 0.13
        x, y = 17 + r * math.cos(t), 14 + r * math.sin(t) * 0.8
        c.disc(x, y, 1.1, leather[1])
        if studs and i % 9 == 4:
            c.set(x, y, studs)
    c.shade(lambda x, y, col: col == leather[1] and x + y > 34, leather[0])
    c.shade(lambda x, y, col: col == leather[1] and x + y < 22, leather[2])
    if tip:
        c.disc(17 + 3, 14, 1.8, tip)
    c.line(6, 28, 11, 21, grip[1], width=3)
    c.line(7, 28, 12, 22, grip[0])
    c.rect(10, 20, 13, 22, GOLD[1])
    if gem:
        c.disc(5.5, 28.5, 1.7, gem[1])
        c.set(5, 28, gem[2])


# Metals, from the bronze of a first sword to the tungsten of the level-80 dragonslayer.
BRONZE3 = [hexc("7a4a1a"), hexc("b0782a"), hexc("e8b060")]
SILVER = [hexc("8a92a8"), hexc("d0d6e4"), hexc("ffffff")]
ALLOY = [hexc("4e6a66"), hexc("88aaa4"), hexc("d0eee8")]
PLATINUM = [hexc("8a84a8"), hexc("dcd8f0"), hexc("ffffff")]
TITANIUM = [hexc("3e5a84"), hexc("7c9cc8"), hexc("d4e6ff")]
TUNGSTEN = [hexc("3a3448"), hexc("6a6480"), hexc("b0aac8")]
DRAGONSTEEL = [hexc("5a1418"), hexc("a02a2a"), hexc("ff9a6a")]
ICE = [hexc("4a8ab0"), hexc("9ad8f0"), hexc("f0ffff")]
SHADOW = [hexc("2a1e3a"), hexc("4a3a6a"), hexc("9a8ac8")]
AMBER = [hexc("a0600a"), hexc("e8a020"), hexc("ffe08a")]
EMERALD = [hexc("0e6a3a"), hexc("22b060"), hexc("9af0b8")]
DIAMOND = [hexc("7ab0d0"), hexc("d8f4ff"), WHITE]
SHEEP = [hexc("c8b890"), hexc("f0e6cc"), WHITE]
COWHIDE = [hexc("5a3a22"), hexc("8a5a36"), hexc("c09068")]
DEER = [hexc("8a5a2a"), hexc("c08a4a"), hexc("ecc088")]
MARTEN = [hexc("4a3020"), hexc("6e4a30"), hexc("a07a5a")]
CROC = [hexc("2e4a22"), hexc("4e7a36"), hexc("9ac068")]

SWORDS = [  # id, level, name, drawing, description
    ("novice_bronze_sword", 1, "Novice Bronze Sword", dict(blade=BRONZE3, guard=BRONZE3, grip=LEATHER, length=11), "Every hero's first real blade."),
    ("bronze_sword", 5, "Bronze Sword", dict(blade=BRONZE3, guard=BRONZE3, grip=LEATHER, length=12), "Warm-coloured and dependable."),
    ("bronze_broadsword", 10, "Bronze Broadsword", dict(blade=BRONZE3, guard=BRONZE3, grip=LEATHER, width=5), "Wide enough to hide behind. Almost."),
    ("bronze_longsword", 15, "Bronze Longsword", dict(blade=BRONZE3, guard=GOLD, grip=LEATHER, length=15), "A longer reach for a braver fighter."),
    ("copper_sword", 20, "Copper Sword", dict(blade=COPPER, guard=COPPER, grip=LEATHER, length=13), "Polished until it glows like sunset."),
    ("iron_longsword", 25, "Iron Longsword", dict(blade=IRON, guard=IRON, grip=LEATHER, length=15), "Plain iron, honestly forged."),
    ("silver_inlaid_longsword", 30, "Silver-Inlaid Longsword", dict(blade=IRON, guard=SILVER, grip=NAVY, length=15, gem=SILVER), "Iron with a silver thread down the fuller."),
    ("silver_sword", 35, "Silver Sword", dict(blade=SILVER, guard=SILVER, grip=NAVY, length=14), "Ghosts don't like it one bit."),
    ("blue_frost_sword", 40, "Blue Frost Sword", dict(blade=ICE, guard=SILVER, grip=NAVY, length=15, gem=BLUE), "Cold to the touch, even in the desert."),
    ("tempered_steel_sword", 45, "Tempered Steel Sword", dict(blade=STEEL, guard=STEEL, grip=LEATHER, length=15, width=5), "Folded steel, quenched in snowmelt."),
    ("golden_sword", 50, "Golden Sword", dict(blade=GOLD, guard=GOLD, grip=RED, length=14, gem=RED), "Heavy, gaudy and surprisingly sharp."),
    ("silver_steel_sword", 55, "Silver Steel Sword", dict(blade=SILVER, guard=STEEL, grip=NAVY, length=15, width=5, gem=TEAL), "Steel for strength, silver for shine."),
    ("serpent_sword", 60, "Serpent Sword", dict(blade=STEEL, guard=GREEN, grip=GREEN, length=15, wavy=True, gem=EMERALD), "The blade winds like a snake."),
    ("alloy_shortsword", 65, "Alloy Shortsword", dict(blade=ALLOY, guard=ALLOY, grip=LEATHER, length=11, width=5), "Short, light and very quick."),
    ("platinum_longsword", 70, "Platinum Longsword", dict(blade=PLATINUM, guard=GOLD, grip=VIOLET, length=15, gem=VIOLET), "Never rusts, never dulls."),
    ("ironcleaver_sword", 75, "Ironcleaver", dict(blade=TITANIUM, guard=STEEL, grip=NAVY, length=15, width=5, wings=True), "Cuts through iron like bread."),
    ("tungsten_dragonslayer", 80, "Tungsten Dragonslayer", dict(blade=TUNGSTEN, guard=DRAGON, grip=DRAGON, length=15, width=5, wings=True, gem=RED), "Forged for one purpose."),
    ("aurora_blade", 85, "Aurora Blade", dict(blade=ICE, guard=LILAC, grip=VIOLET, length=15, gem=TEAL, wings=True), "Shimmers green and violet when swung."),
    ("phantom_blade", 90, "Phantom Blade", dict(blade=SHADOW, guard=LILAC, grip=SHADOW, length=15, wavy=True, gem=LILAC), "Hard to see, harder to dodge."),
    ("sky_splitter", 95, "Sky Splitter", dict(blade=SNOW, guard=GOLD, grip=NAVY, length=15, width=5, wings=True, gem=BLUE), "Leaves a line of clear sky behind it."),
    ("moonlight_sword", 100, "Moonlight Sword", dict(blade=PLATINUM, guard=SILVER, grip=NAVY, length=15, wings=True, gem=SNOW), "Brightest under a full moon."),
    ("dragon_god_sword", 105, "Wyrmking Sword", dict(blade=DRAGONSTEEL, guard=GOLD, grip=DRAGON, length=15, width=5, wings=True, gem=AMBER), "The sword of the Wyrmking himself."),
]

AXES = [
    ("novice_axe", 1, "Novice Axe", dict(head=BRONZE3, handle=WOOD, style="hatchet"), "Small, but it bites."),
    ("small_hatchet", 5, "Small Hatchet", dict(head=IRON, handle=WOOD, style="hatchet"), "Good for kindling and for goblins."),
    ("wood_axe", 10, "Woodcutter's Axe", dict(head=IRON, handle=WOOD), "Borrowed from the mill. Please return it."),
    ("hand_axe", 15, "Hand Axe", dict(head=BRONZE3, handle=TEAK), "Balanced for one hand."),
    ("copper_plate_axe", 20, "Copper Plate Axe", dict(head=COPPER, handle=TEAK), "A broad copper head riveted on tight."),
    ("light_war_axe", 25, "Light War Axe", dict(head=COPPER, handle=REDWOOD, style="double"), "Two edges, half the weight."),
    ("windchaser_axe", 30, "Windchaser Axe", dict(head=SILVER, handle=REDWOOD, gem=TEAL), "Whistles as it flies."),
    ("iron_bead_axe", 35, "Iron Bead Axe", dict(head=IRON, handle=REDWOOD, gem=IRON), "An iron bead weights the blow."),
    ("curved_war_axe", 40, "Curved War Axe", dict(head=IRON, handle=YEW, style="crescent"), "The long curve bites deep."),
    ("steel_axe", 45, "Steel Axe", dict(head=STEEL, handle=YEW), "Plain, hard and heavy."),
    ("twin_blade_axe", 50, "Twin-Blade Axe", dict(head=STEEL, handle=DARKWOOD, style="double"), "Dwarves swear by it."),
    ("long_war_axe", 55, "Long War Axe", dict(head=GOLD, handle=DARKWOOD, style="halberd"), "Keeps big monsters at arm's length."),
    ("grey_dragon_axe", 60, "Grey Dragon Axe", dict(head=ALLOY, handle=DARKWOOD, style="crescent", gem=RED), "Carved with a sleeping grey dragon."),
    ("overlord_axe", 65, "Overlord Axe", dict(head=ALLOY, handle=IRON, style="double", gem=GOLD), "Made for someone who gives orders."),
    ("alloy_twin_war_axe", 70, "Alloy Twin War Axe", dict(head=PLATINUM, handle=IRON, style="double", gem=VIOLET), "Two alloy heads, both hungry."),
    ("titanium_dwarf_axe", 75, "Titanium Dwarf Axe", dict(head=TITANIUM, handle=BLOODWOOD, style="crescent"), "Dwarf-made. It says so on the handle."),
    ("tungsten_skybreaker", 80, "Tungsten Skybreaker", dict(head=TUNGSTEN, handle=BLOODWOOD, style="halberd", gem=BLUE), "Said to crack the sky itself."),
    ("aurora_axe", 85, "Aurora Axe", dict(head=ICE, handle=SNOW, style="crescent", gem=TEAL), "Holds the northern lights in its edge."),
    ("phantom_axe", 90, "Phantom Axe", dict(head=SHADOW, handle=YEW, style="double", gem=LILAC), "It swings a moment before you do."),
    ("thunder_god_axe", 95, "Thunder God Axe", dict(head=GOLD, handle=NAVY, style="crescent", gem=BLUE), "Every blow comes with a rumble."),
    ("luna_axe", 100, "Luna Axe", dict(head=PLATINUM, handle=STEEL, style="crescent", gem=SNOW), "Its edge is a slice of the moon."),
    ("dragon_god_axe", 105, "Wyrmking Axe", dict(head=DRAGONSTEEL, handle=BLOODWOOD, style="double", gem=AMBER), "The axe of the Wyrmking himself."),
]

WHIPS = [
    ("sheepskin_whip", 1, "Sheepskin Whip", dict(leather=SHEEP, grip=WOOD, turns=2.4), "Soft enough to tickle."),
    ("handy_whip", 5, "Handy Whip", dict(leather=SHEEP, grip=LEATHER, turns=2.8), "Just the right length."),
    ("cowhide_whip", 10, "Cowhide Whip", dict(leather=COWHIDE, grip=WOOD), "Cracks loud enough to startle birds."),
    ("strong_ox_whip", 15, "Strong Ox Whip", dict(leather=COWHIDE, grip=LEATHER, studs=STEEL[1]), "Braided from the toughest hide."),
    ("whitewood_whip", 20, "Whitewood Whip", dict(leather=COWHIDE, grip=PALE, tip=CLOTH[1]), "A pale poplar handle, well worn."),
    ("cactus_whip", 25, "Cactus Whip", dict(leather=GREEN, grip=PALE, studs=GREEN[2]), "Prickly. Hold it by the handle."),
    ("teak_whip", 30, "Teak Whip", dict(leather=DEER, grip=TEAK), "A teak handle and a deerskin lash."),
    ("golden_deer_whip", 35, "Golden Deer Whip", dict(leather=DEER, grip=TEAK, tip=GOLD[1]), "Tipped in gold, like a deer's antler."),
    ("red_cypress_whip", 40, "Red Cypress Whip", dict(leather=DEER, grip=REDWOOD, tip=RED[1]), "Smells of warm forests."),
    ("deerhide_lash", 45, "Deerhide Lash", dict(leather=DEER, grip=YEW, turns=3.6, studs=GOLD[1]), "Long enough to reach the back row."),
    ("blue_sky_whip", 50, "Blue Sky Whip", dict(leather=BLUE, grip=PALE, gem=BLUE), "The colour of a clear morning."),
    ("amber_whip", 55, "Amber Whip", dict(leather=MARTEN, grip=RATTAN, gem=AMBER), "An amber stone set in the pommel."),
    ("power_whip", 60, "Power Whip", dict(leather=MARTEN, grip=TEAK, gem=RED, studs=GOLD[1]), "Hits harder than it has any right to."),
    ("hardened_whip", 65, "Hardened Whip", dict(leather=CROC, grip=DARKWOOD, gem=DIAMOND, studs=STEEL[1]), "Crocodile hide, hard as armour."),
    ("crocodile_whip", 70, "Crocodile Whip", dict(leather=CROC, grip=DARKWOOD, turns=3.6, tip=CROC[2], gem=EMERALD), "Snaps shut like jaws."),
    ("thorn_whip", 75, "Thorn Whip", dict(leather=GREEN, grip=BLOODWOOD, studs=RED[1], gem=RED), "Grown, not braided."),
    ("azure_dragon_whip", 80, "Azure Dragon Whip", dict(leather=TEAL, grip=BLOODWOOD, tip=TEAL[2], gem=BLUE, studs=SNOW[2]), "Scaled like the Azure Dragon of the east."),
    ("aurora_whip", 85, "Aurora Whip", dict(leather=ICE, grip=SNOW, tip=LILAC[2], gem=TEAL), "Trails light when it cracks."),
    ("phantom_whip", 90, "Phantom Whip", dict(leather=SHADOW, grip=YEW, tip=LILAC[1], gem=LILAC), "It cracks without a sound."),
    ("storm_whip", 95, "Storm Whip", dict(leather=NAVY, grip=NAVY, tip=hexc("ffd84a"), gem=GOLD, studs=hexc("ffd84a")), "Lightning follows the lash."),
    ("luna_whip", 100, "Luna Whip", dict(leather=SILVER, grip=STEEL, turns=3.6, tip=hexc("fff4b0"), gem=SNOW), "Silver as moonlight on water."),
    ("dragon_god_whip", 105, "Wyrmking Whip", dict(leather=DRAGON, grip=BLOODWOOD, turns=3.6, tip=GOLD[1], gem=AMBER, studs=GOLD[1]), "The whip of the Wyrmking himself."),
]

for _id, _level, _name, _args, _desc in SWORDS:
    globals()["draw_" + _id] = (lambda a: lambda c: sword_line(c, **a))(_args)
for _id, _level, _name, _args, _desc in AXES:
    globals()["draw_" + _id] = (lambda a: lambda c: axe_line(c, **a))(_args)
for _id, _level, _name, _args, _desc in WHIPS:
    globals()["draw_" + _id] = (lambda a: lambda c: whip_line(c, **a))(_args)


# ---------------------------------------------------------------- crafting materials
# The original's woodcutting (伐木), mining and smelting (挖礦, 冶煉) and hides, dropped by monsters here.

def log(c, bark, core):
    c.line(7, 23, 22, 12, bark[1], width=9)
    c.shade(lambda x, y, col: col == bark[1] and x + y > 32, bark[0])
    c.shade(lambda x, y, col: col == bark[1] and x + y < 26, bark[2])
    for (x0, y0, x1, y1) in ((6, 20, 11, 17), (10, 25, 15, 22), (14, 17, 18, 14)):   # bark grain
        c.line(x0, y0, x1, y1, bark[0])
    c.disc(23, 11.5, 4.3, core[1])                                                     # cut end
    c.ring(23, 11.5, 3, 2.2, core[0])
    c.set(23, 11, core[0])
    c.shade(lambda x, y, col: col == core[1] and x + y < 32, core[2])


def bamboo_bundle(c):
    for dx in (0, 5, 10):
        c.line(6 + dx, 28, 12 + dx, 4, BAMBOO[1], width=3)
        c.line(7 + dx, 28, 13 + dx, 4, BAMBOO[0])
        for t in (0.3, 0.6, 0.85):
            c.line(5 + dx + 6 * t, 28 - 24 * t, 8 + dx + 6 * t, 28 - 24 * t, BAMBOO[0])
    c.line(20, 6, 26, 3, BAMBOO[2], width=2)


def rattan_coil(c):
    c.ring(16, 17, 10, 6.5, RATTAN[1], ry_scale=0.8)
    c.ring(16, 17, 8.2, 7.4, RATTAN[0], ry_scale=0.8)
    c.shade(lambda x, y, col: col == RATTAN[1] and y < 13, RATTAN[2])
    c.line(24, 14, 29, 9, RATTAN[1], width=2)


def ingot(c, metal):
    dark, mid, light = metal
    c.poly([(10, 10), (22, 10), (25, 15), (7, 15)], light)         # top
    c.poly([(7, 15), (25, 15), (28, 25), (4, 25)], mid)           # sloped front
    c.shade(lambda x, y, col: col == mid and x > 22, dark)
    c.rect(4, 24, 28, 25, dark)
    c.line(11, 12, 17, 12, WHITE)
    c.line(8, 17, 7, 22, light)


def gem(c, color):
    dark, mid, light = color
    c.poly([(10, 8), (22, 8), (28, 14), (16, 28), (4, 14)], mid)
    c.poly([(10, 8), (22, 8), (28, 14), (4, 14)], light)
    c.shade(lambda x, y, col: col == mid and x > 17, dark)
    c.line(4, 14, 28, 14, dark)
    c.line(13, 8, 11, 14, mid); c.line(19, 8, 21, 14, mid)
    c.set(11, 10, WHITE); c.set(12, 10, WHITE)


def banded(c, color):
    """A tumbled stone with curved stripes (agate)."""
    dark, mid, light = color
    for y in range(SIZE):
        for x in range(SIZE):
            if ((x - 16) / 11) ** 2 + ((y - 17) / 9) ** 2 <= 1:
                band = int(math.hypot(x - 8, y - 27) / 2.6) % 3
                c.px[y][x] = (mid, light, mid)[band] if x + y < 38 else (dark, mid, dark)[band]
    c.set(11, 11, WHITE); c.set(12, 11, WHITE)


def pearl(c):
    pearl_c = [hexc("c07a3a"), hexc("ffb070"), hexc("fff0d0")]
    c.disc(16, 17, 9, pearl_c[1])
    light_top_left(c, pearl_c, 16, 17, 9)
    c.disc(12.5, 13.5, 2, WHITE)
    for (x0, y0, x1, y1) in ((6, 27, 9, 22), (26, 27, 23, 22)):   # a dragon's claws hold it
        c.line(x0, y0, x1, y1, GOLD[1], width=2)


def hide(c, color, spots=None, scales=False):
    dark, mid, light = color
    c.poly([(9, 5), (23, 5), (26, 9), (24, 15), (28, 23), (22, 28), (16, 25), (10, 28), (4, 23), (8, 15), (6, 9)], mid)
    c.shade(lambda x, y, col: col == mid and x > 20, dark)
    c.shade(lambda x, y, col: col == mid and x < 11 and y < 14, light)
    if spots:
        for (x, y, r) in ((12, 11, 2.2), (19, 17, 2.8), (13, 21, 1.8), (21, 9, 1.4)):
            c.disc(x, y, r, spots)
    if scales:
        for y in range(8, 25, 4):
            for x in range(8 + (y // 4 % 2) * 2, 25, 4):
                if c.get(x, y) in (mid, dark, light):
                    c.set(x, y, dark); c.set(x + 1, y + 1, light)


MATERIALS = [  # id, kind, level, name, drawing, description
    ("bamboo", "wood", 1, "Bamboo", bamboo_bundle, "Green bamboo canes. Wood for beginner weapons."),
    ("rattan", "wood", 5, "Rattan", rattan_coil, "Bendy rattan, good for handles."),
    ("poplar", "wood", 10, "White Poplar", lambda c: log(c, PALE, CLOTH), "Pale, light wood."),
    ("teak", "wood", 20, "Teak", lambda c: log(c, TEAK, RATTAN), "Oily wood that never warps."),
    ("red_cypress", "wood", 30, "Red Cypress", lambda c: log(c, REDWOOD, ORANGE), "Warm red wood with a forest smell."),
    ("yew", "wood", 40, "Yew", lambda c: log(c, YEW, LILAC), "Purple-hearted and hard as stone."),
    ("ebony", "wood", 50, "Ebony", lambda c: log(c, DARKWOOD, BROWN), "Almost black, and very heavy."),
    ("hemlock", "wood", 60, "Iron Hemlock", lambda c: log(c, IRON, PALE), "Grey bark, iron-hard core."),
    ("red_yew", "wood", 70, "Red Yew", lambda c: log(c, BLOODWOOD, REDWOOD), "The rarest wood in the kingdom."),
    ("bronze_ingot", "metal", 1, "Bronze Ingot", lambda c: ingot(c, BRONZE3), "Smelted from copper and tin."),
    ("copper_ingot", "metal", 15, "Copper Ingot", lambda c: ingot(c, COPPER), "Soft and shiny."),
    ("iron_ingot", "metal", 25, "Iron Ingot", lambda c: ingot(c, IRON), "The blacksmith's bread and butter."),
    ("silver_ingot", "metal", 30, "Silver Ingot", lambda c: ingot(c, SILVER), "Bright, and hated by ghosts."),
    ("gold_ingot", "metal", 40, "Gold Ingot", lambda c: ingot(c, GOLD), "Heavy and handsome."),
    ("steel_ingot", "metal", 45, "Steel Ingot", lambda c: ingot(c, STEEL), "Iron, made much tougher."),
    ("alloy_steel", "metal", 60, "Alloy Steel", lambda c: ingot(c, ALLOY), "Steel mixed with something secret."),
    ("platinum_ingot", "metal", 70, "Platinum Ingot", lambda c: ingot(c, PLATINUM), "Never tarnishes."),
    ("titanium_alloy", "metal", 75, "Titanium Alloy", lambda c: ingot(c, TITANIUM), "Light as wood, strong as steel."),
    ("tungsten_alloy", "metal", 80, "Tungsten Alloy", lambda c: ingot(c, TUNGSTEN), "Dense enough to dent an anvil."),
    ("dragon_steel", "metal", 90, "Dragon Steel", lambda c: ingot(c, DRAGONSTEEL), "Forged in dragon fire. Still warm."),
    ("amber", "gem", 10, "Amber", lambda c: gem(c, AMBER), "Honey-coloured and warm."),
    ("cats_eye", "gem", 25, "Cat's Eye", lambda c: gem(c, [hexc("6a7a1a"), hexc("b8c83a"), hexc("f0ff9a")]), "Seems to follow you around the room."),
    ("emerald", "gem", 35, "Emerald", lambda c: gem(c, EMERALD), "Deep forest green."),
    ("azurite", "gem", 45, "Azurite", lambda c: gem(c, BLUE), "The blue of a clear sky."),
    ("topaz", "gem", 50, "Topaz", lambda c: gem(c, [hexc("c0a010"), hexc("ffe84a"), hexc("fffac0")]), "A little piece of sunshine."),
    ("agate", "gem", 55, "Agate", lambda c: banded(c, [hexc("a0304a"), hexc("e06a7a"), hexc("ffc0c8")]), "Banded in orange and cream."),
    ("diamond", "gem", 65, "Diamond", lambda c: gem(c, DIAMOND), "The hardest thing there is."),
    ("chalcedony", "gem", 75, "Chalcedony", lambda c: gem(c, TEAL), "Milky blue-green jade."),
    ("dragon_pearl", "gem", 90, "Dragon Pearl", pearl, "A dragon guarded this for a thousand years."),
    ("sheepskin", "hide", 1, "Sheepskin", lambda c: hide(c, SHEEP), "Soft and woolly."),
    ("cowhide", "hide", 10, "Cowhide", lambda c: hide(c, CLOTH, spots=COWHIDE[1]), "Tough, patchy leather."),
    ("deer_hide", "hide", 30, "Deer Hide", lambda c: hide(c, DEER, spots=CLOTH[2]), "Supple and strong."),
    ("marten_fur", "hide", 50, "Marten Fur", lambda c: hide(c, MARTEN), "Glossy dark fur."),
    ("crocodile_hide", "hide", 60, "Crocodile Hide", lambda c: hide(c, CROC, scales=True), "Hard and scaly."),
    ("dragon_scale", "hide", 75, "Dragon Scale", lambda c: hide(c, DRAGON, scales=True), "Fireproof, and very rare."),
]

for _id, _kind, _level, _name, _draw, _desc in MATERIALS:
    globals()["draw_" + _id] = _draw


DRAWINGS = {name[5:]: fn for name, fn in globals().items() if name.startswith("draw_")}
# Not drawn here: the Potion is a Retro Diffusion sprite (rd_pro__fantasy) and the Hi-Potion,
# Ether and Hi-Ether are palette swaps of it (`derive` in art/assets.json).

PROMPTS = {  # for a later Retro Diffusion upgrade (python3 tools/rd.py generate item_<id>)
    "potion": "round red healing potion bottle with a cork",
    "hi_potion": "big pink healing potion bottle with a gold star label",
    "ether": "blue mana potion in a cone flask with a cork",
    "hi_ether": "violet mana potion in a cone flask with a gold star",
    "seal_stone": "teal crystal sealing stone with a white spiral rune",
    "homeward_feather": "white feather with a golden quill and a soft glow",
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
    "toy_soldier": "tin toy soldier in a red coat with a wind-up key",
    "toy_blocks": "three stacked wooden toy blocks with letters",
    "toy_music_box": "open wooden music box with a golden crank",
    "toy_ball": "bouncy red rubber ball with a yellow band and a star",
    "toy_bear": "brown teddy bear with a red bow",
    "toy_bubbles": "bubble wand blowing shiny bubbles",
}


for _id, _level, _name, *_rest in STAFFS:
    PROMPTS[_id] = f"{_name.lower()}, a magic staff"


for _table, _what in ((SWORDS, "a sword"), (AXES, "an axe"), (WHIPS, "a whip")):
    for _id, _level, _name, *_rest in _table:
        PROMPTS[_id] = f"{_name.lower()}, {_what}"
for _id, _kind, _level, _name, *_rest in MATERIALS:
    PROMPTS[_id] = f"{_name.lower()}, a crafting material"


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
