#!/usr/bin/env python3
"""Textures for the Tempest Shoals world (src/world/offshore.gd).

    python3 tools/gen_offshore_textures.py

Writes, deterministically and tileable:
  assets/textures/offshore_clouds.png  1024x1024 RGB  storm cloud fields for the sky shader
      R = cloud density (domain-warped fbm), G = fine detail, B = wind-stretched rolls
  assets/textures/offshore_sea.png     512x512 RGBA   sea detail
      RGB = normal map of the small chop (OpenGL style, +Y green up), A = foam pattern

Both are sampled with mipmaps; their .import files set mipmaps/generate=true
(the clouds also use VRAM compression), because materials built in code never
trigger Godot's 3D import detection.
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")
TAU = 2.0 * math.pi


def to8(a):
    return (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def fbm(u, v, base, rng, octaves, persistence=0.5, stretch=(1, 1)):
    """Tileable fbm at texture coords u, v in 0..1 (arrays). `stretch` scales cells per axis."""
    out = np.zeros_like(u)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        cx = base * stretch[0] * (2 ** o)
        cy = base * stretch[1] * (2 ** o)
        c = max(cx, cy)
        lat = rng.random((c, c))
        # Use separate periods per axis by sampling the c x c lattice with per-axis cell counts.
        xs = u * cx
        ys = v * cy
        n = lattice_noise_xy(xs, ys, cx, cy, lat)
        out += n * amp
        total += amp
        amp *= persistence
    return out / total


def lattice_noise_xy(x, y, cx, cy, lat):
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    fx = x - xi
    fy = y - yi
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x0 = xi % cx
    x1 = (xi + 1) % cx
    y0 = yi % cy
    y1 = (yi + 1) % cy
    a = lat[y0, x0]
    b = lat[y0, x1]
    c = lat[y1, x0]
    d = lat[y1, x1]
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy


def gen_clouds():
    n = 1024
    rng = np.random.default_rng(4401)
    v, u = np.meshgrid(np.arange(n) / n, np.arange(n) / n, indexing="ij")
    # Domain warp (periodic: the warp fields tile, offsets wrap through the lattice).
    wu = fbm(u, v, 4, rng, 4) - 0.5
    wv = fbm(u, v, 4, rng, 4) - 0.5
    uu = u + wu * 0.22
    vv = v + wv * 0.22
    dens = fbm(uu % 1.0, vv % 1.0, 5, rng, 6, 0.55)
    dens = sstep(0.32, 0.72, dens)
    # Billowy underside: sharpen into lumps.
    lumps = fbm(u, v, 16, rng, 4, 0.5)
    dens = np.clip(dens * (0.75 + 0.5 * lumps), 0.0, 1.0)
    detail = fbm(uu % 1.0, vv % 1.0, 32, rng, 4, 0.6)
    rolls = fbm(u, v, 3, rng, 5, 0.5, stretch=(1, 6))
    rolls = sstep(0.3, 0.75, rolls)
    img = np.stack([dens, detail, rolls], axis=-1)
    Image.fromarray(to8(img)).save(os.path.join(OUT, "offshore_clouds.png"), optimize=True)
    print("  offshore_clouds.png", img.shape)


def gen_sea():
    n = 512
    rng = np.random.default_rng(9120)
    y, x = np.meshgrid(np.arange(n) / n, np.arange(n) / n, indexing="ij")
    h = np.zeros((n, n))
    # Short wind waves: directional sines with integer wave numbers (tile exactly),
    # mostly along the wind (+x, +y), plus a little cross chop.
    for k in range(18):
        ang = rng.normal(0.65, 0.45)
        freq = rng.uniform(5, 22)
        kx = int(round(math.cos(ang) * freq))
        ky = int(round(math.sin(ang) * freq))
        if kx == 0 and ky == 0:
            continue
        amp = 1.0 / (math.hypot(kx, ky) ** 1.2)
        ph = rng.uniform(0, TAU)
        h += amp * np.sin(TAU * (kx * x + ky * y) + ph)
    h += (fbm(x, y, 16, rng, 4, 0.5) - 0.5) * 0.35
    h /= np.abs(h).max()
    # Normal from the periodic gradient (central differences with wrap).
    scale = 6.0
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * scale
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * scale
    nx = -dx
    ny = dy          # OpenGL style: +Y green up (image rows run down)
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
    # Foam: veins (ridged noise) broken up by fine noise, histogram-equalised so
    # the shader's threshold maps linearly to coverage (1 - t covers fraction t).
    f1 = fbm(x, y, 8, rng, 5, 0.55, stretch=(1, 2))
    f2 = fbm(x, y, 32, rng, 3, 0.5)
    ridge = 1.0 - np.abs(f1 - 0.5) * 2.0
    raw = ridge ** 3 * 0.7 + f2 * 0.3
    ranks = np.empty(raw.size)
    ranks[np.argsort(raw, axis=None)] = np.arange(raw.size)
    foam = (ranks / (raw.size - 1)).reshape(raw.shape)
    img = np.concatenate([nrm, foam[..., None]], axis=-1)
    Image.fromarray(to8(img), "RGBA").save(os.path.join(OUT, "offshore_sea.png"), optimize=True)
    print("  offshore_sea.png", img.shape)


if __name__ == "__main__":
    gen_clouds()
    gen_sea()
