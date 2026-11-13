## Circuit definitions. Each is a TrackBuilder spec (see track_builder.gd for keys).
class_name TrackLibrary
extends RefCounted

static var _cache: Dictionary = {}


static func ids() -> PackedStringArray:
	return PackedStringArray(["helix_bay", "glacier_ring", "atacama_spaceport", "lagrange_station", "serra_verde", "proving_ground"])


static func spec(id: String) -> Dictionary:
	match id:
		"proving_ground":
			return _proving_ground()
		"helix_bay":
			return _helix_bay()
		"glacier_ring":
			return _glacier_ring()
		"atacama_spaceport":
			return _atacama()
		"lagrange_station":
			return _lagrange()
		"serra_verde":
			return _serra_verde()
	push_error("unknown track " + id)
	return {}


static func get_track(id: String) -> TrackData:
	if not _cache.has(id):
		_cache[id] = TrackBuilder.build(spec(id))
	return _cache[id]


## Handling test circuit: a long straight for top speed, a fast banked
## sweeper, a hairpin, an S, a crest and dip, and a jump. Flat open space
## around it, no scenery. Used by the handling bench and tests.
static func _proving_ground() -> Dictionary:
	return {
		"name": "Proving Ground",
		"start": Vector3(0, 20, 0),
		"heading": 0.0,
		"width": 28.0,
		"segments": [
			{"len": 850, "name": "Main straight", "tags": ["start", "recharge"], "flex": true},
			{"len": 500, "turn": 90, "bank": 16, "name": "Sweeper"},
			{"len": 250, "rise": 24, "name": "Climb"},
			{"len": 170, "turn": 180, "bank": 10, "width": 26, "ease": 0.35, "name": "Hairpin"},
			{"len": 250, "rise": -24, "name": "Descent"},
			{"len": 220, "turn": -180, "bank": -12, "ease": 0.35, "name": "Switchback"},
			{"len": 200, "turn": -45, "bank": -10, "name": "S left"},
			{"len": 200, "turn": 45, "bank": 10, "name": "S right"},
			{"len": 120, "rise": 3.0, "exit_slope": 0.09, "name": "Kicker"},
			{"len": 46, "rise": -2.0, "exit_slope": -0.12, "tags": ["gap"], "name": "Jump"},
			{"len": 140, "rise": -1.0, "name": "Landing"},
			{"len": 500, "turn": 90, "bank": 14, "name": "Long right"},
			{"len": 600, "name": "Back straight"},
			{"len": 400, "turn": 90, "bank": 12, "name": "Turn 11"},
			{"len": 830, "name": "Return", "flex": true},
			{"len": 400, "turn": 90, "bank": 12, "name": "Final turn"},
		],
		"pads": [
			{"seg": 12, "at": 0.3, "d": 0.0, "kind": "boost"},
			{"seg": 0, "at": 0.6, "d": -6.0, "kind": "weapon", "length": 8.0},
			{"seg": 0, "at": 0.6, "d": 6.0, "kind": "weapon", "length": 8.0},
			{"seg": 4, "at": 0.5, "d": 0.0, "kind": "weapon", "length": 8.0},
			{"seg": 10, "at": 0.5, "d": -5.0, "kind": "weapon", "length": 8.0},
			{"seg": 14, "at": 0.4, "d": 5.0, "kind": "weapon", "length": 8.0},
		],
	}


## HELIX BAY: the master circuit. A coastal megacity at dusk; the track is an
## elevated ribbon through it. See docs/TRACK_HELIX_BAY.md for the design.
static func _helix_bay() -> Dictionary:
	return {
		"name": "Helix Bay",
		"start": Vector3(0, 18, 0),
		"heading": 0.0,
		"width": 30.0,
		"segments": [
			{"len": 300, "name": "Grand Straight", "tags": ["start"], "flex": true},
			{"len": 320, "tags": ["start", "recharge"], "name": "Recharge Strip"},
			{"len": 420, "turn": 70, "bank": 12, "name": "Arcology Sweep"},
			{"len": 360, "rise": -6, "name": "Seafront"},
			{"len": 240, "turn": -35, "bank": -10, "name": "Promenade Esses"},
			{"len": 280, "turn": 55, "bank": 14},
			{"len": 260, "name": "Pier Straight", "flex": true},
			{"len": 160, "turn": 30, "bank": 10, "width": 27},
			{"len": 864, "turn": 450, "rise": 48, "bank": 26, "width": 26, "ease": 0.12, "name": "The Helix"},
			{"len": 520, "rise": -6, "width": 28, "name": "Skybridge"},
			{"len": 260, "turn": -40, "rise": -18, "bank": -12, "name": "Spire Drop"},
			{"len": 260, "turn": 60, "rise": -12, "bank": 18, "name": "Corkscrew"},
			{"len": 140, "rise": 2.0, "exit_slope": 0.08, "name": "Canal Kicker"},
			{"len": 55, "rise": -6.0, "exit_slope": -0.12, "tags": ["gap"], "name": "Canal Jump"},
			{"len": 160, "rise": -3.0},
			{"len": 420, "turn": -50, "rise": -8, "bank": -8, "tags": ["tunnel"], "ceiling": 9.0, "width": 26, "name": "Harbour Tunnel"},
			{"len": 300, "tags": ["tunnel"], "ceiling": 9.0, "width": 26},
			{"len": 200, "rise": 9, "width": 26, "name": "Dock Rise"},
			{"len": 150, "turn": 160, "bank": 8, "width": 24, "ease": 0.35, "name": "Dock Hairpin"},
			{"len": 320, "width": 34, "name": "Container Run"},
			{"len": 140, "turn": -30, "bank": -8, "width": 28, "name": "Crane Chicane"},
			{"len": 140, "turn": 30, "bank": 8},
			{"len": 300, "turn": 20, "bank": 6, "width": 30, "name": "Bay Curve"},
		],
		"pads": [
			{"seg": 3, "at": 0.45, "d": -6.0, "kind": "boost"},
			{"seg": 9, "at": 0.3, "d": 5.0, "kind": "boost"},
			{"seg": 19, "at": 0.5, "d": 10.0, "kind": "boost"},
			{"seg": 0, "at": 0.55, "d": -7.0, "kind": "weapon", "length": 8.0},
			{"seg": 0, "at": 0.55, "d": 7.0, "kind": "weapon", "length": 8.0},
			{"seg": 9, "at": 0.65, "d": -6.0, "kind": "weapon", "length": 8.0},
			{"seg": 14, "at": 0.6, "d": 0.0, "kind": "weapon", "length": 8.0},
			{"seg": 17, "at": 0.4, "d": -5.0, "kind": "weapon", "length": 8.0},
			{"seg": 19, "at": 0.5, "d": -10.0, "kind": "weapon", "length": 8.0},
		],
		"islands": [
			{"seg": 19, "from": 0.18, "to": 0.82, "d0": -2.5, "d1": 2.5},
		],
	}


## GLACIER RING: Svalbard Ice Laboratory under the aurora. Fast flowing
## sweeps over the ice shelf, a switchback climb up the glacier, the blue
## Crevasse Tunnel and the Ridge Drop jump. See docs/TRACK_GLACIER_RING.md.
static func _glacier_ring() -> Dictionary:
	return {
		"name": "Glacier Ring",
		"start": Vector3(0, 12, 0),
		"heading": 0.0,
		"width": 30.0,
		"segments": [
			{"len": 300, "tags": ["start", "recharge"], "name": "Recharge Strip"},
			{"len": 620, "turn": 100, "bank": 15, "name": "Aurora Sweep"},
			{"len": 260, "rise": -8, "name": "Fjord Run"},
			{"len": 360, "turn": -60, "bank": -12, "name": "Seal Bend"},
			{"len": 190, "turn": 150, "rise": 12, "bank": 10, "width": 26, "ease": 0.3, "name": "Glacier Switchbacks"},
			{"len": 160, "rise": 10, "width": 26},
			{"len": 190, "turn": -150, "rise": 12, "bank": -10, "width": 26, "ease": 0.3},
			{"len": 420, "turn": 40, "rise": -6, "tags": ["tunnel"], "ceiling": 10.0, "width": 26, "name": "Crevasse Tunnel"},
			{"len": 160, "rise": -10, "width": 28, "name": "Ridge Drop"},
			{"len": 110, "rise": 2.5, "exit_slope": 0.1},
			{"len": 70, "rise": -12.0, "exit_slope": -0.16, "tags": ["gap"], "name": "Ridge Jump"},
			{"len": 170, "rise": -8.5, "width": 30},
			{"len": 280, "turn": 50, "bank": 12, "name": "Station Esses"},
			{"len": 160, "turn": 120, "bank": 8, "width": 25, "ease": 0.35, "name": "Radar Hairpin"},
			{"len": 600, "rise": 8, "width": 30, "name": "Tundra Run", "flex": true},
			{"len": 220, "turn": 20, "bank": 5, "name": "Tundra Kinks"},
			{"len": 220, "turn": -20, "bank": -5},
			{"len": 340, "turn": -45, "bank": -10, "name": "Floe Esses"},
			{"len": 340, "turn": 45, "bank": 10},
			{"len": 300},
			{"len": 460, "turn": 110, "bank": 12, "name": "Shelf Turn"},
			{"len": 400, "name": "Ice Shelf Straight", "tags": ["start"], "flex": true},
		],
		"pads": [
			{"seg": 2, "at": 0.4, "d": 6.0, "kind": "boost"},
			{"seg": 11, "at": 0.6, "d": 0.0, "kind": "boost"},
			{"seg": 14, "at": 0.55, "d": -7.0, "kind": "boost"},
			{"seg": 2, "at": 0.15, "d": -6.0, "kind": "weapon", "length": 8.0},
			{"seg": 3, "at": 0.7, "d": 5.0, "kind": "weapon", "length": 8.0},
			{"seg": 8, "at": 0.4, "d": -5.0, "kind": "weapon", "length": 8.0},
			{"seg": 14, "at": 0.25, "d": 6.0, "kind": "weapon", "length": 8.0},
			{"seg": 19, "at": 0.5, "d": 0.0, "kind": "weapon", "length": 8.0},
		],
	}


## ATACAMA SPACEPORT: a high-desert launch complex in full daylight. Runway
## start, a sweep over the white salt flats, a red-rock canyon climb, the drop
## to the flame-trench jump, a banked loop around the rocket on its pad, the
## interior of the vehicle assembly hall, and the long crawlerway home.
## See docs/TRACK_ATACAMA_SPACEPORT.md.
static func _atacama() -> Dictionary:
	return {
		"name": "Atacama Spaceport",
		"start": Vector3(0, 8, 0),
		"heading": 0.0,
		"width": 32.0,
		"segments": [
			{"len": 450, "tags": ["start", "recharge"], "name": "Runway"},
			{"len": 560, "turn": 120, "bank": 14, "name": "Salar Sweep"},
			{"len": 250, "name": "Salt Flat Run"},
			{"len": 260, "turn": -70, "rise": 10, "bank": -12, "width": 28, "name": "Canyon Entry"},
			{"len": 240, "turn": 60, "rise": 8, "bank": 12, "width": 27, "name": "Canyon Esses"},
			{"len": 240, "turn": -60, "rise": 6, "bank": -12, "width": 27},
			{"len": 200, "rise": 4, "width": 28, "name": "Mesa Crest"},
			{"len": 220, "rise": -22, "width": 30, "name": "Canyon Drop"},
			{"len": 100, "rise": 2.0, "exit_slope": 0.1},
			{"len": 60, "rise": -6.0, "exit_slope": -0.12, "tags": ["gap"], "name": "Flame Trench Jump"},
			{"len": 150, "rise": -4.0},
			{"len": 1000, "turn": 200, "rise": 2.0, "bank": 18, "ease": 0.15, "name": "Launch Pad Loop"},
			{"len": 380, "tags": ["tunnel"], "ceiling": 30.0, "width": 30, "name": "Assembly Hall"},
			{"len": 160, "turn": 35, "bank": 8, "width": 28, "name": "Tracking Chicane"},
			{"len": 160, "turn": -35, "bank": -8, "width": 28},
			{"len": 320, "turn": -30, "bank": -8, "width": 30, "name": "Dish Bend"},
			{"len": 600, "name": "Crawlerway", "flex": true},
			{"len": 260, "turn": 15, "bank": 4, "name": "Crawler Kinks"},
			{"len": 260, "turn": -15, "bank": -4},
			{"len": 300},
			{"len": 520, "turn": 140, "bank": 14, "name": "Final Turn"},
			{"len": 200, "tags": ["start"], "name": "Grid Straight", "flex": true},
		],
		"pads": [
			{"seg": 2, "at": 0.5, "d": 7.0, "kind": "boost"},
			{"seg": 10, "at": 0.6, "d": 0.0, "kind": "boost"},
			{"seg": 16, "at": 0.4, "d": -8.0, "kind": "boost"},
			{"seg": 0, "at": 0.55, "d": -7.0, "kind": "weapon", "length": 8.0},
			{"seg": 0, "at": 0.55, "d": 7.0, "kind": "weapon", "length": 8.0},
			{"seg": 3, "at": 0.3, "d": 5.0, "kind": "weapon", "length": 8.0},
			{"seg": 11, "at": 0.45, "d": -6.0, "kind": "weapon", "length": 8.0},
			{"seg": 16, "at": 0.7, "d": 6.0, "kind": "weapon", "length": 8.0},
		],
	}


## LAGRANGE STATION: a racing circuit built through an orbital station above
## a living planet. The Corkscrew rolls the track through 360 degrees (the
## flux lock holds the ship upside down), the Hub Spiral circles the station
## core, the Habitat Ring runs inside the rotating torus and the Docking Bay
## chicane threads the hangar. See docs/TRACK_LAGRANGE_STATION.md.
static func _lagrange() -> Dictionary:
	return {
		"name": "Lagrange Station",
		"start": Vector3(0, 60, 0),
		"heading": 0.0,
		"width": 30.0,
		"segments": [
			{"len": 350, "tags": ["start", "recharge"], "name": "Concourse"},
			{"len": 600, "turn": 90, "bank": 14, "name": "Array Sweep"},
			{"len": 600, "rise": 20, "name": "Truss Run"},
			{"len": 420, "roll": 360, "width": 28, "name": "The Corkscrew"},
			{"len": 300, "turn": 90, "rise": -20, "bank": 12, "name": "Hub Dive"},
			{"len": 500, "rise": -20},
			{"len": 1050, "turn": 360, "rise": -30, "bank": 20, "ease": 0.15, "name": "Hub Spiral"},
			{"len": 500, "turn": 90, "tags": ["tunnel"], "ceiling": 11.0, "width": 26, "name": "Habitat Ring"},
			{"len": 220, "turn": -45, "bank": -10, "name": "Antenna Esses"},
			{"len": 220, "turn": 45, "bank": 10},
			{"len": 500, "rise": 20, "name": "Dock Approach", "flex": true},
			{"len": 170, "turn": -60, "bank": -8, "ease": 0.35, "width": 26, "tags": ["tunnel"], "ceiling": 22.0, "name": "Docking Bay"},
			{"len": 170, "turn": 60, "bank": 8, "ease": 0.35, "width": 26, "tags": ["tunnel"], "ceiling": 22.0},
			{"len": 560, "turn": 90, "rise": 30, "bank": 12, "name": "Return Sweep"},
			{"len": 300, "tags": ["start"], "name": "Grid Straight", "flex": true},
		],
		"pads": [
			{"seg": 2, "at": 0.3, "d": 0.0, "kind": "boost"},
			{"seg": 10, "at": 0.4, "d": -6.0, "kind": "boost"},
			{"seg": 5, "at": 0.5, "d": 7.0, "kind": "boost"},
			{"seg": 0, "at": 0.6, "d": -7.0, "kind": "weapon", "length": 8.0},
			{"seg": 0, "at": 0.6, "d": 7.0, "kind": "weapon", "length": 8.0},
			{"seg": 5, "at": 0.2, "d": -6.0, "kind": "weapon", "length": 8.0},
			{"seg": 8, "at": 0.5, "d": -4.0, "kind": "weapon", "length": 8.0},
			{"seg": 13, "at": 0.6, "d": 6.0, "kind": "weapon", "length": 8.0},
		],
	}


## SERRA VERDE: a rainforest gorge below a hydroelectric dam, in morning rain.
## A figure-eight: the start is on the dam crest, the lap drops into the gorge
## and runs along the river, leaves through a grotto behind a waterfall and
## jumps the plunge pool, climbs through the canopy, and crosses back over the
## River Run on the Sky Bridge, a long viaduct about 40 m above it.
## See docs/TRACK_SERRA_VERDE.md.
static func _serra_verde() -> Dictionary:
	return {
		"name": "Serra Verde",
		"start": Vector3(0, 60, 0),
		"heading": 0.0,
		"width": 30.0,
		"segments": [
			{"len": 420, "tags": ["start", "recharge"], "name": "Dam Crest"},
			{"len": 320, "turn": 90, "rise": -12, "bank": 12, "name": "Spillway Bend"},
			{"len": 200, "rise": -6, "name": "Rim Run"},
			{"len": 540, "turn": 90, "rise": -22, "bank": 13, "name": "Cascade Descent"},
			{"len": 220, "turn": -35, "rise": -4, "bank": -10, "width": 28, "name": "Gorge Esses"},
			{"len": 220, "turn": 35, "rise": -4, "bank": 10, "width": 28},
			{"len": 700, "rise": -2, "name": "River Run", "flex": true},
			{"len": 200, "turn": 12, "bank": 4, "name": "River Bends"},
			{"len": 200, "turn": -12, "bank": -4},
			{"len": 340, "turn": -90, "rise": 6, "bank": -10, "tags": ["tunnel"], "ceiling": 12.0, "width": 26, "name": "Falls Grotto"},
			{"len": 100, "rise": 2.0, "exit_slope": 0.1, "name": "Falls Jump"},
			{"len": 60, "rise": -6.0, "exit_slope": -0.12, "tags": ["gap"]},
			{"len": 150, "rise": -4.0},
			{"len": 420, "turn": -90, "rise": 16, "bank": -12, "name": "Canopy Climb"},
			{"len": 220, "turn": 45, "rise": 8, "bank": 10, "width": 28, "name": "Canopy Esses"},
			{"len": 220, "turn": -45, "rise": 8, "bank": -10, "width": 28},
			{"len": 360, "turn": -90, "rise": 8, "bank": -12, "name": "Ridge Turn"},
			{"len": 900, "rise": 4, "width": 26, "name": "Sky Bridge", "flex": true},
			{"len": 420, "turn": 90, "rise": 8, "bank": 12, "width": 30, "name": "Reservoir Turn"},
			{"len": 250, "tags": ["start"], "name": "Grid Straight"},
		],
		"pads": [
			{"seg": 2, "at": 0.5, "d": -6.0, "kind": "boost"},
			{"seg": 6, "at": 0.35, "d": 6.0, "kind": "boost"},
			{"seg": 17, "at": 0.3, "d": 0.0, "kind": "boost"},
			{"seg": 0, "at": 0.55, "d": -7.0, "kind": "weapon", "length": 8.0},
			{"seg": 0, "at": 0.55, "d": 7.0, "kind": "weapon", "length": 8.0},
			{"seg": 3, "at": 0.4, "d": 5.0, "kind": "weapon", "length": 8.0},
			{"seg": 13, "at": 0.5, "d": -5.0, "kind": "weapon", "length": 8.0},
			{"seg": 17, "at": 0.7, "d": -6.0, "kind": "weapon", "length": 8.0},
		],
	}

