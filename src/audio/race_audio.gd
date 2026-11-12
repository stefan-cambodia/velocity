## Race sound: the player's layered engine, airbrakes, wind, scraping and
## boost; opponents' engines in 3D with Doppler (nearest four); event one-shots;
## and the dynamic music (grid loop, race, intense final lap, victory/defeat).
extends Node

var race: Node
var _low: AudioStreamPlayer
var _mid: AudioStreamPlayer
var _high: AudioStreamPlayer
var _air: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _boost: AudioStreamPlayer
var _ai_pool: Array[AudioStreamPlayer3D] = []
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _song: int = 1
var _last_count: int = -1
var _final: bool = false
var _finished: bool = false
var _scrape_v: float = 0.0
var _thr: float = 0.0
var _wrong_t: float = 0.0


func setup(p_race: Node) -> void:
	race = p_race
	_low = _loop("engine/engine_low", "Engine")
	_mid = _loop("engine/engine_mid", "Engine")
	_high = _loop("engine/engine_high", "Engine")
	_air = _loop("engine/airbrake", "SFX")
	_wind = _loop("engine/wind", "SFX")
	_scrape = _loop("engine/scrape", "SFX")
	_boost = _loop("engine/boost_loop", "Engine")
	var ai_st := Audio.stream("engine/ai_engine", true)
	for k in 4:
		var p := AudioStreamPlayer3D.new()
		p.stream = ai_st
		p.bus = "Engine"
		p.max_distance = 160.0
		p.unit_size = 9.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p.volume_db = -4.0
		add_child(p)
		_ai_pool.append(p)
	for k in 8:
		var s := AudioStreamPlayer.new()
		s.bus = "SFX"
		add_child(s)
		_sfx_pool.append(s)
	_song = 1 + int(hash(race.cfg.get("track", "")) % 2)
	Audio.music("grid", 1.0)
	race.session.lap_completed.connect(_on_lap)
	race.session.racer_finished.connect(_on_finish)
	race.session.racer_eliminated.connect(_on_elim)
	race.rig.cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP


func _loop(path: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = Audio.stream(path, true)
	p.volume_db = -80.0
	add_child(p)
	if p.stream != null:
		p.play(randf() * 0.5)
	return p


func sfx(name: String, db: float = 0.0, pitch: float = 1.0) -> void:
	var st := Audio.stream("sfx/" + name)
	if st == null:
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _process(delta: float) -> void:
	if race == null or race.session == null:
		return
	var s: RaceSession = race.session
	var ph: ShipPhysics = race.player.phys
	var c: ShipControls = race.player.controls
	var vt := clampf(ph.v_fwd / ph.spec.v_top, 0.0, 1.4)
	_thr = lerpf(_thr, c.thrust + (0.6 if ph.boost_t > 0.0 else 0.0), 1.0 - exp(-delta * 6.0))
	var cockpit: bool = race.rig.mode == CameraRig.Mode.COCKPIT
	# Engine layers.
	_lvl(_low, 0.62 + 0.75 * vt + 0.06 * _thr, -9.0 + 4.0 * _thr)
	_lvl(_mid, 0.55 + 1.15 * vt + 0.1 * _thr, -24.0 + 18.0 * minf(vt * 1.4, 1.0) + 3.0 * _thr)
	_lvl(_high, 0.8 + 0.8 * vt, -40.0 + 34.0 * clampf((vt - 0.35) / 0.65, 0.0, 1.0) * (0.6 + 0.4 * _thr))
	_lvl(_boost, 1.0, -6.0 if ph.boost_t > 0.0 else -80.0)
	var ab := maxf(ph.ab_l, ph.ab_r)
	_lvl(_air, 0.8 + 0.4 * vt, linear_to_db(maxf(ab * minf(vt * 1.5, 1.0), 0.0001)) - 2.0)
	_lvl(_wind, 0.7 + 0.5 * vt, linear_to_db(maxf(vt * vt, 0.0001)) - (14.0 if cockpit else 8.0))
	_scrape_v = lerpf(_scrape_v, 1.0 if ph.touching_wall and ph.speed > 8.0 else 0.0, 1.0 - exp(-delta * 18.0))
	_lvl(_scrape, 0.9 + 0.3 * vt, linear_to_db(maxf(_scrape_v, 0.0001)))
	# Opponents: the four nearest get a 3D engine voice.
	var near: Array = []
	for sh: Ship in race.ships:
		if sh == race.player:
			continue
		near.append([sh.global_position.distance_squared_to(race.player.global_position), sh])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in _ai_pool.size():
		var p := _ai_pool[k]
		if p.stream == null:
			continue
		if k < near.size() and float(near[k][0]) < 160.0 * 160.0:
			var sh: Ship = near[k][1]
			p.global_position = sh.global_position
			p.pitch_scale = 0.6 + 0.9 * clampf(sh.phys.v_fwd / sh.phys.spec.v_top, 0.0, 1.3)
			if not p.playing:
				p.play(randf())
		elif p.playing:
			p.stop()
	# Events.
	if ph.ev_wall > 3.0:
		sfx("wall_hit_heavy" if ph.ev_wall > 14.0 else "wall_hit_light", -2.0 + minf(ph.ev_wall * 0.2, 4.0))
	if ph.ev_land > 4.0:
		sfx("land", -6.0 + minf(ph.ev_land * 0.4, 6.0))
	if ph.ev_pad == "boost":
		sfx("boost", -1.0)
	elif ph.ev_pad == "weapon":
		sfx("pad_weapon", -3.0)
	for sh: Ship in race.ships:
		if sh != race.player and sh.phys.ev_wall > 10.0 and sh.global_position.distance_to(race.player.global_position) < 60.0:
			sfx("ship_contact", -10.0)
	# Countdown beeps and the start of the race music.
	if s.state == RaceSession.State.COUNTDOWN:
		var n := int(ceil(s.countdown))
		if n != _last_count and n <= 3 and n >= 1:
			sfx("beep_count", -2.0)
		_last_count = n
	elif _last_count != 0:
		_last_count = 0
		sfx("beep_go", -1.0)
		Audio.music("race%d_main" % _song, 0.8)
	if s.wrong_way:
		_wrong_t -= delta
		if _wrong_t <= 0.0:
			sfx("wrong_way", -4.0)
			_wrong_t = 1.6
	else:
		_wrong_t = 0.0


func _lvl(p: AudioStreamPlayer, pitch: float, db: float) -> void:
	if p.stream == null:
		return
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	p.volume_db = clampf(db, -80.0, 6.0)


func _on_lap(r: RefCounted) -> void:
	var rr := r as RaceSession.Racer
	if not rr.is_player:
		return
	var s: RaceSession = race.session
	if rr.lap == s.laps - 1 and not _final:
		_final = true
		sfx("final_lap", 0.0)
		Audio.music("race%d_intense" % _song, 1.5, true)
	elif rr.lap < s.laps:
		sfx("lap", -2.0)


func _on_finish(r: RefCounted) -> void:
	var rr := r as RaceSession.Racer
	if not rr.is_player or _finished:
		return
	_finished = true
	sfx("finish", 0.0)
	Audio.music("victory" if rr.place <= 3 else "defeat", 0.6, false, true)


func _on_elim(r: RefCounted) -> void:
	var rr := r as RaceSession.Racer
	if rr.is_player:
		sfx("eliminated", 0.0)
		Audio.music("defeat", 0.6, false, true)
	else:
		sfx("explosion", -8.0)


func on_weapon_event(e: Dictionary) -> void:
	var sh: Ship = e["ship"]
	var near: bool = sh == race.player or (e["pos"] as Vector3).distance_to(race.player.global_position) < 90.0
	if not near:
		return
	var mine: bool = sh == race.player
	match e["type"]:
		"pickup":
			if mine:
				sfx("pad_weapon", -3.0)
		"fire":
			var name: String = {"plasma": "plasma_fire", "missile": "missile_launch", "emp": "emp", "shockwave": "shockwave",
				"shield": "shield_up", "mines": "mine_drop", "turbo": "boost", "repair": "repair"}.get(e["kind"], "")
			if name != "":
				sfx(name, -2.0 if mine else -9.0)
		"hit":
			sfx("missile_hit" if e["kind"] in ["missile", "mine"] else "shield_hit", 0.0 if mine else -8.0)
			if e["kind"] == "missile" and mine:
				sfx("explosion", -6.0)
		"blocked":
			sfx("shield_hit", -4.0 if mine else -10.0)
