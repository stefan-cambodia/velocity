## The analytic racing surface: a closed loop of evenly spaced frames (about one
## per metre) built by TrackBuilder. Physics, AI, cameras, progress and respawn
## all query this table; the render mesh is generated from it, so what you see
## is exactly what the ship rides on.
##
## Frames: T = tangent (direction of travel), N = surface normal (banked up),
## B = T x N (to the driver's right). Lateral offset d is measured along B
## (positive = right), height h along N.
class_name TrackData
extends RefCounted

## Per-sample flags.
const F_TUNNEL := 1        ## Covered: ceiling at `ceiling` above the surface.
const F_GAP := 2           ## No surface (jump): ships fly ballistic here.
const F_NO_WALL := 4       ## Barriers absent (visual openings); catch walls still apply.
const F_RECHARGE := 8      ## Energy recharge strip.
const F_START := 16        ## Start/finish straight (grid area).

var name: String = ""
var count: int = 0
var length: float = 0.0
var step: float = 1.0
var pos := PackedVector3Array()
var tan := PackedVector3Array()
var nrm := PackedVector3Array()
var rgt := PackedVector3Array()
var half_l := PackedFloat32Array()     ## Distance from centre to the left barrier.
var half_r := PackedFloat32Array()     ## Distance from centre to the right barrier.
var bank := PackedFloat32Array()       ## Radians, positive = right side low.
var curv_h := PackedFloat32Array()     ## Signed horizontal curvature (1/m), positive = turning right.
var curv_v := PackedFloat32Array()     ## Vertical curvature (1/m), positive = valley (surface curving up).
var flags := PackedInt32Array()
var ceiling := PackedFloat32Array()    ## Height of the tunnel ceiling above the surface (0 = open).
var pad_at := PackedInt32Array()       ## Index into `pads` of the pad covering this sample, or -1.
## Speed / weapon pads: {kind: "boost"|"weapon", s, length, d, half_width}.
var pads: Array[Dictionary] = []
## Lateral obstacles (split-lane islands): {s0, s1, d0, d1}, d0 < d1.
var islands: Array[Dictionary] = []
## Named sections for the map and debugging: {name, s0, s1}.
var sections: Array[Dictionary] = []
## Builder diagnostics.
var closure_error: float = 0.0
var closure_heading_deg: float = 0.0
var flex_lengths: Array = []           ## Solved lengths of the flex straights.


## Result of a projection. Reuse one instance per caller to avoid allocations.
class Hit:
	var i: int = 0            ## Sample index at or before the point.
	var t: float = 0.0        ## Fraction towards sample i + 1.
	var s: float = 0.0        ## Distance along the lap, 0 .. length.
	var d: float = 0.0        ## Lateral offset (right positive).
	var h: float = 0.0        ## Height above the surface plane.
	var c := Vector3.ZERO     ## Centre line point.
	var T := Vector3.FORWARD
	var N := Vector3.UP
	var B := Vector3.RIGHT
	var half_l: float = 10.0
	var half_r: float = 10.0
	var flags: int = 0


func wrap_i(i: int) -> int:
	return posmod(i, count)


func wrap_s(s: float) -> float:
	return fposmod(s, length)


## Signed shortest distance along the lap from s0 to s1 (in -length/2 .. length/2).
func delta_s(s0: float, s1: float) -> float:
	var ds := fposmod(s1 - s0, length)
	return ds - length if ds > length * 0.5 else ds


## Nearest sample by brute force (initialisation, respawn, editor tools).
func nearest_index(p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in count:
		var dd := pos[i].distance_squared_to(p)
		if dd < best_d:
			best_d = dd
			best = i
	return best


## Projects a world point onto the track. `hint` is the previous sample index
## (pass -1 to search the whole lap). Walks along the frames from the hint, so
## the result is local: where the track crosses over itself the projection
## stays on the stretch the point is travelling along.
func project(p: Vector3, hint: int, out: Hit) -> void:
	var i := nearest_index(p) if hint < 0 else wrap_i(hint)
	# Walk until p lies between the planes of samples i and i + 1.
	for _k in 96:
		var a := (p - pos[i]).dot(tan[i])
		if a < 0.0:
			i = wrap_i(i - 1)
			continue
		var j := wrap_i(i + 1)
		var b := (p - pos[j]).dot(tan[j])
		if b >= 0.0:
			i = j
			continue
		break
	var j2 := wrap_i(i + 1)
	var a0 := (p - pos[i]).dot(tan[i])
	var a1 := (p - pos[j2]).dot(tan[j2])
	var t := clampf(a0 / maxf(a0 - a1, 1e-6), 0.0, 1.0)
	_fill(out, i, t)
	var rel := p - out.c
	out.d = rel.dot(out.B)
	out.h = rel.dot(out.N)


## Frame at a distance along the lap.
func frame_at(s: float, out: Hit) -> void:
	var sw := wrap_s(s)
	var f := sw / step
	var i := int(f)
	_fill(out, wrap_i(i), f - i)
	out.d = 0.0
	out.h = 0.0


func _fill(out: Hit, i: int, t: float) -> void:
	var j := wrap_i(i + 1)
	out.i = i
	out.t = t
	out.s = (i + t) * step
	out.c = pos[i].lerp(pos[j], t)
	out.T = tan[i].lerp(tan[j], t).normalized()
	var n := nrm[i].lerp(nrm[j], t)
	# Re-orthogonalise against T.
	n = (n - out.T * n.dot(out.T)).normalized()
	out.N = n
	out.B = out.T.cross(n)
	out.half_l = lerpf(half_l[i], half_l[j], t)
	out.half_r = lerpf(half_r[i], half_r[j], t)
	out.flags = flags[i] if t < 0.5 else flags[j]


## World position of the surface point at (s, d), raised by h along the normal.
func point_at(s: float, d: float, h: float = 0.0) -> Vector3:
	var hit := Hit.new()
	frame_at(s, hit)
	return hit.c + hit.B * d + hit.N * h


## Transform for an object standing on the surface at (s, d), facing along the track.
## Basis: x = right, y = up, z = backwards (Godot's -Z forward convention).
func xform_at(s: float, d: float, h: float = 0.0) -> Transform3D:
	var hit := Hit.new()
	frame_at(s, hit)
	return Transform3D(Basis(hit.B, hit.N, -hit.T), hit.c + hit.B * d + hit.N * h)


func has_flag(s: float, flag: int) -> bool:
	return (flags[wrap_i(int(wrap_s(s) / step))] & flag) != 0


func flag_at_index(i: int, flag: int) -> bool:
	return (flags[wrap_i(i)] & flag) != 0


func curvature_h_at(s: float) -> float:
	var f := wrap_s(s) / step
	var i := int(f)
	return lerpf(curv_h[wrap_i(i)], curv_h[wrap_i(i + 1)], f - i)


func curvature_v_at(s: float) -> float:
	var f := wrap_s(s) / step
	var i := int(f)
	return lerpf(curv_v[wrap_i(i)], curv_v[wrap_i(i + 1)], f - i)


## The pad under (sample i, lateral d), or an empty dictionary. Several pads
## may share a stretch of track side by side; each dictionary has an "index".
func pad_under(i: int, d: float) -> Dictionary:
	if pad_at[wrap_i(i)] < 0:
		return {}
	var s := wrap_i(i) * step
	for pad: Dictionary in pads:
		if fposmod(s - float(pad["s"]), length) <= float(pad["length"]) + step and absf(d - float(pad["d"])) <= float(pad["half_width"]):
			return pad
	return {}


## The island (split-lane divider) at sample i, or an empty dictionary.
func island_at(s: float) -> Dictionary:
	for isl in islands:
		var s0: float = isl["s0"]
		var s1: float = isl["s1"]
		if fposmod(s - s0, length) <= fposmod(s1 - s0, length):
			return isl
	return {}


## Recomputes the derived per-sample data (curvatures, pad lookup) after the
## arrays were filled.
func finalize() -> void:
	curv_h.resize(count)
	curv_v.resize(count)
	for i in count:
		var tp := tan[wrap_i(i - 1)]
		var tn := tan[wrap_i(i + 1)]
		var dt := (tn - tp) / (2.0 * step)
		curv_h[i] = dt.dot(rgt[i])
		curv_v[i] = dt.dot(nrm[i])
	pad_at.resize(count)
	pad_at.fill(-1)
	for k in pads.size():
		var pad: Dictionary = pads[k]
		pad["index"] = k
		var i0 := int(float(pad["s"]) / step)
		var n := int(ceil(float(pad["length"]) / step))
		for q in n + 1:
			pad_at[wrap_i(i0 + q)] = k
