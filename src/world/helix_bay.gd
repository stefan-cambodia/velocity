## HELIX BAY world: a coastal megacity at dusk built around the master circuit.
##
## Districts: the Grand Straight runs along the western sea wall between the
## twin Arcologies; the Seafront and Promenade follow the northern bay; the
## Helix climbs around the 320 m Spire in the city centre; the Skybridge drops
## through the financial district; the Canal Jump crosses the Meridian Canal;
## the Harbour Tunnel runs through the Harbour Arcology megastructure; the
## Dock Hairpin and Container Run sit among cranes and stacked containers.
## Everything is generated here from the track data, so the city always fits
## the circuit.
class_name HelixBay
extends RefCounted

const GROUND_Y := 1.5
## Land outline (x, z), clockwise. West and north of it is the bay.
const LAND := [
	Vector2(-85, 1010), Vector2(-85, -820), Vector2(-40, -1010), Vector2(140, -1160), Vector2(560, -1300),
	Vector2(800, -1440), Vector2(1000, -1580), Vector2(2600, -1580), Vector2(2600, 2600), Vector2(700, 2600), Vector2(700, 1010),
]
const CITY_MIN := Vector2(-85, -1580)
const CITY_MAX := Vector2(1900, 1300)
const BLOCK := 90.0
const STREET := 14.0
const CELL := 450.0

static var rng := RandomNumberGenerator.new()


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 2189
	var t0 := Time.get_ticks_msec()
	_sky(root)
	var canal := _canal_poly(td)
	_land(root, canal)
	_water(root)
	var occ := _occupancy(td)
	var spire_c := _helix_centre(td)
	var reserved: Array[Rect2] = []
	_spire(td, root, spire_c, reserved)
	_arcologies(td, root, reserved)
	_harbour_arcology(td, root)
	_trackside(td, root, spire_c)
	_start_gantry(td, root)
	_docks(td, root, reserved, occ)
	_city(td, root, occ, canal, reserved, spire_c)
	_far(root, spire_c)
	if DevArgs.has("--load-times"):
		print("helix bay world %d ms" % (Time.get_ticks_msec() - t0))


# ------------------------------------------------------------------ environment

static func _sky(root: Node3D) -> void:
	var we: WorldEnvironment = root.get_node("WorldEnvironment") if root.has_node("WorldEnvironment") else null
	if we == null:
		for c in root.get_children():
			if c is WorldEnvironment:
				we = c
	if we == null:
		return
	var env := we.environment
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/sky_dusk.gdshader")
	env.sky.sky_material = sm
	env.sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.ambient_light_energy = 0.9
	env.fog_light_color = Color(0.32, 0.2, 0.32)
	env.fog_density = 0.00055
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	env.tonemap_exposure = 1.05
	for c in root.get_children():
		if c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.rotation = Vector3(deg_to_rad(-9.0), deg_to_rad(-142.0), 0.0)
			sun.light_color = Color(1.0, 0.62, 0.42)
			sun.light_energy = 0.45
			sun.light_color = Color(1.0, 0.58, 0.5)
	# A second, cool fill light from the opposite side (city glow / moonlight).
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(40.0), 0.0)
	fill.light_color = Color(0.45, 0.55, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	root.add_child(fill)


static func _canal_poly(td: TrackData) -> PackedVector2Array:
	# A canal under the Canal Jump, from the north bay to an inland basin.
	var gap_c := Vector3.ZERO
	var n := 0
	for i in td.count:
		if td.flag_at_index(i, TrackData.F_GAP):
			gap_c += td.pos[i]
			n += 1
	gap_c /= maxf(n, 1)
	var c := Vector2(gap_c.x, gap_c.z)
	var a := Vector2(-60, -1060)          # mouth on the north shore
	var dir := (c - a).normalized()
	var b := c + dir * 520.0               # inland basin
	var side := Vector2(-dir.y, dir.x) * 26.0
	return PackedVector2Array([a - side, b - side, b + side * 2.6 - dir * 0.0 + dir * 60.0, b + side, a + side])


static func _land(root: Node3D, canal: PackedVector2Array) -> void:
	var land := PackedVector2Array(LAND)
	var polys := Geometry2D.clip_polygons(land, canal)
	var mk := MeshKit.new()
	for poly: PackedVector2Array in polys:
		if Geometry2D.is_polygon_clockwise(poly) != Geometry2D.is_polygon_clockwise(land):
			continue   # a hole (should not happen: the canal reaches the shore)
		var tris := Geometry2D.triangulate_polygon(poly)
		mk.use("ground")
		var base := mk.group_vertex_count()
		for p in poly:
			mk._vert(Vector3(p.x, GROUND_Y, p.y), Vector3.UP, Color.WHITE, p)
		for t in tris.size() / 3:
			# Godot front faces are clockwise seen from above (+Y).
			mk._tri(base + tris[t * 3], base + tris[t * 3 + 1], base + tris[t * 3 + 2])
		# Quay walls.
		mk.use("concrete")
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var qa := Vector3(a.x, GROUND_Y, a.y)
			var qb := Vector3(b.x, GROUND_Y, b.y)
			var down := Vector3(0, -8, 0)
			mk.quad(qa, qb, qb + down, qa + down, Color(0.5, 0.5, 0.55), Vector2(a.distance_to(b) * 0.25, 2.0), Vector2.ZERO, true)
			# Quay edge lights.
			if k % 1 == 0:
				var len := a.distance_to(b)
				var q := 20.0
				mk.use("lamp")
				while q < len:
					var pp := qa.lerp(qb, q / len) + Vector3(0, 0.6, 0)
					mk.box(pp, Vector3(0.6, 1.2, 0.6), Color.WHITE)
					q += 40.0
				mk.use("concrete")
	var mi := mk.instance("Land", {"ground": Mats.shader_mat("city_ground")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Winding check: if the land was built counter-clockwise it would be culled;
	# the triangulation follows the polygon order, which is clockwise here.


static func _water(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Bay"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	mi.mesh = pm
	mi.position = Vector3(800, 0.0, 0)
	mi.material_override = Mats.shader_mat("water")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ helpers

## Coarse grid of how close the track is (8 m cells): cells within the corridor are blocked.
class Occ:
	var cell: float = 8.0
	var blocked: Dictionary = {}

	func key(x: float, z: float) -> Vector2i:
		return Vector2i(floori(x / cell), floori(z / cell))

	func free_rect(c: Vector2, half: Vector2) -> bool:
		var x := c.x - half.x
		while x <= c.x + half.x:
			var z := c.y - half.y
			while z <= c.y + half.y:
				if blocked.has(key(x, z)):
					return false
				z += cell
			x += cell
		return blocked.has(key(c.x + half.x, c.y + half.y)) == false


static func _occupancy(td: TrackData) -> Occ:
	var o := Occ.new()
	var i := 0
	while i < td.count:
		var p := td.pos[i]
		var r := maxf(td.half_l[i], td.half_r[i]) + 26.0
		var cx := floori(p.x / o.cell)
		var cz := floori(p.z / o.cell)
		var n := int(ceil(r / o.cell))
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				if (dx * dx + dz * dz) * o.cell * o.cell <= r * r:
					o.blocked[Vector2i(cx + dx, cz + dz)] = true
		i += 4
	return o


static func _helix_centre(td: TrackData) -> Vector3:
	for sc: Dictionary in td.sections:
		if sc["name"] == "The Helix":
			var c := Vector3.ZERO
			var n := 0
			var i0 := int(float(sc["s0"]) / td.step)
			var i1 := int(float(sc["s1"]) / td.step)
			# Average over the full 360 degrees in the middle of the spiral.
			for i in range(i0 + (i1 - i0) / 10, i1 - (i1 - i0) / 10):
				c += td.pos[i]
				n += 1
			c /= maxf(n, 1)
			return Vector3(c.x, GROUND_Y, c.z)
	return Vector3(1100, GROUND_Y, -1300)


static func _in_land(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, PackedVector2Array(LAND))


## Vertical prism (n sides) with facade UVs in metres. `col.a` = window style.
static func prism(mk: MeshKit, base: Vector3, r: float, sides: int, h: float, col: Color, r_top: float = -1.0, rot: float = 0.0, cap: bool = true) -> void:
	var rt := r if r_top < 0.0 else r_top
	var side_len := 2.0 * r * sin(PI / sides)
	for k in sides:
		var a0 := rot + TAU * k / sides
		var a1 := rot + TAU * (k + 1) / sides
		var b0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var b1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var t0 := base + Vector3(cos(a0) * rt, h, sin(a0) * rt)
		var t1 := base + Vector3(cos(a1) * rt, h, sin(a1) * rt)
		var u0 := k * side_len
		# Clockwise from outside: t0, t1, b1, b0 viewed from outside... normals computed by quad().
		var i0 := mk.group_vertex_count()
		var nn := ((b1 - b0).cross(t0 - b0)).normalized()
		if nn.dot((b0 + b1) * 0.5 - base) < 0.0:
			nn = -nn
		mk._vert(t1, nn, col, Vector2(u0 + side_len, 0))
		mk._vert(t0, nn, col, Vector2(u0, 0))
		mk._vert(b0, nn, col * 0.85 if col.a > 0.0 else col, Vector2(u0, h))
		mk._vert(b1, nn, col * 0.85 if col.a > 0.0 else col, Vector2(u0 + side_len, h))
		mk._quad_i(i0, i0 + 1, i0 + 2, i0 + 3)
	if cap:
		var top := base + Vector3(0, h, 0)
		var ci := mk._vert(top, Vector3.UP, Color(col.r, col.g, col.b, 0.0), Vector2.ZERO)
		var first := mk.group_vertex_count()
		for k in sides:
			var a := rot + TAU * k / sides
			mk._vert(top + Vector3(cos(a) * rt, 0, sin(a) * rt), Vector3.UP, Color(col.r, col.g, col.b, 0.0), Vector2.ZERO)
		for k in sides:
			mk._tri(ci, first + k, first + (k + 1) % sides)


## Box standing on `base` (centre of its footprint), rotated about Y.
static func block(mk: MeshKit, base: Vector3, size: Vector3, col: Color, rot: float = 0.0) -> void:
	mk.box_t(Transform3D(Basis(Vector3.UP, rot), base + Vector3(0, size.y * 0.5, 0)), size, col)


# ------------------------------------------------------------------ landmarks

static func _spire(td: TrackData, root: Node3D, c: Vector3, reserved: Array[Rect2]) -> void:
	var mk := MeshKit.new()
	mk.use("spire_glass")
	var tint := Color(0.45, 0.55, 0.7, 0.5)
	# Plinth, core, upper shaft, crown.
	prism(mk, c, 46.0, 8, 22.0, Color(0.3, 0.3, 0.33, 0.0), 40.0, PI / 8.0)
	prism(mk, c + Vector3(0, 22, 0), 30.0, 8, 170.0, tint, 26.0, PI / 8.0)
	prism(mk, c + Vector3(0, 192, 0), 26.0, 8, 90.0, tint, 15.0, PI / 8.0)
	prism(mk, c + Vector3(0, 282, 0), 15.0, 8, 26.0, Color(0.12, 0.12, 0.15, 0.0), 2.0, PI / 8.0)
	mk.use("metal_dark")
	mk.cyl(c + Vector3(0, 300, 0), c + Vector3(0, 345, 0), 1.2, 0.3, 6, Color.WHITE)
	# Neon: vertical edge strips and rings.
	mk.use("neon_cyan")
	for k in 8:
		var a := PI / 8.0 + TAU * k / 8.0
		var p0 := c + Vector3(cos(a) * 30.4, 24, sin(a) * 30.4)
		var p1 := c + Vector3(cos(a) * 26.3, 190, sin(a) * 26.3)
		mk.beam(p0, p1, 1.1, 1.1, Color.WHITE)
	mk.use("neon_magenta")
	for y: float in [60.0, 120.0, 192.0, 282.0]:
		var rr := lerpf(30.0, 15.0, (y - 22.0) / 270.0) + 0.6
		mk.torus(c + Vector3(0, y, 0), Vector3.UP, rr, 0.6, 32, 4, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(c + Vector3(0, 346, 0), Vector3(1.2, 1.2, 1.2), 4, 6, Color.WHITE)
	# Radial arms carrying the Helix ramp: from the core to the deck underside.
	mk.use("concrete")
	var i := 0
	while i < td.count:
		var p := td.pos[i]
		var flat := Vector2(p.x - c.x, p.z - c.z)
		if flat.length() < 150.0 and p.y > 14.0:
			var under := p - td.nrm[i] * (TrackMesh.DECK + 0.2)
			var dir := Vector3(flat.x, 0, flat.y).normalized()
			var core := c + dir * 27.0 + Vector3(0, under.y - GROUND_Y - 1.0, 0)
			var outer := under + dir * (td.half_r[i] * 0.6)
			mk.beam(core, outer, 3.0, 2.2, Color(0.75, 0.75, 0.8))
			# A strut down to the ground for the lowest arms.
			if under.y < 30.0:
				mk.box(Vector3(under.x, (under.y + GROUND_Y) * 0.5, under.z), Vector3(2.4, under.y - GROUND_Y, 2.4), Color(0.7, 0.7, 0.75), 0.6, 0.25)
		i += 34
	var mi := mk.instance("Spire", {"spire_glass": Mats.shader_mat("building", {"lit_fraction": 0.62, "window_energy": 2.2, "cool": Color(0.45, 0.85, 1.0), "warm": Color(0.6, 0.9, 1.0), "bay_w": 1.4, "floor_h": 4.2, "windows_tex": Mats.tex("windows")})})
	root.add_child(mi)
	reserved.append(Rect2(c.x - 170, c.z - 170, 340, 340))


static func _arcologies(td: TrackData, root: Node3D, reserved: Array[Rect2]) -> void:
	# Twin stepped arcologies east of the Grand Straight.
	var mk := MeshKit.new()
	for z: float in [-180.0, -560.0]:
		var base := Vector3(205, GROUND_Y, z)
		var w := 150.0
		var y := 0.0
		var tiers := 7
		for t in tiers:
			var h := 16.0
			var s := w * (1.0 - t * 0.11)
			mk.use("bld_dense")
			block(mk, base + Vector3(0, y, 0), Vector3(s, h, s * 0.75), Color(0.28, 0.27, 0.26, 1.0))
			# Terrace edge neon.
			mk.use("neon_amber" if t % 2 == 0 else "neon_cyan")
			mk.box(base + Vector3(0, y + h + 0.3, s * 0.375), Vector3(s, 0.5, 0.5), Color.WHITE)
			mk.box(base + Vector3(-s * 0.5, y + h + 0.3, 0), Vector3(0.5, 0.5, s * 0.75), Color.WHITE)
			y += h
		# Crown mast.
		mk.use("metal_dark")
		mk.cyl(base + Vector3(0, y, 0), base + Vector3(0, y + 40, 0), 2.0, 0.4, 6, Color.WHITE)
		mk.use("warn_red")
		mk.sphere(base + Vector3(0, y + 41, 0), Vector3(1, 1, 1), 4, 6, Color.WHITE)
		reserved.append(Rect2(base.x - 90, z - 70, 180, 140))
	root.add_child(mk.instance("Arcologies"))


static func _harbour_arcology(td: TrackData, root: Node3D) -> void:
	# The tunnel interior (arched roof with strobing light bars) and the
	# megastructure around it.
	var inner := MeshKit.new()
	var outer := MeshKit.new()
	var prev := PackedVector3Array()
	var i := 0
	var in_tunnel_len := 0
	while i <= td.count:
		var j := td.wrap_i(i)
		var tun := td.flag_at_index(j, TrackData.F_TUNNEL)
		if tun:
			var ceil_h := td.ceiling[j]
			var sec := PackedVector3Array()
			var hl := td.half_l[j] + TrackMesh.WALL_T
			var hr := td.half_r[j] + TrackMesh.WALL_T
			var y0 := TrackMesh.WALL_H + 0.18
			for k in 9:
				var a := PI * k / 8.0
				var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
				var hh := y0 + sin(a) * (ceil_h - y0)
				sec.append(td.pos[j] + td.rgt[j] * d + td.nrm[j] * hh)
			if prev.size() > 0:
				inner.use("tunnel")
				var pair: Array[PackedVector3Array] = [prev, sec]
				inner.loft(pair, Color(0.55, 0.55, 0.6), false, false)
			prev = sec
			if in_tunnel_len % 8 == 0:
				# Light bar across the roof.
				inner.use("neon_white")
				var top := td.pos[j] + td.nrm[j] * (ceil_h - 0.15)
				inner.box_t(Transform3D(Basis(td.rgt[j], td.nrm[j], -td.tan[j]), top), Vector3((hl + hr) * 0.55, 0.18, 1.1), Color.WHITE)
				# Amber side lamps between the bars.
				inner.use("neon_amber")
				for side: float in [-1.0, 1.0]:
					var a := PI * (0.18 if side > 0.0 else 0.82)
					var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
					var hh := y0 + sin(a) * (ceil_h - y0) - 0.12
					var lp := td.pos[j] + td.rgt[j] * d + td.nrm[j] * hh
					inner.box_t(Transform3D(Basis(td.rgt[j], td.nrm[j], -td.tan[j]), lp), Vector3(0.6, 0.1, 0.6), Color.WHITE)
			# Side wall strips inside the tube (cyan, continuous).
			if in_tunnel_len % 2 == 0:
				inner.use("neon_cyan")
				for side: float in [-1.0, 1.0]:
					var edge := (td.half_r[j] + TrackMesh.WALL_T - 0.45) if side > 0.0 else -(td.half_l[j] + TrackMesh.WALL_T - 0.45)
					var pp := td.pos[j] + td.rgt[j] * edge + td.nrm[j] * (TrackMesh.WALL_H + 1.6)
					inner.box_t(Transform3D(Basis(td.rgt[j], td.nrm[j], -td.tan[j]), pp), Vector3(0.12, 0.12, 2.1), Color.WHITE)
			if in_tunnel_len % 30 == 0:
				# Megastructure around the tube: two wings beside it and a roof
				# above it, never crossing the tube itself.
				var basis := Basis(td.rgt[j], Vector3.UP, -Vector3(td.tan[j].x, 0, td.tan[j].z).normalized())
				var hgt := 38.0 + 10.0 * sin(i * 0.013)
				var wing := 22.0
				var roof0 := td.pos[j].y + ceil_h + 1.2
				outer.use("bld")
				for side: float in [-1.0, 1.0]:
					var off := (hr + 1.2 + wing * 0.5) if side > 0.0 else -(hl + 1.2 + wing * 0.5)
					var cpos := td.pos[j] + td.rgt[j] * off
					outer.box_t(Transform3D(basis, Vector3(cpos.x, GROUND_Y + hgt * 0.5, cpos.z)), Vector3(wing, hgt, 31.0), Color(0.22, 0.23, 0.26, 0.5))
				var top_y := GROUND_Y + hgt
				if top_y > roof0 + 2.0:
					outer.box_t(Transform3D(basis, Vector3(td.pos[j].x, (roof0 + top_y) * 0.5, td.pos[j].z)), Vector3(hl + hr + 2.4, top_y - roof0, 31.0), Color(0.2, 0.21, 0.24, 0.5))
				outer.use("neon_cyan")
				outer.box_t(Transform3D(basis, Vector3(td.pos[j].x, top_y + 0.4, td.pos[j].z)), Vector3(hl + hr + wing * 2.0, 0.6, 1.0), Color.WHITE)
			in_tunnel_len += 1
		else:
			prev = PackedVector3Array()
			in_tunnel_len = 0
		i += 1
	var mi := inner.instance("TunnelInner", {"tunnel": _tunnel_mat()})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.add_child(outer.instance("HarbourArcology"))


static func _tunnel_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.8, 0.82, 0.9)
	m.albedo_texture = Mats.tex("panel_albedo")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.roughness = 0.35
	m.metallic = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ------------------------------------------------------------------ trackside

static func _trackside(td: TrackData, root: Node3D, spire_c: Vector3) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	var i := 0
	while i < td.count:
		var s := i * td.step
		var p := td.pos[i]
		var key := int(s / 400.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var near_spire := Vector2(p.x - spire_c.x, p.z - spire_c.z).length() < 150.0 and p.y > 14.0
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 6, TrackData.F_GAP) or td.flag_at_index(i - 6, TrackData.F_GAP)
		# Pylons every 48 m under the deck.
		if i % 48 == 0 and not tunnel and not near_spire and not gap:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := GROUND_Y if _in_land(Vector2(p.x, p.z)) else -2.0
			if under.y - foot > 2.5:
				mk.use("concrete")
				var hgt := under.y - foot
				mk.box(Vector3(under.x, foot + hgt * 0.5, under.z), Vector3(3.2, hgt, 3.2), Color(0.75, 0.75, 0.8), 0.55, 0.25)
				mk.box_t(Transform3D(Basis(td.rgt[i], td.nrm[i], -td.tan[i]), under - td.nrm[i] * 0.6), Vector3((td.half_l[i] + td.half_r[i]) * 0.8, 1.2, 3.6), Color(0.7, 0.7, 0.75))
		# Light gates.
		if s - last_gate > 170.0 and s > 120.0 and not tunnel and not near_spire and not gap and td.ceiling[i] <= 0.0:
			last_gate = s
			_gate(mk, td, i, int(s / 170.0))
		i += 1
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if mk.is_empty():
			continue
		var mi := mk.instance("Trackside%02d" % key)
		root.add_child(mi)


static func _gate(mk: MeshKit, td: TrackData, i: int, n: int) -> void:
	var b := Basis(td.rgt[i], td.nrm[i], -td.tan[i])
	var o := td.pos[i]
	var hl := td.half_l[i] + 1.8
	var hr := td.half_r[i] + 1.8
	var h := 10.5
	var xf := Transform3D(b, o)
	mk.use("metal_dark")
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3(-hl, h * 0.5, 0)), Vector3(1.0, h, 1.4), Color.WHITE)
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3(hr, h * 0.5, 0)), Vector3(1.0, h, 1.4), Color.WHITE)
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3((hr - hl) * 0.5, h, 0)), Vector3(hl + hr + 1.0, 1.4, 1.8), Color.WHITE)
	mk.use("neon_cyan" if n % 3 != 2 else "neon_magenta")
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3((hr - hl) * 0.5, h - 0.8, 0)), Vector3(hl + hr - 1.0, 0.18, 0.4), Color.WHITE)
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3(-hl + 0.55, h * 0.5, 0)), Vector3(0.15, h - 2.0, 0.4), Color.WHITE)
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3(hr - 0.55, h * 0.5, 0)), Vector3(0.15, h - 2.0, 0.4), Color.WHITE)
	# Every other gate carries a team board facing the oncoming ships.
	if n % 2 == 0:
		var ids := Catalog.team_ids()
		var tid: String = ids[(n / 2) % ids.size()]
		var mid := o + td.rgt[i] * ((hr - hl) * 0.5) + td.nrm[i] * (h + 0.75) - td.tan[i] * 0.95
		mk.use("metal_dark")
		mk.box_t(Transform3D(b, mid + td.nrm[i] * 2.6 + td.tan[i] * 0.06), Vector3(11.6, 5.6, 0.08), Color(0.25, 0.25, 0.3))
		mk.use("logo_" + tid)
		mk.card(mid, td.rgt[i] * 11.0, td.nrm[i] * 5.5, Color.WHITE, Vector2(0, 1), Vector2(1, 0), false)


static func _start_gantry(td: TrackData, root: Node3D, label: String = "HELIX BAY  /  VELOCITY LEAGUE") -> void:
	var mk := MeshKit.new()
	var i := td.wrap_i(int(8.0 / td.step))
	var b := Basis(td.rgt[i], td.nrm[i], -td.tan[i])
	var xf := Transform3D(b, td.pos[i])
	var hl := td.half_l[i] + 3.0
	var hr := td.half_r[i] + 3.0
	var h := 15.0
	mk.use("metal_dark")
	for x: float in [-hl, hr]:
		mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3(x, h * 0.5, 0)), Vector3(2.4, h, 3.0), Color.WHITE)
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3((hr - hl) * 0.5, h + 1.5, 0)), Vector3(hl + hr + 2.4, 4.0, 3.2), Color.WHITE)
	mk.use("neon_white")
	mk.box_t(xf * Transform3D(Basis.IDENTITY, Vector3((hr - hl) * 0.5, h - 0.6, 1.62)), Vector3(hl + hr - 2.0, 0.25, 0.1), Color.WHITE)
	# Chequered start line across the surface.
	mk.use("neon_white")
	for k in 16:
		var d := lerpf(-td.half_l[0] + 1.0, td.half_r[0] - 1.0, (k + 0.5) / 16.0)
		var size := (td.half_l[0] + td.half_r[0] - 2.0) / 16.0
		var row := Transform3D(Basis(td.rgt[0], td.nrm[0], -td.tan[0]), td.pos[0] + td.rgt[0] * d + td.nrm[0] * 0.035)
		mk.box_t(row * Transform3D(Basis.IDENTITY, Vector3(0, 0, (k % 2) * size * 0.5 - size * 0.25)), Vector3(size * 0.96, 0.02, size * 0.48), Color.WHITE)
	root.add_child(mk.instance("StartGantry"))
	# Start lights: five lamps facing the grid, recoloured by the race.
	var lights: Array = []
	for k in 5:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.75
		sm.height = 1.5
		sm.radial_segments = 12
		sm.rings = 6
		lamp.mesh = sm
		var mat := Mats.glow(Color(0.15, 0.02, 0.02), 1.0)
		lamp.material_override = mat
		lamp.transform = xf * Transform3D(Basis.IDENTITY, Vector3((hr - hl) * 0.5 + (k - 2) * 2.4, h + 0.55, 1.75))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(lamp)
		lights.append(lamp)
	root.set_meta("start_lights", lights)
	var lbl := Label3D.new()
	lbl.text = label
	lbl.font = load("res://assets/fonts/Orbitron.ttf")
	lbl.font_size = 96
	lbl.pixel_size = 0.02
	lbl.modulate = Color(0.85, 0.95, 1.0)
	lbl.outline_size = 0
	lbl.shaded = false
	lbl.pixel_size = 0.016
	lbl.transform = xf * Transform3D(Basis.IDENTITY, Vector3((hr - hl) * 0.5, h + 2.45, 1.7))
	root.add_child(lbl)


# ------------------------------------------------------------------ docks

static func _docks(td: TrackData, root: Node3D, reserved: Array[Rect2], occ: Occ) -> void:
	var mk := MeshKit.new()
	# Ship-to-shore cranes along the western quay south of the Bay Curve.
	for k in 4:
		var z := 430.0 + k * 130.0
		var x := -50.0
		mk.use("paint_yellow")
		for dz: float in [-9.0, 9.0]:
			for dx: float in [-10.0, 10.0]:
				mk.box(Vector3(x + dx, GROUND_Y + 25.0, z + dz), Vector3(1.6, 50.0, 1.6), Color.WHITE)
		mk.box(Vector3(x - 30.0, GROUND_Y + 52.0, z), Vector3(110.0, 4.0, 22.0), Color.WHITE)
		mk.box(Vector3(x + 8.0, GROUND_Y + 60.0, z), Vector3(18.0, 12.0, 14.0), Color(0.9, 0.9, 0.9))
		mk.use("warn_red")
		mk.sphere(Vector3(x - 84.0, GROUND_Y + 55.0, z), Vector3(0.8, 0.8, 0.8), 4, 6, Color.WHITE)
		mk.use("lamp")
		mk.box(Vector3(x - 30.0, GROUND_Y + 49.8, z), Vector3(100.0, 0.3, 0.6), Color.WHITE)
	# Container stacks between the Container Run and the Dock Rise.
	var cols := [Color(0.75, 0.2, 0.12), Color(0.1, 0.35, 0.6), Color(0.85, 0.55, 0.1), Color(0.2, 0.5, 0.3), Color(0.6, 0.6, 0.62), Color(0.5, 0.1, 0.4)]
	mk.use("container")
	for gx in 4:
		for gz in 10:
			var base := Vector3(300.0 + gx * 14.0, GROUND_Y, 380.0 + gz * 7.0 * 4.0)
			if not _in_land(Vector2(base.x, base.z)) or not occ.free_rect(Vector2(base.x, base.z), Vector2(7.0, 3.0)):
				continue
			var stack := rng.randi_range(1, 4)
			for s in stack:
				var c: Color = cols[rng.randi() % cols.size()]
				mk.box(base + Vector3(0, 1.3 + s * 2.6, 0), Vector3(12.0, 2.5, 2.4 * 2.0), c, 0.7)
	# A moored container ship in the harbour west of the cranes.
	var hull := Vector3(-135.0, 0.0, 600.0)
	mk.use("metal_dark")
	mk.box(hull + Vector3(0, 6, 0), Vector3(34.0, 14.0, 230.0), Color(0.4, 0.12, 0.1), 0.6)
	mk.box(hull + Vector3(0, 20, 95.0), Vector3(28.0, 16.0, 20.0), Color(0.85, 0.85, 0.88))
	mk.use("lamp")
	mk.box(hull + Vector3(0, 28.2, 95.0), Vector3(28.4, 0.4, 20.4), Color.WHITE)
	mk.use("container")
	for k in 16:
		for row in 3:
			mk.box(hull + Vector3(-10.0 + row * 10.0, 14.5 + 1.3, -90.0 + k * 11.0), Vector3(9.0, 2.6, 10.0), cols[(k * 3 + row) % cols.size()], 0.7)
	root.add_child(mk.instance("Docks"))
	reserved.append(Rect2(200, 360, 260, 380))


# ------------------------------------------------------------------ city

static func _city(td: TrackData, root: Node3D, occ: Occ, canal: PackedVector2Array, reserved: Array[Rect2], spire_c: Vector3) -> void:
	var cells: Dictionary = {}
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.0022
	var density: float = Quality.p.get("city", 1.0)
	var bx := CITY_MIN.x + BLOCK * 0.5
	while bx < CITY_MAX.x:
		var bz := CITY_MIN.y + BLOCK * 0.5
		while bz < CITY_MAX.y:
			var lot := BLOCK - STREET
			# Split each block into 1, 2 or 4 parcels.
			var split := rng.randi_range(0, 2)
			var parcels: Array = []
			match split:
				0: parcels = [[Vector2(bx, bz), Vector2(lot, lot)]]
				1: parcels = [[Vector2(bx - lot * 0.25, bz), Vector2(lot * 0.5, lot)], [Vector2(bx + lot * 0.25, bz), Vector2(lot * 0.5, lot)]]
				_: parcels = [[Vector2(bx - lot * 0.25, bz - lot * 0.25), Vector2(lot * 0.5, lot * 0.5)], [Vector2(bx + lot * 0.25, bz - lot * 0.25), Vector2(lot * 0.5, lot * 0.5)],
					[Vector2(bx - lot * 0.25, bz + lot * 0.25), Vector2(lot * 0.5, lot * 0.5)], [Vector2(bx + lot * 0.25, bz + lot * 0.25), Vector2(lot * 0.5, lot * 0.5)]]
			for pc: Array in parcels:
				var c: Vector2 = pc[0]
				var sz: Vector2 = pc[1] * rng.randf_range(0.62, 0.9)
				if rng.randf() > density:
					continue
				if not _clear(c, sz * 0.5, occ, canal, reserved):
					continue
				var dc := Vector2(c.x - spire_c.x, c.y - spire_c.z).length()
				var core := exp(-dc / 650.0)
				var n := noise.get_noise_2d(c.x, c.y) * 0.5 + 0.5
				var coast := clampf((c.x + 85.0) / 300.0, 0.25, 1.0)
				var h := (14.0 + 30.0 * n + 170.0 * core * (0.4 + n)) * coast
				h *= rng.randf_range(0.7, 1.25)
				var key := Vector2i(floori(c.x / CELL), floori(c.y / CELL))
				if not cells.has(key):
					cells[key] = MeshKit.new()
				_tower(cells[key], Vector3(c.x, GROUND_Y, c.y), sz, h)
			bz += BLOCK
		bx += BLOCK
	var view: float = Quality.p.get("view", 1.0)
	for key: Vector2i in cells:
		var mk: MeshKit = cells[key]
		var mi := mk.instance("City_%d_%d" % [key.x, key.y])
		mi.visibility_range_end = 1900.0 * view
		mi.visibility_range_end_margin = 200.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(mi)


static func _clear(c: Vector2, half: Vector2, occ: Occ, canal: PackedVector2Array, reserved: Array[Rect2]) -> bool:
	for corner: Vector2 in [c, c + half, c - half, c + Vector2(half.x, -half.y), c + Vector2(-half.x, half.y)]:
		if not _in_land(corner) or Geometry2D.is_point_in_polygon(corner, canal):
			return false
	for r in reserved:
		if r.intersects(Rect2(c - half, half * 2.0)):
			return false
	return occ.free_rect(c, half)


const TINTS := [Color(0.3, 0.31, 0.34), Color(0.12, 0.14, 0.18), Color(0.42, 0.38, 0.33), Color(0.55, 0.56, 0.6), Color(0.2, 0.22, 0.28), Color(0.33, 0.24, 0.2)]


static func _tower(mk: MeshKit, base: Vector3, sz: Vector2, h: float) -> void:
	var tint: Color = TINTS[rng.randi() % TINTS.size()]
	# Window style band + a per-building offset into the window pattern (see building.gdshader).
	var style := (0.5 if rng.randf() < 0.6 else 0.75) + rng.randf() * 0.22
	var col := Color(tint.r, tint.g, tint.b, style)
	var plain := Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.8, 0.0)
	var rot := 0.0 if rng.randf() < 0.75 else rng.randf_range(-0.4, 0.4)
	var neon: String = ["neon_cyan", "neon_magenta", "neon_amber", "neon_white"][rng.randi() % 4]
	var kind := rng.randi() % 6
	if h < 30.0:
		kind = 0
	mk.use("bld")
	match kind:
		0, 1:
			# Slab with podium and crown band.
			block(mk, base, Vector3(sz.x, 7.0, sz.y), plain, rot)
			var w := sz * rng.randf_range(0.6, 0.85)
			block(mk, base + Vector3(0, 7.0, 0), Vector3(w.x, h - 7.0, w.y), col, rot)
			mk.use(neon)
			block(mk, base + Vector3(0, h - 3.0, 0), Vector3(w.x + 0.3, 0.6, w.y + 0.3), Color.WHITE, rot)
			if kind == 1 and h > 50.0:
				# Cantilevered upper block.
				mk.use("bld")
				block(mk, base + Vector3(w.x * 0.2, h * 0.72, 0), Vector3(w.x * 1.25, h * 0.18, w.y * 0.9), col, rot)
		2:
			# Setbacks.
			var w := sz
			var y := 0.0
			var tiers := rng.randi_range(2, 4)
			for t in tiers:
				var th := h / tiers
				block(mk, base + Vector3(0, y, 0), Vector3(w.x, th, w.y), col, rot)
				mk.use(neon)
				block(mk, base + Vector3(0, y + th - 0.4, 0), Vector3(w.x + 0.3, 0.5, w.y + 0.3), Color.WHITE, rot)
				mk.use("bld")
				y += th
				w *= 0.74
		3:
			# Octagonal spire with a tapered top.
			var r := minf(sz.x, sz.y) * 0.45
			prism(mk, base, r * 1.15, 8, 6.0, plain, r * 1.15, PI / 8.0)
			prism(mk, base + Vector3(0, 6, 0), r, 8, h * 0.82, col, r * 0.85, PI / 8.0)
			prism(mk, base + Vector3(0, 6 + h * 0.82, 0), r * 0.85, 8, h * 0.18, Color(tint.r, tint.g, tint.b, 0.0), r * 0.2, PI / 8.0)
			mk.use(neon)
			mk.torus(base + Vector3(0, 6 + h * 0.82, 0), Vector3.UP, r * 0.88, 0.35, 16, 3, Color.WHITE)
		4:
			# Round tower with fins.
			var r := minf(sz.x, sz.y) * 0.42
			prism(mk, base, r, 14, h, col)
			mk.use("metal_dark")
			for k in 4:
				var a := TAU * k / 4.0 + 0.3
				mk.box(base + Vector3(cos(a) * r, h * 0.5, sin(a) * r), Vector3(1.2, h * 0.95, 1.2), Color.WHITE)
			mk.use(neon)
			mk.torus(base + Vector3(0, h + 0.2, 0), Vector3.UP, r, 0.4, 20, 3, Color.WHITE)
		5:
			# Twin towers with a sky bridge.
			var w := Vector2(sz.x * 0.38, sz.y * 0.8)
			var off := sz.x * 0.3
			var h2 := h * rng.randf_range(0.75, 1.0)
			block(mk, base + Vector3(-off, 0, 0), Vector3(w.x, h, w.y), col)
			block(mk, base + Vector3(off, 0, 0), Vector3(w.x, h2, w.y), col)
			mk.use("bld")
			block(mk, base + Vector3(0, h2 * 0.6, 0), Vector3(off * 2.0, 5.0, w.y * 0.4), Color(0.1, 0.12, 0.15, 0.5))
			mk.use(neon)
			block(mk, base + Vector3(0, h2 * 0.6 - 0.4, 0), Vector3(off * 2.0, 0.4, w.y * 0.42), Color.WHITE)
	# Roof clutter and warning lights on tall towers.
	if h > 60.0:
		mk.use("metal_dark")
		mk.cyl(base + Vector3(0, h, 0), base + Vector3(0, h + h * 0.12, 0), 0.6, 0.15, 5, Color.WHITE)
		mk.use("warn_red")
		mk.box(base + Vector3(0, h + h * 0.12 + 0.4, 0), Vector3(0.9, 0.9, 0.9), Color.WHITE)
	mk.use("bld")


# ------------------------------------------------------------------ far scenery

static func _far(root: Node3D, c: Vector3) -> void:
	var mk := MeshKit.new()
	# A distant skyline across the bay (west) and north shore.
	mk.use("bld")
	for k in 140:
		var a := rng.randf_range(0.0, 1.0)
		var x: float
		var z: float
		if k < 80:
			x = rng.randf_range(-3200.0, -2200.0)
			z = lerpf(-3000.0, 2500.0, a)
		else:
			x = lerpf(-2500.0, 2500.0, a)
			z = rng.randf_range(-3600.0, -2900.0)
		var h := rng.randf_range(30.0, 220.0) * (1.0 if rng.randf() < 0.7 else 0.4)
		var w := rng.randf_range(30.0, 80.0)
		block(mk, Vector3(x, 0.0, z), Vector3(w, h, w), Color(0.18, 0.19, 0.24, 0.5))
	# Mountains to the east and south-east, layered for depth.
	mk.use("rock")
	for layer in 2:
		var r := 5200.0 + layer * 1400.0
		var pts := 46
		for k in pts:
			var a0 := lerpf(-1.9, 1.2, float(k) / pts)
			var a1 := lerpf(-1.9, 1.2, float(k + 1) / pts)
			var hgt0 := 420.0 + 380.0 * absf(sin(k * 1.7 + layer)) + 200.0 * sin(k * 0.6)
			var hgt1 := 420.0 + 380.0 * absf(sin((k + 1) * 1.7 + layer)) + 200.0 * sin((k + 1) * 0.6)
			var p0 := c + Vector3(cos(a0) * r, -20.0, sin(a0) * r)
			var p1 := c + Vector3(cos(a1) * r, -20.0, sin(a1) * r)
			var t0 := p0 + Vector3(0, hgt0, 0) - (p0 - c).normalized() * 300.0
			var t1 := p1 + Vector3(0, hgt1, 0) - (p1 - c).normalized() * 300.0
			mk.quad(t0, t1, p1, p0, Color(0.7 - layer * 0.15, 0.7 - layer * 0.15, 0.8 - layer * 0.15), Vector2.ONE, Vector2.ZERO, true)
	var mi := mk.instance("Far")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
