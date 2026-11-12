## Procedural mesh builder. Primitives are appended to named material groups
## with per-vertex colour; commit() turns the groups into one ArrayMesh with a
## surface per material. Everything in the game that is not terrain is built with it.
##
## Conventions: +Y up, counter-clockwise profiles, colours are linear-ish sRGB
## multiplied by the material. `shade` darkens a primitive (cheap baked occlusion).
class_name MeshKit
extends RefCounted

## One material's vertex streams.
class Group:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()

var _groups: Dictionary = {}         ## material key -> Group
var _cur: Group
var xf: Transform3D = Transform3D.IDENTITY   ## Applied to everything appended.
var _stack: Array[Transform3D] = []


func _init() -> void:
	use("default")


## Selects the material group that following primitives go to.
func use(key: String) -> MeshKit:
	if not _groups.has(key):
		_groups[key] = Group.new()
	_cur = _groups[key]
	return self


func push(t: Transform3D) -> MeshKit:
	_stack.append(xf)
	xf = xf * t
	return self


func pop() -> MeshKit:
	xf = _stack.pop_back()
	return self


func is_empty() -> bool:
	for k: String in _groups:
		if (_groups[k] as Group).v.size() > 0:
			return false
	return true


func _vert(p: Vector3, n: Vector3, c: Color, uv: Vector2 = Vector2.ZERO) -> int:
	_cur.v.append(xf * p)
	_cur.n.append((xf.basis * n).normalized())
	_cur.c.append(c)
	_cur.uv.append(uv)
	return _cur.v.size() - 1


func _tri(a: int, b: int, c: int) -> void:
	_cur.i.append(a)
	_cur.i.append(b)
	_cur.i.append(c)


func _quad_i(a: int, b: int, c: int, d: int) -> void:
	_tri(a, b, c)
	_tri(a, c, d)


## Flat quad a-b-c-d (clockwise seen from the front), with UVs 0..1 scaled by `uv_scale`.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv_scale: Vector2 = Vector2.ONE, uv_off: Vector2 = Vector2.ZERO, double: bool = false) -> MeshKit:
	var n := (c - a).cross(b - a).normalized()
	var i0 := _vert(a, n, col, uv_off)
	var i1 := _vert(b, n, col, uv_off + Vector2(uv_scale.x, 0.0))
	var i2 := _vert(c, n, col, uv_off + uv_scale)
	var i3 := _vert(d, n, col, uv_off + Vector2(0.0, uv_scale.y))
	_quad_i(i0, i1, i2, i3)
	if double:
		var j0 := _vert(a, -n, col, uv_off)
		var j1 := _vert(b, -n, col, uv_off + Vector2(uv_scale.x, 0.0))
		var j2 := _vert(c, -n, col, uv_off + uv_scale)
		var j3 := _vert(d, -n, col, uv_off + Vector2(0.0, uv_scale.y))
		_quad_i(j0, j3, j2, j1)
	return self


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, double: bool = false) -> MeshKit:
	var n := (c - a).cross(b - a).normalized()
	_tri(_vert(a, n, col, Vector2(0, 0)), _vert(b, n, col, Vector2(1, 0)), _vert(c, n, col, Vector2(0.5, 1)))
	if double:
		_tri(_vert(a, -n, col), _vert(c, -n, col), _vert(b, -n, col))
	return self


## Axis-aligned box centred on `centre` (in the current transform). `bottom_shade`
## darkens the lower vertices for a grounded look. UVs are metres * uv_scale.
func box(centre: Vector3, size: Vector3, col: Color, bottom_shade: float = 1.0, uv_scale: float = 1.0) -> MeshKit:
	var h := size * 0.5
	var lo := col * bottom_shade
	lo.a = col.a
	var p := func(sx: float, sy: float, sz: float) -> Vector3: return centre + Vector3(h.x * sx, h.y * sy, h.z * sz)
	var faces := [
		[Vector3(0, 0, 1), [p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, -1, 1), p.call(-1, -1, 1)], Vector2(size.x, size.y)],
		[Vector3(0, 0, -1), [p.call(1, 1, -1), p.call(-1, 1, -1), p.call(-1, -1, -1), p.call(1, -1, -1)], Vector2(size.x, size.y)],
		[Vector3(1, 0, 0), [p.call(1, 1, 1), p.call(1, 1, -1), p.call(1, -1, -1), p.call(1, -1, 1)], Vector2(size.z, size.y)],
		[Vector3(-1, 0, 0), [p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(-1, -1, 1), p.call(-1, -1, -1)], Vector2(size.z, size.y)],
		[Vector3(0, 1, 0), [p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(-1, 1, 1)], Vector2(size.x, size.z)],
		[Vector3(0, -1, 0), [p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, -1, -1), p.call(-1, -1, -1)], Vector2(size.x, size.z)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var q: Array = f[1]
		var s: Vector2 = f[2] * uv_scale
		var uvs := [Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)]
		var ids := PackedInt32Array()
		for k in 4:
			var pt: Vector3 = q[k]
			ids.append(_vert(pt, n, lo if pt.y < centre.y else col, uvs[k]))
		_quad_i(ids[0], ids[1], ids[2], ids[3])
	return self


## Box given by a full transform (for rotated beams and panels).
func box_t(t: Transform3D, size: Vector3, col: Color, bottom_shade: float = 1.0, uv_scale: float = 1.0) -> MeshKit:
	push(t)
	box(Vector3.ZERO, size, col, bottom_shade, uv_scale)
	return pop()


## A beam of rectangular section from a to b. `up_hint` orients the section.
func beam(a: Vector3, b: Vector3, width: float, height: float, col: Color, up_hint: Vector3 = Vector3.UP, uv_scale: float = 1.0) -> MeshKit:
	var z := (b - a)
	var length := z.length()
	if length < 0.0001:
		return self
	z /= length
	var x := up_hint.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x)
	return box_t(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(width, height, length), col, 1.0, uv_scale)


static func _frame(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


## Cylinder or cone frustum from a to b. UV: u around, v along (metres * uv_v).
func cyl(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, caps: bool = true, col_b: Color = Color(-1, 0, 0), uv_v: float = 1.0) -> MeshKit:
	var axis := b - a
	var length := axis.length()
	if length < 0.00001:
		return self
	var f := _frame(axis)
	var cb := col if col_b.r < 0.0 else col_b
	var slope := (r0 - r1) / length
	var base := _cur.v.size()
	for k in sides + 1:
		var ang := TAU * k / sides
		var radial := f.x * cos(ang) + f.y * sin(ang)
		var n := (radial + f.z * slope).normalized()
		_vert(a + radial * r0, n, col, Vector2(float(k) / sides, 0.0))
		_vert(b + radial * r1, n, cb, Vector2(float(k) / sides, length * uv_v))
	for k in sides:
		var i := base + k * 2
		_quad_i(i, i + 1, i + 3, i + 2)
	if caps:
		if r0 > 0.0001:
			_cap(a, -f.z, f, r0, sides, col, true)
		if r1 > 0.0001:
			_cap(b, f.z, f, r1, sides, cb, false)
	return self


func _cap(c: Vector3, n: Vector3, f: Basis, r: float, sides: int, col: Color, flip: bool) -> void:
	var ci := _vert(c, n, col, Vector2(0.5, 0.5))
	var first := _cur.v.size()
	for k in sides:
		var ang := TAU * k / sides
		_vert(c + (f.x * cos(ang) + f.y * sin(ang)) * r, n, col, Vector2(0.5 + cos(ang) * 0.5, 0.5 + sin(ang) * 0.5))
	for k in sides:
		var i0 := first + k
		var i1 := first + (k + 1) % sides
		if flip:
			_tri(ci, i0, i1)
		else:
			_tri(ci, i1, i0)


## Round tube through a list of points (roll cages, exhausts, railings, branches).
## `radii` may hold one radius or one per point.
func tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, col: Color, caps: bool = true, uv_v: float = 1.0) -> MeshKit:
	var m := pts.size()
	if m < 2:
		return self
	var base := _cur.v.size()
	var prev_x := Vector3.ZERO
	var dist := 0.0
	var first_frame := Basis.IDENTITY
	var last_frame := Basis.IDENTITY
	for j in m:
		var dir: Vector3
		if j == 0:
			dir = pts[1] - pts[0]
		elif j == m - 1:
			dir = pts[m - 1] - pts[m - 2]
		else:
			dir = (pts[j + 1] - pts[j]).normalized() + (pts[j] - pts[j - 1]).normalized()
		dir = dir.normalized()
		# Parallel-transport the frame so the tube does not twist.
		var x: Vector3
		if j == 0:
			x = _frame(dir).x
		else:
			x = (prev_x - dir * prev_x.dot(dir)).normalized()
			dist += pts[j].distance_to(pts[j - 1])
		prev_x = x
		var y := dir.cross(x)
		var r := radii[mini(j, radii.size() - 1)]
		if j == 0:
			first_frame = Basis(x, y, dir)
		last_frame = Basis(x, y, dir)
		for k in sides + 1:
			var ang := TAU * k / sides
			var radial := x * cos(ang) + y * sin(ang)
			_vert(pts[j] + radial * r, radial, col, Vector2(float(k) / sides, dist * uv_v))
	for j in m - 1:
		for k in sides:
			var i := base + j * (sides + 1) + k
			_quad_i(i, i + sides + 1, i + sides + 2, i + 1)
	if caps:
		_cap(pts[0], -first_frame.z, first_frame, radii[0], sides, col, true)
		_cap(pts[m - 1], last_frame.z, last_frame, radii[mini(m - 1, radii.size() - 1)], sides, col, false)
	return self


## Smooth curve through control points (Catmull-Rom), for use with tube().
static func curve(ctrl: PackedVector3Array, per_segment: int = 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	var m := ctrl.size()
	for i in m - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, m - 1)]
		for j in per_segment:
			var t := float(j) / per_segment
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(ctrl[m - 1])
	return out


## Ellipsoid. `col_bottom` (optional) gives a vertical gradient.
func sphere(centre: Vector3, radius: Vector3, rings: int, sides: int, col: Color, col_bottom: Color = Color(-1, 0, 0)) -> MeshKit:
	var cb := col if col_bottom.r < 0.0 else col_bottom
	var base := _cur.v.size()
	for j in rings + 1:
		var phi := PI * j / rings
		var y := cos(phi)
		var rr := sin(phi)
		for k in sides + 1:
			var th := TAU * k / sides
			var unit := Vector3(rr * cos(th), y, rr * sin(th))
			var n := Vector3(unit.x / radius.x, unit.y / radius.y, unit.z / radius.z).normalized()
			_vert(centre + unit * radius, n, cb.lerp(col, y * 0.5 + 0.5), Vector2(float(k) / sides, float(j) / rings))
	for j in rings:
		for k in sides:
			var i := base + j * (sides + 1) + k
			_quad_i(i, i + sides + 1, i + sides + 2, i + 1)
	return self


## Surface of revolution about +Y from a profile of (radius, height) points, bottom to top.
## UV: u around * uv_u, v along the profile (metres).
func lathe(profile: PackedVector2Array, sides: int, col: Color, uv_u: float = 1.0, smooth: bool = true, arc: float = TAU) -> MeshKit:
	var m := profile.size()
	var base := _cur.v.size()
	var dist := 0.0
	if smooth:
		for j in m:
			var a := profile[maxi(j - 1, 0)]
			var b := profile[mini(j + 1, m - 1)]
			var tang := (b - a).normalized()
			var n2 := Vector2(tang.y, -tang.x)
			if j > 0:
				dist += profile[j].distance_to(profile[j - 1])
			for k in sides + 1:
				var th := arc * k / sides
				_vert(Vector3(profile[j].x * cos(th), profile[j].y, profile[j].x * sin(th)), Vector3(n2.x * cos(th), n2.y, n2.x * sin(th)), col, Vector2(float(k) / sides * uv_u, dist))
		for j in m - 1:
			for k in sides:
				var i := base + j * (sides + 1) + k
				_quad_i(i, i + 1, i + sides + 2, i + sides + 1)
	else:
		for j in m - 1:
			var a := profile[j]
			var b := profile[j + 1]
			var tang := (b - a).normalized()
			var n2 := Vector2(tang.y, -tang.x)
			var seg := a.distance_to(b)
			var s0 := _cur.v.size()
			for k in sides + 1:
				var th := arc * k / sides
				var n := Vector3(n2.x * cos(th), n2.y, n2.x * sin(th))
				_vert(Vector3(a.x * cos(th), a.y, a.x * sin(th)), n, col, Vector2(float(k) / sides * uv_u, dist))
				_vert(Vector3(b.x * cos(th), b.y, b.x * sin(th)), n, col, Vector2(float(k) / sides * uv_u, dist + seg))
			for k in sides:
				var i := s0 + k * 2
				_quad_i(i, i + 2, i + 3, i + 1)
			dist += seg
	return self


## lathe() about an arbitrary axis: the profile's +Y is mapped by `t`.
func lathe_at(t: Transform3D, profile: PackedVector2Array, sides: int, col: Color, uv_u: float = 1.0, smooth: bool = true) -> MeshKit:
	push(t)
	lathe(profile, sides, col, uv_u, smooth)
	return pop()


func torus(centre: Vector3, axis: Vector3, major: float, minor: float, segments: int, sides: int, col: Color, arc: float = TAU) -> MeshKit:
	var f := _frame(axis)
	var base := _cur.v.size()
	for j in segments + 1:
		var a := arc * j / segments
		var radial := f.x * cos(a) + f.y * sin(a)
		for k in sides + 1:
			var b := TAU * k / sides
			var n := radial * cos(b) + f.z * sin(b)
			_vert(centre + radial * major + n * minor, n, col, Vector2(float(j) / segments * 8.0, float(k) / sides))
	for j in segments:
		for k in sides:
			var i := base + j * (sides + 1) + k
			_quad_i(i, i + 1, i + sides + 2, i + sides + 1)
	return self


## Lumpy ball: an icosphere-like shape pushed around by noise. Rocks and tree crowns.
## `flat` gives faceted shading. `col_bottom` darkens the underside.
func blob(centre: Vector3, radius: Vector3, detail: int, noise: FastNoiseLite, strength: float, col: Color, col_bottom: Color, flat: bool = false, seed_off: Vector3 = Vector3.ZERO) -> MeshKit:
	var rings := 3 + detail * 2
	var sides := 5 + detail * 3
	var pts := PackedVector3Array()
	for j in rings + 1:
		var phi := PI * j / rings
		for k in sides:
			var th := TAU * k / sides + (0.5 * TAU / sides if j % 2 == 1 else 0.0)
			var unit := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var disp := 1.0 + noise.get_noise_3dv(unit * 1.7 + seed_off) * strength
			pts.append(centre + unit * radius * disp)
	var idx := PackedInt32Array()
	for j in rings:
		for k in sides:
			var a := j * sides + k
			var b := j * sides + (k + 1) % sides
			var c := (j + 1) * sides + k
			var d := (j + 1) * sides + (k + 1) % sides
			if j % 2 == 0:
				idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
			else:
				idx.append_array(PackedInt32Array([a, d, b, a, c, d]))
	if flat:
		for t in idx.size() / 3:
			var a := pts[idx[t * 3]]
			var b := pts[idx[t * 3 + 1]]
			var c := pts[idx[t * 3 + 2]]
			var n := (c - a).cross(b - a)
			if n.length() < 0.000001:
				continue
			n = n.normalized()
			var shade := col_bottom.lerp(col, clampf(n.y * 0.6 + 0.55, 0.0, 1.0))
			_tri(_vert(a, n, shade, Vector2(a.x, a.z)), _vert(b, n, shade, Vector2(b.x, b.z)), _vert(c, n, shade, Vector2(c.x, c.z)))
	else:
		var base := _cur.v.size()
		for p in pts:
			var n := ((p - centre) / radius).normalized()
			_vert(p, n, col_bottom.lerp(col, clampf(n.y * 0.6 + 0.55, 0.0, 1.0)), Vector2(p.x, p.y))
		for t in idx.size() / 3:
			_tri(base + idx[t * 3], base + idx[t * 3 + 1], base + idx[t * 3 + 2])
	return self


## A textured card (foliage, signs): width x height, standing on `base`, facing `normal`.
## UV covers the rect (uv0..uv1). Double-sided unless told otherwise.
func card(base: Vector3, right: Vector3, up: Vector3, col: Color, uv0: Vector2 = Vector2(0, 1), uv1: Vector2 = Vector2(1, 0), double: bool = true, normal_override: Vector3 = Vector3.ZERO) -> MeshKit:
	var a := base - right * 0.5
	var b := base + right * 0.5
	var n := right.cross(up).normalized() if normal_override == Vector3.ZERO else normal_override
	var i0 := _vert(a, n, col, Vector2(uv0.x, uv0.y))
	var i1 := _vert(b, n, col, Vector2(uv1.x, uv0.y))
	var i2 := _vert(b + up, n, col, Vector2(uv1.x, uv1.y))
	var i3 := _vert(a + up, n, col, Vector2(uv0.x, uv1.y))
	_quad_i(i0, i3, i2, i1)
	if double:
		var nb := -n if normal_override == Vector3.ZERO else normal_override
		var j0 := _vert(a, nb, col, Vector2(uv0.x, uv0.y))
		var j1 := _vert(b, nb, col, Vector2(uv1.x, uv0.y))
		var j2 := _vert(b + up, nb, col, Vector2(uv1.x, uv1.y))
		var j3 := _vert(a + up, nb, col, Vector2(uv0.x, uv1.y))
		_quad_i(j0, j1, j2, j3)
	return self


## Extrudes a closed 2D outline (in the XY plane, counter-clockwise) along Z from z0 to z1.
## For body panels, plates, signs with shaped outlines. Convex or gently concave outlines only.
func extrude(outline: PackedVector2Array, z0: float, z1: float, col: Color, caps: bool = true) -> MeshKit:
	var m := outline.size()
	for k in m:
		var a := outline[k]
		var b := outline[(k + 1) % m]
		quad(Vector3(a.x, a.y, z1), Vector3(b.x, b.y, z1), Vector3(b.x, b.y, z0), Vector3(a.x, a.y, z0), col)
	if caps:
		var tris := Geometry2D.triangulate_polygon(outline)
		for side in 2:
			var z := z1 if side == 0 else z0
			var n := Vector3(0, 0, 1) if side == 0 else Vector3(0, 0, -1)
			var first := _cur.v.size()
			for p in outline:
				_vert(Vector3(p.x, p.y, z), n, col, p)
			for t in tris.size() / 3:
				if side == 0:
					_tri(first + tris[t * 3], first + tris[t * 3 + 2], first + tris[t * 3 + 1])
				else:
					_tri(first + tris[t * 3], first + tris[t * 3 + 1], first + tris[t * 3 + 2])
	return self


## Lofted skin between cross-sections (each a list of points with equal counts).
## For car body shells and fairings. `closed` wraps each section into a ring.
func loft(sections: Array[PackedVector3Array], col: Color, closed: bool = false, flip: bool = false) -> MeshKit:
	var rows := sections.size()
	var cols := sections[0].size()
	var base := _cur.v.size()
	for r in rows:
		for k in cols:
			var p := sections[r][k]
			var pr := sections[mini(r + 1, rows - 1)][k] - sections[maxi(r - 1, 0)][k]
			var k0 := (k - 1 + cols) % cols if closed else maxi(k - 1, 0)
			var k1 := (k + 1) % cols if closed else mini(k + 1, cols - 1)
			var pc := sections[r][k1] - sections[r][k0]
			var n := pc.cross(pr).normalized()
			if flip:
				n = -n
			_vert(p, n, col, Vector2(float(k) / (cols - 1), float(r) / (rows - 1)))
	var span := cols if closed else cols - 1
	for r in rows - 1:
		for k in span:
			var a := base + r * cols + k
			var b := base + r * cols + (k + 1) % cols
			var c := base + (r + 1) * cols + (k + 1) % cols
			var d := base + (r + 1) * cols + k
			if flip:
				_quad_i(a, b, c, d)
			else:
				_quad_i(a, d, c, b)
	return self


## Coil spring from a to b.
func spring(a: Vector3, b: Vector3, radius: float, wire: float, turns: float, col: Color, sides: int = 5) -> MeshKit:
	var f := _frame(b - a)
	var length := a.distance_to(b)
	var pts := PackedVector3Array()
	var steps := int(turns * 10.0)
	for j in steps + 1:
		var t := float(j) / steps
		var ang := t * turns * TAU
		pts.append(a + f.z * (length * t) + (f.x * cos(ang) + f.y * sin(ang)) * radius)
	return tube(pts, PackedFloat32Array([wire]), sides, col)


## Multiplies the colour of every vertex in the current group below `y1` by a
## ramp from `dark` at y0 to 1 at y1: a cheap ground-contact occlusion.
func ground_shade(y0: float, y1: float, dark: float) -> MeshKit:
	for key: String in _groups:
		var g: Group = _groups[key]
		for i in g.v.size():
			var t := clampf((g.v[i].y - y0) / (y1 - y0), 0.0, 1.0)
			var m := lerpf(dark, 1.0, t)
			g.c[i] = Color(g.c[i].r * m, g.c[i].g * m, g.c[i].b * m, g.c[i].a)
	return self


func vertex_count() -> int:
	var n := 0
	for key: String in _groups:
		n += (_groups[key] as Group).v.size()
	return n


func triangle_count() -> int:
	var n := 0
	for key: String in _groups:
		n += (_groups[key] as Group).i.size() / 3
	return n


## Builds the mesh. `materials` maps group keys to Material; missing keys fall back to Mats.get_mat(key).
func commit(materials: Dictionary = {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: String in _groups:
		var g: Group = _groups[key]
		if g.v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_TEX_UV] = g.uv
		arrays[Mesh.ARRAY_INDEX] = g.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: Material = materials.get(key, null)
		if mat == null:
			mat = Mats.get_mat(key)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


## Convenience: commit into a MeshInstance3D.
func instance(name: String = "Mesh", materials: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit(materials)
	return mi


## Loft with a colour per section point (same layout as `sections`). Used for
## painted hulls where the livery mask varies along and around the body.
func loft_colored(sections: Array[PackedVector3Array], colors: Array[PackedColorArray], closed: bool = false, flip: bool = false) -> MeshKit:
	var rows := sections.size()
	var cols := sections[0].size()
	var base := _cur.v.size()
	for r in rows:
		for k in cols:
			var p := sections[r][k]
			var pr := sections[mini(r + 1, rows - 1)][k] - sections[maxi(r - 1, 0)][k]
			var k0 := (k - 1 + cols) % cols if closed else maxi(k - 1, 0)
			var k1 := (k + 1) % cols if closed else mini(k + 1, cols - 1)
			var pc := sections[r][k1] - sections[r][k0]
			var n := pc.cross(pr).normalized()
			if flip:
				n = -n
			_vert(p, n, colors[r][k], Vector2(float(k) / (cols - 1), float(r) / (rows - 1)))
	var span := cols if closed else cols - 1
	for r in rows - 1:
		for k in span:
			var a := base + r * cols + k
			var b := base + r * cols + (k + 1) % cols
			var c := base + (r + 1) * cols + (k + 1) % cols
			var d := base + (r + 1) * cols + k
			if flip:
				_quad_i(a, b, c, d)
			else:
				_quad_i(a, d, c, b)
	return self


## Appends a mirrored copy (x -> -x, winding flipped) of everything added to
## the current group since vertex index `from`.
func mirror_x_since(from: int) -> MeshKit:
	var g := _cur
	var nv := g.v.size()
	var ni := g.i.size()
	var first_i := -1
	# Find the first index entry referring to vertices >= from.
	for k in range(0, ni, 3):
		if g.i[k] >= from and g.i[k + 1] >= from and g.i[k + 2] >= from:
			first_i = k
			break
	if first_i < 0:
		return self
	var off := nv - from
	for k in range(from, nv):
		var p := g.v[k]
		var n := g.n[k]
		g.v.append(Vector3(-p.x, p.y, p.z))
		g.n.append(Vector3(-n.x, n.y, n.z))
		g.c.append(g.c[k])
		g.uv.append(g.uv[k])
	for k in range(first_i, ni, 3):
		g.i.append(g.i[k] + off)
		g.i.append(g.i[k + 2] + off)
		g.i.append(g.i[k + 1] + off)
	return self


func group_vertex_count() -> int:
	return _cur.v.size()
