## Combat rules: hits in track space, homing, shield, mines, EMP, pickup odds.
extends TestCase

const DT := 1.0 / 60.0


func _track() -> TrackData:
	return TrackBuilder.build({"start": Vector3.ZERO, "width": 30.0, "segments": [
		{"len": 3000}, {"len": 1500, "turn": 180}, {"len": 3000}, {"len": 1500, "turn": 180}]})


func _ship(td: TrackData, s: float, d: float, v: float = 0.0) -> Ship:
	var sh := Ship.new()
	sh.setup(ShipSpec.new(), td, Catalog.team("halden"), false)
	sh.place(s, d)
	sh.phys.vel = sh.phys.fwd * v
	return sh


func _run(w: WeaponSystem, ships: Array, seconds: float) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for k in int(seconds / DT):
		for sh: Ship in ships:
			sh.tick(DT)
		w.tick(DT)
		all.append_array(w.drain_events())
	return all


func _free(ships: Array) -> void:
	for sh: Ship in ships:
		sh.free()


func _hits(events: Array[Dictionary], target: Ship) -> int:
	var n := 0
	for e in events:
		if e["type"] == "hit" and e["ship"] == target:
			n += 1
	return n


func test_plasma_hits_in_lane_and_misses_other_lane() -> void:
	var td := _track()
	var a := _ship(td, 100.0, 0.0, 60.0)
	var b := _ship(td, 160.0, 0.5, 60.0)     # same lane
	var c := _ship(td, 160.0, 9.0, 60.0)     # other lane
	var ships := [a, b, c]
	var w := WeaponSystem.new(td, ships)
	w.give(a, "plasma")
	var e0 := b.phys.energy
	ok(w.fire(a), "fired")
	var ev := _run(w, ships, 1.0)
	eq(_hits(ev, b), 1, "bolt hits the ship ahead in the same lane")
	eq(_hits(ev, c), 0, "and not the one 9 m across")
	ok(b.phys.energy < e0, "damage")
	# Same start as c (unhit, other lane): the hit costs b speed.
	ok(b.phys.speed < c.phys.speed * 0.95, "speed loss (%.1f vs %.1f m/s)" % [b.phys.speed, c.phys.speed])
	eq(w.ammo_of(a), 2, "two bolts left")
	_free(ships)


func test_missile_homes_across_lanes() -> void:
	var td := _track()
	var a := _ship(td, 100.0, -8.0, 60.0)
	var b := _ship(td, 220.0, 8.0, 60.0)
	var ships := [a, b]
	var w := WeaponSystem.new(td, ships)
	w.give(a, "missile")
	eq(w.would_lock(a), b, "locks the ship ahead")
	w.fire(a)
	ok(w.missile_on(b), "target warned")
	var yaw0 := absf(b.phys.yaw_rate)
	var ev := _run(w, ships, 3.0)
	eq(_hits(ev, b), 1, "missile reaches a target 16 m across the track")
	ok(b.phys.energy <= b.phys.spec.shield - float(WeaponSystem.MISSILE["damage"]) + 0.01)
	ok(absf(b.phys.yaw_rate) > yaw0 or b.phys.stun_t >= 0.0, "spun / stunned")
	_free(ships)


func test_shield_blocks() -> void:
	var td := _track()
	var a := _ship(td, 100.0, 0.0, 60.0)
	var b := _ship(td, 150.0, 0.0, 60.0)
	var ships := [a, b]
	var w := WeaponSystem.new(td, ships)
	w.give(b, "shield")
	w.fire(b)
	ok(b.phys.shield_t > 3.9, "shield up")
	w.give(a, "plasma")
	w.fire(a)
	var e0 := b.phys.energy
	var ev := _run(w, ships, 1.0)
	eq(_hits(ev, b), 0, "no hit through the shield")
	near(b.phys.energy, e0, 0.001, "no damage")
	var blocked := 0
	for e in ev:
		if e["type"] == "blocked":
			blocked += 1
	eq(blocked, 1, "blocked event")
	_free(ships)


func test_mines_catch_a_follower() -> void:
	var td := _track()
	var leader := _ship(td, 300.0, 0.0, 0.0)
	var follower := _ship(td, 200.0, 0.0, 70.0)
	var ships := [leader, follower]
	var w := WeaponSystem.new(td, ships)
	w.give(leader, "mines")
	w.fire(leader)
	eq(w.mines.size(), 3, "three mines across the track")
	follower.controls.thrust = 1.0
	var ev := _run(w, ships, 3.0)
	eq(_hits(ev, follower), 1, "the follower hits one mine")
	eq(w.mines.size(), 2, "that mine is gone")
	_free(ships)


func test_emp_radius() -> void:
	var td := _track()
	var a := _ship(td, 100.0, 0.0)
	var near_s := _ship(td, 125.0, 3.0)
	var far_s := _ship(td, 200.0, 0.0)
	var ships := [a, near_s, far_s]
	var w := WeaponSystem.new(td, ships)
	w.give(a, "emp")
	w.fire(a)
	ok(near_s.phys.stun_t > 1.0, "ship 25 m away stunned")
	near(far_s.phys.stun_t, 0.0, 0.001, "ship 100 m away untouched")
	near(a.phys.stun_t, 0.0, 0.001, "not the user")
	_free(ships)


func test_leaders_never_draw_missiles() -> void:
	var td := _track()
	var a := _ship(td, 100.0, 0.0)
	var w := WeaponSystem.new(td, [a], 7)
	var got := {}
	for k in 400:
		w.slot.clear()
		got[w.give_random(a, 1, 8)] = true
	ok(not got.has("missile") and not got.has("shockwave"), "leader table is defensive: %s" % str(got.keys()))
	var back := {}
	for k in 400:
		w.slot.clear()
		back[w.give_random(a, 8, 8)] = true
	ok(back.has("missile"), "the back of the field can draw missiles")
	a.free()


func test_projectiles_stay_inside_barriers() -> void:
	var td := _track()
	var a := _ship(td, 2900.0, 13.0, 80.0)  # near the right barrier, entering the turn
	var w := WeaponSystem.new(td, [a])
	w.give(a, "plasma")
	w.fire(a)
	var hit := TrackData.Hit.new()
	for k in 120:
		w.tick(DT)
		for p in w.projectiles:
			td.frame_at(p.s, hit)
			ok(p.d <= hit.half_r - 0.79 and p.d >= -hit.half_l + 0.79, "bolt inside the barriers")
		if failures.size() > 0:
			break
	a.free()
