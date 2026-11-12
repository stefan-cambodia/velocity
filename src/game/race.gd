## One race from the grid to the results. Builds the world, the ships and the
## AI, runs the simulation on the physics tick and draws interpolated frames.
##   cfg: {track, team, class, laps, opponents, difficulty, mode}
class_name Race
extends Node3D

signal ready_to_race

var cfg: Dictionary = {}
var track: TrackData
var line: RacingLine
var ships: Array[Ship] = []
var player: Ship
var ais: Array[AIDriver] = []
var autopilot: AIDriver
var session: RaceSession
var rig: CameraRig
var hud: Node
var touch: Node
var input := DriveInput.new()
var world: Node3D
var fx: RaceFx
var audio: Node
var paused_menu: Node
var weapons: WeaponSystem
var weapon_fx: WeaponFx
var _racer_of: Dictionary = {}       ## Ship -> RaceSession.Racer
var _ai_of: Dictionary = {}          ## Ship -> AIDriver
var _ai_rng := RandomNumberGenerator.new()
var _last_attacker: Dictionary = {}  ## Ship -> Ship (combat knockouts)

var assist := SteerAssist.new()
var _results_shown: bool = false
var _cam_cooldown: float = 0.0


func _ready() -> void:
	DriveInput.ensure_actions()
	var t0 := Time.get_ticks_msec()
	var track_id: String = cfg.get("track", "proving_ground")
	var class_idx: int = cfg.get("class", 1)
	track = TrackLibrary.get_track(track_id)
	var team_id: String = cfg.get("team", "halden")
	var pspec := Catalog.spec_for(team_id, class_idx)
	line = RacingLine.compute(track, pspec)
	var t_line := Time.get_ticks_msec()
	# World.
	world = TrackWorld.build(track_id, track, self)
	var t_world := Time.get_ticks_msec()
	# Ships: player first on the grid's back half, AI ahead (a fair start position mid-pack).
	var mode: String = cfg.get("mode", "race")
	session = RaceSession.new(track, int(cfg.get("laps", 3)), mode)
	if mode == "speed":
		session.set_targets(line.lap_estimate)
	var n_ai: int = clampi(int(cfg.get("opponents", 7)), 0, 11)
	var pilots := _pick_pilots(team_id, n_ai)
	var grid_order: Array = []
	for i in n_ai:
		grid_order.append(pilots[i])
	var player_slot := mini(n_ai, maxi(0, n_ai / 2 + 1))
	grid_order.insert(player_slot, {"name": "YOU", "team": team_id, "style": "technical", "player": true})
	var seed := int(cfg.get("seed", 1234))
	for k in grid_order.size():
		var pd: Dictionary = grid_order[k]
		var is_p: bool = pd.get("player", false)
		var team := Catalog.team(pd["team"])
		var spec := Catalog.spec_for(pd["team"], class_idx)
		var sh := Ship.new()
		sh.name = "Ship_" + str(pd["name"]).replace(" ", "_").replace(".", "")
		sh.is_player = is_p
		sh.pilot_name = pd["name"]
		add_child(sh)
		sh.setup(spec, track, team, is_p)
		ships.append(sh)
		session.add(sh, pd["name"], pd["team"], is_p)
		if is_p:
			player = sh
		else:
			var ai := AIDriver.new(sh, line, pd.get("style", "technical"), int(cfg.get("difficulty", 1)), seed + k * 17)
			ai.name = pd["name"]
			ais.append(ai)
	for ai in ais:
		ai.others = ships
	session.place_on_grid()
	for r in session.racers:
		_racer_of[r.ship] = r
	for ai in ais:
		_ai_of[ai.ship] = ai
	weapons = WeaponSystem.new(track, ships, seed)
	weapons.enabled = mode in ["race", "elimination", "combat"] and bool(cfg.get("weapons", true))
	weapons.combat = mode == "combat"
	for ai in ais:
		ai.weapons = weapons
	_ai_rng.seed = seed + 5
	if DevArgs.has("--autopilot"):
		autopilot = AIDriver.new(player, line, "technical", 2, seed)
		autopilot.others = ships
		autopilot.pace = float(_dev_value("--ap-pace=", "1.0")) * 0.985
		autopilot.weapons = weapons
	# Camera, effects, audio, HUD, touch controls.
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.motion = Settings.f("camera_motion")
	rig.mode = clampi(int(Settings.get_v("camera")), 0, CameraRig.MODE_COUNT - 1)
	if DevArgs.has("--cockpit"):
		rig.mode = CameraRig.Mode.COCKPIT
	rig.attach(player)
	rig.cam.current = true
	fx = RaceFx.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(self)
	weapon_fx = WeaponFx.new()
	weapon_fx.name = "WeaponFx"
	add_child(weapon_fx)
	weapon_fx.setup(self, weapons)
	var sfx := SpeedFx.new()
	sfx.name = "SpeedFx"
	add_child(sfx)
	sfx.setup(self)
	if ResourceLoader.exists("res://src/audio/race_audio.gd"):
		audio = load("res://src/audio/race_audio.gd").new()
		audio.name = "RaceAudio"
		add_child(audio)
		audio.call("setup", self)
	hud = load("res://src/ui/hud.gd").new()
	hud.name = "Hud"
	add_child(hud)
	hud.call("setup", self)
	if ResourceLoader.exists("res://src/input/touch_controls.gd") and (OS.has_feature("mobile") or DevArgs.has("--touch")):
		touch = load("res://src/input/touch_controls.gd").new()
		touch.name = "Touch"
		add_child(touch)
		input.touch = touch
		touch.set("paused_cb", toggle_pause)
		touch.set("camera_cb", func() -> void:
			rig.cycle()
			Settings.set_v("camera", rig.mode))
	if not DevArgs.has("--no-capture"):
		var dc := DevCapture.new()
		dc.name = "DevCapture"
		add_child(dc)
	session.lap_completed.connect(_on_lap)
	session.racer_eliminated.connect(_on_eliminated)
	session.racer_finished.connect(_on_finish)
	if DevArgs.has("--load-times"):
		print("load: line %d ms (lap est %.1f s), world %d ms, total %d ms" % [t_line - t0, line.lap_estimate, t_world - t_line, Time.get_ticks_msec() - t0])
	await get_tree().process_frame
	await get_tree().process_frame
	ready_to_race.emit()


func _dev_value(prefix: String, def: String) -> String:
	for a in DevArgs.all():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return def


func _pick_pilots(player_team: String, n: int) -> Array:
	var out := []
	for p: Dictionary in Catalog.PILOTS:
		if p["team"] != player_team:
			out.append(p)
	for p: Dictionary in Catalog.PILOTS:
		if p["team"] == player_team:
			out.append(p)
	return out.slice(0, n)


func _physics_process(dt: float) -> void:
	if session == null:
		return
	# Player input (or the autopilot for automated tests).
	if autopilot != null:
		autopilot.drive(dt)
	else:
		var c := input.update(dt)
		player.controls.copy_from(c)
		assist.apply(player.controls, player.phys, int(Settings.get_v("steer_assist")))
		if session.state == RaceSession.State.COUNTDOWN:
			player.controls.thrust = c.thrust
	if session.player.finished or session.player.eliminated:
		# The AI takes over after the flag so the ship coasts round naturally.
		if autopilot == null:
			autopilot = AIDriver.new(player, line, "technical", 0, 7)
			autopilot.others = ships
			autopilot.pace = 0.8
	for ai in ais:
		ai.drive(dt)
	for sh in ships:
		sh.tick(dt)
		_safety_respawn(sh)
	_collide_ships()
	_combat(dt)
	session.update(dt)
	fx.tick(dt)
	if session.state == RaceSession.State.FINISHED and not _results_shown and (session.finish_wait > 6.0 or session.all_done()):
		_results_shown = true
		_finish()


func _process(delta: float) -> void:
	_start_lights()
	var frac := Engine.get_physics_interpolation_fraction()
	for sh in ships:
		sh.draw(frac, delta)
	_cam_cooldown -= delta
	if Input.is_action_just_pressed("camera") and _cam_cooldown <= 0.0:
		rig.cycle()
		Settings.set_v("camera", rig.mode)
		_cam_cooldown = 0.2
	if Input.is_action_just_pressed("telemetry"):
		Settings.set_v("show_telemetry", not Settings.get_v("show_telemetry"))
	if Input.is_action_just_pressed("pause"):
		toggle_pause()


## Gantry lamps: red one by one through the countdown, all green at GO.
func _start_lights() -> void:
	var lights: Array = world.get_meta("start_lights", [])
	if lights.is_empty():
		return
	var lit := 0
	var green := false
	if session.state == RaceSession.State.COUNTDOWN:
		lit = clampi(int((RaceSession.COUNTDOWN_TIME - session.countdown) / (RaceSession.COUNTDOWN_TIME / 5.0)) + 1, 0, 5)
	elif session.time < 4.0:
		green = true
	for k in lights.size():
		var mat: ShaderMaterial = (lights[k] as MeshInstance3D).material_override
		if green:
			mat.set_shader_parameter("color", Color(0.2, 1.0, 0.35))
			mat.set_shader_parameter("energy", 5.0)
		elif k < lit:
			mat.set_shader_parameter("color", Color(1.0, 0.08, 0.05))
			mat.set_shader_parameter("energy", 6.0)
		else:
			mat.set_shader_parameter("color", Color(0.15, 0.02, 0.02))
			mat.set_shader_parameter("energy", 1.0)


func toggle_pause() -> void:
	if session.state == RaceSession.State.COUNTDOWN and session.countdown > 3.0:
		return
	if ResourceLoader.exists("res://src/ui/pause_menu.gd"):
		if paused_menu == null:
			paused_menu = load("res://src/ui/pause_menu.gd").new()
			add_child(paused_menu)
		paused_menu.call("toggle")


## Items: pickups from weapon pads, the player's fire button, AI decisions,
## then the projectiles; events go to effects, sound and the HUD.
func _combat(dt: float) -> void:
	if not weapons.enabled:
		input.consume_fire()
		return
	var racing := session.is_racing()
	for sh in ships:
		if sh.phys.ev_pad == "weapon" and racing:
			var r: RaceSession.Racer = _racer_of[sh]
			weapons.give_random(sh, r.place, ships.size())
	if racing:
		if autopilot != null and not session.player.finished:
			if weapons.ai_wants_fire(player, 0.6) and _ai_rng.randf() < dt * 2.0:
				weapons.fire(player)
		elif input.consume_fire():
			weapons.fire(player)
		for sh in ships:
			if sh == player or not _ai_of.has(sh):
				continue
			var ai: AIDriver = _ai_of[sh]
			var aggr := float(ai.style.get("aggression", 0.5))
			if weapons.ai_wants_fire(sh, aggr) and _ai_rng.randf() < dt * (1.0 + 2.0 * aggr):
				weapons.fire(sh)
	else:
		input.consume_fire()
	weapons.tick(dt)
	for e in weapons.drain_events():
		if e["type"] == "hit" and e.get("by") != null and e["by"] != e["ship"]:
			_last_attacker[e["ship"]] = e["by"]
			if session.mode == "combat":
				session.add_points(e["by"], RaceSession.COMBAT_HIT)
		weapon_fx.on_event(e)
		if audio:
			audio.call("on_weapon_event", e)
		if hud:
			hud.call("on_weapon_event", e)


## Puts a ship back on the track if it ever ends up outside it (fell through a
## gap, pushed out by a contact): last safe point, 1 s of shield penalty-free grace.
func _safety_respawn(sh: Ship) -> void:
	var ph := sh.phys
	if not ph.enabled:
		return
	var out := ph.hit.h < -12.0 or ph.hit.h > 60.0 or ph.hit.d > ph.hit.half_r + 8.0 or ph.hit.d < -ph.hit.half_l - 8.0
	if out:
		ph.respawn()
		if sh.is_player and hud:
			hud.call("message", "RESPAWN", Color(1.0, 0.45, 0.12), 1.5)


## Hull-to-hull contact: each ship is a capsule along its nose axis.
func _collide_ships() -> void:
	var n := ships.size()
	for i in n:
		var a := ships[i].phys
		if not a.enabled:
			continue
		for j in range(i + 1, n):
			var b := ships[j].phys
			if not b.enabled:
				continue
			if absf(track.delta_s(a.hit.s, b.hit.s)) > 9.0:
				continue
			# Closest points between the two hull segments.
			var a0 := a.pos - a.fwd * 1.6
			var a1 := a.pos + a.fwd * 1.6
			var b0 := b.pos - b.fwd * 1.6
			var b1 := b.pos + b.fwd * 1.6
			var cp := Geometry3D.get_closest_points_between_segments(a0, a1, b0, b1)
			var pa: Vector3 = cp[0]
			var pb: Vector3 = cp[1]
			var sep := pb - pa
			var nn := a.surf_n
			sep -= nn * sep.dot(nn)
			var dist := sep.length()
			var rr := a.spec.half_wid + b.spec.half_wid - 0.15
			if dist >= rr or dist < 1e-4:
				continue
			var nrm := sep / dist
			var pen := rr - dist
			var ma := a.spec.mass
			var mb := b.spec.mass
			var wa := mb / (ma + mb)
			var wb := ma / (ma + mb)
			a.pos -= nrm * pen * wa
			b.pos += nrm * pen * wb
			var rel := (b.vel - a.vel).dot(nrm)
			if rel < 0.0:
				var jimp := -(1.0 + 0.35) * rel
				a.impulse(-nrm * jimp * wa, -signf(a.right().dot(nrm)) * 0.02 * -rel)
				b.impulse(nrm * jimp * wb, signf(b.right().dot(nrm)) * 0.02 * -rel)
				# A little drag from the rub, and a touch of damage on hard knocks.
				if -rel > 6.0:
					a.energy -= 0.15 * (-rel - 6.0)
					b.energy -= 0.15 * (-rel - 6.0)
				fx.contact((pa + pb) * 0.5, -rel)


func _on_eliminated(r: RaceSession.Racer) -> void:
	if session.mode == "combat" and not r.knocked_out and _last_attacker.has(r.ship):
		session.add_points(_last_attacker[r.ship], RaceSession.COMBAT_KO)
	if hud:
		hud.call("on_eliminated", r)


func _on_lap(r: RaceSession.Racer) -> void:
	if r.is_player and hud:
		hud.call("on_lap", r)


func _on_finish(r: RaceSession.Racer) -> void:
	if r.is_player:
		if hud:
			hud.call("on_finish", r)
		if not DevArgs.has("--autopilot"):
			rig.set_mode(CameraRig.Mode.TRACKSIDE)


func _finish() -> void:
	var res := session.player_result()
	var booked := SaveData.book_race(cfg.get("track", ""), int(cfg.get("class", 1)), res)
	SaveData.book_meta(cfg, res, session.results(), booked)
	Game.last_result = {"player": res, "table": session.results(), "booked": booked, "cfg": cfg}
	if DevArgs.has("--quit-on-end"):
		return
	if ResourceLoader.exists(Game.MENU_SCRIPT):
		Game.goto_menu("results", Game.last_result)
