## Handling bench: repeatable measurements of every team's ship in a speed class.
##   godot --headless --path . -s tools/handling_bench.gd -- [class=1] [laps] [team ...]
## Prints, per team: 0-90 % time, top speed, coasting and airbrake deceleration,
## steady lateral g at 25/50/100 % steering, turn-in time, airbrake path gain,
## speed kept after a 20° wall hit, and an AI lap on the proving ground.
extends SceneTree

const DT := 1.0 / 120.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var cls := 1
	var do_laps := true
	var teams: Array = []
	for a in args:
		if a.begins_with("class="):
			cls = int(a.substr(6))
		elif a == "nolap":
			do_laps = false
		else:
			teams.append(a)
	if teams.is_empty():
		teams = Array(Catalog.team_ids())
	var flat := TrackBuilder.build({"start": Vector3.ZERO, "width": 600.0, "segments": [
		{"len": 5000}, {"len": 2000, "turn": 180}, {"len": 5000}, {"len": 2000, "turn": 180}]})
	var narrow := TrackBuilder.build({"start": Vector3.ZERO, "width": 30.0, "segments": [
		{"len": 5000}, {"len": 2000, "turn": 180}, {"len": 5000}, {"len": 2000, "turn": 180}]})
	var pg := TrackLibrary.get_track("proving_ground")
	print("class %s  (displayed km/h = m/s x %.1f)" % [ShipSpec.CLASSES[cls]["name"], 3.6 * ShipSpec.SPEED_SCALE])
	print("%-9s %5s %6s %5s %5s | %5s %5s %5s %6s | %5s %5s | %5s | %7s %4s %5s" % ["team", "t90", "top", "coast", "brake",
		"g25", "g50", "g100", "turnin", "path", "+ab%", "wall%", "lap", "hits", "vmax"])
	for tid: String in teams:
		var spec := Catalog.spec_for(tid, cls)
		var row := [tid]
		row.append_array(_straight(spec, flat))
		row.append_array(_steer(spec, flat))
		row.append_array(_airbrake(spec, flat))
		row.append(_wall(spec, narrow))
		if do_laps:
			row.append_array(_lap(spec, pg, tid))
		else:
			row.append_array([0.0, 0, 0.0])
		print("%-9s %5.2f %6.0f %5.1f %5.1f | %5.2f %5.2f %5.2f %6.3f | %5.0f %5.0f | %5.0f | %7.2f %4d %5.0f" % row)
	quit()


func _ship(spec: ShipSpec, td: TrackData, s: float = 50.0) -> ShipPhysics:
	var ph := ShipPhysics.new(spec, td)
	ph.place(s, 0.0)
	return ph


func _straight(spec: ShipSpec, td: TrackData) -> Array:
	var ph := _ship(spec, td)
	var c := ShipControls.new()
	c.thrust = 1.0
	var t90 := -1.0
	for k in int(30.0 / DT):
		ph.step(DT, c)
		if t90 < 0.0 and ph.v_fwd > 0.9 * spec.v_top:
			t90 = k * DT
	var top := ph.displayed_kmh()
	var v0 := ph.v_fwd
	c.thrust = 0.0
	for k in 120:
		ph.step(DT, c)
	var coast := v0 - ph.v_fwd
	var ph2 := _ship(spec, td)
	ph2.vel = ph2.fwd * spec.v_top
	c.ab_l = 1.0
	c.ab_r = 1.0
	for k in 120:
		ph2.step(DT, c)
	return [t90, top, coast, spec.v_top - ph2.v_fwd]


func _steer(spec: ShipSpec, td: TrackData) -> Array:
	var out := []
	var v := spec.v_top * 0.85
	for st: float in [0.25, 0.5, 1.0]:
		var ph := _ship(spec, td)
		ph.vel = ph.fwd * v
		var c := ShipControls.new()
		c.thrust = 0.8
		c.steer = st
		var turn_in := -1.0
		var w_ss := 0.0
		var hist := PackedFloat32Array()
		for k in int(2.5 / DT):
			ph.step(DT, c)
			hist.append(ph.yaw_rate)
		w_ss = hist[hist.size() - 1]
		for k in hist.size():
			if turn_in < 0.0 and hist[k] >= 0.9 * w_ss:
				turn_in = k * DT
		var lat := 0.0
		for k in 60:
			ph.step(DT, c)
			lat += ph.accel_lat
		out.append(lat / 60.0 / 9.81)
		if st == 1.0:
			out.append(turn_in)
	return out


func _airbrake(spec: ShipSpec, td: TrackData) -> Array:
	var res := []
	for brake: float in [0.0, 1.0]:
		var ph := _ship(spec, td)
		ph.vel = ph.fwd * spec.v_top * 0.9
		var c := ShipControls.new()
		c.thrust = 1.0
		c.steer = 1.0
		c.ab_r = brake
		var h0 := ph.fwd
		for k in int(1.5 / DT):
			ph.step(DT, c)
		res.append(rad_to_deg(absf(h0.signed_angle_to(ph.vel.normalized(), ph.up))))
	return [res[0], (res[1] / res[0] - 1.0) * 100.0]


func _wall(spec: ShipSpec, td: TrackData) -> float:
	var ph := _ship(spec, td, 100.0)
	ph.fwd = ph.fwd.rotated(ph.up, -deg_to_rad(20.0))
	ph.vel = ph.fwd * spec.v_top * 0.9
	var v0 := ph.vel.length()
	var c := ShipControls.new()
	c.thrust = 1.0
	for k in 72:
		ph.step(DT, c)
	return ph.speed / v0 * 100.0


func _lap(spec: ShipSpec, td: TrackData, tid: String) -> Array:
	var sh := Ship.new()
	sh.setup(spec, td, Catalog.team(tid), false)
	sh.place(td.length - 30.0, 0.0)
	var line := RacingLine.compute(td, spec)
	var ai := AIDriver.new(sh, line, "technical", 2, 1)
	ai.others = [sh]
	var progress := -30.0
	var last_s := sh.phys.hit.s
	var t := 0.0
	var lap1 := -1.0
	var hits := 0
	var vmax := 0.0
	while t < 400.0:
		ai.drive(1.0 / 60.0)
		sh.tick(1.0 / 60.0)
		t += 1.0 / 60.0
		var s := sh.phys.hit.s
		progress += td.delta_s(last_s, s)
		last_s = s
		if sh.phys.ev_wall > 4.0:
			hits += 1
		vmax = maxf(vmax, sh.phys.displayed_kmh())
		if lap1 < 0.0 and progress >= td.length:
			lap1 = t
		if progress >= 2.0 * td.length:
			sh.free()
			return [t - lap1, hits, vmax]
	sh.free()
	return [-1.0, hits, vmax]
