## The menus: one root with a 3D showroom behind a stack of screens.
##   open("home" | "race" | "settings" | "records" | "results", args)
## Navigable by touch, mouse, keyboard and gamepad (focus-based).
extends Node

const UNLOCK_TEAM_CREDITS := {"halden": 0, "tempest": 0, "vantor": 0, "meridian": 1500, "shiranui": 3000, "azimuth": 4500, "aurelle": 6500, "nyx": 9000}
const UNLOCK_CLASS_CREDITS := [0, 0, 3000, 8000]
const MODES := [
	{"id": "race", "name": "QUICK RACE", "blurb": "Seven rivals, full race distance."},
	{"id": "time_trial", "name": "TIME TRIAL", "blurb": "Alone on the circuit against the clock and your records."},
	{"id": "practice", "name": "PRACTICE", "blurb": "The Proving Ground handling course, no opponents, telemetry on."},
]
## Modes offered in the race setup screen.
const RACE_MODES := ["race", "elimination", "combat", "speed"]
const RACE_MODE_NAMES := ["SINGLE RACE", "ELIMINATION", "COMBAT", "SPEED CHALLENGE"]

var showroom: Node3D
var ui: CanvasLayer
var screen: Control
var _cfg: Dictionary = {}
var _ship_parts: ShipModel.Parts
var _turntable: Node3D
var _cam: Camera3D
var _t: float = 0.0
var _screen_name: String = ""
var _quit_dialog: Control = null


func _ready() -> void:
	DriveInput.ensure_actions()
	_cfg = Game.default_cfg()
	_cfg["mode"] = "race"
	_build_showroom()
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	Audio.music("menu", 1.5)
	for a in DevArgs.all():
		if a.begins_with("--menu-shot="):
			_shot(a.substr(12))
		elif a == "--menu-quit":     # dev: open the quit confirmation (screenshots)
			get_tree().create_timer(0.5).timeout.connect(_confirm_quit)


func _shot(path: String) -> void:
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	get_tree().quit()


func open(name: String, args: Dictionary = {}) -> void:
	_screen_name = name
	_quit_dialog = null
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = UIKit.theme()
	ui.add_child(screen)
	_frame_ship(name == "race")
	match name:
		"race": _race_setup()
		"career": _career()
		"cups": _cups()
		"settings": _settings(args.get("tab", "controls"))
		"records": _records()
		"results": _results(args)
		_: _home()
	Audio.music("menu", 1.5)


func _process(delta: float) -> void:
	_t += delta
	if _turntable:
		_turntable.rotation.y = _t * 0.35


# ------------------------------------------------------------------ showroom

func _build_showroom() -> void:
	showroom = Node3D.new()
	add_child(showroom)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/sky_dusk.gdshader")
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = Quality.p["glow"]
	env.glow_intensity = 0.7
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.2, 0.32)
	env.fog_density = 0.0011
	var we := WorldEnvironment.new()
	we.environment = env
	showroom.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-40), 0)
	key.light_color = Color(1.0, 0.75, 0.6)
	key.light_energy = 1.3
	key.shadow_enabled = true
	showroom.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-15), deg_to_rad(150), 0)
	rim.light_color = Color(0.4, 0.7, 1.0)
	rim.light_energy = 1.4
	showroom.add_child(rim)
	# Platform: dark disc with a glowing ring.
	var mk := MeshKit.new()
	mk.use("metal_dark")
	mk.cyl(Vector3(0, -1.6, 0), Vector3(0, -1.2, 0), 4.0, 3.85, 48, Color(0.5, 0.5, 0.55))
	mk.use("neon_cyan")
	mk.torus(Vector3(0, -1.2, 0), Vector3.UP, 3.9, 0.05, 64, 4, Color.WHITE)
	showroom.add_child(mk.instance("Platform"))
	# A ring of distant towers for depth.
	var city := MeshKit.new()
	city.use("bld")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(170.0, 420.0)
		var h := rng.randf_range(30.0, 210.0)
		HelixBay.block(city, Vector3(cos(a) * r, -1.6, sin(a) * r), Vector3(rng.randf_range(10, 26), h, rng.randf_range(10, 26)), Color(0.25, 0.27, 0.32, 0.5))
	showroom.add_child(city.instance("Skyline"))
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1200, 1200)
	floor_mi.mesh = pm
	floor_mi.position = Vector3(0, -1.62, 0)
	floor_mi.material_override = Mats.shader_mat("ground_grid", {"spacing": 6.0})
	showroom.add_child(floor_mi)
	_turntable = Node3D.new()
	showroom.add_child(_turntable)
	_set_ship(_cfg.get("team", "halden"))
	_cam = Camera3D.new()
	_cam.fov = 34.0
	showroom.add_child(_cam)
	_frame_ship(false)
	_cam.current = true


## Ship on the right (home) or centred above the options (race setup).
func _frame_ship(centred: bool) -> void:
	if centred:
		_cam.position = Vector3(1.2, 3.4, 13.0)
		_cam.look_at(Vector3(0.6, -1.9, 0), Vector3.UP)
	else:
		_cam.position = Vector3(3.0, 1.9, 11.0)
		_cam.look_at(Vector3(-2.3, -0.1, 0), Vector3.UP)


func _set_ship(team_id: String) -> void:
	for c in _turntable.get_children():
		c.queue_free()
	_ship_parts = ShipModel.build(Catalog.team(team_id).get("livery", {}), false, Catalog.team(team_id).get("design", {}))
	_turntable.add_child(_ship_parts.root)
	for pl in _ship_parts.plumes:
		pl.set_instance_shader_parameter("thrust", 0.6)


# ------------------------------------------------------------------ screens

## A vertical scroll area for lists that outgrow the screen (touch drag, wheel,
## and focus-following for gamepad and keyboard).
func _scroll(pos: Vector2, size: Vector2) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.position = pos
	sc.size = size
	sc.follow_focus = true
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	screen.add_child(sc)
	return sc


func _col(x: float, y: float, w: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = Vector2(x, y)
	box.custom_minimum_size = Vector2(w, 0)
	box.add_theme_constant_override("separation", 10)
	screen.add_child(box)
	return box


func _home() -> void:
	var box := _col(64, 70, 420)
	box.add_child(UIKit.title("VELOCITY", 72))
	var sub := UIKit.label("ANTI-GRAVITY LEAGUE  ·  2189", 24, UIKit.ACC)
	box.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	box.add_child(gap)
	box.add_theme_constant_override("separation", 7)
	var first := UIKit.button("CAREER", func() -> void: open("career"), 420)
	box.add_child(first)
	box.add_child(UIKit.button("QUICK RACE", _choose_mode.bind("race"), 420))
	box.add_child(UIKit.button("CHAMPIONSHIP", func() -> void: open("cups"), 420))
	box.add_child(UIKit.button("TIME TRIAL", _choose_mode.bind("time_trial"), 420))
	box.add_child(UIKit.button("PRACTICE", _choose_mode.bind("practice"), 420))
	box.add_child(UIKit.button("RECORDS", func() -> void: open("records"), 420))
	box.add_child(UIKit.button("SETTINGS", func() -> void: open("settings"), 420))
	var quit := UIKit.button("QUIT", _confirm_quit, 420)
	box.add_child(quit)
	for b in box.get_children():
		if b is Button:
			(b as Button).custom_minimum_size = Vector2(420, 50)
	var cr := UIKit.label("CREDITS  %d" % int(SaveData.d["credits"]), 24, UIKit.ACC)
	cr.position = Vector2(1060, 30)
	screen.add_child(cr)
	var foot := UIKit.label("STEER: TILT / TOUCH / PAD   ·   AIRBRAKES: L / R", 18, UIKit.DIM, false)
	foot.position = Vector2(640, 676)
	screen.add_child(foot)
	first.grab_focus.call_deferred()


## Asks before closing the game: on a phone a stray tap on QUIT (or the back
## button) should not end the session. CANCEL has the focus, so a pad or
## keyboard press defaults to staying.
func _confirm_quit() -> void:
	if _quit_dialog != null:
		return
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)
	_quit_dialog = dim
	var p := UIKit.panel(Vector2(560, 0))
	p.position = Vector2(360, 250)
	dim.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	v.add_child(UIKit.label("QUIT VELOCITY?", 32))
	v.add_child(UIKit.label("Progress and records are saved.", 20, UIKit.DIM, false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var yes := UIKit.button("QUIT", func() -> void: get_tree().quit(), 260)
	var no := UIKit.button("CANCEL", _close_quit_dialog, 260)
	row.add_child(yes)
	row.add_child(no)
	no.grab_focus.call_deferred()


func _close_quit_dialog() -> void:
	if _quit_dialog != null:
		_quit_dialog.queue_free()
		_quit_dialog = null
	if screen:
		for c in screen.find_children("*", "Button", true, false):
			if (c as Button).text == "QUIT":
				(c as Button).grab_focus.call_deferred()
				break


func _notification(what: int) -> void:
	# Android back button: on the home screen it asks to quit; elsewhere it goes home.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _quit_dialog != null:
			_close_quit_dialog()
		elif _screen_name == "home" or _screen_name == "":
			_confirm_quit()
		else:
			open("home")


func _choose_mode(id: String) -> void:
	_cfg["mode"] = id
	if id == "practice":
		var cfg := _cfg.duplicate()
		cfg["track"] = "proving_ground"
		cfg["opponents"] = 0
		cfg["laps"] = 99
		Settings.set_v("show_telemetry", true)
		Game.start_race(cfg)
		return
	open("race")


func _race_setup() -> void:
	var tt := "TIME TRIAL" if _cfg["mode"] == "time_trial" else "QUICK RACE"
	var head := UIKit.title(tt, 40)
	head.position = Vector2(56, 32)
	screen.add_child(head)
	# Team list (left).
	var teams := _col(40, 96, 280)
	teams.add_theme_constant_override("separation", 7)
	teams.add_child(UIKit.label("TEAM", 18, UIKit.DIM))
	var credits := int(SaveData.d["credits"])
	var panel_bg := ColorRect.new()
	panel_bg.color = Color(0.02, 0.03, 0.05, 0.72)
	panel_bg.position = Vector2(884, 86)
	panel_bg.size = Vector2(376, 520)
	screen.add_child(panel_bg)
	var info := _col(900, 96, 340)
	var first: Button = null
	for t: Dictionary in Catalog.TEAMS:
		var tid: String = t["id"]
		var need: int = UNLOCK_TEAM_CREDITS.get(tid, 0)
		var unlocked := credits >= need or (SaveData.d["unlocked_teams"] as Array).has(tid)
		var b := UIKit.button(t["short"] if unlocked else "%s  ·  %d CR" % [t["short"], need], func() -> void:
			_cfg["team"] = tid
			Settings.set_v("team", tid)
			_set_ship(tid)
			_team_info(info, tid), 280)
		b.disabled = not unlocked
		b.custom_minimum_size = Vector2(280, 44)
		b.add_theme_font_size_override("font_size", 21)
		b.focus_entered.connect(func() -> void:
			if unlocked:
				_cfg["team"] = tid
				_set_ship(tid)
				_team_info(info, tid))
		teams.add_child(b)
		if tid == _cfg.get("team", "halden"):
			first = b
	_team_info(info, _cfg.get("team", "halden"))
	# Race options (bottom centre).
	var opt_bg := ColorRect.new()
	opt_bg.color = Color(0.02, 0.03, 0.05, 0.72)
	opt_bg.position = Vector2(335, 402)
	opt_bg.size = Vector2(540, 276)
	screen.add_child(opt_bg)
	var opts := _col(345, 410, 520)
	opts.add_theme_constant_override("separation", 2)
	if _cfg["mode"] != "time_trial":
		opts.add_child(UIKit.option_row("Mode", PackedStringArray(RACE_MODE_NAMES), maxi(0, RACE_MODES.find(_cfg["mode"])), func(i: int) -> void:
			_cfg["mode"] = RACE_MODES[i], 520))
	var track_ids := Array(TrackLibrary.ids())
	var track_names := PackedStringArray()
	for tid: String in track_ids:
		track_names.append(tid.replace("_", " ").to_upper())
	opts.add_child(UIKit.option_row("Circuit", track_names, maxi(0, track_ids.find(_cfg["track"])), func(i: int) -> void:
		_cfg["track"] = track_ids[i]
		Settings.set_v("track", track_ids[i]), 520))
	var classes := PackedStringArray()
	for k in ShipSpec.CLASSES.size():
		var locked: bool = credits < UNLOCK_CLASS_CREDITS[k]
		classes.append(ShipSpec.CLASSES[k]["name"] + ("  (LOCKED)" if locked else ""))
	opts.add_child(UIKit.option_row("Class", classes, int(_cfg["class"]), func(i: int) -> void:
		if credits >= UNLOCK_CLASS_CREDITS[i]:
			_cfg["class"] = i
			Settings.set_v("speed_class", i), 520))
	opts.add_child(UIKit.option_row("Laps", PackedStringArray(["1", "2", "3", "4", "5"]), clampi(int(_cfg["laps"]) - 1, 0, 4), func(i: int) -> void:
		_cfg["laps"] = i + 1
		Settings.set_v("laps", i + 1), 520))
	if _cfg["mode"] != "time_trial":
		opts.add_child(UIKit.option_row("Difficulty", PackedStringArray(["ROOKIE", "PRO", "ELITE"]), int(_cfg["difficulty"]), func(i: int) -> void:
			_cfg["difficulty"] = i
			Settings.set_v("difficulty", i), 520))
	var go := UIKit.button("START", func() -> void:
		var cfg := _cfg.duplicate()
		if cfg["mode"] in ["time_trial", "speed"]:
			cfg["opponents"] = 0
		else:
			cfg["opponents"] = 7
		Game.start_race(cfg), 340)
	go.add_theme_color_override("font_color", UIKit.ACC)
	go.custom_minimum_size = Vector2(340, 64)
	go.position = Vector2(900, 628)
	screen.add_child(go)
	var back := UIKit.button("BACK", func() -> void: open("home"), 200)
	back.position = Vector2(40, 640)
	screen.add_child(back)
	if first:
		first.grab_focus.call_deferred()


func _team_info(box: VBoxContainer, tid: String) -> void:
	for c in box.get_children():
		c.queue_free()
	var t := Catalog.team(tid)
	var logo := TextureRect.new()
	logo.texture = Mats.tex("logo_" + tid)
	logo.custom_minimum_size = Vector2(200, 100)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	box.add_child(logo)
	var name := UIKit.label(t["name"], 24, UIKit.TEXT)
	box.add_child(name)
	box.add_child(UIKit.label(t["ship"] + "   ·   " + t["origin"].to_upper(), 18, UIKit.ACC))
	var blurb := UIKit.label(t["blurb"], 18, UIKit.DIM, false)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	blurb.custom_minimum_size = Vector2(340, 0)
	box.add_child(blurb)
	var r: Dictionary = t["ratings"]
	for key: String in ["speed", "thrust", "handling", "stability", "shield", "airbrake"]:
		var row := HBoxContainer.new()
		var l := UIKit.label(key.to_upper(), 18, UIKit.DIM)
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		row.add_child(UIKit.bar(float(r[key]) / 10.0, 210.0, UIKit.ACC))
		box.add_child(row)
	var spec := Catalog.spec_for(tid, int(_cfg.get("class", 1)))
	box.add_child(UIKit.label("TOP SPEED  %d KM/H" % int(spec.v_top * 3.6 * ShipSpec.SPEED_SCALE), 20, UIKit.TEXT))


func _settings(tab: String) -> void:
	var head := UIKit.title("SETTINGS", 40)
	head.position = Vector2(56, 32)
	screen.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(56, 96)
	tabs.add_theme_constant_override("separation", 8)
	screen.add_child(tabs)
	for t: String in ["controls", "camera", "graphics", "audio"]:
		var b := UIKit.button(t.to_upper(), func() -> void: open("settings", {"tab": t}), 180)
		if t == tab:
			b.add_theme_color_override("font_color", UIKit.ACC)
		tabs.add_child(b)
	var box := _col(56, 170, 640)
	match tab:
		"controls":
			box.add_child(UIKit.option_row("Steering", Settings.SCHEMES, Settings.scheme(), func(i: int) -> void: Settings.set_scheme(i), 640))
			box.add_child(UIKit.slider_row("Steering sensitivity", Settings.f("steer_sens"), 0.5, 1.6, func(v: float) -> void: Settings.set_v("steer_sens", v), 640))
			box.add_child(UIKit.slider_row("Centre softness", Settings.f("steer_curve"), 0.0, 1.0, func(v: float) -> void: Settings.set_v("steer_curve", v), 640))
			box.add_child(UIKit.slider_row("Tilt sensitivity", Settings.f("tilt_sens"), 0.5, 2.0, func(v: float) -> void: Settings.set_v("tilt_sens", v), 640))
			box.add_child(UIKit.slider_row("Tilt dead zone", Settings.f("tilt_dead"), 0.0, 0.12, func(v: float) -> void: Settings.set_v("tilt_dead", v), 640))
			box.add_child(UIKit.button("CALIBRATE TILT (HOLD THE PHONE AS YOU PLAY)", func() -> void:
				Settings.set_v("tilt_zero", DriveInput.read_tilt_raw())
				Audio.ui("ui_select"), 640))
			box.add_child(UIKit.option_row("Thrust", PackedStringArray(["AUTOMATIC", "THRUST PAD"]), 0 if Settings.get_v("auto_thrust") else 1, func(i: int) -> void: Settings.set_v("auto_thrust", i == 0), 640))
			box.add_child(UIKit.option_row("Steering assist", PackedStringArray(["OFF", "LOW", "HIGH"]), int(Settings.get_v("steer_assist")), func(i: int) -> void: Settings.set_v("steer_assist", i), 640))
			box.add_child(UIKit.option_row("Haptics", PackedStringArray(["OFF", "ON"]), 1 if Settings.get_v("haptics") else 0, func(i: int) -> void: Settings.set_v("haptics", i == 1), 640))
			box.add_child(UIKit.slider_row("Control opacity", Settings.f("ctrl_opacity"), 0.2, 1.0, func(v: float) -> void: Settings.set_v("ctrl_opacity", v), 640))
			box.add_child(UIKit.slider_row("Control size", Settings.f("ctrl_scale"), 0.7, 1.4, func(v: float) -> void: Settings.set_v("ctrl_scale", v), 640))
		"camera":
			box.add_child(UIKit.option_row("Default camera", CameraRig.NAMES.slice(0, CameraRig.MODE_COUNT), int(Settings.get_v("camera")), func(i: int) -> void: Settings.set_v("camera", i), 640))
			box.add_child(UIKit.slider_row("Camera motion", Settings.f("camera_motion"), 0.0, 1.5, func(v: float) -> void: Settings.set_v("camera_motion", v), 640))
			box.add_child(UIKit.option_row("Telemetry overlay", PackedStringArray(["OFF", "ON"]), 1 if Settings.get_v("show_telemetry") else 0, func(i: int) -> void: Settings.set_v("show_telemetry", i == 1), 640))
		"graphics":
			var presets := PackedStringArray(["AUTO"])
			presets.append_array(Quality.NAMES)
			box.add_child(UIKit.option_row("Quality", presets, int(Settings.get_v("preset")) + 1, func(i: int) -> void: Settings.set_v("preset", i - 1), 640))
			var caps := [30, 60, 90, 120]
			box.add_child(UIKit.option_row("Frame rate cap", PackedStringArray(["30", "60", "90", "120"]), maxi(0, caps.find(int(Settings.get_v("fps_cap")))), func(i: int) -> void: Settings.set_v("fps_cap", caps[i]), 640))
			box.add_child(UIKit.option_row("Adaptive resolution", PackedStringArray(["OFF", "ON"]), 1 if Settings.get_v("adaptive_res") else 0, func(i: int) -> void: Settings.set_v("adaptive_res", i == 1), 640))
			box.add_child(UIKit.option_row("Motion blur", PackedStringArray(["OFF", "ON"]), 1 if Settings.get_v("motion_blur") else 0, func(i: int) -> void: Settings.set_v("motion_blur", i == 1), 640))
			box.add_child(UIKit.option_row("Speed lines", PackedStringArray(["OFF", "ON"]), 1 if Settings.get_v("speed_lines") else 0, func(i: int) -> void: Settings.set_v("speed_lines", i == 1), 640))
			box.add_child(UIKit.option_row("Show FPS", PackedStringArray(["OFF", "ON"]), 1 if Settings.get_v("show_fps") else 0, func(i: int) -> void: Settings.set_v("show_fps", i == 1), 640))
		"audio":
			for k: Array in [["Master", "vol_master"], ["Music", "vol_music"], ["Effects", "vol_sfx"], ["Engine", "vol_engine"]]:
				box.add_child(UIKit.slider_row(k[0], Settings.f(k[1]), 0.0, 1.0, func(v: float) -> void: Settings.set_v(k[1], v), 640))
	var back := UIKit.button("BACK", func() -> void: open("home"), 200)
	back.position = Vector2(56, 640)
	screen.add_child(back)
	(tabs.get_child(0) as Button).grab_focus.call_deferred()


func _team_row(w: float) -> HBoxContainer:
	var credits := int(SaveData.d["credits"])
	var ids: Array = []
	var names := PackedStringArray()
	for t: Dictionary in Catalog.TEAMS:
		if credits >= int(UNLOCK_TEAM_CREDITS.get(t["id"], 0)) or (SaveData.d["unlocked_teams"] as Array).has(t["id"]):
			ids.append(t["id"])
			names.append(t["short"])
	var cur := maxi(0, ids.find(_cfg.get("team", "halden")))
	return UIKit.option_row("Team", names, cur, func(i: int) -> void:
		_cfg["team"] = ids[i]
		Settings.set_v("team", ids[i])
		_set_ship(ids[i]), w)


func _career() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var head := UIKit.title("CAREER", 40)
	head.position = Vector2(56, 24)
	screen.add_child(head)
	var done: Dictionary = SaveData.d["career"]
	var cr := UIKit.label("CREDITS %d" % int(SaveData.d["credits"]), 22, UIKit.ACC)
	cr.position = Vector2(1000, 36)
	screen.add_child(cr)
	var first: Button = null
	# Two columns of series inside one scroll area: the list grows with every
	# circuit, and the focused event is kept in view (follow_focus).
	var scroll := _scroll(Vector2(56, 80), Vector2(1170, 552))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	scroll.add_child(cols)
	var sides: Array[VBoxContainer] = []
	for k in 2:
		var side := VBoxContainer.new()
		side.custom_minimum_size = Vector2(570, 0)
		side.add_theme_constant_override("separation", 18)
		cols.add_child(side)
		sides.append(side)
	for t in Career.TIERS.size():
		var tier: Dictionary = Career.TIERS[t]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		sides[t % 2].add_child(col)
		var open_t := Career.tier_open(t, done)
		var hdr := "%s   %d/%d" % [tier["name"], Career.completed_in(t, done), (tier["events"] as Array).size()]
		if not open_t:
			hdr = "%s   ·   LOCKED: COMPLETE %d EVENTS OF THE PREVIOUS SERIES" % [tier["name"], int(tier["need"])]
		col.add_child(UIKit.label(hdr, 19, UIKit.ACC if open_t else UIKit.DIM))
		for e: Dictionary in tier["events"]:
			var ok_e: bool = done.get(e["id"], false)
			var text := "%s%s  ·  %s" % ["✓ " if ok_e else "", e["title"].to_upper(), Career.goal_text(e["goal"])]
			var ev: Dictionary = e
			var cls: int = tier["class"]
			var b := UIKit.button(text, func() -> void:
				var cfg := Career.race_cfg(_cfg, ev, cls, int(_cfg.get("difficulty", 1)))
				cfg["career_event"] = ev["id"]
				Game.start_race(cfg), 570)
			b.custom_minimum_size = Vector2(570, 36)
			b.add_theme_font_size_override("font_size", 18)
			UIKit.compact(b)
			b.disabled = not open_t
			if ok_e:
				b.add_theme_color_override("font_color", UIKit.ACC)
			col.add_child(b)
			if first == null and open_t and not ok_e:
				first = b
	var tr := _team_row(560)
	tr.position = Vector2(56, 646)
	screen.add_child(tr)
	var back := UIKit.button("BACK", func() -> void: open("home"), 200)
	back.position = Vector2(1020, 646)
	screen.add_child(back)
	if first:
		first.grab_focus.call_deferred()
	else:
		back.grab_focus.call_deferred()


func _cups() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var head := UIKit.title("CHAMPIONSHIP", 40)
	head.position = Vector2(56, 24)
	screen.add_child(head)
	var scroll := _scroll(Vector2(56, 96), Vector2(660, 536))
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	var running: Dictionary = SaveData.d["cup"]
	var first: Button = null
	if not running.is_empty():
		var c := Career.cup(running["id"])
		var rounds: Array = c["rounds"]
		var rnd := int(running["round"])
		var b := UIKit.button("CONTINUE %s  ·  ROUND %d/%d" % [c["name"], rnd + 1, rounds.size()], func() -> void:
			var cfg := Career.race_cfg(_cfg, rounds[rnd], int(c["class"]), int(c["difficulty"]))
			cfg["cup"] = c["id"]
			Game.start_race(cfg), 640)
		b.add_theme_color_override("font_color", UIKit.ACC)
		box.add_child(b)
		first = b
		var st := _col(740, 100, 480)
		st.add_child(UIKit.label("STANDINGS AFTER ROUND %d" % rnd, 20, UIKit.DIM))
		for row: Array in Career.sorted_standings(running["standings"]):
			st.add_child(UIKit.label("%-16s %3d" % [row[0], row[1]], 20, UIKit.ACC if row[0] == "YOU" else UIKit.TEXT, row[0] == "YOU"))
	var credits := int(SaveData.d["credits"])
	for c: Dictionary in Career.CUPS:
		var rounds: Array = c["rounds"]
		var desc := PackedStringArray()
		for r: Dictionary in rounds:
			desc.append("%s %s" % [String(r["track"]).replace("_", " ").to_upper(), String(r["mode"]).to_upper()])
		var locked: bool = credits < UNLOCK_CLASS_CREDITS[int(c["class"])]
		var cc: Dictionary = c
		var won := (SaveData.d["cups_won"] as Array).has(c["id"])
		var b := UIKit.button("%s%s  ·  %s  ·  %d ROUNDS%s" % ["✓ " if won else "", c["name"], ShipSpec.CLASSES[int(c["class"])]["name"], rounds.size(), "  (LOCKED)" if locked else ""], func() -> void:
			SaveData.d["cup"] = {"id": cc["id"], "round": 0, "standings": {}}
			SaveData.save()
			var cfg := Career.race_cfg(_cfg, cc["rounds"][0], int(cc["class"]), int(cc["difficulty"]))
			cfg["cup"] = cc["id"]
			Game.start_race(cfg), 640)
		b.disabled = locked
		box.add_child(b)
		var l := UIKit.label("   " + "  ›  ".join(desc), 17, UIKit.DIM, false)
		box.add_child(l)
		if first == null and not locked:
			first = b
	box.add_child(UIKit.label("Points per round: 25 18 15 12 10 8 6 4. Winning a cup pays 2000 credits.", 18, UIKit.DIM, false))
	var tr := _team_row(560)
	tr.position = Vector2(56, 646)
	screen.add_child(tr)
	var back := UIKit.button("BACK", func() -> void: open("home"), 200)
	back.position = Vector2(1020, 646)
	screen.add_child(back)
	if first:
		first.grab_focus.call_deferred()


func _records() -> void:
	var head := UIKit.title("RECORDS", 40)
	head.position = Vector2(56, 32)
	screen.add_child(head)
	var box := _col(56, 110, 760)
	var st: Dictionary = SaveData.d["stats"]
	box.add_child(UIKit.label("RACES %d   ·   WINS %d   ·   PODIUMS %d   ·   CREDITS %d" % [int(st["races"]), int(st["wins"]), int(st["podiums"]), int(SaveData.d["credits"])], 22, UIKit.ACC))
	var recs: Dictionary = SaveData.d["records"]
	if recs.is_empty():
		box.add_child(UIKit.label("No records yet. Finish a race or a time trial.", 22, UIKit.DIM, false))
	for key: String in recs:
		var r: Dictionary = recs[key]
		var parts := key.split("/")
		var cname: String = ShipSpec.CLASSES[clampi(int(parts[1]), 0, 3)]["name"]
		var races_txt := PackedStringArray()
		var br: Dictionary = r.get("best_races", {})
		for lk: String in br:
			races_txt.append("%s LAPS %s" % [lk, Hud.fmt_time(float(br[lk]))])
		box.add_child(UIKit.label("%s  ·  %s     BEST LAP %s     %s     RACES %d  WINS %d" % [
			parts[0].replace("_", " ").to_upper(), cname, Hud.fmt_time(float(r["best_lap"])), "   ".join(races_txt), int(r["races"]), int(r["wins"])], 20, UIKit.TEXT, false))
	var back := UIKit.button("BACK", func() -> void: open("home"), 200)
	back.position = Vector2(56, 640)
	screen.add_child(back)
	back.grab_focus.call_deferred()


func _results(args: Dictionary) -> void:
	var res: Dictionary = args.get("player", {})
	var table: Array = args.get("table", [])
	var booked: Dictionary = args.get("booked", {})
	var cfg: Dictionary = args.get("cfg", {})
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var place: int = res.get("place", 0)
	var title := "ELIMINATED" if not res.get("finished", false) else ("VICTORY" if place == 1 else "FINISHED  %s" % _ordinal(place))
	match cfg.get("mode", "race"):
		"time_trial":
			if res.get("finished", false):
				title = "TIME TRIAL COMPLETE"
		"speed":
			title = ["NO MEDAL", "BRONZE MEDAL", "SILVER MEDAL", "GOLD MEDAL"][int(res.get("medal", 0))]
		"elimination":
			title = "LAST SHIP STANDING" if place == 1 else ("KNOCKED OUT  ·  %s" % _ordinal(place))
		"combat":
			title = ("COMBAT VICTORY" if place == 1 else "COMBAT  ·  %s" % _ordinal(place))
	var head := UIKit.title(title, 44)
	head.position = Vector2(56, 32)
	screen.add_child(head)
	var box := _col(56, 110, 760)
	var mode: String = cfg.get("mode", "race")
	for r: Dictionary in table:
		var row := HBoxContainer.new()
		var col := UIKit.ACC if r["player"] else UIKit.TEXT
		var status: String
		match mode:
			"elimination":
				if r["finished"] and not r["eliminated"]:
					status = "WINNER"
				elif r.get("knocked_out", false):
					status = "OUT " + Hud.fmt_time(r["time"])
				elif r["eliminated"]:
					status = "SHIELD OUT"
				else:
					status = "SURVIVOR"
			"combat":
				status = "%d PTS" % int(r.get("points", 0))
			_:
				status = (("~" if r.get("estimated", false) else "") + Hud.fmt_time(r["time"])) if r["finished"] else ("ELIM" if r["eliminated"] else "DNF")
		for cell: Array in [[str(r["place"]), 50], [r["name"], 220], [Catalog.team(r["team"])["short"], 160],
				[status, 170], ["BEST " + Hud.fmt_time(r["best_lap"]), 200]]:
			var l := UIKit.label(cell[0], 22, col, r["player"])
			l.custom_minimum_size = Vector2(cell[1], 0)
			row.add_child(l)
		box.add_child(row)
	var side := _col(860, 110, 360)
	var laps: Array = res.get("laps", [])
	for k in laps.size():
		side.add_child(UIKit.label("LAP %d   %s" % [k + 1, Hud.fmt_time(float(laps[k]))], 22, UIKit.TEXT))
	side.add_child(UIKit.label("TOP SPEED  %d KM/H" % int(float(res.get("top_speed", 0.0)) * 3.6 * ShipSpec.SPEED_SCALE), 22, UIKit.DIM))
	var tg: Array = res.get("targets", [])
	if tg.size() == 3:
		side.add_child(UIKit.label("GOLD %s   SILVER %s   BRONZE %s" % [Hud.fmt_time(tg[0]), Hud.fmt_time(tg[1]), Hud.fmt_time(tg[2])], 18, UIKit.DIM))
	if cfg.get("mode", "") == "combat":
		side.add_child(UIKit.label("POINTS  %d" % int(res.get("points", 0)), 26, UIKit.ACC))
	if booked.get("new_lap", false):
		side.add_child(UIKit.label("NEW LAP RECORD", 26, UIKit.ACC2))
	if booked.get("new_race", false):
		side.add_child(UIKit.label("NEW RACE RECORD", 26, UIKit.ACC2))
	side.add_child(UIKit.label("+%d CREDITS" % int(booked.get("credits", 0)), 26, UIKit.ACC))
	if booked.has("career_event"):
		var ev := Career.event(booked["career_event"])
		if booked.get("goal_met", false):
			side.add_child(UIKit.label("OBJECTIVE COMPLETE", 26, UIKit.ACC2))
		else:
			side.add_child(UIKit.label("OBJECTIVE: " + Career.goal_text(ev.get("goal", {})), 22, UIKit.DIM))
	if booked.has("cup_round"):
		var title_c := "CUP ROUND %d/%d" % [int(booked["cup_round"]), int(booked["cup_rounds"])]
		if booked.get("cup_done", false):
			title_c = "CUP WON  +2000" if booked.get("cup_won", false) else "CUP COMPLETE"
		side.add_child(UIKit.label(title_c, 24, UIKit.ACC2))
		var shown := 0
		for row: Array in booked.get("cup_standings", []):
			if shown >= 5:
				break
			side.add_child(UIKit.label("%-14s %3d" % [row[0], row[1]], 18, UIKit.ACC if row[0] == "YOU" else UIKit.TEXT))
			shown += 1
	var row := HBoxContainer.new()
	row.position = Vector2(56, 630)
	row.add_theme_constant_override("separation", 12)
	screen.add_child(row)
	var again: Button
	if booked.has("cup_round") and not booked.get("cup_done", false):
		again = UIKit.button("NEXT ROUND", func() -> void:
			var cupd: Dictionary = SaveData.d["cup"]
			var c := Career.cup(cupd["id"])
			var cfg2 := Career.race_cfg(cfg, c["rounds"][int(cupd["round"])], int(c["class"]), int(c["difficulty"]))
			cfg2["cup"] = c["id"]
			Game.start_race(cfg2), 260)
	else:
		again = UIKit.button("RACE AGAIN", func() -> void: Game.restart_race(), 260)
	row.add_child(again)
	if booked.has("career_event"):
		row.add_child(UIKit.button("CAREER", func() -> void: open("career"), 200))
	row.add_child(UIKit.button("MENU", func() -> void: open("home"), 200))
	again.grab_focus.call_deferred()
	Audio.music("menu", 2.0)


func _ordinal(n: int) -> String:
	var suf := "TH"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "ST"
			2: suf = "ND"
			3: suf = "RD"
	return "%d%s" % [n, suf]
