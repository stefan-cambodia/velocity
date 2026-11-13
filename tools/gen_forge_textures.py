#!/usr/bin/env python3
"""Baked data textures for FORGE CALDERA (numpy + Pillow, deterministic).

    python3 tools/gen_forge_textures.py

forge_noise.png  512x512 RGBA, tileable. Sampled by the volcanic terrain and
                 lava shaders instead of per-pixel value noise:
                   R = fbm value noise (8 cells, 5 octaves)
                   G = cell edges (Voronoi F2 - F1, 0 on an edge, ~1 inside)
                   B = fbm value noise (4 cells, 4 octaves, another seed)
                   A = random value per Voronoi cell
forge_clouds.png 512x512 L, tileable. Ash cloud density for sky_forge (domain-
                 warped fbm, billowy), sampled by planar projection.

The .import files keep mipmaps on (textures bound in code never trigger the
importer's 3D detection) and use VRAM compression.
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")


def to8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def periodic_noise(n, cells, rng, octaves=4, persistence=0.5):
    """Tileable value noise from a periodic lattice, summed over octaves (0..1)."""
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


def voronoi(n, cells, rng):
    """Tileable Voronoi: (F2 - F1) in cell units and a random value per cell."""
    pts = rng.random((cells, cells, 2)) * 0.8 + 0.1
    ids = rng.random((cells, cells))
    y, x = np.mgrid[0:n, 0:n] / n * cells
    cy = np.floor(y).astype(int)
    cx = np.floor(x).astype(int)
    f1 = np.full((n, n), 9.0)
    f2 = np.full((n, n), 9.0)
    idv = np.zeros((n, n))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            gy = cy + dy
            gx = cx + dx
            p = pts[gy % cells, gx % cells]
            d = np.hypot(gx + p[..., 0] - x, gy + p[..., 1] - y)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            idv = np.where(closer, ids[gy % cells, gx % cells], idv)
            f1 = np.where(closer, d, f1)
    return f2 - f1, idv


def warp_sample(field, u, v):
    """Bilinear, wrapping lookup of `field` at fractional pixel coords."""
    n = field.shape[0]
    x0 = np.floor(u).astype(int)
    y0 = np.floor(v).astype(int)
    fx = u - x0
    fy = v - y0
    a = field[y0 % n, x0 % n]
    b = field[y0 % n, (x0 + 1) % n]
    c = field[(y0 + 1) % n, x0 % n]
    d = field[(y0 + 1) % n, (x0 + 1) % n]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def gen_noise():
    n = 512
    rng = np.random.default_rng(4401)
    r = periodic_noise(n, 8, rng, 5)
    edge, idv = voronoi(n, 10, rng)
    g = np.clip(edge / 0.6, 0.0, 1.0)
    b = periodic_noise(n, 4, rng, 4)
    r = (r - r.min()) / (r.max() - r.min())
    b = (b - b.min()) / (b.max() - b.min())
    img = np.dstack([to8(r), to8(g), to8(b), to8(idv)])
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "forge_noise.png"), optimize=True)
    print("   forge_noise.png", img.shape)


def gen_clouds():
    n = 512
    rng = np.random.default_rng(7707)
    base = periodic_noise(n, 4, rng, 6, 0.55)
    wx = periodic_noise(n, 3, rng, 3)
    wy = periodic_noise(n, 3, rng, 3)
    y, x = np.mgrid[0:n, 0:n].astype(float)
    c = warp_sample(base, x + (wx - 0.5) * 120.0, y + (wy - 0.5) * 120.0)
    c = (c - c.min()) / (c.max() - c.min())
    # Billowy: soft threshold with a long tail, so the shader can pick cover.
    c = np.clip((c - 0.25) / 0.6, 0.0, 1.0) ** 1.2
    Image.fromarray(to8(c), "L").save(os.path.join(OUT, "forge_clouds.png"), optimize=True)
    print("   forge_clouds.png", c.shape)


if __name__ == "__main__":
    gen_noise()
    gen_clouds()
