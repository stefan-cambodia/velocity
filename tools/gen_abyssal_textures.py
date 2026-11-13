#!/usr/bin/env python3
"""Baked textures for Thalassa Deep (src/world/abyssal.gd). Deterministic.

    python3 tools/gen_abyssal_textures.py

abyss_caustics.png (256 x 256, tiles seamlessly):
  R, G  two caustic networks (bright ridges along Voronoi cell borders, warped
        so the cells look like refracted light, not a honeycomb). The seabed
        shader scrolls them in different directions and takes the minimum, so
        the pattern crawls and shimmers like light through a moving surface.
  B     tileable value-noise fbm (sand mottling, rock tint, glass smudges).
  A     ripple field for sand: wavy parallel crests, tileable.
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
N = 256


def torus_dist(px, py, qx, qy):
    dx = np.abs(px - qx)
    dy = np.abs(py - qy)
    dx = np.minimum(dx, 1.0 - dx)
    dy = np.minimum(dy, 1.0 - dy)
    return np.sqrt(dx * dx + dy * dy)


def value_noise(rng, cells, n=N):
    g = rng.random((cells, cells))
    y, x = np.mgrid[0:n, 0:n] / n * cells
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1 = (x0 + 1) % cells
    y1 = (y0 + 1) % cells
    x0 %= cells
    y0 %= cells
    a = g[y0, x0] * (1 - fx) + g[y0, x1] * fx
    b = g[y1, x0] * (1 - fx) + g[y1, x1] * fx
    return a * (1 - fy) + b * fy


def fbm(rng, base, octaves):
    acc = np.zeros((N, N))
    amp = 1.0
    tot = 0.0
    for k in range(octaves):
        acc += value_noise(rng, base * 2 ** k) * amp
        tot += amp
        amp *= 0.5
    return acc / tot


def caustic(seed, cells=9):
    rng = np.random.default_rng(seed)
    # Jittered points on the torus.
    pts = []
    for j in range(cells):
        for i in range(cells):
            pts.append(((i + 0.15 + 0.7 * rng.random()) / cells, (j + 0.15 + 0.7 * rng.random()) / cells))
    pts = np.array(pts)
    y, x = np.mgrid[0:N, 0:N] / N
    # Domain warp: the borders wobble like refracted light.
    wx = (fbm(rng, 4, 3) - 0.5) * 0.06
    wy = (fbm(rng, 4, 3) - 0.5) * 0.06
    px = (x + wx) % 1.0
    py = (y + wy) % 1.0
    f1 = np.full((N, N), 9.0)
    f2 = np.full((N, N), 9.0)
    for qx, qy in pts:
        d = torus_dist(px, py, qx, qy)
        f2 = np.where(d < f1, f1, np.minimum(f2, d))
        f1 = np.minimum(f1, d)
    edge = (f2 - f1) * cells          # 0 on borders, ~0.5 in cell centres
    c = np.exp(-edge * 9.0) * 0.9 + np.exp(-edge * 3.0) * 0.25
    c *= 0.75 + 0.5 * fbm(rng, 8, 2)  # uneven brightness along the network
    return np.clip(c, 0.0, 1.0)


def ripples(seed):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:N, 0:N] / N
    warp = (fbm(rng, 4, 3) - 0.5) * 0.9
    # 12 crests across the tile, bent by the warp; asymmetric profile (steep lee side).
    ph = (x * 12.0 + y * 3.0 + warp * 3.0) % 1.0
    prof = np.where(ph < 0.7, ph / 0.7, (1.0 - ph) / 0.3)
    return np.clip(prof * (0.6 + 0.4 * fbm(rng, 8, 2)), 0.0, 1.0)


def main():
    r = caustic(11)
    g = caustic(23, cells=7)
    b = fbm(np.random.default_rng(5), 8, 4)
    b = (b - b.min()) / (b.max() - b.min())
    a = ripples(31)
    img = np.stack([r, g, b, a], axis=-1)
    Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "abyss_caustics.png"))
    print("wrote abyss_caustics.png")


if __name__ == "__main__":
    main()
