#!/usr/bin/env python3
"""Baked textures for Cirrus Heights (src/world/skyport.gd).

Standalone, numpy + Pillow only, deterministic (fixed seeds). Writes to
assets/textures/:

  skyport_clouds.png  2048 x 2048 RGB, tileable. The top of the cloud sea,
                      covering CLOUD_TILE metres of world space per repeat:
                        R  direct sunlight, including the long shadows the
                           puffs cast in the low morning sun (SUN_AZ, SUN_EL)
                        G  cloud-top height, 0..1 (CLOUD_RELIEF metres)
                        B  ambient term: dark in the folds between puffs
                      cloud_sea.gdshader turns these into colour; lighting is
                      baked because per-pixel noise over half the screen is
                      too expensive on the target phone.
  skyport_cirrus.png  1024 x 1024 L, tileable. Streaky high cirrus for the
                      sky shader (sky_dawn.gdshader).

    python3 tools/gen_skyport_textures.py            # both
    python3 tools/gen_skyport_textures.py clouds     # only names containing a filter

The sun constants must match Skyport.SUN_AZ / SUN_EL in src/world/skyport.gd:
the world is mapped u = x / CLOUD_TILE, v = z / CLOUD_TILE (image column = x,
row = z), azimuth measured from north (-z) towards east (+x).
"""
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")

SUN_AZ = 90.0          # degrees from north towards east (sun due east)
SUN_EL = 9.0           # degrees above the horizon
CLOUD_TILE = 2400.0    # metres of world per texture repeat
CLOUD_RELIEF = 80.0    # metres from the lowest fold to the highest puff


def to8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def periodic_noise(n, cells, rng, octaves=4, persistence=0.5):
    """Tileable value noise from a periodic lattice, summed over octaves."""
    out = np.zeros((n, n), np.float32)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        lat = rng.random((c, c)).astype(np.float32)
        y = np.linspace(0, c, n, endpoint=False)
        yi = np.floor(y).astype(int)
        fy = y - yi
        fy = (fy * fy * (3 - 2 * fy)).astype(np.float32)
        a = lat[yi % c][:, yi % c]
        b = lat[yi % c][:, (yi + 1) % c]
        cc = lat[(yi + 1) % c][:, yi % c]
        d = lat[(yi + 1) % c][:, (yi + 1) % c]
        top = a + (b - a) * fy[None, :]
        bot = cc + (d - cc) * fy[None, :]
        out += (top + (bot - top) * fy[:, None]) * amp
        total += amp
        amp *= persistence
    return out / total


def blur_wrap(a, r):
    """Box blur with wrap-around, three passes (close to Gaussian)."""
    out = a.copy()
    for _ in range(3):
        for axis in (0, 1):
            c = np.cumsum(np.concatenate([out.take(range(-r - 1, 0), axis=axis), out, out.take(range(0, r), axis=axis)], axis=axis), axis=axis)
            hi = c.take(range(2 * r + 1, 2 * r + 1 + out.shape[axis]), axis=axis)
            lo = c.take(range(0, out.shape[axis]), axis=axis)
            out = (hi - lo) / (2 * r + 1)
    return out


def puffs(n, cells, rng, rmin, rmax, wx, wy):
    """Tileable field of soft rounded puffs: one jittered centre per cell,
    radius rmin..rmax cells, height proportional to the radius. Overlapping
    puffs merge smoothly (soft maximum), so there are no creases. wx, wy:
    domain warp in cells (breaks the round outlines into lumpy heads)."""
    pts = rng.random((cells, cells, 2))
    rad = rng.uniform(rmin, rmax, (cells, cells))
    g = (np.arange(n, dtype=np.float32) + 0.5) / n * cells
    gx, gy = np.meshgrid(g, g)
    gx = gx + wx
    gy = gy + wy
    ix = np.floor(gx).astype(int)
    iy = np.floor(gy).astype(int)
    acc = np.zeros((n, n), np.float32)
    k = 14.0
    for dy in (-2, -1, 0, 1, 2):
        for dx in (-2, -1, 0, 1, 2):
            cx = ix + dx
            cy = iy + dy
            p = pts[cy % cells, cx % cells]
            r = rad[cy % cells, cx % cells]
            px = cx + p[..., 0]
            py = cy + p[..., 1]
            d2 = (gx - px) ** 2 + (gy - py) ** 2
            bump = r * np.maximum(0.0, 1.0 - d2 / (r * r)) ** 0.65
            acc += np.exp(k * bump)
    return np.log(acc) / k


def sample_wrap(a, x, y):
    """Bilinear sample with wrap-around at float pixel coordinates."""
    n = a.shape[0]
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    x0 %= n
    y0 %= n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    top = a[y0, x0] * (1 - fx) + a[y0, x1] * fx
    bot = a[y1, x0] * (1 - fx) + a[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def gen_clouds(n=2048, out=None):
    blur = max(1, n // 1024)
    rng = np.random.default_rng(4471)
    px = CLOUD_TILE / n                                    # metres per pixel
    # Cloud masses: big rounded heads, smaller puffs riding on them, fine
    # billows, all modulated by a slow field that opens a few deeper folds.
    def warp(cells, amount):
        # Gentle domain warp, in puff cells, from noise a little coarser than the puffs.
        wx = periodic_noise(n, cells, rng, octaves=2) - 0.5
        wy = periodic_noise(n, cells, rng, octaves=2) - 0.5
        return wx * amount, wy * amount
    def norm(a):
        return (a - a.min()) / (a.max() - a.min())
    big = norm(puffs(n, 8, rng, 0.6, 1.0, *warp(4, 0.35)))
    mid = norm(puffs(n, 20, rng, 0.55, 0.95, *warp(10, 0.4)))
    small = norm(puffs(n, 50, rng, 0.5, 0.9, *warp(24, 0.45)))
    fine = periodic_noise(n, 64, rng, octaves=3, persistence=0.5)
    mass = periodic_noise(n, 4, rng, octaves=3, persistence=0.55)
    mass = sstep(0.3, 0.7, mass)
    h = 0.6 * big + 0.27 * mid * (0.3 + 0.7 * big) + 0.11 * small * (0.25 + 0.75 * mid) + 0.02 * fine
    h = h * (0.6 + 0.4 * mass) + 0.06 * mass
    h = blur_wrap(h.astype(np.float32), blur)
    h = (h - h.min()) / (h.max() - h.min())
    H = h * CLOUD_RELIEF
    # Normals (metres).
    dx = (np.roll(H, -1, axis=1) - np.roll(H, 1, axis=1)) / (2 * px)
    dz = (np.roll(H, -1, axis=0) - np.roll(H, 1, axis=0)) / (2 * px)
    nrm = np.stack([-dx, np.ones_like(H), -dz], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    az = math.radians(SUN_AZ)
    el = math.radians(SUN_EL)
    sun = np.array([math.sin(az) * math.cos(el), math.sin(el), -math.cos(az) * math.cos(el)], np.float32)
    ndl = nrm @ sun
    direct = np.clip((ndl + 0.18) / 1.18, 0.0, 1.0)
    # Soft shadows: march towards the sun across the height field.
    sx = math.sin(az) / px          # pixels per metre along the ground, x (columns)
    sz = -math.cos(az) / px         # rows (z)
    tan_el = math.tan(el)
    gy, gx = np.mgrid[0:n, 0:n].astype(np.float32)
    shade = np.ones_like(H)
    t = 2.0
    while t < 900.0:
        q = sample_wrap(H, gx + sx * t, gy + sz * t)
        over = q - (H + t * tan_el)                     # > 0: the ray is blocked
        shade = np.minimum(shade, np.clip(1.0 - over / (2.0 + t * 0.05), 0.0, 1.0))
        t *= 1.06
        t += 1.5
    light = direct * (0.08 + 0.92 * shade)
    # Ambient: folds between puffs see less sky.
    ao = np.clip(0.62 + (H - blur_wrap(H, max(2, n // 80))) / 22.0, 0.0, 1.0)
    ao = ao * (0.7 + 0.3 * h)
    img = np.dstack([to8(light), to8(h), to8(ao)])
    Image.fromarray(img, "RGB").save(out or os.path.join(OUT, "skyport_clouds.png"), optimize=True)
    print("   skyport_clouds.png", img.shape, "lit %.2f" % float(light.mean()))


def gen_cirrus():
    n = 1024
    rng = np.random.default_rng(907)
    # Streaks: noise stretched along x (8 cells across, 40 down), warped.
    lat = rng.random((40, 40)).astype(np.float32)
    g = np.arange(n, dtype=np.float32) / n
    gx, gy = np.meshgrid(g, g)
    warp = periodic_noise(n, 3, rng, octaves=3) - 0.5
    def vn(x, y, cx, cy, lat):
        # periodic value noise with independent cell counts per axis
        X = x * cx
        Y = y * cy
        xi = np.floor(X).astype(int)
        yi = np.floor(Y).astype(int)
        fx = X - xi
        fy = Y - yi
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        L = lat.shape[0]
        a = lat[yi % cy % L, xi % cx % L]
        b = lat[yi % cy % L, (xi + 1) % cx % L]
        c = lat[(yi + 1) % cy % L, xi % cx % L]
        d = lat[(yi + 1) % cy % L, (xi + 1) % cx % L]
        return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
    y = (gy + warp * 0.12) % 1.0
    s = vn(gx, y, 4, 32, lat) * 0.55 + vn(gx, y, 8, 40, np.roll(lat, 7, 0)) * 0.3 + vn(gx, y, 16, 40, np.roll(lat, 13, 1)) * 0.15
    patches = periodic_noise(n, 3, rng, octaves=2)
    c = sstep(0.5, 0.78, s) * sstep(0.35, 0.65, patches)
    c = blur_wrap(c.astype(np.float32), 1)
    Image.fromarray(to8(c), "L").save(os.path.join(OUT, "skyport_cirrus.png"), optimize=True)
    print("   skyport_cirrus.png", c.shape, "cover %.2f" % float(c.mean()))


GENS = [gen_clouds, gen_cirrus]

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    flt = sys.argv[1:]
    for gen in GENS:
        if flt and not any(f in gen.__name__ for f in flt):
            continue
        print(gen.__name__)
        gen()
