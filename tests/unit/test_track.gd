## Track builder and projection queries.
extends TestCase


func _oval() -> TrackData:
	return TrackBuilder.build({
		"start": Vector3.ZERO, "width": 30.0,
		"segments": [
			{"len": 400},
			{"len": 471.24, "turn": 180, "bank": 20},
			{"len": 400},
			{"len": 471.24, "turn": 180, "bank": 20},
		]})


func test_oval_closes_and_has_expected_length() -> void:
	var td := _oval()
	note("length %.1f closure %.3f m heading %.3f deg" % [td.length, td.closure_error, td.closure_heading_deg])
	between(td.length, 1700.0, 1800.0, "lap length")
	ok(td.closure_error < 1.0, "closure error %.3f" % td.closure_error)
	near(td.step, 1.0, 0.01, "step")
	# Consecutive samples are evenly spaced and tangents continuous.
	var worst_turn := 0.0
	for i in td.count:
		var a := td.pos[i]
		var b := td.pos[(i + 1) % td.count]
		near(a.distance_to(b), td.step, 0.05, "spacing at %d" % i)
		worst_turn = maxf(worst_turn, td.tan[i].angle_to(td.tan[(i + 1) % td.count]))
		if failures.size() > 3:
			return
	ok(worst_turn < deg_to_rad(1.0), "max tangent change per metre %.3f deg" % rad_to_deg(worst_turn))


func test_frames_are_orthonormal_and_banked() -> void:
	var td := _oval()
	for i in range(0, td.count, 37):
		near(td.tan[i].length(), 1.0, 1e-3)
		near(td.nrm[i].dot(td.tan[i]), 0.0, 1e-3)
		near(td.rgt[i].dot(td.nrm[i]), 0.0, 1e-3)
	# Mid-turn of a right-hander: banked into the turn (normal leans right).
	var hit := TrackData.Hit.new()
	td.frame_at(400.0 + 235.0, hit)
	ok(hit.N.dot(hit.B.slide(Vector3.UP).normalized()) > -1.0)
	var bank_deg := rad_to_deg(td.bank[int(635.0 / td.step)])
	near(bank_deg, 20.0, 1.0, "peak bank")
	# Curvature mid-turn: the mean is 1/150 m; the eased profile peaks at mean / profile mean.
	var mean := 0.0
	for k in 1000:
		mean += TrackBuilder.profile((k + 0.5) / 1000.0, 0.3, 0.3) / 1000.0
	# Measured in the banked surface plane: horizontal curvature x cos(bank).
	near(td.curvature_h_at(635.0), (PI / 471.24) / mean * cos(deg_to_rad(20.0)), 0.0002, "curvature mid turn")


func test_projection_round_trip() -> void:
	var td := _oval()
	var hit := TrackData.Hit.new()
	var hint := 0
	for k in 200:
		var s := fposmod(k * 9.37, td.length)
		var d := -12.0 + fmod(k * 3.1, 24.0)
		var h := 0.5 + fmod(k * 0.7, 4.0)
		var p := td.point_at(s, d, h)
		td.project(p, hint, hit)
		hint = hit.i
		near(absf(td.delta_s(s, hit.s)), 0.0, 0.05, "s at k=%d" % k)
		near(hit.d, d, 0.05, "d at k=%d" % k)
		near(hit.h, h, 0.05, "h at k=%d" % k)
		if failures.size() > 3:
			return


func test_projection_stays_local_on_crossover() -> void:
	# A figure-eight style crossing: the track passes 12 m above itself.
	# Figure eight through the origin: R = 150 loops, 12 m apart at the crossing.
	var arc := 150.0 * 1.5 * PI
	var td := TrackBuilder.build({
		"start": Vector3.ZERO, "width": 24.0, "heading": 45.0,
		"segments": [
			{"len": 150, "flex": true},
			{"len": arc, "turn": -270, "rise": 12, "ease": 0.0},
			{"len": 300, "flex": true},
			{"len": arc, "turn": 270, "rise": -12, "ease": 0.0},
			{"len": 150},
		]})
	note("crossover length %.0f closure %.2f flex %s" % [td.length, td.closure_error, str(td.flex_lengths)])
	ok(td.closure_error < 0.5, "closure after flex solve")
	# The two passes really are 12 m apart at the crossing.
	var a := TrackData.Hit.new()
	td.project(Vector3(0, 0.5, 0), 0, a)
	near(a.h, 0.5, 0.2, "low pass under the origin")
	var hit := TrackData.Hit.new()
	# Follow the centre line at 1.2 m height with a hint; s must advance monotonically.
	var hint := 0
	var prev := 0.0
	var steps := int(td.length / 2.0)
	for k in range(1, steps):
		var s := k * 2.0
		var p := td.point_at(s, 3.0, 1.2)
		td.project(p, hint, hit)
		hint = hit.i
		near(hit.s - prev, 2.0, 0.1, "advance at s=%.0f" % s)
		prev = hit.s
		if failures.size() > 3:
			return


func test_proving_ground_builds() -> void:
	var td := TrackLibrary.get_track("proving_ground")
	note("proving ground %.0f m, closure %.2f m / %.2f deg, %d sections" % [td.length, td.closure_error, td.closure_heading_deg, td.sections.size()])
	ok(td.count > 3000)
	eq(td.pads.size(), 6)
	var gaps := 0
	for i in td.count:
		if td.flag_at_index(i, TrackData.F_GAP):
			gaps += 1
	between(gaps, 38.0, 52.0, "jump gap samples")
	ok(td.closure_error < 1.0, "closure %.2f" % td.closure_error)
