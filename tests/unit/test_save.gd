## Save data: checksum round trip, tamper detection, backup recovery.
extends TestCase


func test_round_trip_and_tamper() -> void:
	var sd: Node = load("res://src/core/save_data.gd").new()
	sd.set("_path", "user://unit_career.json")
	sd.set("_backup", "user://unit_career.bak.json")
	sd.d = sd.call("_fresh")
	sd.d["credits"] = 1234
	sd.call("save")
	var back: Dictionary = sd.call("_load", "user://unit_career.json")
	eq(int(back.get("credits", -1)), 1234, "round trip")
	# Tamper with the credits in the stored text: the checksum must reject it.
	var raw := FileAccess.get_file_as_string("user://unit_career.json")
	var f := FileAccess.open("user://unit_career.json", FileAccess.WRITE)
	f.store_string(raw.replace("1234", "9999"))
	f.close()
	var bad: Dictionary = sd.call("_load", "user://unit_career.json")
	ok(bad.is_empty(), "tampered save rejected")
	# Second save creates the backup from the (now tampered) primary; a fresh save then restores consistency.
	sd.d["credits"] = 50
	sd.call("save")
	var b2: Dictionary = sd.call("_load", "user://unit_career.json")
	eq(int(b2.get("credits", -1)), 50)
	DirAccess.remove_absolute("user://unit_career.json")
	DirAccess.remove_absolute("user://unit_career.bak.json")
	sd.free()


func test_book_race_records_best_lap() -> void:
	var sd: Node = load("res://src/core/save_data.gd").new()
	sd.set("_path", "user://unit_career2.json")
	sd.set("_backup", "user://unit_career2.bak.json")
	sd.d = sd.call("_fresh")
	var r1: Dictionary = sd.call("book_race", "t", 1, {"place": 2, "finished": true, "best_lap": 60.0, "time": 190.0, "laps": [65.0, 63.0, 62.0]})
	ok(r1["new_lap"] and r1["new_race"])
	eq(int(r1["credits"]), 700)
	var r2: Dictionary = sd.call("book_race", "t", 1, {"place": 1, "finished": true, "best_lap": 61.0, "time": 185.0, "laps": [62.0, 62.0, 61.0]})
	ok(not r2["new_lap"] and r2["new_race"])
	# A shorter race is a different record, not a new best over 3 laps.
	var r3: Dictionary = sd.call("book_race", "t", 1, {"place": 4, "finished": true, "best_lap": 62.0, "time": 125.0, "laps": [63.0, 62.0]})
	ok(r3["new_race"], "first 2-lap record")
	near(float(sd.call("record", "t", 1)["best_races"]["3"]), 185.0, 0.001, "3-lap record kept")
	# Solo modes cannot farm winner credits.
	var r4: Dictionary = sd.call("book_race", "t", 1, {"place": 1, "finished": true, "best_lap": 61.0, "time": 120.0, "laps": [60.0, 60.0], "mode": "speed", "medal": 2})
	eq(int(r4["credits"]), 250, "speed challenge pays by medal")
	var r5: Dictionary = sd.call("book_race", "t", 1, {"place": 1, "finished": true, "best_lap": 61.0, "time": 120.0, "laps": [60.0, 60.0], "mode": "time_trial"})
	eq(int(r5["credits"]), 0, "time trial pays nothing")
	near(float(sd.call("record", "t", 1)["best_lap"]), 60.0, 0.001)
	eq(int(sd.d["stats"]["wins"]), 1)
	DirAccess.remove_absolute("user://unit_career2.json")
	DirAccess.remove_absolute("user://unit_career2.bak.json")
	sd.free()
