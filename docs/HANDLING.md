# Handling: model, tuning and test procedure

The ship simulation is `src/vehicle/ship_physics.gd`. It is pure data, deterministic, and steps at 120 Hz
(the 60 Hz physics tick runs 2 substeps). All parameters live in `ShipSpec`
(`src/vehicle/ship_spec.gd`). Team ratings (1–10) map onto them in `ShipSpec.from_ratings()`, with
the speed class scaling the base values.

## The model in one page

| Stage | What happens | Key parameters |
|-------|--------------|----------------|
| Surface probes | Four probes at the hull corners (±`probe_len`, ±`probe_wid`) are projected onto the analytic track. A plane fit gives the surface normal under the hull and the hull's height above it. | `probe_len` 2.3, `probe_wid` 1.1 |
| Flux lock | Below `lock_h` the ship is "locked": a spring-damper holds `hover_h` and gravity points along −N (`g_track`), so banks and steep sections hold the ship. Pull-down on crests saturates at `pull_max`, so going over a crest faster than √((g_track+pull_max)/κ) launches the ship. | `hover_h` 1.05, `hover_k` 420, `hover_c` 34 (ζ≈0.83), `g_track` 16, `pull_max` 24 |
| Slopes and banks | The component of world gravity in the surface plane accelerates the ship downhill and pulls it into the inside of a banked turn. It fades out on decks rolled past ~55° (`planar_fade`), where the lock alone holds the ship. | `planar_g` 1.0 |
| Rolling decks | Co-rotating lock: where the deck rolls about its centre line (w rad/m), the velocity, nose, hull up and the step's surface normal are turned rigidly with the deck by w·v·dt. This happens before the yaw and grip stages read the planar velocity. The normal pull as the roll rate changes, v²·(−w′·d − w²·h), is a force. The hover gap's sideways sweep, w·h·v, moves the position, not the velocity, so grip does not read it as slip. A twist drives like a straight. | none: geometry from the track frames |
| Thrust | a = thrust·A0 − A0·(v/v_top)²·(coast + (1−coast)·thrust). Top speed is v_top at full thrust; with the throttle closed the ship coasts down at ≈coast·A0. | `accel`, `v_top`, `coast` 0.35 |
| Yaw | The nose turns at a yaw rate that approaches its target with inertia (`yaw_response`). Target = steer × w_lim, where w_lim = min(`yaw_low`, `steer_k`·a_lat/v): steering is grip-limited at speed and rate-limited when slow. | `yaw_response` 7.5, `steer_k` 1.08, `yaw_low` 1.9 |
| Grip | The velocity turns towards the nose at `align` per second, limited to a_lat/v rad/s. Asking for more yaw than the keels can follow builds slip (drift), and slip costs speed (`scrub`). | `a_lat` 36 m/s² (ARC), `align` 9, `scrub` 0.5 |
| Airbrakes | Each flap (deploys in 80 ms) adds drag `ab_drag`·v, a yaw demand of `ab_yaw`·w_lim towards its side, and `ab_grip` extra lateral capacity. One brake tightens the line; both brake and stay neutral. | `ab_drag` 0.11, `ab_yaw` 0.62, `ab_grip` 0.16 |
| Contact | The floor is a hard limit (`min_clear`): the hull never enters the track, and inbound speed is absorbed and scrubbed. Barriers are analytic and use the hull's extent across the track for its current yaw. The response is restitution `wall_e`, speed loss `wall_mu`·v_in, a yaw kick away from the wall, and damage `wall_dmg`·(v_in−4)^1.3. Yaw damping scales with impact severity, so a ship scraping the outside wall can still steer off it. | `wall_e` 0.22, `wall_mu` 0.5 |
| Air | Gravity `g_air` (1.5 g), the nose eases onto the flight path, and steering keeps `air_control` of its authority. | `g_air` 15, `air_control` 0.35 |

Visual motion (lean, pitch, hover bob, flap angles, plumes) is layered on the model in
`src/vehicle/ship.gd` and never feeds back into the simulation.

## Test procedure

1. **Unit tests**: `godot --headless --path . -s tests/run_tests.gd`. 17 tests. The handling ones:
   hover settles with no residual bobbing and never under minimum clearance; launch time and top
   speed; coast vs. airbrake deceleration; single airbrakes yaw symmetrically; steering is
   progressive and grip-limited; an airbrake tightens a full-lock turn; a full lap of a banked
   oval with grades has no wall contact and no loss of lock; a jump flies and lands without
   penetration; a 20° wall hit deflects without sticking; determinism.
2. **Handling bench**: `tools/dev.sh bench [class=N] [team…] [nolap]`. Repeatable measurements per
   team, plus an AI lap of the Proving Ground.
3. **In-game telemetry**: F3 (or Settings › Camera › Telemetry) shows speed, longitudinal and
   lateral acceleration, lateral velocity, slip, yaw rate, inputs, airbrakes, hover height, lock
   state, pitch and roll, surface alignment, track position and wall impacts.
4. **Telemetry log**: `--csv=/abs/file.csv` records every physics tick of the player's ship
   (20 channels) for plotting.
5. **Practice mode**: the Proving Ground (long straight, banked sweeper, hairpin, S-bends, crest,
   jump, boost pad), no opponents, telemetry on.

## Bench results (ARC class, 2026-11-12)

```
team        t90    top coast brake |   g25   g50  g100 turnin |  path  +ab% | wall% |     lap hits  vmax
halden     5.17    648   8.2  22.7 |  1.01  2.02  3.76  0.275 |    33    30 |    80 |   68.52    2   714
shiranui   5.29    648   8.0  23.7 |  1.06  2.11  3.94  0.258 |    35    34 |    80 |   68.05    2   705
vantor     5.61    654   7.6  22.0 |  0.98  1.95  3.63  0.283 |    32    28 |    80 |   68.85    1   724
aurelle    5.48    671   8.0  22.8 |  0.96  1.92  3.58  0.300 |    30    29 |    80 |   68.45    1   729
meridian   4.78    642   8.7  23.3 |  1.01  2.02  3.76  0.275 |    33    32 |    81 |   68.77    1   703
azimuth    5.57    665   7.8  22.1 |  0.98  1.95  3.64  0.292 |    31    27 |    80 |   68.47    0   732
nyx        5.07    665   8.5  23.8 |  1.02  2.05  3.83  0.275 |    33    32 |    80 |   67.55    1   723
tempest    5.29    648   8.0  24.1 |  1.01  2.02  3.76  0.275 |    33    35 |    80 |   68.67    1   701
```
Columns: t90 = seconds to 90 % of top speed; top = displayed km/h; coast/brake = m/s lost in 1 s
from top speed with the throttle closed / both airbrakes; g25/g50/g100 = steady lateral g at
25/50/100 % steering at 85 % of top speed; turnin = seconds to 90 % of the steady yaw rate; path =
degrees the path turns in 1.5 s at full right lock, and +ab% = the extra turn with the right airbrake;
wall% = speed kept 0.6 s after a 20° hit at 90 % of top speed; lap = AI lap of the Proving Ground
(Elite AI driver).

Re-run on 2026-11-13, after the co-rotating lock, the gravity fade and the AI edge guard: every
handling column is identical for all eight teams. The AI's Proving Ground laps are 0.02–0.10 s
slower, and its wall hits fell from 0–2 per lap to 0.

QUASAR class: top speeds 936–961 km/h, lateral 5.0–5.2 g at full lock, and the same turn-in time.
Faster classes are harder because lateral capacity grows with class as (v_top ratio)^0.85, slower
than speed itself.

## Decisions taken from measurements

- **Steering lock tied to grip, not to a speed curve.** Lateral g grows in proportion to input
  (1.0/2.0/3.8 g at 25/50/100 %), so the steering never saturates early, and full lock asks for
  1.08 × the grip, which gives a small, controllable drift.
- **Yaw damping on wall contact scales with impact speed.** A constant ×0.25 per contact step
  (first version) pinned ships to the outside wall of long corners: the banked-oval test had 904
  contact steps. Now it has 0.
- **Wall damage** was 35 % of the shield for a 20° hit at 80 m/s, and is now 16 %.
- **Co-rotating lock for rolling decks** (Lagrange Station's Corkscrew). In pure world space, a
  ship off the centre line of a rolling deck rides a helix that needs w²·v²·d of centripetal pull,
  about 18 m/s² at the barrier of a 420 m roll at 80 m/s. Nothing supplied it, so the AI hit the
  outside wall mid-roll every lap. Fixing it took four attempts, each measured with a hands-off
  probe:
  1. A centripetal force on its own did almost nothing.
  2. Adding nose transport left a 6 m sideways drift from the hover gap.
  3. Rotating the position kinematically gave the damper a phantom 15 m/s normal velocity, because
     a helicoid's normal tilts by atan(w·d).
  4. A rigid rotation of velocity and orientation still drifted. Grip rebuilt the velocity from a
     planar copy taken before the rotation. Moving the rotation ahead of the yaw stage, and turning
     the step's normal with it, fixed it.

  Result: at most 1 m of drift at 88 m/s and no heading error after the roll
  (`test_corkscrew_keeps_an_off_centre_line_hands_off`). On ordinary bank changes the effect is
  negligible: the four existing circuits keep their lap times and wall counts.
- **Surface alignment** uses normalised interpolation instead of `slerp`. Float32 `slerp` between
  nearly parallel normals raised engine errors 852 times in the jump test.

## Open tuning questions (need hands-on play)

- A 20° wall hit keeps about 80 % of the speed, which may be too forgiving (`wall_mu`).
- Turn-in time is 0.27 s. A shorter time may feel better with touch buttons (`yaw_response`).
- Tilt sensitivity defaults (full lock at 24°) and the steering-assist strength have not been
  tried by a person yet.
- PRO AI best laps on Helix Bay are 82.7–88.3 s and ROOKIE AI 91.0–98.1 s, against an Elite
  autopilot's 82.3 s. No difficulty has been checked against a human player.
- `--time-scale=N` runs now raise the physics tick rate by N, so each step stays 1/60 s. An
  earlier run at a quarter of the intended rate gave the same lap time to within 0.2 s, so the
  simulation is robust to the step size.
