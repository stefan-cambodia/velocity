# Performance

## Measured on hardware

**Samsung Galaxy A56 (SM-A566B, Exynos 1580 / Xclipse 540, Android 17), 2026-11-12, debug APK.**
Helix Bay, 1 lap, 8 ships, autopilot, chase camera, auto preset **High** (render scale 0.9 with
adaptive resolution, MSAA 2×, shadows, glow, post pass on).

| Metric | Value |
|--------|-------|
| World build (city, track, AI line) | 4.4 s (line 1.5 s, world 2.2 s) |
| Ready to race (includes first-run shader compilation) | 10.5 s |
| Frame rate (1 s samples, 60 fps cap) | mean 58.1 fps, 71 of 86 samples ≥ 57 |
| Worst samples | 35 fps (one sample, approach to the Helix), 46–55 on the Helix top and Skybridge |
| Draw calls | median 173, max 237 |
| Primitives | 150k–310k |
| Battery temperature over the run | 33.6 → 34.3 °C |

The dips happen on views across the dense city core towards the Spire.

### After optimisation (same phone, same day, 2-lap run)

Changes: post pass 6 → 4 taps, city draw distance 2600 → 1900 m (× preset view factor), facade
windows from three per-pixel hashes to one texture lookup (its mipmaps also provide the distance
average), tunnel sweep light limited to High and Ultra.

| Metric | Lap 1 | Lap 2 |
|--------|-------|-------|
| Mean fps (60 cap) | 58.9 | **59.0** |
| Lowest 1 s sample | 44 (first sight of the tunnel: shader pipeline compilation) | **51** (Helix climb) |
| Samples below 57 | 10 of 86 | 13 of 84, all 51–56, mostly on the Helix section |
| Draw calls | median 196, max 252 | |

- World build 1.5 s (was 2.2 s). Ready to race 9.1 s, including first-run shader compilation.
- Battery 33.0 °C after about 3.5 min of racing (two runs back to back). This is not a thermal soak test.
- One-off hitches the first time a material is drawn (tunnel, effects) disappear on lap 2.

### Glacier Ring (same phone, 2 laps, High)

| Metric | Lap 1 | Lap 2 |
|--------|-------|-------|
| Mean fps | 59.8 | 59.9 |
| Lowest 1 s sample | 52 | 55 |
| Draw calls | median 142, max 215 | |

World build 1.3 s (terrain heightfield 0.7 s); ready to race 8.4 s.

Not measured yet: 90/120 Hz caps, Low/Medium/Ultra presets on device, a
sustained thermal run (5+ races), battery drain rate, memory footprint, other devices and aspect ratios.

## Budgets and techniques

- Physics in pure GDScript data structures, with O(1) local track projection (6 per ship per
  substep). The 8-ship race simulates at 120 Hz without visible CPU cost on the A56.
- The track is chunked into about 96 m meshes (frustum culled), each carrying three shared materials.
- The city is merged into 450 m cell meshes with visibility ranges. Buildings use one facade shader
  with procedural windows (no textures) that fade to their average with distance.
- Particles: streaks (90 × preset factor), pooled spark emitters.
- Audio: 4 positional engine voices for the nearest opponents. Only the player's engine is layered
  (3 loops).
- Quality presets Low/Medium/High/Ultra control render scale, MSAA, shadows, glow, post pass, city
  density, particle count and view distance. Adaptive resolution trades render scale (down to 0.62
  of the preset) to hold the frame-rate cap.

## How to measure

```sh
adb shell "run-as com.velocity.agl sh -c 'echo \"--race=helix_bay --autopilot --telemetry --laps=1 --load-times\" > files/dev_args.txt'"
adb shell monkey -p com.velocity.agl -c android.intent.category.LAUNCHER 1
adb logcat -s godot     # 1 Hz lines: fps, draws, prims, preset, render scale, audio bus peaks
```
