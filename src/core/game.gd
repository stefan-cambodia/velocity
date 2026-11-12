## Scene flow between the menus and a race. Autoload "Game".
##   Game.start_race({track, team, class, laps, opponents, mode})
##   Game.goto_menu("results", {...})
## Only one top-level screen exists at a time; it is a child of the root window.
extends Node

signal screen_changed(node: Node)

const MENU_SCRIPT := "res://src/ui/menu/menu_root.gd"
const RACE_SCRIPT := "res://src/game/race.gd"

## Parameters of the last race started (for restart).
var race_cfg: Dictionary = {}
var last_result: Dictionary = {}
var current: Node

var _fade: ColorRect
var _layer: CanvasLayer
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.01, 0.012, 0.02, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)


func goto_menu(screen: String = "home", args: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	await _fade_to(1.0, 0.22)
	get_tree().paused = false
	var menu: Node = load(MENU_SCRIPT).new()
	await _swap(menu)
	if menu.has_method("open"):
		menu.call("open", screen, args)
	await get_tree().process_frame
	await _fade_to(0.0, 0.25)
	_busy = false


func start_race(cfg: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	race_cfg = cfg.duplicate(true)
	var t0 := Time.get_ticks_msec()
	await _fade_to(1.0, 0.22)
	get_tree().paused = false
	var race: Node = load(RACE_SCRIPT).new()
	race.set("cfg", race_cfg)
	await _swap(race)
	if race.has_signal("ready_to_race"):
		await race.ready_to_race
	if DevArgs.has("--load-times"):
		print("race ready %d ms after start_race" % (Time.get_ticks_msec() - t0))
	await _fade_to(0.0, 0.3)
	_busy = false


func restart_race() -> void:
	start_race(race_cfg)


## Default race configuration from the settings (and dev arguments).
func default_cfg() -> Dictionary:
	var cfg := {
		"track": Settings.get_v("track"), "team": Settings.get_v("team"), "class": Settings.get_v("speed_class"),
		"laps": Settings.get_v("laps"), "opponents": 7, "difficulty": Settings.get_v("difficulty"), "mode": "race",
	}
	for a in DevArgs.all():
		if a.begins_with("--race="): cfg["track"] = a.substr(7)
		elif a.begins_with("--team="): cfg["team"] = a.substr(7)
		elif a.begins_with("--class="): cfg["class"] = int(a.substr(8))
		elif a.begins_with("--laps="): cfg["laps"] = int(a.substr(7))
		elif a.begins_with("--opponents="): cfg["opponents"] = int(a.substr(12))
		elif a.begins_with("--difficulty="): cfg["difficulty"] = int(a.substr(13))
		elif a.begins_with("--mode="): cfg["mode"] = a.substr(7)
	for a in DevArgs.all():
		if a.begins_with("--career="):
			var ev := Career.event(a.substr(9))
			cfg = Career.race_cfg(cfg, ev, Career.TIERS[Career.tier_of(ev["id"])]["class"], int(cfg["difficulty"]))
			cfg["career_event"] = ev["id"]
		elif a.begins_with("--cup="):
			var c := Career.cup(a.substr(6))
			var cupd: Dictionary = SaveData.d["cup"]
			if cupd.get("id", "") != c["id"]:
				cupd = {"id": c["id"], "round": 0, "standings": {}}
				SaveData.d["cup"] = cupd
			cfg = Career.race_cfg(cfg, c["rounds"][int(cupd["round"])], int(c["class"]), int(c["difficulty"]))
			cfg["cup"] = c["id"]
	if not TrackLibrary.ids().has(cfg["track"]):
		cfg["track"] = TrackLibrary.ids()[0]
	return cfg


func _swap(node: Node) -> void:
	if is_instance_valid(current):
		current.queue_free()
	current = node
	get_tree().root.add_child.call_deferred(node)
	await node.ready
	screen_changed.emit(node)


func _fade_to(alpha: float, time: float) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.0 else Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, time)
	await tw.finished
