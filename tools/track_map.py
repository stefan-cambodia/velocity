#!/usr/bin/env python3
"""Renders a top-down circuit map from tools/track_dump.gd output.

    python3 tools/track_map.py track.json out.png
Colour = height (blue low .. orange high); red = jump gap; grey hatch = tunnel;
yellow = boost pad; labels = sections; white dot + arrow = start and direction.
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

data = json.load(open(sys.argv[1]))
out = sys.argv[2]
pts = data["pts"]
xs = [p[0] for p in pts]
zs = [p[2] for p in pts]
ys = [p[1] for p in pts]
pad = 140
W = 1600
span = max(max(xs) - min(xs), max(zs) - min(zs))
sc = (W - 2 * pad) / span
H = int((max(zs) - min(zs)) * sc + 2 * pad)
img = Image.new("RGB", (W, max(H, 400)), (14, 16, 22))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("assets/fonts/Rajdhani-SemiBold.ttf", 22)
except OSError:
    font = ImageFont.load_default()
ymin, ymax = min(ys), max(ys)


def P(x, z):
    return ((x - min(xs)) * sc + pad, (z - min(zs)) * sc + pad)


def col(y):
    t = 0.0 if ymax - ymin < 1e-3 else (y - ymin) / (ymax - ymin)
    return (int(40 + 215 * t), int(110 + 60 * (1 - abs(t - 0.5) * 2)), int(230 - 200 * t))


n = len(pts)
# Track edges as filled quads.
for i in range(n):
    a = pts[i]
    b = pts[(i + 1) % n]
    def edge(p, side):
        hw = p[4] if side > 0 else -p[3]
        return P(p[0] + p[9] * hw, p[2] + p[10] * hw)
    poly = [edge(a, -1), edge(a, 1), edge(b, 1), edge(b, -1)]
    c = col(a[1])
    if a[6] & 2:
        c = (200, 40, 40)
    elif a[6] & 1:
        c = (int(c[0] * 0.45), int(c[1] * 0.45), int(c[2] * 0.45))
    d.polygon(poly, fill=c)
# Pads.
for p in data["pads"]:
    i = int(p["s"] / data["step"]) % n
    q = pts[i]
    x, y = P(q[0] + q[9] * p["d"], q[2] + q[10] * p["d"])
    d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(255, 220, 40))
# Start.
x, y = P(pts[0][0], pts[0][2])
d.ellipse([x - 8, y - 8, x + 8, y + 8], fill=(255, 255, 255))
x2, y2 = P(pts[40][0], pts[40][2])
d.line([x, y, x2, y2], fill=(255, 255, 255), width=4)
# Labels.
for s in data["sections"]:
    i = int((s["s0"] + s["s1"]) * 0.5 / data["step"]) % n
    q = pts[i]
    off = 34
    x, y = P(q[0] - q[9] * off / sc * 1.0 - q[9] * 30, q[2] - q[10] * 30)
    d.text((x, y), s["name"], fill=(230, 230, 240), font=font, anchor="mm")
title = "%s  %.0f m  closure %.2f m  height %.0f..%.0f m" % (data["name"], data["length"], data["closure"], ymin, ymax)
d.text((20, 16), title, fill=(255, 255, 255), font=font)
img.save(out)
print("wrote", out, img.size)
