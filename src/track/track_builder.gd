## Builds a TrackData from a circuit written as segments (see TrackLibrary).
##
## Segment keys (all optional except len):
##   len        horizontal length in metres
##   turn       heading change in degrees, positive = right
##   ease       fraction of the segment over which curvature ramps in and out (0.3)
##   ease_in / ease_out   override ease per end (0 = curvature starts at full value)
##   bank       peak bank in degrees during the segment, following the curvature
##              profile (positive = right side low, i.e. into a right turn)
##   bank_base  persistent bank reached by the end of the segment (smoothstep)
##   rise       height change in metres (cubic Hermite, continuous slope)
##   exit_slope slope (dy/dx) at the end of the segment, 0 by default
##   width      full track width reached by the end of the segment
##   tags       ["tunnel", "gap", "no_wall", "recharge", "start"]
##   ceiling    tunnel ceiling height above the surface
##   name       section name (map, telemetry)
##
## Corners never have curvature steps: each turn ramps in and out smoothly, so
## the ship's yaw demand is continuous. The loop is closed by spreading the
## heading error over the turns and the position error along the lap.
class_name TrackBuilder
extends RefCounted

const DX := 0.5   ## Horizontal integration step (m).


static func _ramp(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Curvature shape of a turn over u in 0..1, peak 1.
static func profile(u: float, ein: float, eout: float) -> float:
	var a := 1.0 if ein <= 0.0 else _ramp(u / ein)
	var b := 1.0 if eout <= 0.0 else _ramp((1.0 - u) / eout)
	return a * b


static func _profile_mean(ein: float, eout: float) -> float:
	var n := 256
	var acc := 0.0
	for k in n:
		acc += profile((k + 0.5) / n, ein, eout)
	return acc / n


static func _hermite(u: float, y0: float, m0: float, y1: float, m1: float) -> float:
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * y0 + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * y1 + (u3 - u2) * m1


class _Raw:
	var p := PackedVector3Array()
	var bank := PackedFloat32Array()
	var hl := PackedFloat32Array()
	var hr := PackedFloat32Array()
	var flags := PackedInt32Array()
	var ceil := PackedFloat32Array()
	var seg := PackedInt32Array()      ## Segment index of each raw sample.
	var heading_end: float = 0.0
	var seg_heading := PackedFloat32Array()   ## Heading at the start of each segment.


static func _integrate(spec: Dictionary, turns: PackedFloat32Array, lens: PackedFloat32Array) -> _Raw:
	var raw := _Raw.new()
	var segs: Array = spec["segments"]
	var psi: float = deg_to_rad(float(spec.get("heading", 0.0)))
	var p: Vector3 = spec.get("start", Vector3.ZERO)
	var y := p.y
	var slope := 0.0
	var width: float = spec.get("width", 28.0)
	var bank_base := 0.0
	for si in segs.size():
		var sg: Dictionary = segs[si]
		var L: float = lens[si]
		raw.seg_heading.append(psi)
		var n := maxi(1, int(round(L / DX)))
		var dx := L / n
		var ein: float = sg.get("ease_in", sg.get("ease", 0.3))
		var eout: float = sg.get("ease_out", sg.get("ease", 0.3))
		var turn := turns[si]
		var mean := _profile_mean(ein, eout)
		var k_scale := turn / (L * mean) if absf(turn) > 1e-9 else 0.0
		var bank_peak := deg_to_rad(float(sg.get("bank", 0.0)))
		var bb0 := bank_base
		var bb1 := deg_to_rad(float(sg.get("bank_base", rad_to_deg(bank_base))))
		var y0 := y
		var y1: float = y + float(sg.get("rise", 0.0))
		var m0 := slope
		var m1: float = sg.get("exit_slope", 0.0)
		var w0 := width
		var w1: float = sg.get("width", width)
		var f := 0
		for tag: String in sg.get("tags", []):
			match tag:
				"tunnel": f |= TrackData.F_TUNNEL
				"gap": f |= TrackData.F_GAP
				"no_wall": f |= TrackData.F_NO_WALL
				"recharge": f |= TrackData.F_RECHARGE
				"start": f |= TrackData.F_START
		var ceil_h: float = sg.get("ceiling", 0.0)
		var start_k := 0 if si == 0 else 1
		for k in range(start_k, n + 1):
			var u := float(k) / n
			if k > 0:
				# Midpoint heading for the step.
				var um := (k - 0.5) / n
				psi += k_scale * profile(um, ein, eout) * dx
				p.x += sin(psi) * dx
				p.z -= cos(psi) * dx
			var yy := _hermite(u, y0, m0 * L, y1, m1 * L)
			var w := lerpf(w0, w1, _ramp(u))
			var b := lerpf(bb0, bb1, _ramp(u)) + bank_peak * profile(u, ein, eout)
			raw.p.append(Vector3(p.x, yy, p.z))
			raw.bank.append(b)
			raw.hl.append(w * 0.5)
			raw.hr.append(w * 0.5)
			raw.flags.append(f)
			raw.ceil.append(ceil_h)
			raw.seg.append(si)
		y = y1
		slope = m1
		width = w1
		bank_base = bb1
	raw.heading_end = psi
	return raw


## Builds the track. Returns null if the spec is malformed.
static func build(spec: Dictionary) -> TrackData:
	var segs: Array = spec["segments"]
	var turns := PackedFloat32Array()
	var lens := PackedFloat32Array()
	var flex: Array[int] = []
	var total_abs := 0.0
	for si in segs.size():
		var sg: Dictionary = segs[si]
		var t := deg_to_rad(float(sg.get("turn", 0.0)))
		turns.append(t)
		lens.append(float(sg["len"]))
		total_abs += absf(t)
		if sg.get("flex", false) and absf(t) < 1e-9:
			flex.append(si)
	# Pass 1: find the heading error and spread it over the turns.
	var raw := _integrate(spec, turns, lens)
	var psi0 := deg_to_rad(float(spec.get("heading", 0.0)))
	var full := raw.heading_end - psi0
	var target: float = round(full / TAU) * TAU
	var err: float = full - target
	if total_abs > 0.0:
		for si in turns.size():
			turns[si] -= err * absf(turns[si]) / total_abs
		raw = _integrate(spec, turns, lens)
	var td := TrackData.new()
	# Pass 2: two "flex" straights in different directions absorb the
	# horizontal position gap exactly (straights do not change later headings).
	if flex.size() >= 2:
		var g0 := raw.p[raw.p.size() - 1] - raw.p[0]
		var a := flex[0]
		var b := flex[1]
		var da := Vector2(sin(raw.seg_heading[a]), -cos(raw.seg_heading[a]))
		var db := Vector2(sin(raw.seg_heading[b]), -cos(raw.seg_heading[b]))
		var det := da.x * db.y - da.y * db.x
		if absf(det) > 0.2:
			var ex := -g0.x
			var ez := -g0.z
			var ka := (ex * db.y - ez * db.x) / det
			var kb := (da.x * ez - da.y * ex) / det
			lens[a] += ka
			lens[b] += kb
			td.flex_lengths = [lens[a], lens[b]]
			if lens[a] < 20.0 or lens[b] < 20.0:
				push_warning("track %s: flex straights solved to %.0f / %.0f m" % [spec.get("name", ""), lens[a], lens[b]])
			raw = _integrate(spec, turns, lens)
		else:
			push_warning("track %s: flex straights are nearly parallel" % spec.get("name", ""))
	td.name = spec.get("name", "")
	td.closure_heading_deg = rad_to_deg(err)
	# Close the position gap linearly along the horizontal distance.
	var m := raw.p.size()
	var gap := raw.p[m - 1] - raw.p[0]
	td.closure_error = gap.length()
	var hd := PackedFloat32Array()
	hd.resize(m)
	hd[0] = 0.0
	for k in range(1, m):
		var a := raw.p[k - 1]
		var b := raw.p[k]
		hd[k] = hd[k - 1] + Vector2(b.x - a.x, b.z - a.z).length()
	var htot := hd[m - 1]
	for k in m:
		raw.p[k] -= gap * (hd[k] / htot)
	# Drop the duplicated closing sample.
	m -= 1
	# Resample by 3D arc length.
	var cum := PackedFloat32Array()
	cum.resize(m + 1)
	cum[0] = 0.0
	for k in m:
		cum[k + 1] = cum[k] + raw.p[k].distance_to(raw.p[(k + 1) % m])
	var L3 := cum[m]
	var count := int(round(L3))
	td.count = count
	td.length = L3
	td.step = L3 / count
	td.pos.resize(count)
	td.bank.resize(count)
	td.half_l.resize(count)
	td.half_r.resize(count)
	td.flags.resize(count)
	td.ceiling.resize(count)
	var seg_of := PackedInt32Array()
	seg_of.resize(count)
	var r := 0
	for i in count:
		var s := i * td.step
		while r < m - 1 and cum[r + 1] <= s:
			r += 1
		var r1 := (r + 1) % m
		var seg_len := maxf(cum[r + 1] - cum[r], 1e-6)
		var t := clampf((s - cum[r]) / seg_len, 0.0, 1.0)
		td.pos[i] = raw.p[r].lerp(raw.p[r1], t)
		td.bank[i] = lerpf(raw.bank[r], raw.bank[r1], t)
		td.half_l[i] = lerpf(raw.hl[r], raw.hl[r1], t)
		td.half_r[i] = lerpf(raw.hr[r], raw.hr[r1], t)
		var near := r if t < 0.5 else r1
		td.flags[i] = raw.flags[near]
		td.ceiling[i] = raw.ceil[near]
		seg_of[i] = raw.seg[near]
	_frames(td)
	# Section ranges in lap distance.
	var seg_s0 := PackedFloat32Array()
	var seg_s1 := PackedFloat32Array()
	seg_s0.resize(segs.size())
	seg_s1.resize(segs.size())
	seg_s0.fill(-1.0)
	for i in count:
		var si := seg_of[i]
		if seg_s0[si] < 0.0:
			seg_s0[si] = i * td.step
		seg_s1[si] = (i + 1) * td.step
	for si in segs.size():
		var sg: Dictionary = segs[si]
		if sg.has("name"):
			td.sections.append({"name": sg["name"], "s0": seg_s0[si], "s1": seg_s1[si], "seg": si})
	# Pads and islands are placed by segment and fraction.
	for pd: Dictionary in spec.get("pads", []):
		var si: int = pd["seg"]
		var s := lerpf(seg_s0[si], seg_s1[si], float(pd.get("at", 0.5)))
		td.pads.append({"kind": pd.get("kind", "boost"), "s": s, "length": float(pd.get("length", 12.0)),
			"d": float(pd.get("d", 0.0)), "half_width": float(pd.get("half_width", 3.2))})
	for isl: Dictionary in spec.get("islands", []):
		var si: int = isl["seg"]
		var span := seg_s1[si] - seg_s0[si]
		td.islands.append({"s0": seg_s0[si] + span * float(isl.get("from", 0.1)), "s1": seg_s0[si] + span * float(isl.get("to", 0.9)),
			"d0": float(isl["d0"]), "d1": float(isl["d1"])})
	td.finalize()
	return td


## Tangents by central differences, then zero-roll normals rotated by the bank.
static func _frames(td: TrackData) -> void:
	var n := td.count
	td.tan.resize(n)
	td.nrm.resize(n)
	td.rgt.resize(n)
	for i in n:
		var t := (td.pos[(i + 1) % n] - td.pos[(i - 1 + n) % n]).normalized()
		td.tan[i] = t
	for i in n:
		var t := td.tan[i]
		var n0 := (Vector3.UP - t * t.y).normalized()
		var b0 := t.cross(n0)
		var b := td.bank[i]
		var nn := (n0 * cos(b) + b0 * sin(b)).normalized()
		td.nrm[i] = nn
		td.rgt[i] = t.cross(nn)
