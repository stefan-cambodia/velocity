## Career and championship data and rules (no UI here).
##
## Career: four tiers following the speed classes. Each event has an objective
## (finishing place, medal or points) and a credit reward; a tier opens when
## enough events of the previous tier are complete. Credits also unlock teams
## and classes (see menu_root UNLOCK_*), so every race moves the player on.
##
## Championships: cups of rounds mixing formats; points per finishing place;
## standings are saved between rounds.
class_name Career
extends RefCounted

const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1, 0, 0]

const TIERS := [
	{"name": "SPARK ROOKIE SERIES", "class": 0, "need": 0, "events": [
		{"id": "s1", "title": "First Flight", "mode": "speed", "track": "proving_ground", "laps": 2, "goal": {"medal": 1}, "reward": 300},
		{"id": "s2", "title": "Proving Ground Sprint", "mode": "race", "track": "proving_ground", "laps": 2, "difficulty": 0, "goal": {"place": 3}, "reward": 400},
		{"id": "s3", "title": "Helix Bay Debut", "mode": "race", "track": "helix_bay", "laps": 2, "difficulty": 0, "goal": {"place": 3}, "reward": 500},
		{"id": "s6", "title": "Runway Sprint", "mode": "race", "track": "atacama_spaceport", "laps": 2, "difficulty": 0, "goal": {"place": 3}, "reward": 500},
		{"id": "s5", "title": "Ice Shelf Sprint", "mode": "race", "track": "glacier_ring", "laps": 2, "difficulty": 0, "goal": {"place": 3}, "reward": 500},
		{"id": "s7", "title": "Station Shakedown", "mode": "race", "track": "lagrange_station", "laps": 2, "difficulty": 0, "goal": {"place": 3}, "reward": 500},
		{"id": "s4", "title": "Last Ship Standing", "mode": "elimination", "track": "helix_bay", "difficulty": 0, "goal": {"place": 3}, "reward": 500},
	]},
	{"name": "ARC PRO SERIES", "class": 1, "need": 3, "events": [
		{"id": "a1", "title": "Seafront Sprint", "mode": "race", "track": "helix_bay", "laps": 3, "difficulty": 1, "goal": {"place": 3}, "reward": 700},
		{"id": "a2", "title": "Harbour Brawl", "mode": "combat", "track": "helix_bay", "laps": 2, "difficulty": 1, "goal": {"place": 3}, "reward": 700},
		{"id": "a6", "title": "Salar Speed Trial", "mode": "speed", "track": "atacama_spaceport", "laps": 2, "goal": {"medal": 2}, "reward": 800},
		{"id": "a5", "title": "Aurora Duel", "mode": "combat", "track": "glacier_ring", "laps": 2, "difficulty": 1, "goal": {"place": 2}, "reward": 800},
		{"id": "a7", "title": "Zero-G Time Attack", "mode": "speed", "track": "lagrange_station", "laps": 2, "goal": {"medal": 2}, "reward": 800},
		{"id": "a3", "title": "Helix Time Attack", "mode": "speed", "track": "helix_bay", "laps": 3, "goal": {"medal": 2}, "reward": 800},
		{"id": "a4", "title": "Knockout Night", "mode": "elimination", "track": "proving_ground", "difficulty": 1, "goal": {"place": 2}, "reward": 800},
	]},
	{"name": "NOVA MASTERS", "class": 2, "need": 3, "events": [
		{"id": "n1", "title": "Masters Grand Prix", "mode": "race", "track": "helix_bay", "laps": 3, "difficulty": 1, "goal": {"place": 2}, "reward": 1200},
		{"id": "n2", "title": "Proving Ground Gauntlet", "mode": "combat", "track": "proving_ground", "laps": 3, "difficulty": 2, "goal": {"place": 2}, "reward": 1200},
		{"id": "n3", "title": "Nova Gold Run", "mode": "speed", "track": "helix_bay", "laps": 2, "goal": {"medal": 3}, "reward": 1500},
		{"id": "n5", "title": "Launch Day", "mode": "race", "track": "atacama_spaceport", "laps": 3, "difficulty": 1, "goal": {"place": 2}, "reward": 1300},
		{"id": "n6", "title": "Habitat Knockout", "mode": "elimination", "track": "lagrange_station", "difficulty": 1, "goal": {"place": 2}, "reward": 1400},
		{"id": "n4", "title": "Crevasse Knockout", "mode": "elimination", "track": "glacier_ring", "difficulty": 2, "goal": {"place": 2}, "reward": 1500},
	]},
	{"name": "QUASAR ELITE", "class": 3, "need": 2, "events": [
		{"id": "q1", "title": "Elite Invitational", "mode": "race", "track": "helix_bay", "laps": 3, "difficulty": 2, "goal": {"place": 1}, "reward": 2500},
		{"id": "q2", "title": "The Last Lap of Light", "mode": "elimination", "track": "helix_bay", "difficulty": 2, "goal": {"place": 1}, "reward": 2500},
		{"id": "q4", "title": "Orbit Insertion", "mode": "combat", "track": "atacama_spaceport", "laps": 3, "difficulty": 2, "goal": {"place": 1}, "reward": 2500},
		{"id": "q5", "title": "Lagrange Grand Prix", "mode": "race", "track": "lagrange_station", "laps": 3, "difficulty": 2, "goal": {"place": 1}, "reward": 2500},
		{"id": "q3", "title": "Polar Night Record", "mode": "speed", "track": "glacier_ring", "laps": 3, "goal": {"medal": 3}, "reward": 2500},
	]},
]

const CUPS := [
	{"id": "bay_open", "name": "HELIX BAY OPEN", "class": 1, "difficulty": 1, "rounds": [
		{"track": "helix_bay", "mode": "race", "laps": 3},
		{"track": "glacier_ring", "mode": "race", "laps": 3},
		{"track": "helix_bay", "mode": "elimination"},
	]},
	{"id": "polar_cup", "name": "POLAR CUP", "class": 1, "difficulty": 1, "rounds": [
		{"track": "glacier_ring", "mode": "race", "laps": 3},
		{"track": "proving_ground", "mode": "combat", "laps": 3},
		{"track": "glacier_ring", "mode": "elimination"},
		{"track": "helix_bay", "mode": "race", "laps": 3},
	]},
	{"id": "solar_cup", "name": "SOLAR CUP", "class": 1, "difficulty": 1, "rounds": [
		{"track": "atacama_spaceport", "mode": "race", "laps": 3},
		{"track": "helix_bay", "mode": "combat", "laps": 2},
		{"track": "atacama_spaceport", "mode": "elimination"},
	]},
	{"id": "orbit_cup", "name": "ORBIT CUP", "class": 2, "difficulty": 1, "rounds": [
		{"track": "lagrange_station", "mode": "race", "laps": 3},
		{"track": "atacama_spaceport", "mode": "race", "laps": 3},
		{"track": "lagrange_station", "mode": "combat", "laps": 2},
		{"track": "glacier_ring", "mode": "elimination"},
	]},
	{"id": "iron_cup", "name": "IRON CUP", "class": 2, "difficulty": 2, "rounds": [
		{"track": "proving_ground", "mode": "combat", "laps": 3},
		{"track": "helix_bay", "mode": "race", "laps": 3},
		{"track": "helix_bay", "mode": "combat", "laps": 2},
		{"track": "glacier_ring", "mode": "race", "laps": 4},
	]},
]


static func event(id: String) -> Dictionary:
	for t: Dictionary in TIERS:
		for e: Dictionary in t["events"]:
			if e["id"] == id:
				return e
	return {}


static func tier_of(id: String) -> int:
	for k in TIERS.size():
		for e: Dictionary in TIERS[k]["events"]:
			if e["id"] == id:
				return k
	return -1


## True when the result meets the event objective.
static func goal_met(goal: Dictionary, res: Dictionary) -> bool:
	if not res.get("finished", false):
		return false
	if goal.has("place") and int(res.get("place", 99)) > int(goal["place"]):
		return false
	if goal.has("medal") and int(res.get("medal", 0)) < int(goal["medal"]):
		return false
	return true


static func goal_text(goal: Dictionary) -> String:
	if goal.has("medal"):
		return "%s MEDAL OR BETTER" % ["", "BRONZE", "SILVER", "GOLD"][int(goal["medal"])]
	var p := int(goal.get("place", 1))
	return "WIN" if p == 1 else "FINISH TOP %d" % p


## Number of completed events in a tier, from the career save dictionary.
static func completed_in(tier: int, done: Dictionary) -> int:
	var n := 0
	for e: Dictionary in TIERS[tier]["events"]:
		if done.get(e["id"], false):
			n += 1
	return n


static func tier_open(tier: int, done: Dictionary) -> bool:
	if tier == 0:
		return true
	return completed_in(tier - 1, done) >= int(TIERS[tier]["need"])


static func cup(id: String) -> Dictionary:
	for c: Dictionary in CUPS:
		if c["id"] == id:
			return c
	return {}


## Race configuration for a career event or a cup round.
static func race_cfg(base: Dictionary, src: Dictionary, class_idx: int, difficulty: int) -> Dictionary:
	var cfg := base.duplicate()
	cfg["track"] = src["track"]
	cfg["mode"] = src["mode"]
	cfg["laps"] = int(src.get("laps", 3))
	cfg["class"] = class_idx
	cfg["difficulty"] = int(src.get("difficulty", difficulty))
	cfg["opponents"] = 0 if src["mode"] in ["speed", "time_trial"] else 7
	return cfg


## Adds a round's finishing order to the cup standings ({name: points}).
static func score_round(standings: Dictionary, table: Array) -> void:
	for r: Dictionary in table:
		var p := int(r["place"])
		var pts: int = POINTS[clampi(p - 1, 0, POINTS.size() - 1)]
		var key: String = "YOU" if r["player"] else String(r["name"])
		standings[key] = int(standings.get(key, 0)) + pts


static func sorted_standings(standings: Dictionary) -> Array:
	var rows := []
	for k: String in standings:
		rows.append([k, int(standings[k])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows
