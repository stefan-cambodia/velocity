## Generates the visible track from TrackData: racing surface, barriers and the
## structural deck underneath, in chunks of CHUNK samples (each its own
## MeshInstance3D so frustum culling works). The surface uses exactly the same
## frames as the physics, so what is drawn is what the ship rides on.
class_name TrackMesh
extends RefCounted

const CHUNK := 96
const WALL_H := 1.25         ## Barrier height above the surface.
const WALL_T := 0.7          ## Barrier thickness.
const DECK := 1.6            ## Deck depth under the surface.


class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, nn: Vector3, cc: Color, u: Vector2, u2: Vector2 = Vector2.ZERO) -> int:
		v.append(p)
		n.append(nn)
		c.append(cc)
		uv.append(u)
		uv2.append(u2)
		return v.size() - 1

	func quad(a: int, b: int, cc: int, d: int) -> void:
		idx.append_array(PackedInt32Array([a, b, cc, a, cc, d]))

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if idx.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Lateral columns of the surface (fractions of the way between the barriers):
## dense near the edges for the occlusion gradient.
const COLS := [0.0, 0.02, 0.06, 0.25, 0.5, 0.75, 0.94, 0.98, 1.0]


static func build(td: TrackData, parent: Node3D) -> void:
	var chunks := int(ceil(float(td.count) / CHUNK))
	for ci in chunks:
		var i0 := ci * CHUNK
		var i1 := mini(i0 + CHUNK, td.count)   # inclusive end sample index (wraps)
		var mesh := ArrayMesh.new()
		_surface(td, i0, i1).commit(mesh, Mats.get_mat("track"))
		_barriers(td, i0, i1).commit(mesh, Mats.get_mat("barrier"))
		_deck(td, i0, i1).commit(mesh, Mats.get_mat("deck"))
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Track%03d" % ci
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	_pads(td, parent)


## Turn signal for barrier chevrons: curvature a little ahead, mapped to 0..1.
static func _turn(td: TrackData, i: int) -> float:
	var k := 0.0
	for q in [0, 20, 40, 60]:
		k += td.curv_h[td.wrap_i(i + q)]
	k /= 4.0
	return clampf(0.5 + k * 60.0, 0.0, 1.0) if absf(k) > 1.0 / 450.0 else 0.5


static func _gap(td: TrackData, i: int) -> bool:
	return td.flag_at_index(i, TrackData.F_GAP)


static func _surface(td: TrackData, i0: int, i1: int) -> Builder:
	var b := Builder.new()
	var ncol := COLS.size()
	var prev_row := -1
	for i in range(i0, i1 + 1):
		var j := td.wrap_i(i)
		if _gap(td, j):
			prev_row = -1
			continue
		var s := i * td.step
		var hl := td.half_l[j]
		var hr := td.half_r[j]
		var row := b.v.size()
		for k in ncol:
			var f: float = COLS[k]
			var d := lerpf(-hl, hr, f)
			var p := td.pos[j] + td.rgt[j] * d
			var edge := minf(d + hl, hr - d)
			var ao := lerpf(0.55, 1.0, clampf(edge / 2.5, 0.0, 1.0))
			var rech := 0.0 if td.flag_at_index(j, TrackData.F_RECHARGE) else 1.0
			b.add(p, td.nrm[j], Color(ao, ao, ao, rech), Vector2(d, s), Vector2(d + hl, hr - d))
		if prev_row >= 0:
			for k in ncol - 1:
				b.quad(prev_row + k, row + k, row + k + 1, prev_row + k + 1)
		prev_row = row
	return b


## Cross-section of one barrier, from the surface edge outwards: (out, up) pairs
## and the face each segment belongs to (1 = facing the track).
const WALL_PROFILE := [
	[0.0, 0.0], [0.0, WALL_H], [0.18, WALL_H + 0.18], [WALL_T, WALL_H + 0.18], [WALL_T + 0.12, 0.0], [WALL_T + 0.12, -DECK * 0.55]]
const WALL_INNER := [1, 1, 0, 0, 0]


static func _barriers(td: TrackData, i0: int, i1: int) -> Builder:
	var b := Builder.new()
	for side: float in [-1.0, 1.0]:
		var np := WALL_PROFILE.size()
		var prev := -1
		for i in range(i0, i1 + 1):
			var j := td.wrap_i(i)
			if _gap(td, j):
				prev = -1
				continue
			var s := i * td.step
			var edge := td.half_r[j] if side > 0.0 else -td.half_l[j]
			var turn := _turn(td, j)
			var row := b.v.size()
			# Two vertices per profile point (flat shading per segment).
			for k in np - 1:
				var p0: Array = WALL_PROFILE[k]
				var p1: Array = WALL_PROFILE[k + 1]
				var a := td.pos[j] + td.rgt[j] * (edge + side * float(p0[0])) + td.nrm[j] * float(p0[1])
				var c := td.pos[j] + td.rgt[j] * (edge + side * float(p1[0])) + td.nrm[j] * float(p1[1])
				var seg := c - a
				var nn := td.tan[j].cross(seg).normalized() * -side
				var inner: int = WALL_INNER[k]
				var col := Color(1, 1, 1, turn)
				b.add(a, nn, col, Vector2(s, float(p0[1])), Vector2(inner, side))
				b.add(c, nn, col, Vector2(s, float(p1[1])), Vector2(inner, side))
			if prev >= 0:
				for k in np - 1:
					var a0 := prev + k * 2
					var a1 := row + k * 2
					if side > 0.0:
						b.quad(a0, a1, a1 + 1, a0 + 1)
					else:
						b.quad(a0, a0 + 1, a1 + 1, a1)
			prev = row
	return b


static func _deck(td: TrackData, i0: int, i1: int) -> Builder:
	var b := Builder.new()
	# Underside: a chamfered beam beneath the surface.
	var prof := [[-1.0, -DECK * 0.55, 0.0], [-0.82, -DECK, 0.0], [0.82, -DECK, 0.0], [1.0, -DECK * 0.55, 0.0]]
	var prev := -1
	for i in range(i0, i1 + 1):
		var j := td.wrap_i(i)
		if _gap(td, j):
			prev = -1
			continue
		var s := i * td.step
		var wl := td.half_l[j] + WALL_T + 0.12
		var wr := td.half_r[j] + WALL_T + 0.12
		var row := b.v.size()
		for k in prof.size() - 1:
			var p0: Array = prof[k]
			var p1: Array = prof[k + 1]
			var d0: float = p0[0] * (wr if p0[0] > 0.0 else wl)
			var d1: float = p1[0] * (wr if p1[0] > 0.0 else wl)
			var a := td.pos[j] + td.rgt[j] * d0 + td.nrm[j] * float(p0[1])
			var c := td.pos[j] + td.rgt[j] * d1 + td.nrm[j] * float(p1[1])
			var nn := td.tan[j].cross(c - a).normalized()
			b.add(a, nn, Color(0.7, 0.7, 0.75), Vector2(s, d0))
			b.add(c, nn, Color(0.7, 0.7, 0.75), Vector2(s, d1))
		if prev >= 0:
			for k in prof.size() - 1:
				var a0 := prev + k * 2
				var a1 := row + k * 2
				b.quad(a0, a0 + 1, a1 + 1, a1)
		prev = row
	return b


static func _pads(td: TrackData, parent: Node3D) -> void:
	for pad: Dictionary in td.pads:
		var mk := MeshKit.new()
		var s0: float = pad["s"]
		var L: float = pad["length"]
		var d: float = pad["d"]
		var hw: float = pad["half_width"]
		var n := 8
		var secs: Array[PackedVector3Array] = []
		for q in n + 1:
			var s := s0 + L * q / n
			var hit := TrackData.Hit.new()
			td.frame_at(s, hit)
			secs.append(PackedVector3Array([hit.c + hit.B * (d - hw) + hit.N * 0.03, hit.c + hit.B * (d + hw) + hit.N * 0.03]))
		mk.use("pad_boost" if pad["kind"] == "boost" else "pad_weapon")
		mk.loft(secs, Color.WHITE, false, false)
		var mi := mk.instance("Pad")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
