# Controls

Every input source writes the same `ShipControls` frame (steer, thrust, left airbrake, right airbrake,
fire); `DriveInput` merges them. The AI writes the same structure.

## Touch (Android)

Pick a scheme in Settings › Controls (or in the pause menu). Until the player picks one, phones with a
motion sensor use **Tilt** and the others use **Touch buttons**.

| Scheme | Left thumb | Right thumb | Steering |
|--------|-----------|-------------|----------|
| Tilt | Left airbrake | Right airbrake, Fire above it | Tilt the phone (calibrate in Settings; dead zone, sensitivity, full lock at 24°) |
| Touch buttons | ◀ ▶ buttons (wind on to full lock in 0.22 s) | L / R airbrake, Fire | Digital with a ramp: a tap corrects, a hold is a full turn |
| Touch slider | Floating pad: steering follows how far the finger slides from where it landed | L / R airbrake, Fire | Analogue |

- Both airbrakes together = brake. Thrust is automatic by default; Settings › Thrust › "Thrust pad"
  adds a thrust control instead.
- Generous zones: any touch in the lower left or right third of the screen goes to the nearest thumb control.
- Pause (top centre) and CAM (camera cycle) buttons. Optional haptics on press.
- Opacity and size are in Settings. Per-control positions can be stored under
  `Settings.layout["<scheme>/<id>"] = [x, y, radius]` in viewport fractions. **There is no in-game
  layout editor yet.**
- Steering assist (Off / Low / High) adds the steering the track curvature needs while the player's
  own input is near zero, and nudges away from a barrier the ship is about to touch. It fades out as
  soon as the player steers.

## Keyboard

| Key | Action |
|-----|--------|
| ← → / A D | Steer (ramped) |
| ↑ / W | Thrust (automatic by default) |
| ↓ / S | Brake (both airbrakes) |
| Q / Z | Left airbrake |
| E / C | Right airbrake |
| Space | Fire |
| V / Tab | Cycle camera (standard, wide, close, cockpit) |
| F3 | Telemetry overlay |
| Esc / P | Pause |

## Gamepad

Left stick steers (analogue, dead zone 0.08, sensitivity in Settings). LT / RT are the analogue
left / right airbrakes, LB / RB the digital airbrakes, A thrust, B brake, X fire, Y camera, Start pause.
Menus are fully navigable by d-pad and stick. Button remapping is not implemented yet.
