# Art direction: VELOCITY, Anti-Gravity League (2189)

## Pillars

1. **Industrial futurism, not generic sci-fi.** Late-90s aerospace and racing engineering: faceted
   panels with hard creases (chines), bolted plates, exposed structure, functional detail. No
   sleek blobs, no greebles without a purpose.
2. **Dusk megacity.** Every circuit belongs to a lived-in world with depth: water, skylines, distant
   mountains, haze. The track is a ribbon threaded through it, usually elevated.
3. **Light is information.** Emissive colour always means something: cyan for the racing surface and
   barriers, orange for corners and speed rhythm, magenta and amber for city accents, red for
   warnings, team colour for ships.
4. **Readable at 900 km/h on a 6-inch screen.** Strong value contrast between the dark track and its
   bright edges, chevrons on the outside of every corner, and the centre of the screen kept free of
   effects.

## Palette

| Role | Colour (linear) | Use |
|------|-----------------|-----|
| Night base | `#05070B` – `#141A24` | Track surface, deck, UI panels |
| Track cyan | `0.25, 0.8, 1.0` | Barrier foot strip, barrier rail, gates, UI accent |
| Rhythm amber | `1.0, 0.55, 0.15` | Speed-rhythm bars every 24 m, corner chevrons |
| City warm / cool windows | `1.0, 0.72, 0.42` / `0.55, 0.78, 1.0` | Facades |
| Accent magenta | `1.0, 0.2, 0.75` | Landmark rings, some gates |
| Warning red | `1.0, 0.05, 0.03` | Aircraft lights, start lights |
| Sky | zenith `#04081A` → violet `#22143F` → horizon `#F2613A` | Dusk sky shader |

## Materials

- **Track surface:** composite deck plates (4 × 2 m) with a fine etched hexagonal "conductor
  lattice". This is the physical reason ships hover only over the track. Low metal and low
  specular, so the low sun never washes it brown. Markings are analytic in the shader.
- **Barriers:** bolted gunmetal panels with an energy band at the foot and a rail light. Scrolling
  orange chevrons appear on the outside wall of any corner, pointing the way.
- **Ship paint:** clear-coated metallic livery driven by a vertex-colour mask (primary, secondary,
  accent, carbon trim) with procedural panel seams, so one hull serves every team.
- **Buildings:** a facade shader with procedural windows. Whole floors light together, bays are
  1.7 × 3.3 m, and windows fade to their average brightness with distance, so far towers never
  shimmer.
- **Water:** dark gloss with Fresnel sky reflection and broken warm streaks.

## Architecture language

Brutalist mass with precise light. Stepped arcologies with neon terrace edges, octagonal spires
with tapered crowns and neon rings, slabs with cantilevered upper blocks, twin towers joined by sky
bridges, round towers with structural fins. Trackside structure is honest engineering: T-pylons
under the deck, radial cantilever arms carrying the Helix, light gates as portal frames.

## Circuit worlds

Each circuit has its own time of day and light, while track, barrier and gate language stays the
same everywhere, so the racing surface always reads the same way.

| Circuit | World | Light | Signature |
|---------|-------|-------|-----------|
| Helix Bay | Dusk megacity on a bay | Low warm sun, violet sky, haze | The Helix climb, the Spire, the seafront |
| Glacier Ring | Arctic research station | Polar night, aurora, snowfall | Ice tunnel, crevasse jump |
| Atacama Spaceport | High-desert launch complex | Full daylight, hard shadows | Rocket and tower, flame-trench jump, assembly hall |
| Lagrange Station | Racing station in low orbit | Hard white sun, black sky, blue planet-shine from below, no fog | The planet filling the lower view, the 360° Corkscrew, the spiral round the station core, habitat gardens |
| Forge Caldera | Volcanic foundry island | Night, ash clouds lit orange from below, lava as the main light | The lava lake and Lava Bridge, Foundry Hall's crucibles, steam vents |
| Costa Branca | White Mediterranean town | Bright summer afternoon, deep blue sky, turquoise sea | The town climb, the church dome, the sea arch, the lighthouse headland |
| Cirrus Heights | Sky port above the clouds | Sunrise: pastel pink and gold, long shadows, cloud sea below | The Spire Spiral, moored airships, the cloud bank dive |
| Tempest Shoals | Offshore platforms | Night storm: blue-grey, sodium deck lights, lightning, rain | The swell under the causeway, the Gasholder Spiral, the Flare Jump |
| Thalassa Deep | Undersea research city | Blue-green water column, light shafts, bioluminescence | Glass tubes over kelp and reef, the blue hole tower, the trench spiral |
| Serra Verde | Rainforest gorge below a dam | Overcast morning, soft warm sun, rain, valley mist, wet glossy track | The dam crest start, the cable-stayed Sky Bridge over the River Run, the grotto's water curtain, the Veil |

In orbit the "lived-in world with depth" pillar comes from the planet (clouds, coasts, night-side
cities), the moon, the wheel habitat and the station's own structure. Exposed trusses, solar wings
and lit interiors play the role the skyline plays elsewhere.

## Vehicle design language

Long low noses, a faceted central fuselage with chine creases, bubble canopies, and twin flux-keel
pods with glowing emitters underneath. Canted fins are joined by a rear aerofoil, and there are
three engines. Airbrakes are visible flaps on the wing trailing edges that physically open.
Liveries use three paint zones with crisp edges (paired loft rows on every boundary), never
gradients.

## Teams

| Team | Identity | Livery (primary / secondary / accent) | Character |
|------|----------|---------------------------------------|-----------|
| Halden Aerospace | Nordic orbital yards | glacier white / cobalt / signal orange | Balanced, forgiving |
| Shiranui Works | Kyushu foundry | crimson / black / bone | Razor handling, thin shield |
| Vantor Schwerwerk | Ruhr heavy industry | gunmetal / hazard amber / black | Armoured, slow to wake |
| Aurelle | Lyon couture aerodynamics | ivory / deep teal / gold | Fastest in a straight line |
| Meridian Flux Labs | Belém biotech | emerald / sun yellow / white | Explosive thrust, light |
| Azimuth Ares | Mars colony consortium | rust orange / charcoal / white | High speed, stable |
| Nyx Syndicate | Unregistered prototype | black / magenta / violet | Expert ship, fragile |
| Tempest Orbital | Perth launch complex | sky cyan / white / violet | Airbrake specialist |

Each team flies its own hull, built from one parametric design (`ShipModel.DEFAULT_DESIGN` plus
`Catalog.TEAMS[].design`). For example, Shiranui is a narrow knife with a centre fin, Vantor a wide
blunt brick with quad fins, and Aurelle a long needle with a strut wing. Team logos for menus and
billboards are a planned asset and have not been made yet.

## UI

Uppercase Rajdhani for labels, Orbitron for numerals. Dark translucent panels with a cyan
left-edge bar, and the focused element gets a wider bar. The HUD is corner-anchored on desktop. On
touch devices the speed gauge moves to the bottom centre and the shield to the top centre, so both
thumbs stay clear.

## Effects

FOV widening with speed, world-anchored speed streaks, an edge-only radial blur with chromatic
aberration, ship energy trails in team colour, a light sweep in tunnels, bloom on emissives, impact
sparks and camera shake. The centre of the screen is always left untouched.

## Open issues

- Vertex colours: `StandardMaterial3D` treats them as linear unless `vertex_color_is_srgb` is set,
  which makes vertex-tinted props paler than intended. Costa Branca sets it on its own materials;
  the shared materials in `Mats` and the older worlds have not been reviewed for this yet.
