#!/usr/bin/env python3
"""Makes a stockier, shorter copy of a 4×4 walk sheet (48 px frames): a free stand-in for dwarf
art until Retro Diffusion draws the real thing.

    python3 tools/dwarfify.py player_walk dwarf_walk

Each frame is squashed from the feet up (shorter) and widened around its middle (chubbier),
with nearest-neighbour sampling so the pixels stay crisp.
"""

import pathlib
import struct
import sys
import zlib


SPRITES = pathlib.Path(__file__).resolve().parent.parent / "art" / "sprites"
FRAME = 48
TALL = 0.80     # height kept
WIDE = 1.22     # body widened by this much
HEAD = 0.42     # the top part of the sprite (the head) is squashed less, so it stays big


def encode_png(width, height, raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def read_png(path):
    data = path.read_bytes()
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and colour == 6, "expects 8-bit RGBA"
        elif kind == b"IDAT":
            idat += body
    raw, stride, rows, prev, i = zlib.decompress(idat), width * 4, [], bytearray(width * 4), 0
    for _ in range(height):
        kind, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b, c = prev[x], (prev[x - 4] if x >= 4 else 0)
            if kind == 1: line[x] = (line[x] + a) & 255
            elif kind == 2: line[x] = (line[x] + b) & 255
            elif kind == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x:x + 4]) for x in range(0, stride, 4)])
        prev = line
    return width, height, rows


def stockier(frame):
    """frame: 48 rows of 48 RGBA tuples → the same size, shorter and wider, feet on the same line."""
    opaque = [(x, y) for y in range(FRAME) for x in range(FRAME) if frame[y][x][3]]
    if not opaque:
        return frame
    top, bottom = min(y for _, y in opaque), max(y for _, y in opaque)
    left, right = min(x for x, _ in opaque), max(x for x, _ in opaque)
    cx = (left + right + 1) / 2
    height = bottom - top + 1
    head = int(height * HEAD)
    # Rows of the result, from the feet up: the body is squashed hard, the head only a little.
    body_src = height - head
    body_dst = max(1, round(body_src * TALL * 0.9))
    head_dst = max(1, round(head * 0.95))
    src_rows = [bottom - int((i + 0.5) * body_src / body_dst) for i in range(body_dst)]
    src_rows += [top + head - 1 - int((i + 0.5) * head / head_dst) for i in range(head_dst)]
    out = [[(0, 0, 0, 0)] * FRAME for _ in range(FRAME)]
    for i, sy in enumerate(src_rows):
        dy = bottom - i
        if dy < 0:
            break
        is_head = i >= body_dst
        wide = 1.08 if is_head else WIDE
        for dx in range(FRAME):
            sx = int(round(cx + (dx + 0.5 - cx) / wide - 0.5))
            if 0 <= sx < FRAME:
                out[dy][dx] = frame[sy][sx]
    return out


def main(source, target):
    width, height, rows = read_png(SPRITES / f"{source}.png")
    result = [[None] * width for _ in range(height)]
    for fy in range(0, height, FRAME):
        for fx in range(0, width, FRAME):
            frame = [row[fx:fx + FRAME] for row in rows[fy:fy + FRAME]]
            for y, row in enumerate(stockier(frame)):
                result[fy + y][fx:fx + FRAME] = row
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in result)
    (SPRITES / f"{target}.png").write_bytes(encode_png(width, height, raw))
    print(f"wrote art/sprites/{target}.png from {source}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
