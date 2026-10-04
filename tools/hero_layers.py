#!/usr/bin/env python3
"""Splits each race's walk sheets into paper-doll layers, like Fairyland Online dressed its heroes:

    art/sprites/body_<race>.png          the body, bald (the hair taken off, the scalp drawn in)
    art/sprites/locks_<race>.png         hair that stays with the body whatever the style: a lock
                                         over the shoulder, a beard (copied, so the body stays whole)
    art/sprites/hair_<style>_<race>.png  every hairstyle, fitted to every race's head
    art/sprites/hood_<race>.png          a hood and a helmet sized to the bare head; the game
    art/sprites/helmet_<race>.png        colours them like the armour (see MARKERS below)

The game stacks body + locks + hair (or body + locks + hood/helmet: no hair pokes through). The
body is recoloured like the whole sheet used to be (skin, hair, outfit); the locks and hair layers
hold nothing but hair, so the hair colour reaches every shade of them (appearance.json
`hairLayer`). A gender with its own sheet (classes.json `sheets`) gets
the same set with a _<gender> suffix (body_elf_male.png, ...). Rerun after changing a walk sheet:

    python3 tools/hero_layers.py            # writes the PNGs
    python3 tools/hero_layers.py --preview /tmp/layers.png

Needs pillow + numpy.
"""
import argparse
import colorsys
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import palette_preview as pp  # noqa: E402

F = 48
DIRS = ["up", "right", "down", "left"]
OUTLINE = np.array([0.16, 0.12, 0.18])
# Hairstyles, each taken from the race whose sheet it was drawn on.
STYLES = {"spiky": "human", "long": "elf", "crop": "dwarf"}
# Headgear is drawn in magenta, which no recolour touches (skin 5-45°, hair 12-58°, outfit 85-170°)
# and no hero sheet uses. The game paints soft magenta (saturation 0.6) in the armour's colour,
# keeping the shade (value: 0.92 light, 0.7 mid, 0.45 dark), and full magenta in its trim colour.
# Fairyland/Art/GearOverlay.swift and tools/gear_preview.py read these.
MARK_HUE = 300 / 360
# Sheets whose hair rises well above the skull (a bun): the top of the head is the first row with
# this many hair pixels instead of four, so the bald scalp sits on the real head, not the bun.
TUFTS = {"human_female_walk": 8}
# Locks are looked for down to this many rows below the brow (over the shoulders, not the belt).
LOCK_DEPTH = 14


def hsv(p):
    return colorsys.rgb_to_hsv(*p[:3])


def opaque(p):
    return p[3] >= 0.5


def is_hair(p):
    """Bright hair: the rule content/appearance.json recolours (hue 12-58, saturated, bright)."""
    if not opaque(p):
        return False
    h, s, v = hsv(p)
    return 12 <= h * 360 <= 58 and s >= 0.55 and v >= 0.55


def is_skin(p):
    if not opaque(p):
        return False
    h, s, v = hsv(p)
    return h * 360 <= 40 and 0.15 < s < 0.55 and v > 0.6


def is_outfit(p):
    if not opaque(p):
        return False
    h, s, _ = hsv(p)
    return 85 <= h * 360 <= 170 and s >= 0.3


def hairish(p):
    """A darker strand of hair: same hues, dimmer. Only counts when it touches the bright hair."""
    if not opaque(p) or is_skin(p):
        return False
    h, s, v = hsv(p)
    return 5 <= h * 360 <= 62 and s >= 0.3 and v >= 0.2


def lockish(p):
    """Any shade of hair: gold to deep red, highlight to shadow. Bright reds only when strong (an
    auburn highlight), so pink ears and cheeks stay skin."""
    if not opaque(p) or is_skin(p):
        return False
    h, s, v = hsv(p)
    h *= 360
    if 5 <= h <= 62:
        return s >= 0.3 and v >= 0.12
    if h >= 345 or h < 5:
        return s >= (0.6 if v >= 0.6 else 0.4) and v >= 0.12
    return False


def dark(p):
    return opaque(p) and max(p[:3]) < 0.35


def frame(sheet, row, col):
    return sheet[row * F:(row + 1) * F, col * F:(col + 1) * F]


def crown(f, width=4):
    """Top of the head: the first row with `width` hair pixels (four skips a lone spike's tip; a
    sheet with a bun on top asks for more, see TUFTS)."""
    for y in range(F):
        if sum(is_hair(f[y, x]) for x in range(F)) >= width:
            return y
    return None


def skin_run(f, y):
    """The widest run of skin on row y, as (left, right)."""
    best, run = None, []
    for x in range(F + 1):
        if x < F and is_skin(f[y, x]):
            run.append(x)
        elif run:
            if best is None or len(run) > best[1] - best[0] + 1:
                best = (run[0], run[-1])
            run = []
    return best


def flood(f, seeds, ok):
    m = np.zeros((F, F), bool)
    stack = list(seeds)
    for y, x in stack:
        m[y, x] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < F and 0 <= xx < F and not m[yy, xx] and ok(f[yy, xx]):
                m[yy, xx] = True
                stack.append((yy, xx))
    return m


def neighbours8(y, x):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if (dy or dx) and 0 <= y + dy < F and 0 <= x + dx < F:
                yield y + dy, x + dx


class Head:
    """Where one frame's head is: crown, brow (first row of the face), face span, skull ellipse."""

    def __init__(self, f, facing, drop, half, tuft=4):
        self.top = crown(f, tuft)
        self.brow = self.top + drop
        self.facing = facing
        xs = [x for y in range(self.top, self.brow) for x in range(F) if is_hair(f[y, x])]
        cx = (min(xs) + max(xs)) / 2
        runs = [r for r in (skin_run(f, y) for y in range(self.brow, self.brow + 4)) if r]
        self.face = (min(r[0] for r in runs), max(r[1] for r in runs)) if runs else None
        if self.face and facing in ("right", "left"):
            front = self.face[1] if facing == "right" else self.face[0]
            cx = front - (half - 1.5) if facing == "right" else front + (half - 1.5)
        elif self.face and facing == "down":
            cx = (self.face[0] + self.face[1]) / 2
        self.cx = cx
        self.half = half
        self.ry = half * 0.9
        self.cy = self.brow + 1          # the skull's widest row, just below the brow

    def inside(self, x, y, grow=0.0):
        return ((x - self.cx) / (self.half + grow)) ** 2 + ((y - self.cy) / (self.ry + grow)) ** 2 <= 1


class Race:
    def __init__(self, race_id, sheet_id):
        self.id = race_id
        self.sheet = pp.raw(sheet_id)
        self.tuft = TUFTS.get(sheet_id, 4)
        down = frame(self.sheet, DIRS.index("down"), 0)
        top = crown(down, self.tuft)
        # The brow: the first row of face, i.e. skin carrying on into the row below (a stray
        # skin-coloured highlight in the hair doesn't count).
        self.drop = next(y - top for y in range(top, F - 1)
                         if (r := skin_run(down, y)) and r[1] - r[0] >= 2
                         and (n := skin_run(down, y + 1)) and n[1] - n[0] >= 1)
        face = skin_run(down, top + self.drop + 1) or skin_run(down, top + self.drop)
        self.half = (face[1] - face[0]) / 2 + 3.5
        self.skin = np.median([down[y, x, :3] for y in range(top + self.drop, top + self.drop + 4)
                               for x in range(F) if is_skin(down[y, x])], axis=0)
        self.beard = self._bearded(down, top)
        self.heads = {}
        self.body = self.sheet.copy()
        self.hair = np.zeros_like(self.sheet)
        self.locks = np.zeros_like(self.sheet)
        for row, facing in enumerate(DIRS):
            for col in range(self.sheet.shape[1] // F):
                self._split(row, col, facing)

    def _bearded(self, down, top):
        brow = top + self.drop
        hair = flood(down, [(y, x) for y in range(top, brow) for x in range(F) if is_hair(down[y, x])], hairish)
        r = skin_run(down, brow + 1)
        cx = (r[0] + r[1]) / 2 if r else F / 2
        chin = brow + 5
        return sum(hair[y, x] for y in range(chin, chin + 6) for x in range(F) if abs(x - cx) < 4) >= 12

    def is_beard(self, head, x, y):
        if not self.beard or head.facing == "up" or y < head.brow + 3:
            return False
        if head.facing == "down":
            return abs(x - head.cx) < head.half - 1
        side = 1 if head.facing == "right" else -1
        return (x - head.cx) * side > -2

    def _split(self, row, col, facing):
        f = frame(self.sheet, row, col)
        body = frame(self.body, row, col)
        hair_layer = frame(self.hair, row, col)
        head = Head(f, facing, self.drop, self.half, self.tuft)
        self.heads[row, col] = head
        # Seed from the very top of the hair, so a bun above the skull (TUFTS) comes off too.
        hair = flood(f, [(y, x) for y in range(crown(f), head.brow) for x in range(F) if is_hair(f[y, x])], hairish)
        for y in range(F):
            for x in range(F):
                if hair[y, x] and self.is_beard(head, x, y):
                    hair[y, x] = False
        # The hair's own outline goes with it: dark pixels that only touch hair (or nothing).
        lines = np.zeros((F, F), bool)
        for y in range(F):
            for x in range(F):
                if dark(f[y, x]) and not hair[y, x]:
                    near = [q for q in neighbours8(y, x) if opaque(f[q]) and not dark(f[q])]
                    if near and all(hair[q] for q in near) and y < head.brow + 12:
                        lines[y, x] = True
        take = hair | lines
        hair_layer[take] = f[take]
        body[take] = 0
        if self.tuft != 4:
            # A bun's hair tie and highlights don't count as hair: clear whatever is left above the skull.
            body[:max(0, int(head.cy - head.ry) - 1)] = 0
        self._scalp(body, head)
        self._patch(body, head, take, row, col)
        self._locks(f, body, head, take, row, col)

    def _locks(self, f, body, head, taken, row, col):
        """Hair the body keeps (a lock over the shoulder, a beard): every hair-coloured pixel still
        joined to the hair that came off, down to the shoulders. Copied, not cut, so the body
        stays whole; the game draws them over it in the hair colour."""
        candidate = np.zeros((F, F), bool)
        for y in range(min(F, head.brow + LOCK_DEPTH + 1)):
            for x in range(F):
                candidate[y, x] = lockish(f[y, x]) and np.array_equal(body[y, x], f[y, x])
        seeds = [(y, x) for y, x in zip(*np.nonzero(candidate)) if any(taken[q] for q in neighbours8(y, x))]
        locks = np.zeros((F, F), bool)
        stack = list(seeds)
        for y, x in stack:
            locks[y, x] = True
        while stack:
            y, x = stack.pop()
            for q in neighbours8(y, x):
                if candidate[q] and not locks[q]:
                    locks[q] = True
                    stack.append(q)
        frame(self.locks, row, col)[locks] = f[locks]

    def _scalp(self, body, head):
        """Draws the bare skull round the face, shaded, with an outline, and joins the ears to it."""
        light, shade = mix(self.skin, (1, 1, 1), 0.25), self.skin * 0.82
        painted = np.zeros((F, F), bool)

        def paint(x, y):
            lit = (x - head.cx) / head.half - (head.cy - y) / head.ry * 0.7
            body[y, x, :3] = light if lit < -0.6 else (shade if lit > 0.45 else self.skin)
            body[y, x, 3] = 1
            painted[y, x] = True

        for y in range(F):
            for x in range(F):
                if head.inside(x, y) and not (y >= head.brow and opaque(body[y, x])):
                    paint(x, y)               # above the face, or round it where hair used to be
        # Ears (skin left beside the skull): bridge each one back to the head.
        for y in range(head.brow - 4, head.brow + 3):
            for x in range(F):
                if is_skin(body[y, x]) and not head.inside(x, y, 0.5):
                    step = 1 if x < head.cx else -1
                    xx = x + step
                    while 0 <= xx < F and not painted[y, xx] and not head.inside(xx, y) and abs(xx - x) < 6:
                        if not opaque(body[y, xx]) or dark(body[y, xx]):
                            paint(xx, y)
                        xx += step
        # Specks left floating where the hair was (an ear tip's outline): gone.
        for y in range(F):
            for x in range(F):
                if opaque(body[y, x]) and not painted[y, x] and y < head.brow and not any(
                        opaque(body[q]) for q in neighbours8(y, x)):
                    body[y, x, 3] = 0
        outline(body, painted)

    def _patch(self, body, head, taken, row, col):
        """Fills what the hair used to hide below the head (a long-haired back, the neck) with the
        same part of the human body; anything outside it becomes see-through."""
        if TEMPLATE is None or TEMPLATE is self:
            return
        holes = taken & np.array([[not opaque(body[y, x]) for x in range(F)] for y in range(F)])
        holes[:head.cy + 1] = False
        if not holes.any():
            return
        t = frame(TEMPLATE.body, row, col)
        dx = int(round(centre_x(body) - centre_x(t)))
        dy = feet(body) - feet(t)
        outfit_mid = np.median([p[:3] for p in body.reshape(-1, 4) if is_outfit(p)], axis=0)
        t_mid = np.median([p[:3] for p in t.reshape(-1, 4) if is_outfit(p)], axis=0)
        for y, x in zip(*np.nonzero(holes)):
            ty, tx = y - dy, x - dx
            if not (0 <= ty < F and 0 <= tx < F) or not opaque(t[ty, tx]):
                continue
            p = t[ty, tx]
            if is_outfit(p):
                c = np.clip(outfit_mid * (max(p[:3]) / max(1e-3, max(t_mid))), 0, 1)
            elif is_skin(p):
                c = np.clip(self.skin * (max(p[:3]) / max(1e-3, max(TEMPLATE.skin))), 0, 1)
            else:
                c = p[:3]
            body[y, x, :3] = c
            body[y, x, 3] = 1


def mix(c, d, t):
    return np.clip(np.array(c[:3]) * (1 - t) + np.array(d[:3]) * t, 0, 1)


def outline(img, painted):
    for y in range(F):
        for x in range(F):
            if painted[y, x] or opaque(img[y, x]):
                continue
            if any(painted[q] for q in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1))
                   if 0 <= q[0] < F and 0 <= q[1] < F):
                img[y, x, :3] = OUTLINE
                img[y, x, 3] = 1


def centre_x(f):
    xs = [x for y in range(F) for x in range(F) if is_outfit(f[y, x])]
    return sum(xs) / len(xs) if xs else F / 2


def feet(f):
    return max(y for y in range(F) if any(opaque(f[y, x]) for x in range(F)))


def fit_hair(source, target):
    """The source race's hair, moved frame by frame onto the target race's head."""
    out = np.zeros_like(target.sheet)
    for (row, col), head in target.heads.items():
        src = source.heads[row, col]
        dx = int(round(head.cx - src.cx))
        dy = head.brow - src.brow
        s = frame(source.hair, row, col)
        o = frame(out, row, col)
        for y, x in zip(*np.nonzero(s[:, :, 3] > 0.5)):
            if 0 <= y + dy < F and 0 <= x + dx < F:
                o[y + dy, x + dx] = s[y, x]
    return out


def marker(v, s=0.6):
    return np.array(colorsys.hsv_to_rgb(MARK_HUE, s, v))



def headgear(race, kind):
    """A hood or helmet hugging the bare head, face left open, in marker colours."""
    out = np.zeros_like(race.sheet)
    hood = kind == "hood"
    grow = 1.6 if hood else 1.0
    for (row, col), head in race.heads.items():
        o = frame(out, row, col)
        body = frame(race.body, row, col)
        chin = head.brow + (5 if hood else 3)
        top = head.cy - head.ry - grow
        side = {"right": 1, "left": -1}.get(head.facing, 0)
        painted = np.zeros((F, F), bool)
        for y in range(F):
            for x in range(F):
                if y > chin:
                    continue
                inside = head.inside(x, y, grow) if y <= head.cy else abs(x - head.cx) <= head.half + grow - 0.5
                if not inside or y < top:
                    continue
                if y >= head.brow and head.facing != "up":
                    face = head.face or (int(head.cx) - 2, int(head.cx) + 2)
                    if side == 0 and face[0] <= x <= face[1]:
                        continue              # the face stays open
                    if side and (x - (face[0] if side > 0 else face[1])) * side >= 0:
                        continue
                lit = (x - head.cx) / (head.half + grow) - (head.cy - y) / (head.ry + grow) * 0.8
                v = 0.92 if lit < -0.55 else (0.45 if lit > 0.55 else 0.7)
                o[y, x, :3] = marker(v)
                o[y, x, 3] = 1
                painted[y, x] = True
        # A darker fold where it meets the face; a point at the back of a hood.
        for y in range(F):
            for x in range(F):
                if painted[y, x] and y >= head.brow - 1 and head.facing != "up" and any(
                        not painted[q] and opaque(body[q]) for q in ((y, x - 1), (y, x + 1), (y + 1, x))
                        if 0 <= q[1] < F and q[0] < F):
                    o[y, x, :3] = marker(0.4) if hood else marker(0.9, 1.0)
        if hood:
            tip_x = int(np.floor(head.cx - 2.5 * side + 0.5))
            tip_y = int(np.ceil(top)) - 1
            if 0 <= tip_y < F and 0 <= tip_x < F:
                o[tip_y, tip_x, :3] = marker(0.7)
                o[tip_y, tip_x, 3] = 1
                painted[tip_y, tip_x] = True
        else:
            # Trim: a band along the brow and a crest over the top.
            ridge = int(np.floor(head.cx - side + 0.5))
            for y in range(F):
                if painted[y, ridge] and y < head.brow - 1:
                    o[y, ridge, :3] = marker(0.9, 1.0)
            if head.facing != "up":
                for x in range(F):
                    if painted[head.brow - 1, x]:
                        o[head.brow - 1, x, :3] = marker(0.9, 1.0)
        outline(o, painted)
    return out


TEMPLATE = None


def build():
    global TEMPLATE
    races_json = json.load(open(ROOT / "content" / "classes.json"))["races"]
    sheets = {r["id"]: r.get("art") or "player_walk" for r in races_json}
    races = {}
    TEMPLATE = races["human"] = Race("human", sheets["human"])
    for rid, sheet in sheets.items():
        if rid not in races:
            races[rid] = Race(rid, sheet)
    # A gender with its own walk sheet (classes.json `sheets`) gets its own set: <layer>_<race>_<gender>.
    for r in races_json:
        for gender, sheet in (r.get("sheets") or {}).items():
            races[f"{r['id']}_{gender}"] = Race(r["id"], sheet)
    layers = {}
    for rid, race in races.items():
        layers[f"body_{rid}"] = race.body
        layers[f"locks_{rid}"] = race.locks
        layers[f"hood_{rid}"] = headgear(race, "hood")
        layers[f"helmet_{rid}"] = headgear(race, "helmet")
        for style, source in STYLES.items():
            layers[f"hair_{style}_{rid}"] = race.hair if source == rid else fit_hair(races[source], race)
    return races, layers


def to_image(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")


def stack(*layers):
    out = to_image(layers[0])
    for layer in layers[1:]:
        out.alpha_composite(to_image(layer))
    return np.asarray(out).astype(float) / 255


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--preview", help="write a contact sheet here instead of the PNGs")
    args = parser.parse_args()
    races, layers = build()
    if not args.preview:
        for name, layer in layers.items():
            to_image(layer).save(ROOT / "art" / "sprites" / f"{name}.png")
        print(f"wrote {len(layers)} layers to art/sprites/: {', '.join(sorted(layers))}")
        return
    zoom = 3
    combos = [("body", None)] + [(f"hair_{s}", s) for s in STYLES] + [("hood", None), ("helmet", None)]
    sheet = Image.new("RGB", (len(combos) * 4 * F * zoom, len(races) * F * zoom), (80, 130, 80))
    for r, (rid, race) in enumerate(races.items()):
        for k, (name, style) in enumerate(combos):
            under = (layers[f"body_{rid}"], layers[f"locks_{rid}"])
            img = stack(*under) if name == "body" else stack(*under, layers[f"{name}_{rid}"])
            im = to_image(img)
            for c, row in enumerate((2, 1, 0, 3)):
                fr = im.crop((0, row * F, F, row * F + F)).resize((F * zoom, F * zoom), Image.NEAREST)
                sheet.paste(fr, ((k * 4 + c) * F * zoom, r * F * zoom), fr)
    sheet.save(args.preview)
    print(f"wrote {args.preview}: columns {', '.join(n for n, _ in combos)}; rows {', '.join(races)}")


if __name__ == "__main__":
    main()
