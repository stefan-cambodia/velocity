## The league: teams, ships and pilots. All names and identities are original
## to this project. Ratings are 1..10 (5 = reference), see ShipSpec.from_ratings.
## Every team trades something away: no ship is best in every category.
class_name Catalog
extends RefCounted

const TEAMS := [
	{"id": "halden", "name": "HALDEN AEROSPACE", "short": "HALDEN", "ship": "HX-7 SKADI", "origin": "Tromsø Orbital Yards",
	 "blurb": "Glacier-white precision engineering. Forgiving, balanced, quick off the line.",
	 "livery": {"primary": Color(0.9, 0.92, 0.95), "secondary": Color(0.06, 0.22, 0.72), "accent": Color(1.0, 0.42, 0.08)},
	 "glow": Color(0.3, 0.8, 1.0),
	 "design": {},
	 "ratings": {"speed": 5, "thrust": 6, "handling": 6, "stability": 6, "shield": 5, "airbrake": 5}},
	{"id": "shiranui", "name": "SHIRANUI WORKS", "short": "SHIRANUI", "ship": "KAGERO R", "origin": "Kita-Kyushu Foundry",
	 "blurb": "Razor turn-in and furious airbrakes. Paper-thin shield.",
	 "livery": {"primary": Color(0.62, 0.03, 0.05), "secondary": Color(0.04, 0.04, 0.05), "accent": Color(0.95, 0.92, 0.85)},
	 "glow": Color(1.0, 0.3, 0.2),
	 "design": {"fuse_len": 1.15, "nose": "sharp", "pod_x": 0.98, "pod_scale": 0.82, "pod_len": 0.95, "fins": "center", "aerofoil": false, "canards": true, "engine_r": 0.9},
	 "ratings": {"speed": 5, "thrust": 5, "handling": 9, "stability": 4, "shield": 3, "airbrake": 8}},
	{"id": "vantor", "name": "VANTOR SCHWERWERK", "short": "VANTOR", "ship": "VS-40 BASTION", "origin": "Ruhr Arcology",
	 "blurb": "An armoured heavyweight. Slow to wake, impossible to push around.",
	 "livery": {"primary": Color(0.24, 0.25, 0.27), "secondary": Color(1.0, 0.68, 0.05), "accent": Color(0.05, 0.05, 0.05)},
	 "glow": Color(1.0, 0.7, 0.2),
	 "design": {"fuse_w": 1.18, "nose": "blunt", "pod_x": 1.36, "pod_scale": 1.25, "fins": "quad", "aerofoil": true, "aero_h": 0.75, "canards": false, "engine_r": 1.2, "wing_chord": 1.15},
	 "ratings": {"speed": 6, "thrust": 3, "handling": 4, "stability": 8, "shield": 9, "airbrake": 4}},
	{"id": "aurelle", "name": "AURELLE", "short": "AURELLE", "ship": "LUMEN 9", "origin": "Lyon Skyport",
	 "blurb": "Couture aerodynamics: the fastest straight-line ship in the league. Demands commitment.",
	 "livery": {"primary": Color(0.93, 0.89, 0.8), "secondary": Color(0.0, 0.42, 0.45), "accent": Color(0.85, 0.65, 0.25)},
	 "glow": Color(0.4, 1.0, 0.9),
	 "design": {"fuse_len": 1.18, "fuse_w": 0.92, "nose": "sharp", "pod_x": 1.26, "pod_scale": 0.85, "pod_len": 1.15, "pod_z": 0.25, "fins": "center", "aerofoil": true, "aero_h": 0.62, "canards": false},
	 "ratings": {"speed": 9, "thrust": 5, "handling": 3, "stability": 5, "shield": 5, "airbrake": 4}},
	{"id": "meridian", "name": "MERIDIAN FLUX LABS", "short": "MERIDIAN", "ship": "MFL CORAL", "origin": "Belém Biotech Coast",
	 "blurb": "Bio-grown keels with explosive thrust. Lighter than it should be.",
	 "livery": {"primary": Color(0.02, 0.45, 0.25), "secondary": Color(1.0, 0.85, 0.1), "accent": Color(0.95, 0.95, 0.95)},
	 "glow": Color(0.5, 1.0, 0.4),
	 "design": {"fuse_len": 0.9, "pod_x": 1.1, "pod_scale": 1.12, "pod_z": -0.35, "pod_len": 0.9, "fins": "twin", "aerofoil": false, "canards": true, "engine_r": 1.25, "canopy_z": 0.15},
	 "ratings": {"speed": 4, "thrust": 9, "handling": 6, "stability": 4, "shield": 5, "airbrake": 6}},
	{"id": "azimuth", "name": "AZIMUTH ARES", "short": "AZIMUTH", "ship": "AA-3 THARSIS", "origin": "Arsia Mons Colony",
	 "blurb": "Built for thin Martian air: high top speed and rock-steady at the limit.",
	 "livery": {"primary": Color(0.85, 0.32, 0.08), "secondary": Color(0.12, 0.12, 0.14), "accent": Color(0.9, 0.9, 0.9)},
	 "glow": Color(1.0, 0.5, 0.2),
	 "design": {"nose": "blunt", "pod_x": 1.3, "pod_len": 1.2, "pod_z": 0.35, "fins": "twin", "aerofoil": true, "aero_h": 0.82, "canards": false, "engine_r": 1.1},
	 "ratings": {"speed": 8, "thrust": 4, "handling": 4, "stability": 7, "shield": 6, "airbrake": 3}},
	{"id": "nyx", "name": "NYX SYNDICATE", "short": "NYX", "ship": "UMBRA", "origin": "Unregistered",
	 "blurb": "Black-market prototype. Ferocious in expert hands, fragile and twitchy in anyone else's.",
	 "livery": {"primary": Color(0.03, 0.03, 0.04), "secondary": Color(0.85, 0.05, 0.6), "accent": Color(0.6, 0.3, 1.0)},
	 "glow": Color(0.9, 0.2, 1.0),
	 "design": {"fuse_len": 1.12, "nose": "sharp", "fuse_w": 0.9, "pod_x": 1.02, "pod_scale": 0.9, "fins": "quad", "aerofoil": false, "canards": true, "canopy_z": -0.15},
	 "ratings": {"speed": 8, "thrust": 8, "handling": 7, "stability": 2, "shield": 2, "airbrake": 6}},
	{"id": "tempest", "name": "TEMPEST ORBITAL", "short": "TEMPEST", "ship": "TO-5 SQUALL", "origin": "Perth Launch Complex",
	 "blurb": "Airbrake specialists. The best ship for carving a perfect line through the technical sections.",
	 "livery": {"primary": Color(0.08, 0.65, 0.85), "secondary": Color(0.95, 0.96, 0.98), "accent": Color(0.45, 0.2, 0.75)},
	 "glow": Color(0.4, 0.9, 1.0),
	 "design": {"pod_x": 1.42, "pod_scale": 0.85, "fins": "center", "aerofoil": true, "aero_h": 0.7, "canards": true, "wing_chord": 1.3},
	 "ratings": {"speed": 5, "thrust": 5, "handling": 6, "stability": 5, "shield": 5, "airbrake": 9}},
]

## AI pilots: personality parameters (see AIDriver).
const PILOTS := [
	{"name": "S. ARNESEN", "team": "halden", "style": "technical"},
	{"name": "K. IZUMI", "team": "shiranui", "style": "aggressive"},
	{"name": "M. VOSS", "team": "vantor", "style": "defensive"},
	{"name": "C. DELACROIX", "team": "aurelle", "style": "speed"},
	{"name": "R. AZEVEDO", "team": "meridian", "style": "risk"},
	{"name": "T. OKONKWO", "team": "azimuth", "style": "speed"},
	{"name": "V. NULL", "team": "nyx", "style": "aggressive"},
	{"name": "J. MARRA", "team": "tempest", "style": "technical"},
]


static func team(id: String) -> Dictionary:
	for t: Dictionary in TEAMS:
		if t["id"] == id:
			return t
	return TEAMS[0]


static func team_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for t: Dictionary in TEAMS:
		out.append(t["id"])
	return out


static func spec_for(team_id: String, class_idx: int) -> ShipSpec:
	return ShipSpec.from_ratings(team(team_id)["ratings"], class_idx)
