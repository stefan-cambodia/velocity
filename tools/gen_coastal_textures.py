#!/usr/bin/env python3
"""Baked textures for the Costa Branca circuit (numpy + Pillow, deterministic).

    python3 tools/gen_coastal_textures.py

coastal_clouds.png  512 x 512, tileable. Fair-weather cumulus for the sky
                    shader (sky_coastal.gdshader): R = cloud density, G = a
                    blurred density used to shade the cloud cores.
coastal_ripples.png 256 x 256, tileable. Sea ripples for sea.gdshader:
                    RGB = normal map (OpenGL style), A = foam/breakup noise.
coastal_noise.png   512 x 512, tileable. Value noise at three scales (R coarse
                    patches, G medium, B fine grain) for the ground and the
                    house facades, so those shaders need no per-pixel noise.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")


def periodic_noise(n, cells, rng, octaves=4, persistence=0.5):
    """Tileable value noise from a periodic lattice, summed over octaves."""
    out = np.zeros((n, n))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        lat = rng.random((c, c))
        y = np.linspace(0, c, n, endpoint=False)
        yi = np.floor(y).astype(int)
        fy = y - yi
        fy = fy * fy * (3 - 2 * fy)
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
    out = a.copy()
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for k in range(-r, r + 1):
            acc += np.roll(out, k, axis=axis)
        out = acc / (2 * r + 1)
    return out


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def gen_clouds():
    n = 512
    rng = np.random.default_rng(4242)
    yy, xx = np.mgrid[0:n, 0:n].astype(float)
    # Clusters of round puffs (cumulus heads), wrapped so the texture tiles.
    field = np.zeros((n, n))
    for _ in range(16):
        cx, cy = rng.random(2) * n
        size = rng.uniform(10.0, 24.0)
        for _k in range(rng.integers(5, 11)):
            px = cx + rng.normal(0.0, size * 1.1)
            py = cy + rng.normal(0.0, size * 0.6)
            r = size * rng.uniform(0.45, 0.9)
            dx = (xx - px + n / 2) % n - n / 2
            dy = (yy - py + n / 2) % n - n / 2
            field += np.exp(-(dx * dx + dy * dy) / (2.0 * r * r))
    detail = periodic_noise(n, 8, rng, octaves=4)
    fine = periodic_noise(n, 32, rng, octaves=3)
    dens = sstep(0.6, 1.25, field * (0.45 + 1.0 * detail) + 1.4 * (fine - 0.5))
    core = blur_wrap(dens, 6)
    img = np.dstack([dens, core, np.zeros_like(dens)])
    arr = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT, "coastal_clouds.png"), optimize=True)
    print("   coastal_clouds.png", arr.shape, "cover %.2f" % float((dens > 0.3).mean()))


def gen_ripples():
    n = 256
    rng = np.random.default_rng(77)
    h = periodic_noise(n, 6, rng, octaves=5, persistence=0.55)
    # Sharpen into wave crests (ridged), keeping it tileable.
    h = 1.0 - np.abs(h * 2.0 - 1.0)
    h = blur_wrap(h, 1)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * 6.0
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * 6.0
    nrm = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    foam = periodic_noise(n, 12, rng, octaves=3)
    img = np.dstack([nrm * 0.5 + 0.5, foam])
    arr = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(os.path.join(OUT, "coastal_ripples.png"), optimize=True)
    print("   coastal_ripples.png", arr.shape)


def gen_noise():
    n = 512
    rng = np.random.default_rng(31)
    r = periodic_noise(n, 4, rng, octaves=4)
    g = periodic_noise(n, 16, rng, octaves=3)
    b = periodic_noise(n, 64, rng, octaves=2)
    img = np.dstack([r, g, b])
    img = (img - img.min(axis=(0, 1))) / (img.max(axis=(0, 1)) - img.min(axis=(0, 1)))
    arr = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(arr).save(os.path.join(OUT, "coastal_noise.png"), optimize=True)
    print("   coastal_noise.png", arr.shape)


if __name__ == "__main__":
    gen_clouds()
    gen_ripples()
    gen_noise()
