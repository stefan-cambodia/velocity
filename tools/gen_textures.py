#!/usr/bin/env python3
"""Procedural texture generator for VELOCITY.

Writes every texture in assets/textures/ from code (numpy + Pillow only).
Deterministic (fixed seeds), all tileable textures wrap exactly.

    python3 tools/gen_textures.py              # everything
    python3 tools/gen_textures.py track glow   # only generators whose name contains a filter

Normal maps are OpenGL style (+Y green up), as Godot expects.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
TAU = 2.0 * math.pi


def to8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def save(name, arr):
    arr = to8(arr) if arr.dtype != np.uint8 else arr
    Image.fromarray(arr).save(os.path.join(OUT, name), optimize=True)
    print("  ", name, arr.shape)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_noise(n, cells, rng, octaves=4, persistence=0.5):
    """Tileable value noise built from a periodic lattice, summed over octaves."""
    out = np.zeros((n, n))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        lat = rng.random((c, c))
        y = np.linspace(0, c, n, endpoint=False)
        x = np.linspace(0, c, n, endpoint=False)
        yi = np.floor(y).astype(int)
        xi = np.floor(x).astype(int)
        fy = y - yi
        fx = x - xi
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        a = lat[yi % c][:, xi % c]
        b = lat[yi % c][:, (xi + 1) % c]
        cc = lat[(yi + 1) % c][:, xi % c]
        d = lat[(yi + 1) % c][:, (xi + 1) % c]
        top = a + (b - a) * fx[None, :]
        bot = cc + (d - cc) * fx[None, :]
        out += (top + (bot - top) * fy[:, None]) * amp
        total += amp
        amp *= persistence
    return out / total


def blur_wrap(a, r):
    """Box blur with wrap-around (keeps tileability)."""
    if r <= 0:
        return a
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=axis)
        out = acc / (2 * r + 1)
    return out


def height_to_normal(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, dy, nz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


# --------------------------------------------------------------------------
# Track surface: composite deck plates over a conductor lattice.
# Texture covers 8 m x 8 m of track. RGB = albedo, A = roughness.
# --------------------------------------------------------------------------
def gen_track():
    n = 512
    rng = np.random.default_rng(11)
    y, x = np.mgrid[0:n, 0:n] / n          # 0..1 = 0..8 m
    base = 0.105 + 0.03 * (periodic_noise(n, 4, rng, 5) - 0.5)
    grain = periodic_noise(n, 64, rng, 2) - 0.5
    base += grain * 0.025
    # Plates: 4 m along, 2 m across, offset every other row; seams are dark grooves.
    px = x * 4.0
    py = y * 2.0
    row = np.floor(py)
    px = px + (row % 2) * 0.5
    fx = px - np.floor(px)
    fy = py - np.floor(py)
    seam = np.minimum(np.minimum(fx, 1 - fx) * 4.0 * 128, np.minimum(fy, 1 - fy) * 2.0 * 128)  # pixels to seam
    groove = 1.0 - sstep(0.6, 2.2, seam)
    # Per-plate tint variation.
    plate_id = (np.floor(px) * 7 + row * 13) % 17
    base *= 0.93 + 0.1 * (plate_id / 16.0)
    # Conductor lattice: fine hexagonal-ish grid etched into the plates.
    lx = x * 16.0
    ly = y * 16.0 * 0.866
    a1 = np.abs(((lx + ly * 0.577) % 1.0) - 0.5)
    a2 = np.abs(((lx - ly * 0.577) % 1.0) - 0.5)
    a3 = np.abs((ly * 1.1547 % 1.0) - 0.5)
    lat = np.maximum(np.maximum(sstep(0.47, 0.495, a1), sstep(0.47, 0.495, a2)), sstep(0.47, 0.495, a3))
    # Scuffs along the direction of travel (y = along track).
    sc = periodic_noise(n, 8, rng, 3)
    streak = blur_wrap((rng.random((n, n)) > 0.9965).astype(float), 1)
    streak = np.clip(sum(np.roll(streak, k, axis=0) for k in range(0, 40, 2)) * 0.25, 0, 1)
    alb = base * (1.0 - 0.55 * groove) + lat * 0.035 - streak * 0.025 + (sc - 0.5) * 0.02
    alb = np.clip(alb, 0.02, 1.0)
    rgb = np.stack([alb * 0.92, alb * 0.96, alb * 1.08], axis=-1)
    rough = np.clip(0.62 + 0.18 * (sc - 0.5) - streak * 0.25 + groove * 0.2 - lat * 0.15, 0.2, 1.0)
    save("track_albedo.png", np.dstack([rgb, rough]))
    h = -groove * 1.0 - lat * 0.25 + (periodic_noise(n, 32, rng, 2) - 0.5) * 0.15
    save("track_normal.png", height_to_normal(h, 3.0))


# --------------------------------------------------------------------------
# Barrier / structure metal panels. Covers 4 m x 4 m. RGB albedo, A roughness.
# --------------------------------------------------------------------------
def gen_panels():
    n = 512
    rng = np.random.default_rng(23)
    y, x = np.mgrid[0:n, 0:n] / n
    base = 0.36 + 0.06 * (periodic_noise(n, 4, rng, 4) - 0.5)
    # Panel grid 1 m x 0.5 m with bolts.
    px = x * 4.0
    py = y * 8.0
    fx = px - np.floor(px)
    fy = py - np.floor(py)
    seam = np.minimum(np.minimum(fx, 1 - fx) * 128, np.minimum(fy, 1 - fy) * 64)
    groove = 1.0 - sstep(0.5, 2.0, seam)
    bx = np.minimum(fx, 1 - fx) * 128
    by = np.minimum(fy, 1 - fy) * 64
    bolt = sstep(3.5, 2.0, np.hypot(bx - 6.0, by - 6.0))
    pid = (np.floor(px) * 5 + np.floor(py) * 3) % 7
    base *= 0.9 + 0.05 * pid / 6.0
    dirt = periodic_noise(n, 6, rng, 4)
    streaks = blur_wrap(periodic_noise(n, 32, rng, 1), 0)
    streaks = np.clip(np.cumsum(streaks - 0.5, axis=0) / n * 0, 0, 0) + streaks
    alb = base * (1 - 0.5 * groove) * (0.85 + 0.25 * dirt) + bolt * 0.12
    rgb = np.stack([alb * 0.95, alb * 0.98, alb * 1.04], axis=-1)
    rough = np.clip(0.42 + 0.25 * (dirt - 0.5) + groove * 0.3 - bolt * 0.2, 0.15, 1.0)
    save("panel_albedo.png", np.dstack([rgb, rough]))
    h = -groove + bolt * 0.6 + (periodic_noise(n, 48, rng, 2) - 0.5) * 0.1
    save("panel_normal.png", height_to_normal(h, 2.5))


# --------------------------------------------------------------------------
# Particle sprites.
# --------------------------------------------------------------------------
def gen_glow():
    n = 128
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.hypot(x, y)
    a = np.clip(1 - r, 0, 1) ** 2.2
    core = np.clip(1 - r * 3.0, 0, 1) ** 2
    v = np.clip(a + core * 0.5, 0, 1)
    save("glow.png", np.dstack([np.ones_like(v), np.ones_like(v), np.ones_like(v), v]))


def gen_streak():
    # Long thin speed streak (u across, v along).
    w, h = 32, 256
    y, x = np.mgrid[0:h, 0:w]
    u = (x / (w - 1)) * 2 - 1
    v = y / (h - 1)
    across = np.clip(1 - np.abs(u), 0, 1) ** 3
    along = np.sin(np.pi * v) ** 1.5 * (0.4 + 0.6 * v)
    a = across * along
    save("streak.png", np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a]))


def gen_spark():
    n = 64
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    a = np.clip(1 - np.abs(x) * 6, 0, 1) * np.clip(1 - np.abs(y), 0, 1) ** 0.6
    a = np.maximum(a, np.clip(1 - np.hypot(x, y) * 2.5, 0, 1) ** 2)
    save("spark.png", np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a]))


def gen_smoke():
    n = 128
    rng = np.random.default_rng(5)
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.hypot(x, y)
    nz = periodic_noise(n, 4, rng, 4)
    a = np.clip(1 - r, 0, 1) ** 1.5 * (0.5 + nz)
    a = np.clip(a, 0, 1)
    save("smoke.png", np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a]))


GENS = [gen_track, gen_panels, gen_glow, gen_streak, gen_spark, gen_smoke]



# --------------------------------------------------------------------------
# Launcher icons: an original "V" chevron emblem over a dusk gradient.
# --------------------------------------------------------------------------
def gen_icons():
    out = os.path.join(ROOT, "assets", "icons")
    os.makedirs(out, exist_ok=True)

    def emblem(size, bg=True, fg=True):
        s = size * 4
        im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        if bg:
            for y in range(s):
                t = y / s
                c = (int(10 + 60 * t), int(12 + 18 * t), int(40 + 40 * t), 255)
                d.line([(0, y), (s, y)], fill=c)
            # horizon glow
            for k in range(60):
                a = int(90 * (1 - k / 60))
                d.line([(0, int(s * 0.68) + k), (s, int(s * 0.68) + k)], fill=(255, 110, 60, a))
        if fg:
            cx = s / 2
            # Two nested chevrons forming a V, cyan and white.
            def chevron(w, top, depth, thick, col):
                pts = [(cx - w, top), (cx, top + depth), (cx + w, top), (cx + w - thick, top), (cx, top + depth - thick * 1.35), (cx - w + thick, top)]
                d.polygon(pts, fill=col)
            chevron(s * 0.30, s * 0.30, s * 0.42, s * 0.085, (240, 248, 255, 255))
            chevron(s * 0.20, s * 0.30, s * 0.28, s * 0.06, (70, 215, 255, 255))
        return im.resize((size, size), Image.LANCZOS)

    emblem(192).save(os.path.join(out, "icon_192.png"))
    emblem(432, bg=False).save(os.path.join(out, "icon_adaptive_fg.png"))
    emblem(432, fg=False).save(os.path.join(out, "icon_adaptive_bg.png"))
    emblem(512).save(os.path.join(out, "icon_512.png"))
    print("   icons")


GENS.append(gen_icons)



# --------------------------------------------------------------------------
# Team logos (original geometric emblems + wordmark). 512x256 RGBA, transparent.
# --------------------------------------------------------------------------
TEAM_LOGOS = {
    "halden": ("HALDEN", (240, 245, 255), (20, 70, 200), (255, 120, 30)),
    "shiranui": ("SHIRANUI", (200, 20, 25), (20, 20, 22), (245, 235, 215)),
    "vantor": ("VANTOR", (255, 175, 15), (60, 62, 68), (20, 20, 20)),
    "aurelle": ("AURELLE", (240, 230, 205), (0, 110, 115), (215, 165, 60)),
    "meridian": ("MERIDIAN", (10, 120, 65), (255, 215, 25), (245, 245, 245)),
    "azimuth": ("AZIMUTH", (220, 85, 20), (35, 35, 40), (235, 235, 235)),
    "nyx": ("NYX", (215, 15, 155), (12, 12, 14), (155, 80, 255)),
    "tempest": ("TEMPEST", (25, 170, 220), (245, 248, 252), (115, 50, 190)),
}


def _emblem(d, tid, cx, cy, r, c1, c2, c3):
    if tid == "halden":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c1)
        for k, col in ((0, c2), (1, c3)):
            o = k * r * 0.32
            d.polygon([(cx - r * 0.7, cy + r * 0.25 - o), (cx, cy - r * 0.45 - o), (cx + r * 0.7, cy + r * 0.25 - o),
                       (cx + r * 0.7, cy + r * 0.48 - o), (cx, cy - r * 0.2 - o), (cx - r * 0.7, cy + r * 0.48 - o)], fill=col)
    elif tid == "shiranui":
        for k in range(3):
            x = cx - r * 0.6 + k * r * 0.45
            d.polygon([(x, cy + r), (x + r * 0.35, cy - r), (x + r * 0.62, cy - r), (x + r * 0.27, cy + r)], fill=c1 if k != 1 else c3)
    elif tid == "vantor":
        pts = [(cx + r * math.cos(a), cy + r * math.sin(a)) for a in [math.pi / 6 + k * math.pi / 3 for k in range(6)]]
        d.polygon(pts, fill=c2)
        pts2 = [(cx + r * 0.72 * math.cos(a), cy + r * 0.72 * math.sin(a)) for a in [math.pi / 6 + k * math.pi / 3 for k in range(6)]]
        d.polygon(pts2, fill=c1)
        d.rectangle([cx - r * 0.5, cy - r * 0.14, cx + r * 0.5, cy + r * 0.14], fill=c3)
    elif tid == "aurelle":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c3, width=int(r * 0.12))
        d.polygon([(cx, cy - r * 0.75), (cx + r * 0.45, cy + r * 0.6), (cx + r * 0.25, cy + r * 0.6), (cx, cy - r * 0.1), (cx - r * 0.25, cy + r * 0.6), (cx - r * 0.45, cy + r * 0.6)], fill=c2)
    elif tid == "meridian":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c1)
        d.arc([cx - r * 0.45, cy - r, cx + r * 0.45, cy + r], 270, 90, fill=c2, width=int(r * 0.14))
        d.arc([cx - r * 0.45, cy - r, cx + r * 0.45, cy + r], 90, 270, fill=c3, width=int(r * 0.08))
    elif tid == "azimuth":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c3, width=int(r * 0.08))
        d.polygon([(cx, cy - r * 0.9), (cx + r * 0.3, cy + r * 0.3), (cx, cy + r * 0.1), (cx - r * 0.3, cy + r * 0.3)], fill=c1)
        d.polygon([(cx, cy + r * 0.9), (cx + r * 0.2, cy + r * 0.3), (cx, cy + r * 0.1), (cx - r * 0.2, cy + r * 0.3)], fill=c2)
    elif tid == "nyx":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c1)
        d.ellipse([cx - r * 0.55, cy - r * 1.05, cx + r * 1.2, cy + r * 0.6], fill=(0, 0, 0, 0))
        sx, sy = cx + r * 0.55, cy + r * 0.45
        star = []
        for k in range(10):
            a = -math.pi / 2 + k * math.pi / 5
            rr = r * (0.3 if k % 2 == 0 else 0.12)
            star.append((sx + rr * math.cos(a), sy + rr * math.sin(a)))
        d.polygon(star, fill=c3)
    elif tid == "tempest":
        for k in range(3):
            rr = r * (1.0 - k * 0.28)
            d.arc([cx - rr, cy - rr, cx + rr, cy + rr], 200 + k * 40, 200 + k * 40 + 220, fill=(c1, c3, c1)[k], width=int(r * 0.13))


def gen_logos():
    from PIL import ImageFont
    out = os.path.join(ROOT, "assets", "textures")
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "Orbitron.ttf"), 112)
    for tid, (name, c1, c2, c3) in TEAM_LOGOS.items():
        W, H = 1024, 512
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        _emblem(d, tid, 190, 256, 150, c1 + (255,), c2 + (255,), c3 + (255,))
        d.text((380, 256), name, font=font, fill=(245, 248, 255, 255), anchor="lm")
        d.rectangle([380, 330, 380 + min(600, 80 * len(name)), 342], fill=c1 + (255,))
        im = im.resize((512, 256), Image.LANCZOS)
        im.save(os.path.join(out, "logo_%s.png" % tid))
    print("   logos", len(TEAM_LOGOS))


GENS.append(gen_logos)



# --------------------------------------------------------------------------
# Facade windows: 32 bays x 32 floors, 16 px per cell. R = light (0 = dark),
# G = colour temperature (0 cool .. 1 warm), B = glass pane mask. Mipmaps of
# this texture give the far-distance average for free.
# --------------------------------------------------------------------------
def gen_windows():
    rng = np.random.default_rng(42)
    cells = 32
    px = 16
    n = cells * px
    R = np.zeros((n, n))
    G = np.zeros((n, n))
    B = np.zeros((n, n))
    floor_on = rng.random((cells, cells // 8)) > 0.3          # floors lit in runs of 8 bays
    for fy in range(cells):
        for bx in range(cells):
            lit = (rng.random() < 0.5) and floor_on[fy, bx // 8]
            warm = 1.0 if rng.random() > 0.35 else 0.0
            bright = 0.5 + 0.5 * rng.random()
            y0, x0 = fy * px, bx * px
            # Pane inside the cell: 3 px frame left/right, 3 px top, 2 px bottom (v grows downwards).
            B[y0 + 3:y0 + px - 2, x0 + 3:x0 + px - 3] = 1.0
            if lit:
                R[y0 + 3:y0 + px - 2, x0 + 3:x0 + px - 3] = bright
            G[y0:y0 + px, x0:x0 + px] = warm
    save("windows.png", np.dstack([R, G, B, np.ones_like(R)]))


GENS.append(gen_windows)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    flt = sys.argv[1:]
    for g in GENS:
        if flt and not any(f in g.__name__ for f in flt):
            continue
        print(g.__name__)
        g()
