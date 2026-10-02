#!/usr/bin/env python3
"""Previews worn armour on the hero's walk sheet: the same algorithm as Fairyland/Art/GearOverlay.swift
(chain links, open vests, pauldrons and a helmet, robe hems, a cape and hood, blue speed boots), to
tune it without a Mac.

    python3 tools/gear_preview.py /tmp/gear.png      # every armour in items.json on every race, four facings each

Needs pillow + numpy.
"""
import colorsys
import numpy as np

FRAME = 48
DIRS = ['up', 'right', 'down', 'left']


def hsv(c):
    return colorsys.rgb_to_hsv(*c)


def outfit_mask(base):
    """Outfit pixels on the original sheet: green (hue 85-170), saturated."""
    h, w = base.shape[:2]
    m = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            r, g, b, a = base[y, x]
            if a < 0.5:
                continue
            hh, s, v = hsv((r, g, b))
            m[y, x] = 85 <= hh * 360 <= 170 and s >= 0.3
    return m


def shade(c, k):
    return np.clip(np.array(c[:3]) * k, 0, 1)


def mix(c, d, t):
    return np.clip(np.array(c[:3]) * (1 - t) + np.array(d[:3]) * t, 0, 1)


def hexc(s):
    v = int(s.lstrip('#'), 16)
    return np.array([(v >> 16) & 255, (v >> 8) & 255, v & 255]) / 255


def is_hair(p):
    """Hair on the original sheet: the same rule content/appearance.json recolours (hue 12-58, bright)."""
    if p[3] < 0.5:
        return False
    hh, s, v = hsv(tuple(p[:3]))
    return 12 <= hh * 360 <= 58 and s >= 0.55 and v >= 0.55


def is_skin(p):
    if p[3] < 0.5:
        return False
    hh, s, v = hsv(tuple(p[:3]))
    return hh * 360 <= 40 and 0.15 < s < 0.55 and v > 0.6


def crown(f):
    """Top of the head: the first row with at least four hair pixels (skips a lone spike's tip)."""
    for y in range(FRAME):
        if sum(is_hair(f[y, x]) for x in range(FRAME)) >= 4:
            return y
    return None


def face_drop(base):
    """Rows from the crown to the top of the face, measured on the first facing-down frame."""
    f = base[2 * FRAME:3 * FRAME, 0:FRAME]
    top = crown(f)
    for y in range(top or 0, FRAME):
        run = 0
        for x in range(FRAME):
            run = run + 1 if is_skin(f[y, x]) else 0
            if run >= 3:                     # three skin pixels side by side: the forehead, not an ear
                return y - top
    return 10


def hairish(p):
    """A darker hair strand: the same hues, dimmer. Only counts when it touches the bright hair."""
    if p[3] < 0.5 or is_skin(p):
        return False
    hh, s, v = hsv(tuple(p[:3]))
    return 5 <= hh * 360 <= 62 and s >= 0.3 and v >= 0.2


def hair_mask(b, top, brow):
    """Every hair pixel of the head: bright hair on the scalp, flooded out through darker strands
    (long hair, sideburns, a beard). A belt buckle or boots don't touch it, so they stay out."""
    m = np.zeros((FRAME, FRAME), bool)
    stack = [(y, x) for y in range(top, brow) for x in range(FRAME) if is_hair(b[y, x])]
    for y, x in stack:
        m[y, x] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < FRAME and 0 <= xx < FRAME and not m[yy, xx] and hairish(b[yy, xx]):
                m[yy, xx] = True
                stack.append((yy, xx))
    return m


def bearded(base, drop):
    """Whether the hero has a beard: plenty of hair under the chin on the first facing-down frame."""
    f = base[2 * FRAME:3 * FRAME, 0:FRAME]
    top = crown(f)
    if top is None:
        return False
    hair = hair_mask(f, top, top + drop)
    xs = [x for y in range(top, top + drop) for x in range(FRAME) if is_hair(f[y, x])]
    cx = (min(xs) + max(xs)) / 2
    chin = top + drop + 5
    return sum(hair[y, x] for y in range(chin, min(FRAME, chin + 6)) for x in range(FRAME) if abs(x - cx) < 4) >= 12


def cover_head(f, b, facing, drop, wear, mid, acc, has_beard=False):
    """A helmet (plate) or hood (cloak) over the hair: a smooth dome from the crown down to the chin
    that leaves the face open. Tufts outside the dome are erased, and long hair below it is covered
    too (a mail neck guard, or the hood's cloth); a beard in front of the face stays."""
    top = crown(b)
    if top is None:
        return
    brow = top + drop                        # first row of the face
    chin = brow + 5
    hood = wear == 'cloak'
    hair = hair_mask(b, top, brow)
    xs = [x for y in range(top, brow) for x in range(FRAME) if is_hair(b[y, x])]
    x0, x1 = min(xs), max(xs)
    cx = (x0 + x1) / 2
    half = (x1 - x0) / 2 + (1.0 if hood else 0.5)
    lid = top - (1 if hood else 0)
    reach = brow - lid                       # the dome's height above the brow
    side = {'right': 1, 'left': -1}.get(facing, 0)   # which way the face looks

    def inside(x, y):
        if y < lid or y > chin:
            return False
        dy = max(0, brow - y) / reach
        return ((x - cx) / half) ** 2 + dy ** 2 <= 1

    def beard(x, y):
        """Hair in front of the face, below the eyes: a beard or moustache, which stays."""
        if not has_beard or y < brow + 3 or facing == 'up':
            return False
        if side:
            return (x - cx) * side > -1
        return abs(x - cx) < half - 3

    dark, light = shade(mid, 0.55), mix(mid, (1, 1, 1), 0.4)
    outline = np.array([0.16, 0.12, 0.18])
    painted = np.zeros((FRAME, FRAME), bool)
    for y in range(0, min(FRAME, chin + 1)):
        for x in range(FRAME):
            p = b[y, x]
            if inside(x, y):
                if y >= brow and facing != 'up':
                    # The face stays open: only hair, and empty pixels beside or behind it, get covered.
                    empty = p[3] < 0.5
                    behind = (x - cx) * side < 0 if side else abs(x - cx) >= half - 2
                    if not ((hair[y, x] and not beard(x, y)) or (empty and behind)):
                        continue
                lit = (x - cx) / half - (brow - y) / reach * 0.8
                c = light if lit < -0.55 else (dark if lit > 0.55 else mid)
                f[y, x, :3] = c
                f[y, x, 3] = 1
                painted[y, x] = True
            elif y < brow and p[3] >= 0.5 and not is_skin(p):
                f[y, x, 3] = 0                # a tuft poking out of the helmet
    # Long hair below the dome or behind the head: a mail neck guard, or the hood's cloth.
    for y in range(brow, FRAME):
        for x in range(FRAME):
            if painted[y, x] or not hair[y, x] or beard(x, y):
                continue
            if hood:
                f[y, x, :3] = mid if (x + 2 * y) % 7 else dark
            else:
                f[y, x, :3] = mid if (x + y) % 2 == 0 else dark
            painted[y, x] = True
    # Dark outline round the outside, and an inner fold where it meets the face.
    rim = []
    for y in range(FRAME):
        for x in range(FRAME):
            near = [(yy, xx) for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1))
                    if 0 <= yy < FRAME and 0 <= xx < FRAME]
            if not painted[y, x] and f[y, x, 3] < 0.5 and any(painted[q] for q in near):
                rim.append((y, x, outline))
            elif painted[y, x] and y >= brow - 1 and facing != 'up' and any(
                    not painted[q] and f[q][3] >= 0.5 and not hair[q] for q in near):
                rim.append((y, x, dark if hood else acc))
    for y, x, c in rim:
        f[y, x, :3] = c
        f[y, x, 3] = 1
    if hood:
        # A soft point at the top of the hood, falling back behind the head.
        tip = int(np.floor(cx - 2 * side + 0.5))
        if lid >= 1 and 0 <= tip < FRAME:
            f[lid - 1, tip, :3] = outline
            f[lid - 1, tip, 3] = 1
            f[lid, tip, :3] = mid
            f[lid, tip, 3] = 1
    else:
        # A crest over the top, from the brow back.
        ridge = int(np.floor(cx - side + 0.5))
        for y in range(lid, brow - 1):
            if painted[y, ridge]:
                f[y, ridge, :3] = acc


def apply(base, recolored, wear=None, accent=None, boots=False):
    out = recolored.copy()
    mask = outfit_mask(base)
    acc = hexc(accent) if accent else np.array([0.95, 0.78, 0.25])
    drop = face_drop(base)
    beard = bearded(base, drop)
    for row, facing in enumerate(DIRS):
        for col in range(base.shape[1] // FRAME):
            oy, ox = row * FRAME, col * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            m = mask[oy:oy + FRAME, ox:ox + FRAME]
            a = base[oy:oy + FRAME, ox:ox + FRAME, 3] > 0.5
            if not m.any():
                continue
            ys, xs = np.nonzero(m)
            y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
            yb = np.nonzero(a.any(1))[0].max()          # lowest opaque row (feet)
            mid = np.median(f[m][:, :3], axis=0)
            dark, light = shade(mid, 0.55), mix(mid, (1, 1, 1), 0.35)
            outline = np.array([0.16, 0.12, 0.18])

            def put(x, y, c, only_empty=False):
                if 0 <= x < FRAME and 0 <= y < FRAME and (not only_empty or not a[y, x]):
                    f[y, x, :3] = c
                    f[y, x, 3] = 1

            if wear == 'mail':
                for y, x in zip(ys, xs):
                    if (x + y) % 2 == 0:
                        f[y, x, :3] = light
                    elif (x + 2 * y) % 4 == 1:
                        f[y, x, :3] = dark
            elif wear == 'vest':
                if facing == 'down':
                    cx = (x0 + x1) // 2
                    for y, x in zip(ys, xs):
                        if abs(x - cx) <= 1 and y < y1 - 1:
                            f[y, x, :3] = (0.93, 0.88, 0.76) if x != cx else (0.8, 0.74, 0.62)
                    put(cx - 2, y0 + 3, acc)
                    put(cx + 2, y0 + 3, acc)
            elif wear == 'plate':
                # Round pauldrons on the shoulders: a dome with a rim, lit from the top left.
                pads = {'down': [x0 + 1, x1 - 1], 'up': [x0 + 1, x1 - 1], 'right': [x1 - 1], 'left': [x0 + 1]}[facing]
                for px in pads:
                    for dy in range(-1, 3):
                        for dx in range(-2, 3):
                            if dx * dx + (dy - 0.6) ** 2 * 1.6 <= 4.4:
                                c = light if dy <= 0 else mid
                                if dy == 2 or abs(dx) == 2 and dy >= 1:
                                    c = dark
                                put(px + dx, y0 + dy, c)
                    put(px - 1, y0 - 1, (1, 1, 1))
                if facing in ('down', 'up'):
                    cx = (x0 + x1) // 2
                    for y in range(y0 + 3, y1):
                        if m[y, cx]:
                            f[y, cx, :3] = light
                    if facing == 'down':
                        put(cx, y0 + 4, acc)
            elif wear == 'robe':
                # The hem drops past the knees: below the tunic, fill to just above the boots.
                bottom = {}
                for y, x in zip(ys, xs):
                    bottom[x] = max(bottom.get(x, 0), y)
                hem_top = max(bottom.values())
                hem_bottom = yb - 2
                cols = [x for x in bottom if bottom[x] >= hem_top - 2]
                lx, rx = min(cols), max(cols)
                for y in range(hem_top + 1, hem_bottom + 1):
                    flare = (y - hem_top + 1) // 2
                    for x in range(lx - flare, rx + flare + 1):
                        c = mid
                        if x in (lx - flare, rx + flare):
                            c = dark
                        put(x, y, c)
                for x in range(lx - (hem_bottom - hem_top + 1) // 2, rx + (hem_bottom - hem_top + 1) // 2 + 1):
                    put(x, hem_bottom, dark)
                    put(x, hem_bottom - 1, acc)
            elif wear == 'cloak':
                top, bot = y0, yb - 3
                cx = (x0 + x1) // 2
                if facing == 'up':
                    # From behind: the cape covers the back, widening toward the hem.
                    for y in range(top, bot + 1):
                        w = (y - top) // 3
                        for x in range(x0 - w, x1 + w + 1):
                            edge = x in (x0 - w, x1 + w) or y == bot
                            put(x, y, outline if edge else (light if x == cx - 2 else mid))
                else:
                    # From the front or side: the cape shows just outside the body's outline.
                    for y in range(top + 1, bot + 1):
                        filled = np.nonzero(a[y])[0]
                        if len(filled) == 0:
                            continue
                        left, right = filled.min(), filled.max()
                        flare = (y - top) // 5
                        if facing == 'down':
                            spots = [(left - 1 - flare, True), (right + 1 + flare, True)]
                            spots += [(left - flare, False)] if flare else []
                            spots += [(right + flare, False)] if flare else []
                        elif facing == 'right':
                            spots = [(left - 1 - flare, True)] + [(left - k, False) for k in range(0, flare + 1)]
                        else:
                            spots = [(right + 1 + flare, True)] + [(right + k, False) for k in range(0, flare + 1)]
                        for x, outer in spots:
                            put(x, y, outline if outer else mid, only_empty=True)
                    if facing == 'down':
                        put(cx, top, acc); put(cx - 1, top, acc); put(cx, top + 1, shade(acc, 0.7))
            if wear in ('plate', 'cloak'):
                cover_head(f, base[oy:oy + FRAME, ox:ox + FRAME], facing, drop, wear, mid, acc, beard)
            if boots:
                for y in range(max(0, yb - 5), yb + 1):
                    for x in range(FRAME):
                        if not a[y, x]:
                            continue
                        hh, s, v = hsv(tuple(f[y, x, :3]))
                        if 0.02 <= hh <= 0.12 and s > 0.35 and v < 0.75:
                            r, g, b = colorsys.hsv_to_rgb(0.58, min(1, s * 0.9), min(1, v * 1.5))
                            f[y, x, :3] = (r, g, b)
    return out


def main(out):
    import json
    import pathlib
    import sys
    from PIL import Image
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import palette_preview as pp
    root = pathlib.Path(__file__).resolve().parent.parent
    items = [i for i in json.load(open(root / "content" / "items.json"))["items"] if i["type"] == "armor"]
    bodies = ["player_walk", "elf_walk", "dwarf_walk"]
    zoom = 3
    sheet = Image.new("RGB", (len(bodies) * 4 * 48 * zoom, len(items) * 48 * zoom), (80, 130, 80))
    for k, body in enumerate(bodies):
        base = pp.raw(body)
        for r, item in enumerate(items):
            dressed = pp.recolor(base, item["recolor"]) if item.get("recolor") else base.copy()
            dressed = apply(base, dressed, item.get("wear"), item.get("accent"))
            image = Image.fromarray((np.clip(dressed, 0, 1) * 255).astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(i['id'] for i in items)}")


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else "gear-preview.png")
