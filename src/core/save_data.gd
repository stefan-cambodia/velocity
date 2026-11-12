## Career progress and records, stored as versioned JSON with a SHA-256
## checksum and a backup copy, so a torn or tampered write never loses a career.
extends Node

signal changed

const VERSION := 1
const PATH := "user://career.json"
const BACKUP := "user://career.bak.json"
const SALT := "velocity-agl-v1"

var d: Dictionary = {}
var _path: String = PATH
var _backup: String = BACKUP


func _ready() -> void:
	if DevArgs.has("--autopilot") or DevArgs.has("--test-save"):
		_path = "user://test_career.json"
		_backup = "user://test_career.bak.json"
	d = _load(_path)
	if d.is_empty():
		d = _load(_backup)
		if not d.is_empty():
			push_warning("career restored from backup")
	d = _migrate(d)


func _fresh() -> Dictionary:
	return {
		"version": VERSION,
		"credits": 0,
		"records": {},            # "<track>/<class>" -> {best_lap, best_race, races, wins}
		"unlocked_teams": ["halden", "tempest", "vantor"],
		"unlocked_tracks": ["helix_bay"],
		"unlocked_classes": [0, 1],
		"stats": {"races": 0, "wins": 0, "podiums": 0, "distance": 0.0},
		"career": {},             # event id -> true when the objective was met
		"cup": {},                # running championship: {id, round, standings: {name: points}}
		"cups_won": [],
	}


func _migrate(src: Dictionary) -> Dictionary:
	var base := _fresh()
	if src.is_empty():
		return base
	for k: String in base:
		if not src.has(k):
			src[k] = base[k]
	src["version"] = VERSION
	return src


## File format: {"v": VERSION, "data": "<json text>", "sum": sha256(json text + salt)}.
## The checksum covers the exact stored text (JSON numbers do not round-trip
## as the same text once parsed, so the data is kept as a string).
func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not parsed.has("data") or not parsed.has("sum") or not (parsed["data"] is String):
		return {}
	var text: String = parsed["data"]
	if (text + SALT).sha256_text() != parsed["sum"]:
		push_warning("save %s failed its checksum" % path)
		return {}
	var data: Variant = JSON.parse_string(text)
	return data if data is Dictionary else {}


func save() -> void:
	var text := JSON.stringify(d)
	var wrapped := JSON.stringify({"v": VERSION, "data": text, "sum": (text + SALT).sha256_text()})
	if FileAccess.file_exists(_path):
		DirAccess.copy_absolute(_path, _backup)
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f != null:
		f.store_string(wrapped)
		f.close()
	changed.emit()


func record(track: String, class_idx: int) -> Dictionary:
	var key := "%s/%d" % [track, class_idx]
	var r: Dictionary = d["records"]
	if not r.has(key):
		r[key] = {"best_lap": 0.0, "best_race": 0.0, "races": 0, "wins": 0}
	return r[key]


## Career and championship bookkeeping for a finished race; adds to `out`.
func book_meta(cfg: Dictionary, res: Dictionary, table: Array, out: Dictionary) -> void:
	var ev_id: String = cfg.get("career_event", "")
	if ev_id != "":
		var ev := Career.event(ev_id)
		var met := Career.goal_met(ev.get("goal", {}), res)
		out["career_event"] = ev_id
		out["goal_met"] = met
		var car: Dictionary = d["career"]
		if met and not car.get(ev_id, false):
			car[ev_id] = true
			out["credits"] = int(out["credits"]) + int(ev["reward"])
			d["credits"] = int(d["credits"]) + int(ev["reward"])
			out["reward"] = int(ev["reward"])
	var cup_id: String = cfg.get("cup", "")
	if cup_id != "":
		var cupd: Dictionary = d["cup"]
		if cupd.get("id", "") != cup_id:
			cupd = {"id": cup_id, "round": 0, "standings": {}}
		Career.score_round(cupd["standings"], table)
		cupd["round"] = int(cupd["round"]) + 1
		var rounds: int = (Career.cup(cup_id)["rounds"] as Array).size()
		out["cup_round"] = cupd["round"]
		out["cup_rounds"] = rounds
		out["cup_standings"] = Career.sorted_standings(cupd["standings"])
		if int(cupd["round"]) >= rounds:
			var top: Array = out["cup_standings"][0]
			out["cup_done"] = true
			if top[0] == "YOU":
				(d["cups_won"] as Array).append(cup_id)
				out["credits"] = int(out["credits"]) + 2000
				d["credits"] = int(d["credits"]) + 2000
				out["cup_won"] = true
			cupd = {}
		d["cup"] = cupd
	save()


## Books a finished race. Returns {credits, new_lap, new_race}.
## Best race times are kept per lap count ("best_races": {"3": seconds}).
## Credits: by finishing place against opponents; solo modes pay by medal
## (speed challenge) or nothing (time trial, practice) so they cannot be farmed.
func book_race(track: String, class_idx: int, res: Dictionary) -> Dictionary:
	var r := record(track, class_idx)
	if not r.has("best_races"):
		r["best_races"] = {}
	var out := {"credits": 0, "new_lap": false, "new_race": false}
	r["races"] = int(r["races"]) + 1
	var st: Dictionary = d["stats"]
	st["races"] = int(st["races"]) + 1
	var place: int = res.get("place", 0)
	var mode: String = res.get("mode", "race")
	var solo: bool = mode in ["speed", "time_trial", "practice"]
	if res.get("finished", false):
		var lap: float = res.get("best_lap", 0.0)
		if lap > 0.0 and (float(r["best_lap"]) <= 0.0 or lap < float(r["best_lap"])):
			r["best_lap"] = lap
			out["new_lap"] = true
		var total: float = res.get("time", 0.0)
		var laps_key := str((res.get("laps", []) as Array).size())
		var races: Dictionary = r["best_races"]
		if mode in ["race", "time_trial", "speed"] and total > 0.0 and (not races.has(laps_key) or total < float(races[laps_key])):
			races[laps_key] = total
			r["best_race"] = total
			out["new_race"] = true
		if not solo:
			if place == 1:
				r["wins"] = int(r["wins"]) + 1
				st["wins"] = int(st["wins"]) + 1
			if place >= 1 and place <= 3:
				st["podiums"] = int(st["podiums"]) + 1
			out["credits"] = [0, 1000, 700, 500, 350, 250, 180, 120, 80][clampi(place, 0, 8)]
		elif mode == "speed":
			out["credits"] = [0, 120, 250, 400][clampi(int(res.get("medal", 0)), 0, 3)]
	st["distance"] = float(st["distance"]) + float(res.get("distance", 0.0))
	d["credits"] = int(d["credits"]) + int(out["credits"])
	save()
	return out
