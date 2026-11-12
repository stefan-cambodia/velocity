## Development helper for automated play tests: screenshots at intervals,
## telemetry printouts, camera cycling, result line, quit.
##   -- --race=<id> [--autopilot] [--shots=/abs/prefix] [--every=4] [--quit-at=60]
##      [--cam-every=0] [--telemetry] [--quit-on-end] [--shot-at=t1,t2,...]
class_name DevCapture
extends Node

var prefix: String = ""
var every: float = 0.0
var quit_at: float = -1.0
var cam_every: float = 0.0
var telemetry: bool = false
var quit_on_end: bool = false
var shot_at: PackedFloat32Array = []
var _t: float = 0.0
var _next_shot: float = 0.0
var _next_cam: float = 0.0
var _next_tel: float = 0.0
var _n: int = 0
var _reported: bool = false
var _walls: int = 0
var _min_h: float = INF
var _air: int = 0
var _fps_samples: PackedFloat32Array = []
var _csv: FileAccess = null
var _demo: bool = false
var _demo_items := ["plasma", "missile", "shockwave", "mines", "emp", "shield", "turbo"]
var _demo_i: int = 0
var _demo_next: float = 8.0
var _demo_shot: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in DevArgs.all():
		if a.begins_with("--shots="): prefix = a.substr(8)
		elif a.begins_with("--every="): every = float(a.substr(8))
		elif a.begins_with("--quit-at="): quit_at = float(a.substr(10))
		elif a.begins_with("--cam-every="): cam_every = float(a.substr(12))
		elif a == "--telemetry": telemetry = true
		elif a == "--quit-on-end": quit_on_end = true
		elif a == "--weapon-demo": _demo = true
		elif a.begins_with("--csv="):
			_csv = FileAccess.open(a.substr(6), FileAccess.WRITE)
			_csv.store_line("t,s,d,h,speed,v_fwd,v_lat,slip_deg,yaw_rate,accel_long,accel_lat,steer,thrust,ab_l,ab_r,locked,align_deg,wall,energy,place")
		elif a.begins_with("--shot-at="):
			for v in a.substr(10).split(","):
				shot_at.append(float(v))
	_next_shot = every if every > 0.0 else INF
	_next_cam = cam_every if cam_every > 0.0 else INF


func _race() -> Race:
	return get_parent() as Race


func _shoot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%02d.png" % [prefix, _n])
	_n += 1


func _process(delta: float) -> void:
	_t += delta
	var race := _race()
	if prefix != "":
		if _t >= _next_shot:
			_next_shot += every
			_shoot()
		while not shot_at.is_empty() and _t >= shot_at[0]:
			shot_at.remove_at(0)
			_shoot()
	if _demo and race != null and race.session != null and race.session.is_racing():
		if _t >= _demo_next and _demo_i < _demo_items.size():
			_demo_next += 3.0
			race.weapons.slot.erase(race.player)
			race.weapons.give(race.player, _demo_items[_demo_i])
			race.weapons.fire(race.player)
			print("demo fired ", _demo_items[_demo_i])
			_demo_i += 1
			_demo_shot = _t + (0.45 if _demo_items[_demo_i - 1] in ["plasma", "missile", "shockwave"] else 0.2)
		if _demo_shot > 0.0 and _t >= _demo_shot and prefix != "":
			_demo_shot = -1.0
			_shoot()
	if quit_at > 0.0 and _t >= quit_at:
		_print_summary()
		get_tree().quit()
	if race == null or race.session == null:
		return
	var s := race.session
	var ph := race.player.phys
	if s.is_racing():
		if ph.ev_wall > 3.0:
			_walls += 1
		if ph.locked:
			_min_h = minf(_min_h, ph.hit.h)
		if _t > 5.0:
			_fps_samples.append(1.0 / maxf(delta, 1e-4))
	if not _reported and s.state == RaceSession.State.FINISHED and race._results_shown:
		_reported = true
		_print_summary()
		if quit_on_end:
			get_tree().quit()
	if _t >= _next_cam:
		_next_cam += cam_every
		race.rig.cycle()
	if telemetry and _t >= _next_tel:
		_next_tel += 1.0
		print("  render draws=%d prims=%d objects=%d preset=%s scale=%.2f gpu=%s" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			Quality.NAMES[Quality.level], get_viewport().scaling_3d_scale, RenderingServer.get_video_adapter_name()])
		var peaks := []
		for b: String in ["Master", "Engine", "Music", "SFX"]:
			var bi := AudioServer.get_bus_index(b)
			peaks.append("%s %.0f" % [b, maxf(AudioServer.get_bus_peak_volume_left_db(bi, 0), -99.0) if bi >= 0 else -99.0])
		print("  audio dB: " + "  ".join(peaks))
		print("t=%5.1f st=%d lap=%d/%d pos=%d s=%5.0f d=%+5.1f v=%5.1f (%4.0f km/h) slip=%4.1f h=%.2f %s E=%5.1f thr=%.1f st=%+.2f ab=%.1f/%.1f fps=%3.0f" % [
			_t, s.state, s.lap_shown(s.player), s.laps, s.player.place, ph.hit.s, ph.hit.d, ph.speed, ph.displayed_kmh(), rad_to_deg(ph.slip), ph.h_c,
			"LOCK" if ph.locked else "AIR ", ph.energy, race.player.controls.thrust, race.player.controls.steer, ph.ab_l, ph.ab_r, Quality.fps])


func _physics_process(_dt: float) -> void:
	if _csv == null:
		return
	var race := _race()
	if race == null or race.session == null or not race.session.is_racing():
		return
	var ph := race.player.phys
	var c := race.player.controls
	_csv.store_line("%.3f,%.1f,%.2f,%.3f,%.2f,%.2f,%.2f,%.2f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.1f,%.1f,%d" % [
		race.session.time, ph.hit.s, ph.hit.d, ph.h_c, ph.speed, ph.v_fwd, ph.v_lat, rad_to_deg(ph.slip), ph.yaw_rate, ph.accel_long, ph.accel_lat,
		c.steer, c.thrust, ph.ab_l, ph.ab_r, int(ph.locked), rad_to_deg(ph.align_err), ph.ev_wall, ph.energy, race.session.player.place])


func _print_summary() -> void:
	var race := _race()
	if race == null or race.session == null:
		return
	var s := race.session
	var fps_med := 0.0
	if not _fps_samples.is_empty():
		var arr := _fps_samples.duplicate()
		arr.sort()
		fps_med = arr[arr.size() / 2]
	print("RESULT track=%s finished=%s place=%d/%d time=%.2f best_lap=%.2f laps=%s player_wall_hits=%d min_h=%.2f fps_median=%.0f" % [
		race.cfg.get("track", ""), s.player.finished, s.player.place, s.racers.size(), s.player.finish_time, s.player.best_lap,
		str(Array(s.player.lap_times).map(func(x: float) -> String: return "%.2f" % x)), _walls, _min_h, fps_med])
	if race.weapons and race.weapons.enabled:
		var keys := race.weapons.stats.keys()
		keys.sort()
		print("  combat: " + ", ".join(keys.map(func(k: String) -> String: return "%s=%d" % [k, race.weapons.stats[k]])))
	if Game.last_result.has("booked"):
		var b: Dictionary = Game.last_result["booked"]
		var keys := b.keys()
		keys.sort()
		print("  booked: " + ", ".join(keys.map(func(k: String) -> String: return "%s=%s" % [k, str(b[k])])))
	for r: Dictionary in s.results():
		print("  %d. %-14s %-9s %s best %s %s" % [r["place"], r["name"], r["team"], (("~" if r.get("estimated", false) else "") + Hud.fmt_time(r["time"])) if r["finished"] else ("ELIM" if r["eliminated"] else "DNF"),
			Hud.fmt_time(r["best_lap"]), "top %.0f km/h" % (float(r["top_speed"]) * 3.6 * ShipSpec.SPEED_SCALE)])
