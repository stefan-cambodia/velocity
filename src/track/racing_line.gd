## The racing line and its speed profile, computed once per track and ship
## class at load time.
##
## Line: lateral offsets every STEP metres, relaxed like a taut string between
## the barriers (minus a safety margin) by iterative smoothing. This hugs the
## inside of corners with late apexes and straightens chicanes.
## Speed: lateral grip limit from the line's curvature (plus banking), crest
## limit from the vertical curvature, then a backward braking pass and a
## forward acceleration pass around the loop.
class_name RacingLine
extends RefCounted

const STEP := 4.0

var track: TrackData
var n: int = 0
var d := PackedFloat32Array()      ## Lateral offset of the line.
var k := PackedFloat32Array()      ## Signed curvature of the line in the surface plane.
var v := PackedFloat32Array()      ## Target speed (m/s) for the reference spec.
var lap_estimate: float = 0.0      ## Seconds, at profile speed.


static func compute(td: TrackData, spec: ShipSpec, margin: float = 3.0, iterations: int = 600) -> RacingLine:
	var rl := RacingLine.new()
	rl.track = td
	rl.n = int(td.length / STEP)
	rl.d.resize(rl.n)
	rl.k.resize(rl.n)
	rl.v.resize(rl.n)
	var c := PackedVector3Array()
	var b := PackedVector3Array()
	var nn := PackedVector3Array()
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	var hit := TrackData.Hit.new()
	c.resize(rl.n)
	b.resize(rl.n)
	nn.resize(rl.n)
	lo.resize(rl.n)
	hi.resize(rl.n)
	for i in rl.n:
		td.frame_at(i * rl.step_len(), hit)
		c[i] = hit.c
		b[i] = hit.B
		nn[i] = hit.N
		lo[i] = -hit.half_l + margin
		hi[i] = hit.half_r - margin
		rl.d[i] = 0.0
	# Split-lane islands: keep the line on one side (the shorter one, decided after relaxing).
	# Relax.
	for it in iterations:
		var w := 0.55
		for i in rl.n:
			var p0 := c[(i - 1 + rl.n) % rl.n] + b[(i - 1 + rl.n) % rl.n] * rl.d[(i - 1 + rl.n) % rl.n]
			var p2 := c[(i + 1) % rl.n] + b[(i + 1) % rl.n] * rl.d[(i + 1) % rl.n]
			var mid := (p0 + p2) * 0.5
			var want := (mid - c[i]).dot(b[i])
			rl.d[i] = clampf(lerpf(rl.d[i], want, w), lo[i], hi[i])
	for isl: Dictionary in td.islands:
		var s0: float = isl["s0"]
		var s1: float = isl["s1"]
		var i0 := int(s0 / rl.step_len())
		var i1 := int(s1 / rl.step_len())
		var avg := 0.0
		for i in range(i0, i1 + 1):
			avg += rl.d[i % rl.n]
		var left := avg / maxf(1.0, i1 - i0 + 1) < (float(isl["d0"]) + float(isl["d1"])) * 0.5
		for i in range(i0 - 6, i1 + 7):
			var j := posmod(i, rl.n)
			if left:
				hi[j] = minf(hi[j], float(isl["d0"]) - margin)
			else:
				lo[j] = maxf(lo[j], float(isl["d1"]) + margin)
		for it in 200:
			for i in rl.n:
				var p0 := c[(i - 1 + rl.n) % rl.n] + b[(i - 1 + rl.n) % rl.n] * rl.d[(i - 1 + rl.n) % rl.n]
				var p2 := c[(i + 1) % rl.n] + b[(i + 1) % rl.n] * rl.d[(i + 1) % rl.n]
				rl.d[i] = clampf(lerpf(rl.d[i], ((p0 + p2) * 0.5 - c[i]).dot(b[i]), 0.55), lo[i], hi[i])
	# Curvature of the line (Menger, in the surface plane) and vertical curvature.
	var pts := PackedVector3Array()
	pts.resize(rl.n)
	for i in rl.n:
		pts[i] = c[i] + b[i] * rl.d[i]
	for i in rl.n:
		var a := pts[(i - 2 + rl.n) % rl.n]
		var m := pts[i]
		var e := pts[(i + 2) % rl.n]
		var t1 := (m - a)
		var t2 := (e - m)
		var cr := t1.cross(t2)
		var area2 := cr.dot(nn[i])
		var denom := t1.length() * t2.length() * (e - a).length()
		rl.k[i] = -2.0 * area2 / maxf(denom, 1e-6)
	# Speed profile.
	var g := 9.81
	for i in rl.n:
		var kk := absf(rl.k[i])
		var j := td.wrap_i(int(i * rl.step_len() / td.step))
		# Banking helps when the turn goes into the bank.
		var bank_help := g * sin(td.bank[j]) * signf(rl.k[i]) * spec.planar_g * ShipPhysics.planar_fade(td.nrm[j].y)
		var a_lat := spec.a_lat * 0.92 + maxf(bank_help, -3.0)
		var vl := sqrt(maxf(a_lat, 5.0) / maxf(kk, 1e-5))
		# Crests: stay under the speed that would lift the ship off (unless it is a jump).
		var kv := td.curv_v[j]
		if kv < -1e-4 and not td.flag_at_index(j, TrackData.F_GAP) and not td.flag_at_index(j + 30, TrackData.F_GAP):
			vl = minf(vl, sqrt((spec.g_track + spec.pull_max) * 0.9 / -kv))
		rl.v[i] = minf(vl, spec.v_top * 1.02)
	var brake := 15.0
	for rep in 2:
		for q in rl.n:
			var i := rl.n - 1 - q
			var nx := rl.v[(i + 1) % rl.n]
			rl.v[i] = minf(rl.v[i], sqrt(nx * nx + 2.0 * brake * rl.step_len()))
	var vmax := rl.v.duplicate()
	for rep in 2:
		for i in rl.n:
			var pv := rl.v[(i - 1 + rl.n) % rl.n]
			var acc := spec.accel * maxf(0.05, 1.0 - pow(pv / spec.v_top, 2.0))
			rl.v[i] = minf(vmax[i], sqrt(pv * pv + 2.0 * acc * rl.step_len()))
	rl.lap_estimate = 0.0
	for i in rl.n:
		rl.lap_estimate += rl.step_len() / maxf(rl.v[i], 5.0)
	return rl


func step_len() -> float:
	return track.length / n


func _idx(s: float) -> Array:
	var f := fposmod(s, track.length) / step_len()
	var i := int(f)
	return [i % n, (i + 1) % n, f - i]


func d_at(s: float) -> float:
	var q := _idx(s)
	return lerpf(d[q[0]], d[q[1]], q[2])


func v_at(s: float) -> float:
	var q := _idx(s)
	return lerpf(v[q[0]], v[q[1]], q[2])


func k_at(s: float) -> float:
	var q := _idx(s)
	return lerpf(k[q[0]], k[q[1]], q[2])


## Lowest profile speed in [s, s + ahead].
func v_min_ahead(s: float, ahead: float) -> float:
	var m := INF
	var q := 0.0
	while q <= ahead:
		m = minf(m, v_at(s + q))
		q += STEP
	return m
