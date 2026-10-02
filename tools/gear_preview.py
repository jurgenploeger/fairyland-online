#!/usr/bin/env python3
"""Previews worn armour on the hero: the same algorithm as Fairyland/Art/GearOverlay.swift (chain
links, open vests, pauldrons, robe hems, capes, helmets and hoods, blue speed boots), on the same
paper-doll layers the game stacks (tools/hero_layers.py), to tune it without a Mac.

    python3 tools/gear_preview.py /tmp/gear.png      # every armour in items.json on every race

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


def apply(base, recolored, wear=None, accent=None, boots=False):
    out = recolored.copy()
    mask = outfit_mask(base)
    acc = hexc(accent) if accent else np.array([0.95, 0.78, 0.25])
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
            # A helmet or hood (hero_layers.py) comes in magenta: soft magenta takes the armour's
            # colour, keeping its shade, and full magenta the trim.
            for y in range(FRAME):
                for x in range(FRAME):
                    if not a[y, x]:
                        continue
                    hh, s, v = hsv(tuple(base[oy + y, ox + x, :3]))
                    if abs(hh * 360 - 300) < 12 and s > 0.3:
                        f[y, x, :3] = acc if s > 0.85 else (light if v > 0.82 else (dark if v < 0.55 else mid))
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
    races = json.load(open(root / "content" / "classes.json"))["races"]
    zoom = 3
    sheet = Image.new("RGB", (len(races) * 4 * 48 * zoom, len(items) * 48 * zoom), (80, 130, 80))
    for k, race in enumerate(races):
        for r, item in enumerate(items):
            # The layers the game stacks (GameSession.layers): body, then hair or headgear.
            head = {"plate": "helmet", "cloak": "hood"}.get(item.get("wear"))
            top = f"{head}_{race['id']}" if head else f"hair_{race['hair']}_{race['id']}"
            base = Image.open(root / "art" / "sprites" / f"body_{race['id']}.png").convert("RGBA")
            base.alpha_composite(Image.open(root / "art" / "sprites" / f"{top}.png").convert("RGBA"))
            base = np.asarray(base).astype(float) / 255
            dressed = pp.recolor(base, item["recolor"]) if item.get("recolor") else base.copy()
            dressed = apply(base, dressed, item.get("wear"), item.get("accent"))
            image = Image.fromarray((np.clip(dressed, 0, 1) * 255).astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(i['id'] for i in items)} on {', '.join(r['id'] for r in races)}")


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else "gear-preview.png")
