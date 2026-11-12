# Glacier Ring: Svalbard Ice Laboratory

6.3 km, clockwise, 4–38 m above the fjord ice, under a polar twilight sky with an aurora.
Definition: `TrackLibrary._glacier_ring()`. World: `src/world/glacier.gd`.
Map: `tools/dev.sh map glacier_ring /tmp/gr.png`.

It is the counterpart to Helix Bay: Helix Bay is a dense night city with tight technical
sections, while Glacier Ring is open, bright and fast, with long sweeps and a big jump.

| Section | Character |
|---------|-----------|
| Recharge Strip / Ice Shelf Straight | Start and finish over the ice shelf; shield recharge |
| Aurora Sweep | 100° right, 15° bank, R≈254 m: flat out at ARC |
| Fjord Run | Descends to 4 m over the frozen fjord; boost pad, weapon pad |
| Seal Bend | 60° left |
| Glacier Switchbacks | ±150° hairpins (R≈51 m) climbing 34 m up the glacier: the technical section |
| Crevasse Tunnel | 420 m through the glacier, glowing blue ice walls, 40° right |
| Ridge Drop / Ridge Jump | 10 m drop, 5.7° kicker, 70 m gap over a crevasse: 2.2 s of air at ARC top speed |
| Station Esses / Radar Hairpin | Around the research station (domes, radar dishes, habitat modules, masts, turbines) |
| Tundra Run / Kinks / Floe Esses | About 2 km of fast running back along the fjord: the top-speed section, with gentle kinks and an S |
| Shelf Turn | 110° right onto the start straight |

Measured (ARC, autopilot, 3 laps): best lap 78.9 s, PRO AI 79.1–84.6 s, longest air 2.18 s,
peak slip 19.9° (switchbacks), lowest hull height 0.97 m (no surface contact).

## How the world is built

- **Terrain**: a 32 m heightfield (FBM snow mountains rising away from the circuit and towards
  the edge of the map) that is always pulled below the track deck within the corridor. Where it
  drops under 0 m, the frozen fjord shows through.
- **Glacier ridge**: a lofted mound over the Crevasse Tunnel with ice portal faces. It is separate
  geometry because a heightfield cannot contain a tunnel.
- **Lighting**: a low pink-gold sun from the south, cool fill, bright ambient light from the aurora sky shader,
  cold fog, light snowfall around the camera.
