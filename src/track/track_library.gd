## Circuit definitions. Each is a TrackBuilder spec (see track_builder.gd for keys).
class_name TrackLibrary
extends RefCounted

static var _cache: Dictionary = {}


static func ids() -> PackedStringArray:
	return PackedStringArray(["helix_bay", "glacier_ring", "proving_ground"])


static func spec(id: String) -> Dictionary:
	match id:
		"proving_ground":
			return _proving_ground()
		"helix_bay":
			return _helix_bay()
		"glacier_ring":
			return _glacier_ring()
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
			{"len": 850, "name": "Main straight", "tags": ["start"], "flex": true},
			{"len": 500, "turn": 90, "bank": 16, "name": "Sweeper"},
			{"len": 250, "rise": 14, "name": "Climb"},
			{"len": 170, "turn": 180, "bank": 10, "width": 26, "ease": 0.35, "name": "Hairpin"},
			{"len": 250, "rise": -14, "name": "Descent"},
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
