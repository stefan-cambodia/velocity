## Ship physics: hover, thrust, steering, airbrakes, surface following, walls, jumps.
extends TestCase

const DT := 1.0 / 120.0


func _straight_track(width: float = 30.0) -> TrackData:
	# A long oval: 4 km straights, gentle 180° turns.
	return TrackBuilder.build({"start": Vector3.ZERO, "width": width, "segments": [
		{"len": 4000}, {"len": 1500, "turn": 180}, {"len": 4000}, {"len": 1500, "turn": 180}]})


func _ship(td: TrackData, s: float = 20.0, d: float = 0.0) -> ShipPhysics:
	var ph := ShipPhysics.new(ShipSpec.new(), td)
	ph.place(s, d)
	return ph


func _run(ph: ShipPhysics, c: ShipControls, seconds: float, each: Callable = Callable()) -> void:
	for k in int(seconds / DT):
		if each.is_valid():
			each.call(ph, c)
		ph.step(DT, c)


## Simple centre-line follower used by several tests (the AI builds on the same idea).
func _follow(ph: ShipPhysics, c: ShipControls, target_d: float = 0.0) -> void:
	var td := ph.track
	var hit := TrackData.Hit.new()
	var look := clampf(ph.speed * 0.45, 12.0, 60.0)
	td.frame_at(ph.hit.s + look, hit)
	var aim := hit.c + hit.B * target_d
	var to := (aim - ph.pos)
	var r := ph.right()
	var ang := atan2(to.dot(r), to.dot(ph.fwd))
	# Feedforward: the yaw rate the curve needs, as a fraction of the steering limit.
	var w_lim := minf(ph.spec.yaw_low, ph.spec.steer_k * ph.spec.a_lat / maxf(ph.speed, 4.0))
	var ff := ph.speed * td.curvature_h_at(ph.hit.s + ph.speed * 0.15) / w_lim
	c.steer = clampf(ff + ang * 2.4 - (ph.yaw_rate - ff * w_lim) * 0.25, -1.0, 1.0)
	# Speed management: the tightest curvature in the next 2.5 s of travel sets a limit.
	var kmax := 0.0
	var ahead := maxf(ph.speed * 2.5, 60.0)
	var q := 0.0
	while q < ahead:
		var k := absf(td.curvature_h_at(ph.hit.s + q))
		# Allow braking distance: what is reachable from here at ~20 m/s².
		var v_lim := sqrt(0.85 * ph.spec.a_lat / maxf(k, 1e-5))
		var v_ok := sqrt(v_lim * v_lim + 2.0 * 20.0 * q)
		if v_ok < ph.speed:
			kmax = maxf(kmax, 1.0)
		q += 10.0
	c.thrust = 0.0 if kmax > 0.0 else 1.0
	c.ab_l = 0.6 if kmax > 0.0 else 0.0
	c.ab_r = c.ab_l


func test_hover_settles_without_oscillation() -> void:
	var ph := _ship(_straight_track())
	ph.pos += ph.up * 0.8     # Drop it from 0.8 m above rest height.
	var c := ShipControls.new()
	# Lambdas capture locals by value: accumulate into a dictionary.
	var st := {"lo": INF, "hs": []}
	_run(ph, c, 3.0, func(p: ShipPhysics, _c: ShipControls) -> void:
		st["lo"] = minf(st["lo"], p.h_c)
		st["hs"].append(p.h_c))
	var lo: float = st["lo"]
	var hs: Array = st["hs"]
	eq(hs.size(), 360, "sampled every step")
	var eq_h := ph.spec.hover_h - ph.spec.g_track / ph.spec.hover_k
	near(ph.h_c, eq_h, 0.02, "rest height")
	ok(lo >= ph.spec.min_clear - 0.001, "never below min clearance (lowest %.3f)" % lo)
	# Last second: still (no bobbing in the simulation itself).
	var mx := -INF
	var mn := INF
	for k in range(hs.size() - 120, hs.size()):
		mx = maxf(mx, hs[k])
		mn = minf(mn, hs[k])
	ok(mx - mn < 0.005, "settled band %.4f" % (mx - mn))
	ok(ph.locked, "locked")


func test_launch_and_top_speed() -> void:
	var ph := _ship(_straight_track())
	var c := ShipControls.new()
	c.thrust = 1.0
	var t90 := -1.0
	var t := 0.0
	for k in int(30.0 / DT):
		ph.step(DT, c)
		t += DT
		if t90 < 0.0 and ph.v_fwd >= 0.9 * ph.spec.v_top:
			t90 = t
	note("0-90%% top speed %.2f s, final %.1f m/s (%.0f km/h shown)" % [t90, ph.v_fwd, ph.displayed_kmh()])
	between(t90, 4.0, 8.0, "time to 90 % of top speed")
	near(ph.v_fwd, ph.spec.v_top, ph.spec.v_top * 0.02, "top speed")
	near(ph.hit.d, 0.0, 0.05, "runs straight")


func test_coast_and_airbrakes_decelerate() -> void:
	var td := _straight_track()
	var c := ShipControls.new()
	# Coasting from top speed.
	var ph := _ship(td)
	ph.vel = ph.fwd * ph.spec.v_top
	_run(ph, c, 1.0)
	var coast := ph.spec.v_top - ph.v_fwd
	# Both airbrakes from top speed.
	var ph2 := _ship(td)
	ph2.vel = ph2.fwd * ph2.spec.v_top
	c.ab_l = 1.0
	c.ab_r = 1.0
	_run(ph2, c, 1.0)
	var braked := ph2.spec.v_top - ph2.v_fwd
	note("speed lost in 1 s from %.0f m/s: coast %.1f, both airbrakes %.1f" % [ph.spec.v_top, coast, braked])
	between(coast, 5.0, 11.0, "coast deceleration")
	ok(braked > coast * 2.0, "airbrakes brake much harder than coasting")
	near(ph2.hit.d, 0.0, 0.05, "both airbrakes: no yaw")
	near(ph2.yaw_rate, 0.0, 0.001)


func test_single_airbrake_yaws_and_is_symmetric() -> void:
	var td := _straight_track(200.0)
	var c := ShipControls.new()
	c.thrust = 1.0
	var ph_l := _ship(td)
	ph_l.vel = ph_l.fwd * 80.0
	c.ab_l = 1.0
	_run(ph_l, c, 0.8)
	var ph_r := _ship(td)
	ph_r.vel = ph_r.fwd * 80.0
	c.ab_l = 0.0
	c.ab_r = 1.0
	_run(ph_r, c, 0.8)
	note("left brake: yaw %.3f rad/s d %.2f m; right brake: yaw %.3f d %.2f" % [ph_l.yaw_rate, ph_l.hit.d, ph_r.yaw_rate, ph_r.hit.d])
	ok(ph_l.yaw_rate < -0.05, "left airbrake yaws left")
	ok(ph_r.yaw_rate > 0.05, "right airbrake yaws right")
	near(ph_l.yaw_rate, -ph_r.yaw_rate, 1e-4, "symmetric")
	ok(ph_l.hit.d < -0.5 and ph_r.hit.d > 0.5, "moves towards the braked side")
	ok(ph_l.v_fwd < 80.0 and ph_r.v_fwd < 80.0, "and slows down")


func test_steering_is_progressive_and_grip_limited() -> void:
	var td := _straight_track(400.0)
	var out := []
	for st: float in [0.25, 0.5, 1.0]:
		var ph := _ship(td, 50.0, 0.0)
		ph.vel = ph.fwd * 80.0
		var c := ShipControls.new()
		c.thrust = 0.75
		c.steer = st
		var lat := 0.0
		var yaw := 0.0
		var n := 0
		_run(ph, c, 2.0)
		# Average over the next half second at steady state.
		for k in 60:
			ph.step(DT, c)
			lat += ph.accel_lat
			yaw += ph.yaw_rate
			n += 1
		out.append([st, lat / n, yaw / n, rad_to_deg(ph.slip), ph.v_fwd])
	for o: Array in out:
		note("steer %.2f -> lateral %.1f m/s² (%.2f g), yaw %.3f rad/s, slip %.1f deg, speed %.1f" % [o[0], o[1], o[1] / 9.81, o[2], o[3], o[4]])
	# Lateral acceleration grows with input and saturates near the keel capacity.
	ok(out[0][1] < out[1][1] and out[1][1] < out[2][1], "progressive")
	var cap := ShipSpec.new().a_lat
	between(out[2][1], cap * 0.85, cap * 1.12, "full steer uses the grip")
	between(out[1][1] / out[2][1], 0.42, 0.62, "half steer is about half the lateral g")
	ok(absf(out[2][3]) < 8.0, "full steer at 80 m/s: modest slip, not a spin")


func test_airbrake_tightens_a_full_lock_turn() -> void:
	var td := _straight_track(600.0)
	var res := []
	for brake in [0.0, 1.0]:
		var ph := _ship(td, 50.0, 0.0)
		ph.vel = ph.fwd * 85.0
		var c := ShipControls.new()
		c.thrust = 1.0
		c.steer = 1.0
		c.ab_r = brake
		var head0 := ph.fwd
		_run(ph, c, 1.5)
		res.append([rad_to_deg(head0.signed_angle_to(ph.fwd, ph.up)), rad_to_deg(head0.signed_angle_to(ph.vel.normalized(), ph.up)), ph.v_fwd])
	note("1.5 s full right: heading %.0f deg, path %.0f deg, %.0f m/s; with right airbrake: heading %.0f, path %.0f, %.0f m/s" % [
		-res[0][0], -res[0][1], res[0][2], -res[1][0], -res[1][1], res[1][2]])
	ok(absf(res[1][1]) > absf(res[0][1]) * 1.12, "airbrake turns the path at least 12 % further")
	ok(res[1][2] < res[0][2], "at a cost in speed")


func test_follows_banked_oval_without_touching() -> void:
	var td := TrackBuilder.build({"start": Vector3.ZERO, "width": 30.0, "segments": [
		{"len": 600, "rise": 20}, {"len": 520, "turn": 180, "bank": 28}, {"len": 600, "rise": -20}, {"len": 520, "turn": 180, "bank": 28}]})
	var ph := _ship(td)
	var c := ShipControls.new()
	c.thrust = 1.0
	var st := {"lowest": INF, "walls": 0, "unlocked": 0, "max_err": 0.0, "dist": 0.0, "last_s": ph.hit.s}
	_run(ph, c, 60.0, func(p: ShipPhysics, cc: ShipControls) -> void:
		_follow(p, cc)
		st["lowest"] = minf(st["lowest"], p.hit.h)
		if p.ev_wall > 0.0: st["walls"] += 1
		if not p.locked: st["unlocked"] += 1
		st["max_err"] = maxf(st["max_err"], p.align_err)
		st["dist"] += absf(td.delta_s(st["last_s"], p.hit.s))
		st["last_s"] = p.hit.s)
	var lowest: float = st["lowest"]
	var walls: int = st["walls"]
	var unlocked: int = st["unlocked"]
	var max_err: float = st["max_err"]
	var dist: float = st["dist"]
	note("60 s: %.0f m (%.1f laps), lowest h %.2f, wall hits %d, unlocked steps %d, max align err %.1f deg, speed %.1f" % [
		dist, dist / td.length, lowest, walls, unlocked, rad_to_deg(max_err), ph.speed])
	ok(dist > td.length * 1.5, "made progress")
	ok(lowest >= ph.spec.min_clear - 0.01, "never under the minimum clearance")
	eq(walls, 0, "no wall hits")
	eq(unlocked, 0, "stays locked on banked turns and grades")
	ok(max_err < deg_to_rad(8.0), "hull stays aligned with the surface")


func test_jump_flies_and_lands() -> void:
	var td := TrackBuilder.build({"start": Vector3.ZERO, "width": 28.0, "segments": [
		{"len": 1200}, {"len": 120, "rise": 3.0, "exit_slope": 0.09}, {"len": 46, "rise": -2.0, "exit_slope": -0.12, "tags": ["gap"]},
		{"len": 200, "rise": -1.0}, {"len": 800, "turn": 180}, {"len": 1366}, {"len": 800, "turn": 180}]})
	var ph := _ship(td)
	var c := ShipControls.new()
	c.thrust = 1.0
	var st := {"max_air": 0.0, "land": 0.0, "lowest": INF}
	_run(ph, c, 30.0, func(p: ShipPhysics, cc: ShipControls) -> void:
		_follow(p, cc)
		st["max_air"] = maxf(st["max_air"], p.air_time)
		st["land"] = maxf(st["land"], p.ev_land)
		if (p.hit.flags & TrackData.F_GAP) == 0:
			st["lowest"] = minf(st["lowest"], p.hit.h))
	var max_air: float = st["max_air"]
	var land: float = st["land"]
	var lowest: float = st["lowest"]
	note("air time %.2f s, landing speed %.1f m/s, lowest h %.2f" % [max_air, land, lowest])
	between(max_air, 0.4, 3.0, "airborne over the gap")
	ok(land > 0.0, "landing registered")
	ok(lowest >= ph.spec.min_clear - 0.01, "no penetration on landing")
	ok(ph.locked, "locked again after landing")


func test_wall_hit_deflects_without_sticking() -> void:
	var td := _straight_track(30.0)
	var ph := _ship(td, 100.0, 0.0)
	# Point 20 degrees towards the right barrier at 80 m/s.
	ph.fwd = ph.fwd.rotated(ph.up, -deg_to_rad(20.0))
	ph.vel = ph.fwd * 80.0
	var c := ShipControls.new()
	c.thrust = 1.0
	var e0 := ph.energy
	var st := {"impact": 0.0}
	_run(ph, c, 0.6, func(p: ShipPhysics, _c: ShipControls) -> void:
		st["impact"] = maxf(st["impact"], p.ev_wall))
	var impact: float = st["impact"]
	note("impact %.1f m/s, speed after %.1f m/s, d %.2f, energy %.1f -> %.1f" % [impact, ph.speed, ph.hit.d, e0, ph.energy])
	ok(impact > 15.0, "hit the wall")
	between(ph.speed, 40.0, 78.0, "loses speed but keeps going")
	ok(ph.hit.d < 15.0 - 1.2, "inside the barrier")
	ok(ph.fwd.dot(ph.hit.B) < 0.2, "nose turned away from or along the wall")
	ok(ph.energy < e0, "damage taken")
	# A second later it is not glued to the wall.
	c.steer = 0.0
	_run(ph, c, 1.0, func(p: ShipPhysics, cc: ShipControls) -> void: _follow(p, cc))
	ok(not ph.touching_wall, "free of the wall")


func test_deterministic() -> void:
	var td := TrackLibrary.get_track("proving_ground")
	var a := _ship(td)
	var b := _ship(td)
	var c := ShipControls.new()
	c.thrust = 1.0
	for k in 1200:
		c.steer = sin(k * 0.01) * 0.6
		c.ab_l = 1.0 if (k / 90) % 3 == 0 else 0.0
		a.step(DT, c)
		b.step(DT, c)
	eq(a.pos, b.pos, "same inputs, same result")


func test_respawn_returns_to_last_safe_point() -> void:
	var td := _straight_track(30.0)
	var ph := _ship(td, 200.0, 3.0)
	var c := ShipControls.new()
	c.thrust = 1.0
	_run(ph, c, 2.0)
	var safe_s := ph.last_safe_s
	ok(safe_s > 200.0, "safe point advanced (%.0f)" % safe_s)
	# Teleport the ship far below the track, as if it had fallen.
	ph.pos -= ph.up * 40.0
	ph.respawn()
	near(absf(td.delta_s(ph.hit.s, safe_s)), 0.0, 1.0, "back at the last safe lap distance")
	near(ph.hit.h, ph.spec.hover_h, 0.05, "on the surface")
	ok(ph.locked and ph.vel.length() < 0.01, "locked and at rest")
	ok(absf(ph.hit.d) <= 4.0, "near the centre")


func test_barrel_roll_holds_the_ship_upside_down() -> void:
	# A 360-degree roll over 500 m on a straight: the ship must stay locked to
	# the surface through the inverted part, at speed and at low speed.
	var td := TrackBuilder.build({"start": Vector3.ZERO, "width": 30.0, "segments": [
		{"len": 800}, {"len": 500, "roll": 360, "ease": 0.0}, {"len": 800},
		{"len": 1500, "turn": 180}, {"len": 2100, "flex": true}, {"len": 1500, "turn": 180}, {"len": 10, "flex": true}]})
	# Frames are continuous through the roll (no flipped sample).
	var worst := 0.0
	for i in td.count:
		worst = maxf(worst, td.nrm[i].angle_to(td.nrm[(i + 1) % td.count]))
	ok(worst < deg_to_rad(2.0), "normal turns at most %.2f deg per metre" % rad_to_deg(worst))
	var mid := TrackData.Hit.new()
	td.frame_at(800.0 + 250.0, mid)
	ok(mid.N.y < -0.95, "upside down in the middle of the roll (N.y %.2f)" % mid.N.y)
	for v0: float in [30.0, 88.0]:
		var ph := _ship(td, 600.0)
		ph.vel = ph.fwd * v0
		var c := ShipControls.new()
		c.thrust = 1.0
		var st := {"unlocked": 0, "lowest": INF, "walls": 0}
		_run(ph, c, 1500.0 / maxf(v0, 30.0) * 0.6, func(p: ShipPhysics, cc: ShipControls) -> void:
			_follow(p, cc)
			if not p.locked: st["unlocked"] += 1
			st["lowest"] = minf(st["lowest"], p.hit.h)
			if p.ev_wall > 3.0: st["walls"] += 1)
		note("roll at %.0f m/s: unlocked steps %d, lowest h %.2f, wall hits %d, now s=%.0f" % [v0, st["unlocked"], st["lowest"], st["walls"], ph.hit.s])
		ok(ph.hit.s > 1300.0, "made it through the roll at %.0f m/s" % v0)
		eq(st["unlocked"], 0, "stays locked at %.0f m/s" % v0)
		ok(float(st["lowest"]) >= ph.spec.min_clear - 0.01, "no surface contact")


func test_corkscrew_keeps_an_off_centre_line_hands_off() -> void:
	# Ships off the centre line, no steering, through a 360-degree roll over
	# 420 m. Plain world-space physics would fling them outward (the deck point
	# rides a helix needing w²·v²·d of centripetal pull, ~18 m/s² at the
	# barrier) and the hull would trail the deck. The co-rotating lock must hold
	# the offset, the hover gap and the heading, at speed and slowly.
	var td := TrackBuilder.build({"start": Vector3.ZERO, "width": 30.0, "segments": [
		{"len": 800}, {"len": 420, "roll": 360, "ease": 0.0}, {"len": 800},
		{"len": 1500, "turn": 180}, {"len": 2020, "flex": true}, {"len": 1500, "turn": 180}, {"len": 10, "flex": true}]})
	for v0: float in [40.0, 88.0]:
		for d0: float in [-11.0, 8.0]:
			var ph := _ship(td, 700.0, d0)
			ph.vel = ph.fwd * v0
			var c := ShipControls.new()
			c.thrust = 1.0 if v0 > 50.0 else 0.0
			var st := {"worst": 0.0, "walls": 0, "hmin": 9.0, "hmax": 0.0, "lag": 0.0, "end": 0.0, "later": 0.0}
			_run(ph, c, 1300.0 / v0 * 1.6, func(p: ShipPhysics, _cc: ShipControls) -> void:
				if p.hit.s > 760.0 and p.hit.s < 1240.0:
					st["worst"] = maxf(st["worst"], absf(p.hit.d - d0))
					st["hmin"] = minf(st["hmin"], p.hit.h)
					st["hmax"] = maxf(st["hmax"], p.hit.h)
					st["lag"] = maxf(st["lag"], rad_to_deg(p.up.angle_to(p.surf_n)))
					st["end"] = p.hit.d
				if p.hit.s < 1540.0:
					st["later"] = p.hit.d
				if p.ev_wall > 0.5 and p.hit.s < 1540.0: st["walls"] += 1)
			note("roll at %.0f m/s from d=%+.0f hands off: drift %.2f m, h %.2f..%.2f, hull lag %.1f deg, d %+.2f at roll end, %+.2f 300 m on, wall hits %d" % [v0, d0, st["worst"], st["hmin"], st["hmax"], st["lag"], st["end"], st["later"], st["walls"]])
			ok(ph.hit.s > 1540.0, "made it through at %.0f m/s" % v0)
			ok(float(st["worst"]) < 2.0, "offset held within 2 m (drifted %.2f)" % st["worst"])
			ok(absf(float(st["later"]) - float(st["end"])) < 0.5, "leaves the roll pointing straight")
			ok(float(st["hmin"]) > 0.9 and float(st["hmax"]) < 1.15, "hover gap steady")
			ok(float(st["lag"]) < 3.0, "hull follows the deck (lag %.1f deg)" % st["lag"])
			eq(st["walls"], 0, "never touches a barrier")
