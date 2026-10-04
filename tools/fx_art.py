#!/usr/bin/env python3
"""Pixel art for the few battle marks that aren't light, drawn in code like tools/item_art.py (free):
writes art/sprites/fx_<name>.png. The elemental spells themselves are drawn in light and colour
(Fairyland/Battle/ElementEffects.swift); these are poison's bubbles (AilmentEffects.swift) and the
marks of poison (a green drop) and a curse (a violet arrow) by a fighter's HP bar.

    python3 tools/fx_art.py                  # every sprite
    python3 tools/fx_art.py --sheet out.png  # also a 4x contact sheet to look at
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from item_art import SPRITES, encode_png, hexc  # noqa: E402

WATER = [hexc("0e3c74"), hexc("1c6ab0"), hexc("48a8f0"), hexc("a8dcff"), hexc("ffffff")]


class Canvas:
    """A width × height pixel canvas (item_art's Canvas is square)."""

    def __init__(self, width, height):
        self.w, self.h = width, height
        self.px = [[None] * width for _ in range(height)]

    def set(self, x, y, color):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color

    def png(self, scale=1):
        rows = []
        for y in range(self.h * scale):
            row = bytearray([0])
            for x in range(self.w * scale):
                row += bytes(self.px[y // scale][x // scale] or (0, 0, 0, 0))
            rows.append(bytes(row))
        return encode_png(self.w * scale, self.h * scale, b"".join(rows))


def pixels(rows, palette):
    """A canvas from rows of characters, each a key of `palette` ('.' is empty)."""
    c = Canvas(len(rows[0]), len(rows))
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            if key != ".":
                c.px[y][x] = palette[key]
    return c


# ---------------------------------------------------------------- poison

def bubble():
    c = Canvas(9, 9)
    for i in range(48):
        a = i / 48 * math.tau
        c.set(4 + math.cos(a) * 3.4, 4 + math.sin(a) * 3.4, WATER[3])
    c.set(3, 2, WATER[4])
    c.set(2, 3, WATER[4])
    return c


# ---------------------------------------------------------------- the dark arts' marks

POISON = [hexc("1e4a14"), hexc("4a9a2a"), hexc("8ee04a"), hexc("d4ff9a")]   # line, dark, mid, light
CURSE = [hexc("2a1240"), hexc("5a2e8a"), hexc("9a62d8"), hexc("dcc0ff")]


def status_poison():
    """Poison's mark by a fighter's HP bar: a sickly green drop."""
    return pixels([
        "...o...",
        "..oMo..",
        ".oMMMo.",
        "oMLMMDo",
        "oLMMMDo",
        "oMMMDDo",
        ".oDDDo.",
        "..ooo..",
    ], {"o": POISON[0], "D": POISON[1], "M": POISON[2], "L": POISON[3]})


def status_curse():
    """A curse's mark: a violet arrow pointing down, for weaker hits."""
    return pixels([
        "..ooo..",
        "..oLo..",
        "..oMo..",
        "oooMooo",
        "oLMMMDo",
        ".oMMDo.",
        "..oDo..",
        "...o...",
    ], {"o": CURSE[0], "D": CURSE[1], "M": CURSE[2], "L": CURSE[3]})


# ---------------------------------------------------------------- all of it

def sprites():
    return {
        "fx_bubble": bubble(),
        "fx_status_poison": status_poison(),
        "fx_status_curse": status_curse(),
    }


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
