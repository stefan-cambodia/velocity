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

### Atacama Spaceport (same phone, 2 laps, High, daylight with shadows)

| Metric | Lap 1 | Lap 2 |
|--------|-------|-------|
| Mean fps | 59.2 | **60.0** |
| Lowest 1 s sample | 50 (first sight of materials) | 59 |
| Draw calls | median 161, max 252 | |

World build 1.5 s; ready to race 11.3 s on the first run after install (shader compilation).

### Lagrange Station (same phone, 2 laps, High), 2026-11-13

First build: lap 1 mean 58.5 fps, lap 2 59.2, lows 49–51 every lap in the Hub Spiral. The dips
did not follow draw calls or primitives: 51 fps at 172 draws and 155k primitives, 60 fps at 208
draws and 279k. Adaptive resolution fell to 0.76, so the cost was per pixel. The suspect was the
sky shader's analytic planet: about 19 value-noise evaluations per planet pixel, and the banked
spiral shows the most planet. The surface fields were then **baked into one texture of the visible
cap** (`gen_textures.py gen_planet`, 2048², VRAM-compressed, mipmapped), so lighting is the only
per-pixel work left.

| Metric | Lap 1 | Lap 2 |
|--------|-------|-------|
| Mean fps (60 cap) | 59.9 (was 58.5) | **60.0** (was 59.2) |
| Lowest 1 s sample | 58 (was 49) | **60** (was 51) |
| Hub Spiral mean / lowest | 60.0 / 60 (was 55.4 / 49) | 60.0 / 60 (was 57.1 / 51) |
| Adaptive render scale | 0.90, the preset value (was down to 0.76) | 0.90 |
| Draw calls | median 178, max 227 | |

World build 1.4 s (orbital world 0.74 s); ready to race 9.0 s.

### Texture mipmaps (all circuits), 2026-11-13

Every 3D shader samples its textures with mipmap filtering (anisotropic on the track and
barriers), but every texture had been imported **without mipmaps**. Godot only switches a texture
to 3D import settings when the editor sees it on a 3D material, and these materials are built in
code. So the deck lattice aliased at distance, the facade windows never averaged with distance as
the building shader intends, and texture-cache use was poor. `track_*`, `panel_*` and `windows`
now import with mipmaps. Helix Bay, the heaviest circuit, re-measured on the same phone:

| Metric | Lap 1 | Lap 2 |
|--------|-------|-------|
| Mean fps | 59.9 (was 58.9) | **60.0** (was 59.0) |
| Lowest 1 s sample | 57 (was 44) | **59** (was 51) |
| Samples below 57 | 0 (was 10 of 86) | 0 (was 13 of 84) |

Battery 36.4 °C after three back-to-back runs (about 10 minutes of racing). This is still not a
thermal soak test.

### Serra Verde (same phone): not measured yet

The first device run was interrupted 3 s into the countdown: the system log shows the Recents
view opening and the game going to the background. A retry found another app in the foreground,
so the phone was not used again. From that start alone: 17,600 trees on High, world build 1.8 s,
ready to race 19.1 s on the first run after install (shader compilation), 258k primitives and 193
draws on the grid, 55–60 fps once warm. This is the heaviest circuit by primitive count (Lagrange
has about 150k), so a full 2-lap measurement must come before any performance claim. Tree count
(`city` preset factor) and visibility range are the levers.

Not measured yet: 90/120 Hz caps, Low/Medium/Ultra presets on device, a
sustained thermal run (5+ races), battery drain rate, memory footprint, other devices and aspect ratios.

## Budgets and techniques

- Physics in pure GDScript data structures, with O(1) local track projection (6 per ship per
  substep). The 8-ship race simulates at 120 Hz without visible CPU cost on the A56.
- The track is chunked into about 96 m meshes (frustum culled), each carrying three shared materials.
- The city is merged into 450 m cell meshes with visibility ranges. Buildings use one facade shader
  whose windows come from one texture lookup. Its mipmaps fade far windows to their average.
- Textures sampled in 3D must be imported with mipmaps. Godot's automatic 3D detection does not
  fire for materials built in code, so this is set explicitly in each `.import` file.
- Expensive per-pixel noise is baked: the Lagrange planet surface is one texture fetch, not 19 noise
  evaluations.
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
