## Race-mode rules: elimination knockouts, combat ranking, speed-challenge medals.
extends TestCase


func _track() -> TrackData:
	return TrackBuilder.build({"start": Vector3.ZERO, "width": 30.0, "segments": [
		{"len": 2000}, {"len": 1000, "turn": 180}, {"len": 2000}, {"len": 1000, "turn": 180}]})


func _session(mode: String, n: int) -> RaceSession:
	var td := _track()
	var s := RaceSession.new(td, 3, mode)
	for k in n:
		var sh := Ship.new()
		sh.setup(ShipSpec.new(), td, Catalog.team("halden"), k == 0)
		s.add(sh, "P%d" % k, "halden", k == 0)
	s.place_on_grid()
	s.countdown = 0.0
	s.update(0.01)      # -> RACING
	return s


func _free(s: RaceSession) -> void:
	for r in s.racers:
		r.ship.free()


func test_elimination_knocks_out_the_last_ship_on_the_timer() -> void:
	var s := _session("elimination", 4)
	# Fix the order: P1 leads, P2, P0 (player), P3 last.
	var prog := [100.0, 400.0, 300.0, 50.0]
	for k in 4:
		s.racers[k].progress = prog[k]
	s.update(RaceSession.KNOCKOUT_EVERY - 1.0)
	eq(s.active_count(), 4, "nobody out before the timer")
	s.update(1.1)
	ok(s.racers[3].eliminated and s.racers[3].knocked_out, "the last ship (P3) is knocked out")
	eq(s.active_count(), 3)
	eq(s.racers[3].place, 4, "first out ranks last")
	# Two more knockouts: P0 (player) then P2; P1 survives and wins.
	s.update(RaceSession.KNOCKOUT_EVERY + 0.1)
	ok(s.racers[0].knocked_out, "player knocked out second")
	eq(s.state, RaceSession.State.FINISHED, "race over for the player")
	s.update(RaceSession.KNOCKOUT_EVERY + 0.1)
	ok(s.racers[1].finished and not s.racers[1].eliminated, "last survivor finishes")
	eq(s.racers[1].place, 1, "winner")
	eq(s.racers[2].place, 2)
	eq(s.racers[0].place, 3)
	var res := s.player_result()
	ok(res["finished"], "a knocked-out player still gets a classified result")
	_free(s)


func test_combat_ranks_by_points() -> void:
	var s := _session("combat", 3)
	s.racers[0].progress = 10.0
	s.racers[1].progress = 500.0
	s.racers[2].progress = 300.0
	s.add_points(s.racers[0].ship, 600)
	s.add_points(s.racers[2].ship, 100)
	s.update(0.1)
	eq(s.racers[0].place, 1, "most points leads despite being last on track")
	eq(s.racers[2].place, 2)
	eq(s.racers[1].place, 3)
	_free(s)


func test_speed_challenge_medals() -> void:
	var s := RaceSession.new(_track(), 1, "speed")
	s.set_targets(80.0)
	eq(s.medal(79.0), 3, "gold")
	eq(s.medal(84.0), 2, "silver")
	eq(s.medal(90.0), 1, "bronze")
	eq(s.medal(95.0), 0, "none")
	eq(s.medal(0.0), 0, "no lap")
