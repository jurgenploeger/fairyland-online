#!/usr/bin/env python3
"""Previews each map's colour palette (theme.palette in content/maps.json) without a Mac build.

    pip install pillow numpy
    python3 tools/palette_preview.py                 # every map → palette-preview.png
    python3 tools/palette_preview.py frog_swamp moonglow -o swamp.png

Each row is a small patch of the map drawn roughly the way the game does it (isometric ground,
path, accent patch, pond, scattered props, the hero, the ambience tint and vignette): left without
the palette, right with it. The grade mirrors Recolor.grade in Fairyland/Art/Recolor.swift.
"""
import json, random, sys, math, colorsys
import numpy as np
from PIL import Image
R = str(__import__('pathlib').Path(__file__).resolve().parent.parent) + '/'
assets = {a['id']: a for a in json.load(open(R + 'art/assets.json'))['assets']}
maps = {m['id']: m for m in json.load(open(R + 'content/maps.json'))['maps']}

# ---------- colour maths (mirrors Recolor.swift) ----------
def rgb2hsv(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx = c.max(-1); mn = c.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    safe = np.where(d > 0, d, 1)
    hr = (60 * ((g - b) / safe)) % 360
    hg = 60 * ((b - r) / safe + 2)
    hb = 60 * ((r - g) / safe + 4)
    h = np.where(mx == r, hr, np.where(mx == g, hg, hb))
    h = np.where(d > 0, h, 0) % 360
    s = np.where(mx > 0, d / np.where(mx > 0, mx, 1), 0)
    return h, s, mx

def hsv2rgb(h, s, v):
    c = v * s; x = c * (1 - np.abs((h / 60) % 2 - 1)); m = v - c
    z = np.zeros_like(h)
    conds = [h < 60, h < 120, h < 180, h < 240, h < 300]
    r = np.select(conds, [c, x, z, z, x], c); g = np.select(conds, [x, c, c, x, z], z); b = np.select(conds, [z, z, x, c, c], x)
    return np.stack([r + m, g + m, b + m], -1)

def recolor(img, rules):
    """img float RGBA 0..1 (straight alpha)."""
    rgb = img[..., :3]; a = img[..., 3]
    h, s, v = rgb2hsv(rgb)
    done = np.zeros(a.shape, bool) | (a == 0)
    nh, ns, nv = h.copy(), s.copy(), v.copy()
    for r in rules:
        m = (s >= r.get('minSaturation', 0.15)) & (s <= r.get('maxSaturation', 1)) & (v >= r.get('minValue', 0)) & (v <= r.get('maxValue', 1))
        if 'hue' in r:
            lo, hi = r['hue']
            m &= ((h >= lo) & (h <= hi)) if lo <= hi else ((h >= lo) | (h <= hi))
        m &= ~done
        if 'to' in r: nh = np.where(m, r['to'], nh)
        elif 'shift' in r: nh = np.where(m, (h + r['shift']) % 360, nh)
        ns = np.where(m, np.minimum(1, s * r.get('saturation', 1)), ns)
        nv = np.where(m, np.minimum(1, v * r.get('value', 1)), nv)
        done |= m
    out = img.copy(); out[..., :3] = hsv2rgb(nh, ns, nv)
    return out

def hexrgb(x): x = x.lstrip('#'); return np.array([int(x[i:i + 2], 16) / 255 for i in (0, 2, 4)])

def grade(img, p):
    if not p: return img
    if p.get('recolor'): img = recolor(img, p['recolor'])
    out = img.copy(); rgb = out[..., :3]
    sat = p.get('saturation', 1)
    if sat != 1:
        h, s, v = rgb2hsv(rgb)
        s2 = np.where(s > 0.08, np.minimum(1, s * sat), s)
        rgb = hsv2rgb(h, s2, v)
    L = np.array([0.299, 0.587, 0.114])
    lum = rgb @ L
    tone = p.get('tone', 0.35)
    # Colour balance: dark pixels lean toward the shadow colour, bright ones toward the highlight
    # colour. Only the colour's offset from grey is added, so brightness stays put.
    if p.get('shadow'):
        c = hexrgb(p['shadow']); off = c - c @ L
        rgb = rgb + (tone * (1 - lum) ** 1.5)[..., None] * off
    if p.get('highlight'):
        c = hexrgb(p['highlight']); off = c - c @ L
        rgb = rgb + (p.get('glow', tone) * lum ** 1.5)[..., None] * off
    out[..., :3] = rgb.clip(0, 1)
    return out

# ---------- sprites ----------
_cache = {}
def raw(i, depth=0):
    if i in _cache: return _cache[i]
    try:
        im = np.asarray(Image.open(R + f'art/sprites/{i}.png').convert('RGBA')).astype(float) / 255
    except FileNotFoundError:
        d = assets[i]['derive']; im = recolor(raw(d['from'], depth + 1), d['recolor'])
        sc = assets[i].get('scale')
    _cache[i] = im
    return im

def sprite(i, palette):
    im = grade(raw(i), palette)
    a = assets.get(i, {})
    scale = a.get('scale') or (assets.get(a.get('derive', {}).get('from'), {}).get('scale')) or 1
    if a.get('kind') == 'walk_sheet':
        im = im[96:144, 0:48]     # facing down
    if scale != 1:
        h, w = im.shape[:2]
        im = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.NEAREST)).astype(float) / 255
    return im

# ---------- map ----------
T = 44; C = math.sqrt(0.5)
def project(gx, gy): return ((gx - gy) * C, (gx + gy) * C * 0.5)

def render(mid, palette, W=420, H=300, seed=3, tint=True):
    m = maps[mid]; th = m['theme']; rng = random.Random(seed)
    N = 16
    ground = [[th.get('border') if (m.get('town') and False) else th['ground'] for _ in range(N)] for _ in range(N)]
    kinds = [['g'] * N for _ in range(N)]
    # a winding path, an accent patch, a pond
    col = N // 2
    for r in range(N):
        kinds[r][col] = 'p'
        if rng.random() < 0.3: col = max(2, min(N - 3, col + rng.choice([-1, 1]))); kinds[r][col] = 'p'
    if th.get('accent'):
        cx, cy = rng.randrange(2, 6), rng.randrange(8, 13)
        for r in range(N):
            for c in range(N):
                if (c - cx) ** 2 + (r - cy) ** 2 < 6 and kinds[r][c] == 'g': kinds[r][c] = 'a'
    if th.get('water'):
        cx, cy = rng.randrange(10, 13), rng.randrange(2, 6)
        for r in range(N):
            for c in range(N):
                if (c - cx) ** 2 + (r - cy) ** 2 < 5 and kinds[r][c] == 'g': kinds[r][c] = 'w'
    tex = {'g': th['ground'], 'p': th['path'], 'a': th.get('accent'), 'w': th.get('water')}
    tiles = {k: grade(raw(v), palette) for k, v in tex.items() if v}
    img = np.zeros((H, W, 4)); img[..., 3] = 1; img[..., :3] = 0.1
    # world origin: centre of grid at screen centre
    ox, oy = project(N * T / 2, N * T / 2)
    ys, xs = np.mgrid[0:H, 0:W]
    px = xs - W / 2 + ox; py = (H / 2 - ys) + oy       # y up
    diff = px / C; summ = py / (C * 0.5)
    gx = (summ + diff) / 2; gy = (summ - diff) / 2
    cc = np.floor(gx / T).astype(int); rr = np.floor(gy / T).astype(int)
    inside = (cc >= 0) & (cc < N) & (rr >= 0) & (rr < N)
    u = ((gx / T) % 1 * 32).astype(int).clip(0, 31); v = ((1 - (gy / T) % 1) * 32).astype(int).clip(0, 31)
    kind_arr = np.array(kinds)
    for k, t in tiles.items():
        sel = inside & (kind_arr[rr.clip(0, N - 1), cc.clip(0, N - 1)] == k)
        img[sel] = t[v[sel], u[sel]]
    img[..., 3] = 1
    # props
    placed = []
    occupied = set()
    props = [p for p in th['props'] if not p.get('within')]
    pool = []
    for p in props:
        pool += [p['art']] * max(1, min(6, p['count'] // 6))
    rng.shuffle(pool)
    for art in pool[:34]:
        for _ in range(20):
            c, r = rng.randrange(N), rng.randrange(N)
            if kinds[r][c] == 'g' and (c, r) not in occupied and abs(c - N / 2) + abs(r - N / 2) > 2: break
        else: continue
        occupied.add((c, r))
        placed.append((art, c, r))
    placed.append(('player_walk', N // 2 - 1, N // 2))
    def screen(c, r):
        x, y = project((c + 0.5) * T, (r + 0.5) * T)
        x -= 0; y -= T * C * 0.5 * 0   # base of cell ~ centre
        return x - ox + W / 2, H / 2 - (y - oy)
    placed.sort(key=lambda t: screen(t[1], t[2])[1])  # back (higher up the screen) first
    for art, c, r in placed:
        s = sprite(art, None if assets[art]['kind'] == 'walk_sheet' else palette)
        h, w = s.shape[:2]
        sx, sy = screen(c, r)
        x0 = int(sx - w / 2 + rng.randint(-5, 5)); y0 = int(sy - h * 0.95)
        xa, ya = max(0, x0), max(0, y0); xb, yb = min(W, x0 + w), min(H, y0 + h)
        if xa >= xb or ya >= yb: continue
        part = s[ya - y0:yb - y0, xa - x0:xb - x0]
        al = (part[..., 3:] > 0.5).astype(float)
        img[ya:yb, xa:xb, :3] = img[ya:yb, xa:xb, :3] * (1 - al) + part[..., :3] * al
    amb = m.get('ambience') or {}
    if tint:
        tc, ta = amb.get('tint'), amb.get('tintAlpha', 0.15)
        if tc: img[..., :3] = img[..., :3] * (1 - ta) + hexrgb(tc) * ta
        vg = amb.get('vignette', 0)
        if vg:
            d = np.sqrt(((xs - W / 2) / (W * 0.62)) ** 2 + ((ys - H / 2) / (H * 0.62)) ** 2)
            f = (np.clip(d - 0.35, 0, 1) / 0.65) ** 1.6 * vg
            img[..., :3] *= (1 - f)[..., None]
    return Image.fromarray((img[..., :3].clip(0, 1) * 255).astype(np.uint8))

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Preview map palettes.')
    parser.add_argument('maps', nargs='*', help='map ids (default: all)')
    parser.add_argument('-o', '--out', default='palette-preview.png')
    args = parser.parse_args()
    ids = args.maps or list(maps)
    W, H = 420, 280
    sheet = Image.new('RGB', (W * 2 + 12, (H + 8) * len(ids)), (20, 20, 24))
    for n, mid in enumerate(ids):
        sheet.paste(render(mid, None, W, H), (0, n * (H + 8)))
        sheet.paste(render(mid, maps[mid]['theme'].get('palette'), W, H), (W + 12, n * (H + 8)))
    sheet.save(args.out)
    print('wrote', args.out)
