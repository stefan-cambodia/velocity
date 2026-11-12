## LAGRANGE STATION world: an orbital racing station in low orbit.
##
## No terrain and no fog. The planet, its atmosphere and the moon are drawn
## by the sky shader (sky_space: ray-cast sphere, baked surface fields), so
## they sit at infinity under the whole circuit. The deck rides on a truss keel. Girder portals span the
## Truss Run, and solar wings fan out from it and from the Array Sweep. The
## station core stands inside the Hub Spiral, glowing rings mark The
## Corkscrew (the track rolls a full 360 degrees), and the Habitat Ring is a
## lit tube with garden terraces and trees. The Docking Bay is a wide arched
## hangar with freighters parked on side decks, and a wheel habitat turns
## slowly off the circuit.
class_name Orbital
extends RefCounted

const SUN_DIR := Vector3(0.55, 0.35, -0.75)

static var rng := RandomNumberGenerator.new()


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 2031
	var t0 := Time.get_ticks_msec()
	_environment(root)
	var lo := td.pos[0]
	var hi := td.pos[0]
	for i in range(0, td.count, 10):
		lo = lo.min(td.pos[i])
		hi = hi.max(td.pos[i])
	_keel(td, root)
	_truss_portals(td, root)
	_corkscrew_rings(td, root)
	_hub(td, root)
	_habitat(td, root)
	_docking_bay(td, root)
	_solar_wings(td, root)
	_wheel(root, lo, hi)
	_gates(td, root)
	HelixBay._start_gantry(td, root, "LAGRANGE STATION  /  VELOCITY LEAGUE")
	if DevArgs.has("--load-times"):
		print("orbital world %d ms" % (Time.get_ticks_msec() - t0))


static func _environment(root: Node3D) -> void:
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			var sm := ShaderMaterial.new()
			sm.shader = load("res://assets/shaders/sky_space.gdshader")
			sm.set_shader_parameter("sun_dir", SUN_DIR.normalized())
			sm.set_shader_parameter("cap_tex", Mats.tex("planet_cap"))
			env.sky.sky_material = sm
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.22, 0.25, 0.32)
			env.ambient_light_energy = 1.0
			env.fog_enabled = false
			env.tonemap_exposure = 0.95
			env.glow_hdr_threshold = 1.1
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.transform = Transform3D(Basis.looking_at(-SUN_DIR.normalized(), Vector3.UP), Vector3.ZERO)
			sun.light_color = Color(1.0, 0.98, 0.94)
			sun.light_energy = 1.9
	# Planet-shine from below: soft blue fill.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(80.0), 0.0, 0.0)
	fill.light_color = Color(0.35, 0.55, 0.9)
	fill.light_energy = 0.35
	root.add_child(fill)


## A truss keel under the deck: frames every 24 samples, chords and diagonals.
static func _keel(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var prev: Array = []
	for i in range(0, td.count, 24):
		var key := int(i * td.step / 500.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		if td.flag_at_index(i, TrackData.F_TUNNEL):
			prev = []
			continue
		var b := td.rgt[i]
		var n := td.nrm[i]
		var top := td.pos[i] - n * TrackMesh.DECK
		var w := minf(td.half_l[i], td.half_r[i]) * 0.7
		var depth := 5.0
		var pts := [top - b * w, top + b * w, top - b * w * 0.5 - n * depth, top + b * w * 0.5 - n * depth]
		mk.use("metal")
		mk.beam(pts[0], pts[2], 0.45, 0.45, Color.WHITE, td.tan[i])
		mk.beam(pts[1], pts[3], 0.45, 0.45, Color.WHITE, td.tan[i])
		mk.beam(pts[2], pts[3], 0.45, 0.45, Color.WHITE, td.tan[i])
		if not prev.is_empty():
			for k in 4:
				mk.beam(prev[k], pts[k], 0.35, 0.35, Color.WHITE, n)
			mk.beam(prev[2], pts[3], 0.25, 0.25, Color.WHITE, n)
		# Navigation lights on the keel, red and white alternating.
		if i % 48 == 0:
			mk.use("warn_red" if (i / 48) % 2 == 0 else "nav_white")
			mk.box((pts[2] + pts[3]) * 0.5 - n * 0.4, Vector3(0.5, 0.5, 0.5), Color.WHITE)
		prev = pts
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Keel%02d" % key))


static func _section(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


## Girder portals over the Truss Run: the deck threads a lattice bridge, and the
## frames flicking past overhead sell the speed.
static func _truss_portals(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Truss Run")
	if r.x < 0.0:
		return
	var mk := MeshKit.new()
	var prev: Array = []
	var s := r.x + 20.0
	var k := 0
	while s < r.y - 20.0:
		var hit := TrackData.Hit.new()
		td.frame_at(s, hit)
		var xl := -(hit.half_l + TrackMesh.WALL_T + 1.2)
		var xr := hit.half_r + TrackMesh.WALL_T + 1.2
		var h := 10.5
		var fl := hit.c + hit.B * xl - hit.N * TrackMesh.DECK
		var fr := hit.c + hit.B * xr - hit.N * TrackMesh.DECK
		var tl := hit.c + hit.B * xl + hit.N * h
		var tr := hit.c + hit.B * xr + hit.N * h
		mk.use("metal")
		mk.beam(fl, tl, 0.9, 0.9, Color.WHITE, hit.T)
		mk.beam(fr, tr, 0.9, 0.9, Color.WHITE, hit.T)
		mk.beam(tl, tr, 1.1, 1.1, Color.WHITE, hit.N)
		# Knee braces.
		mk.beam(tl - hit.N * 3.0, tl + hit.B * 3.0, 0.45, 0.45, Color.WHITE, hit.T)
		mk.beam(tr - hit.N * 3.0, tr - hit.B * 3.0, 0.45, 0.45, Color.WHITE, hit.T)
		if not prev.is_empty():
			mk.beam(prev[0], tl, 0.5, 0.5, Color.WHITE, hit.N)
			mk.beam(prev[1], tr, 0.5, 0.5, Color.WHITE, hit.N)
			if k % 2 == 0:
				mk.beam(prev[0], tr, 0.3, 0.3, Color.WHITE, hit.N)
			else:
				mk.beam(prev[1], tl, 0.3, 0.3, Color.WHITE, hit.N)
		mk.use("neon_cyan" if k % 4 != 0 else "neon_amber")
		mk.beam(tl - hit.N * 0.65 + hit.B * 0.6, tr - hit.N * 0.65 - hit.B * 0.6, 0.25, 0.12, Color.WHITE, hit.N)
		mk.use("warn_red")
		mk.box(tl + hit.N * 0.8, Vector3(0.4, 0.4, 0.4), Color.WHITE)
		mk.box(tr + hit.N * 0.8, Vector3(0.4, 0.4, 0.4), Color.WHITE)
		prev = [tl, tr]
		s += 30.0
		k += 1
	root.add_child(mk.instance("TrussPortals"))


## Glowing hoops around The Corkscrew so the roll reads at speed.
static func _corkscrew_rings(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "The Corkscrew")
	if r.x < 0.0:
		return
	var mk := MeshKit.new()
	var s := r.x - 30.0
	var k := 0
	while s <= r.y + 30.0:
		var hit := TrackData.Hit.new()
		td.frame_at(s, hit)
		var c := hit.c + hit.N * 5.0
		mk.use("neon_cyan" if k % 2 == 0 else "neon_magenta")
		mk.torus(c, hit.T, 22.0, 0.45, 40, 5, Color.WHITE)
		s += 35.0
		k += 1
	var mi := mk.instance("CorkscrewRings")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## The station core inside the Hub Spiral, with radial struts to the deck.
static func _hub(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Hub Spiral")
	if r.x < 0.0:
		return
	var c := Vector3.ZERO
	var n := 0
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	for i in range(i0 + (i1 - i0) / 8, i1 - (i1 - i0) / 8, 5):
		c += td.pos[i]
		n += 1
	c /= maxf(n, 1)
	var mk := MeshKit.new()
	var bottom := c + Vector3(0, -180, 0)
	var top := c + Vector3(0, 220, 0)
	mk.use("bld_dense")
	HelixBay.prism(mk, bottom, 34.0, 16, top.y - bottom.y, Color(0.75, 0.77, 0.82, 0.5))
	mk.use("metal")
	for y: float in [-150.0, -60.0, 40.0, 140.0, 210.0]:
		mk.torus(c + Vector3(0, y, 0), Vector3.UP, 44.0, 4.0, 40, 8, Color(0.85, 0.86, 0.9))
		for k in 6:
			var a := TAU * k / 6.0
			mk.beam(c + Vector3(cos(a) * 34.0, y, sin(a) * 34.0), c + Vector3(cos(a) * 44.0, y, sin(a) * 44.0), 2.0, 2.0, Color.WHITE)
	mk.use("neon_cyan")
	for y: float in [-150.0, -60.0, 40.0, 140.0, 210.0]:
		mk.torus(c + Vector3(0, y + 4.4, 0), Vector3.UP, 44.0, 0.5, 40, 4, Color.WHITE)
	# Communications mast and dish on the crown.
	mk.use("metal_dark")
	mk.cyl(top, top + Vector3(0, 80, 0), 3.0, 0.6, 8, Color.WHITE)
	mk.use("metal")
	mk.cyl(top + Vector3(0, 30, 0), top + Vector3(0, 38, 0), 2.0, 24.0, 20, Color(0.9, 0.9, 0.92))
	mk.use("warn_red")
	mk.sphere(top + Vector3(0, 82, 0), Vector3(2, 2, 2), 4, 6, Color.WHITE)
	# Radial struts from the core to the spiral deck.
	mk.use("metal")
	for i in range(i0, i1, 30):
		var p := td.pos[i]
		var under := p - td.nrm[i] * (TrackMesh.DECK + 0.5)
		var flat := Vector3(under.x - c.x, 0, under.z - c.z)
		var dir := flat.normalized()
		mk.beam(Vector3(c.x, under.y, c.z) + dir * 34.0, under, 2.4, 1.6, Color(0.8, 0.82, 0.86))
	root.add_child(mk.instance("Hub"))


## Cross-section of a tunnel shell at sample j: a half-ellipse from the right
## floor edge over the roof to the left. `extra_side` widens it beyond the
## barriers, `inset` moves it inward (for ribs and portals).
static func _arc(td: TrackData, j: int, extra_side: float, inset: float = 0.0, steps: int = 12) -> PackedVector3Array:
	var ceil_h := td.ceiling[j] - inset
	var hl := td.half_l[j] + TrackMesh.WALL_T + extra_side - inset
	var hr := td.half_r[j] + TrackMesh.WALL_T + extra_side - inset
	var out := PackedVector3Array()
	for k in steps + 1:
		var a := PI * k / float(steps)
		var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
		var h := -0.3 + sin(a) * (ceil_h + 0.3)
		out.append(td.pos[j] + td.rgt[j] * d + td.nrm[j] * h)
	return out


## Sample range of a tunnel section, extended over following tunnel segments.
static func _tunnel_range(td: TrackData, section: String) -> Vector2i:
	var r := _section(td, section)
	if r.x < 0.0:
		return Vector2i(-1, -1)
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	while td.flag_at_index(i1 + 1, TrackData.F_TUNNEL) and i1 - i0 < td.count:
		i1 += 1
	return Vector2i(i0, i1)


## Tube shell (interior and exterior) following a tunnel section of the track.
static func _tube(td: TrackData, ir: Vector2i, extra_side: float, inner_key: String, outer_key: String, mk: MeshKit) -> void:
	var prev_in := PackedVector3Array()
	var prev_out := PackedVector3Array()
	for i in range(ir.x, ir.y + 1, 2):
		var j := td.wrap_i(i)
		var sec_in := _arc(td, j, extra_side)
		var sec_out := _arc(td, j, extra_side + 2.0, -(TrackMesh.DECK + 0.7))
		if prev_in.size() > 0:
			mk.use(inner_key)
			var pi: Array[PackedVector3Array] = [prev_in, sec_in]
			mk.loft(pi, Color.WHITE, false, false)
			mk.use(outer_key)
			var po: Array[PackedVector3Array] = [prev_out, sec_out]
			mk.loft(po, Color(0.82, 0.84, 0.88, 0.5), false, true)
		prev_in = sec_in
		prev_out = sec_out


## Ribs following the inside of the shell every `every` samples.
static func _ribs(td: TrackData, ir: Vector2i, extra_side: float, every: int, mk: MeshKit) -> void:
	for i in range(ir.x + every / 2, ir.y, every):
		var j := td.wrap_i(i)
		var arc := _arc(td, j, extra_side, 0.35, 10)
		for k in arc.size() - 1:
			mk.beam(arc[k], arc[k + 1], 0.7, 0.5, Color.WHITE, td.tan[j])


## Floor strips between the barriers and the shell wall, both sides.
static func _side_floor(td: TrackData, ir: Vector2i, x0: float, x1: float, h: float, key: String, mk: MeshKit) -> void:
	mk.use(key)
	for i in range(ir.x, ir.y, 2):
		var j := td.wrap_i(i)
		var j1 := td.wrap_i(i + 2)
		for side: float in [-1.0, 1.0]:
			var e0 := (td.half_r[j] if side > 0.0 else td.half_l[j]) + TrackMesh.WALL_T
			var e1 := (td.half_r[j1] if side > 0.0 else td.half_l[j1]) + TrackMesh.WALL_T
			var in0 := td.pos[j] + td.rgt[j] * side * (e0 + x0) + td.nrm[j] * h
			var in1 := td.pos[j1] + td.rgt[j1] * side * (e1 + x0) + td.nrm[j1] * h
			var out0 := td.pos[j] + td.rgt[j] * side * (e0 + x1) + td.nrm[j] * h
			var out1 := td.pos[j1] + td.rgt[j1] * side * (e1 + x1) + td.nrm[j1] * h
			var tint := Color(1, 1, 1).darkened(rng.randf() * 0.15)
			if side > 0.0:
				mk.quad(in0, in1, out1, out0, tint, Vector2(1, 1))
			else:
				mk.quad(in0, out0, out1, in1, tint, Vector2(1, 1))


## The Habitat Ring: a bright tube with garden terraces and trees either side.
static func _habitat(td: TrackData, root: Node3D) -> void:
	var ir := _tunnel_range(td, "Habitat Ring")
	if ir.x < 0:
		return
	var extra := 7.5
	var mk := MeshKit.new()
	_tube(td, ir, extra, "hab_in", "bld", mk)
	mk.use("metal")
	_ribs(td, ir, extra, 16, mk)
	_side_floor(td, ir, 0.0, extra + 0.4, -0.25, "grass", mk)
	var s := ir.x * td.step + 5.0
	var k := 0
	while s < ir.y * td.step - 5.0:
		var hit := TrackData.Hit.new()
		td.frame_at(s, hit)
		var b := Basis(hit.B, hit.N, -hit.T)
		var ceil_h := td.ceiling[hit.i]
		mk.use("neon_white")
		mk.box_t(Transform3D(b, hit.c + hit.N * (ceil_h - 0.25)), Vector3(3.0, 0.2, 5.0), Color.WHITE)
		# Trees on the terraces, alternating sides.
		var side := 1.0 if k % 2 == 0 else -1.0
		var edge := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 2.5 + rng.randf() * 3.0
		var foot := hit.c + hit.B * side * edge - hit.N * 0.25
		var th := 2.2 + rng.randf() * 1.6
		mk.use("bark")
		mk.cyl(foot, foot + hit.N * th, 0.22, 0.16, 5, Color.WHITE, false)
		mk.use("leaves")
		var leaf := Color(0.75 + rng.randf() * 0.25, 0.85 + rng.randf() * 0.15, 0.7 + rng.randf() * 0.3)
		var cr := 1.6 + rng.randf() * 0.9
		mk.sphere(foot + hit.N * (th + cr * 0.6), Vector3(cr, cr * 0.85, cr), 4, 7, leaf, leaf.darkened(0.45))
		# Warm lamp strip where the terrace meets the shell wall.
		mk.use("neon_amber")
		var wall := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + extra - 0.2
		mk.box_t(Transform3D(b, hit.c + hit.B * side * wall + hit.N * 0.1), Vector3(0.15, 0.15, 6.0), Color.WHITE)
		s += 7.0
		k += 1
	var hab := StandardMaterial3D.new()
	hab.albedo_color = Color(0.9, 0.9, 0.88)
	hab.albedo_texture = Mats.tex("panel_albedo")
	hab.uv1_triplanar = true
	hab.uv1_scale = Vector3(0.15, 0.15, 0.15)
	hab.roughness = 0.55
	hab.metallic = 0.15
	hab.cull_mode = BaseMaterial3D.CULL_DISABLED
	hab.emission_enabled = true
	hab.emission = Color(0.2, 0.21, 0.22)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.12, 0.3, 0.08)
	grass.vertex_color_use_as_albedo = true
	grass.roughness = 0.95
	grass.emission_enabled = true
	grass.emission = Color(0.02, 0.05, 0.015)
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.16, 0.42, 0.12)
	leaves.vertex_color_use_as_albedo = true
	leaves.roughness = 0.9
	leaves.emission_enabled = true
	leaves.emission = Color(0.03, 0.07, 0.02)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.25, 0.17, 0.1)
	bark.roughness = 1.0
	var mi := mk.instance("Habitat", {"hab_in": hab, "grass": grass, "leaves": leaves, "bark": bark})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## The Docking Bay: a wide hangar with lit ribs, side decks, parked freighters
## and glowing portals at both ends.
static func _docking_bay(td: TrackData, root: Node3D) -> void:
	var ir := _tunnel_range(td, "Docking Bay")
	if ir.x < 0:
		return
	var extra := 26.0
	var mk := MeshKit.new()
	_tube(td, ir, extra, "bay_in", "bld", mk)
	mk.use("metal")
	_ribs(td, ir, extra, 10, mk)
	_side_floor(td, ir, 1.0, extra + 0.4, -0.6, "metal_dark", mk)
	# Hazard strip along the inner edge of each side deck, lamps on the ribs.
	var s := ir.x * td.step
	var k := 0
	while s < ir.y * td.step:
		var hit := TrackData.Hit.new()
		td.frame_at(s, hit)
		var b := Basis(hit.B, hit.N, -hit.T)
		for side: float in [-1.0, 1.0]:
			var e := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 1.3
			mk.use("neon_amber")
			mk.box_t(Transform3D(b, hit.c + hit.B * side * e - hit.N * 0.5), Vector3(0.3, 0.12, 4.0), Color.WHITE)
		if k % 2 == 0:
			mk.use("lamp")
			for x: float in [-20.0, -7.0, 7.0, 20.0]:
				mk.box_t(Transform3D(b, hit.c + hit.B * x + hit.N * (td.ceiling[hit.i] - 1.2 - absf(x) * 0.12)), Vector3(3.0, 0.3, 1.2), Color.WHITE)
		s += 10.0
		k += 1
	# Freighters parked on the side decks.
	var span := Vector2(ir.x * td.step, ir.y * td.step)
	for f in 4:
		var hit := TrackData.Hit.new()
		td.frame_at(lerpf(span.x, span.y, (f + 0.5) / 4.0), hit)
		var side := 1.0 if f % 2 == 0 else -1.0
		var edge := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 14.0
		var b := Basis(hit.B, hit.N, -hit.T)
		var c := hit.c + hit.B * side * edge + hit.N * 3.8
		var paint: Color = [Color(0.9, 0.9, 0.92), Color(0.85, 0.45, 0.12), Color(0.2, 0.35, 0.6), Color(0.75, 0.75, 0.7)][f]
		mk.use("ship_hull")
		mk.box_t(Transform3D(b, c), Vector3(10.0, 6.0, 34.0), paint)
		mk.box_t(Transform3D(b, c + hit.N * 4.0 - hit.T * 10.0), Vector3(7.0, 3.0, 9.0), paint.lightened(0.2))
		mk.box_t(Transform3D(b, c - hit.T * 19.0), Vector3(6.0, 4.0, 4.0), Color(0.3, 0.3, 0.32))
		mk.use("metal_dark")
		for lz: float in [-10.0, 10.0]:
			mk.box_t(Transform3D(b, c - hit.N * 3.4 + hit.T * lz), Vector3(1.0, 1.0, 1.0), Color.WHITE)
		mk.use("engine_glow")
		for e: float in [-2.5, 2.5]:
			mk.box_t(Transform3D(b, c + hit.B * e + hit.T * 17.2), Vector3(2.2, 2.2, 0.3), Color.WHITE)
		mk.use("neon_amber")
		mk.box_t(Transform3D(b, c + hit.N * 3.1), Vector3(10.2, 0.2, 2.0), Color.WHITE)
		mk.use("nav_white")
		mk.box_t(Transform3D(b, c + hit.N * 4.0 - hit.T * 14.6), Vector3(5.0, 1.0, 0.2), Color.WHITE)
	# Portals at both mouths.
	for j: int in [td.wrap_i(ir.x), td.wrap_i(ir.y)]:
		var arc := _arc(td, j, extra, 0.6, 16)
		mk.use("neon_cyan")
		for a in arc.size() - 1:
			mk.beam(arc[a], arc[a + 1], 0.6, 0.6, Color.WHITE, td.tan[j])
	var bay := StandardMaterial3D.new()
	bay.albedo_color = Color(0.62, 0.64, 0.68)
	bay.albedo_texture = Mats.tex("panel_albedo")
	bay.uv1_triplanar = true
	bay.uv1_scale = Vector3(0.12, 0.12, 0.12)
	bay.metallic = 0.5
	bay.roughness = 0.45
	bay.cull_mode = BaseMaterial3D.CULL_DISABLED
	bay.emission_enabled = true
	bay.emission = Color(0.16, 0.17, 0.2)
	var hull := StandardMaterial3D.new()
	hull.vertex_color_use_as_albedo = true
	hull.roughness = 0.4
	hull.metallic = 0.3
	hull.emission_enabled = true
	hull.emission = Color(0.12, 0.12, 0.13)
	root.add_child(mk.instance("DockingBay", {"bay_in": bay, "ship_hull": hull}))


## Solar wings along the outside of the Array Sweep and the Truss Run.
static func _solar_wings(td: TrackData, root: Node3D) -> void:
	var mk := MeshKit.new()
	for sec_name: String in ["Array Sweep", "Truss Run"]:
		var r := _section(td, sec_name)
		if r.x < 0.0:
			continue
		var s := r.x + 60.0
		var k := 0
		while s < r.y - 40.0:
			var hit := TrackData.Hit.new()
			td.frame_at(s, hit)
			var side := -1.0 if k % 2 == 0 else 1.0
			var out := hit.B * side
			var root_p := hit.c + out * (hit.half_r + 25.0) - hit.N * 12.0
			var tip := root_p + out * 150.0 + Vector3(0, 20.0 * side, 0)
			mk.use("metal")
			mk.beam(hit.c - hit.N * 6.0 + out * 10.0, root_p, 1.4, 1.4, Color.WHITE)
			mk.beam(root_p, tip, 1.2, 1.2, Color.WHITE)
			mk.use("warn_red")
			mk.box(tip, Vector3(0.8, 0.8, 0.8), Color.WHITE)
			# Two panel blankets either side of the boom.
			var along := (tip - root_p).normalized()
			var wide := along.cross(Vector3.UP).normalized()
			if wide.length() < 0.1:
				wide = hit.T
			for blanket: float in [-1.0, 1.0]:
				var a := root_p + wide * blanket * 2.0
				var b := tip + wide * blanket * 2.0
				var a2 := a + wide * blanket * 26.0
				var b2 := b + wide * blanket * 26.0
				mk.use("solar")
				if blanket > 0.0:
					mk.quad(a, b, b2, a2, Color.WHITE, Vector2(10, 2), Vector2.ZERO, true)
				else:
					mk.quad(a2, b2, b, a, Color.WHITE, Vector2(10, 2), Vector2.ZERO, true)
				mk.use("gold")
				mk.beam(a2, b2, 0.5, 0.5, Color.WHITE)
			s += 140.0
			k += 1
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.25)
	gold.metallic = 1.0
	gold.roughness = 0.3
	root.add_child(mk.instance("SolarWings", {"solar": Mats.shader_mat("solar_panel"), "gold": gold}))


## The wheel habitat: a rotating ring station well clear of the circuit.
static func _wheel(root: Node3D, lo: Vector3, hi: Vector3) -> void:
	var mk := MeshKit.new()
	var c := Vector3.ZERO
	var rad := 520.0
	mk.use("bld_dense")
	mk.torus(c, Vector3.UP, rad, 34.0, 120, 16, Color(0.85, 0.87, 0.9, 0.5))
	mk.use("metal")
	for k in 8:
		var a := TAU * k / 8.0
		mk.beam(c, c + Vector3(cos(a) * (rad - 25.0), 0, sin(a) * (rad - 25.0)), 10.0, 10.0, Color.WHITE)
	mk.cyl(c - Vector3(0, 60, 0), c + Vector3(0, 60, 0), 55.0, 55.0, 24, Color.WHITE)
	mk.torus(c, Vector3.UP, rad + 34.0, 3.0, 120, 6, Color.WHITE)
	mk.use("neon_cyan")
	mk.torus(c + Vector3(0, 36.0, 0), Vector3.UP, rad, 1.2, 120, 4, Color.WHITE)
	mk.torus(c - Vector3(0, 36.0, 0), Vector3.UP, rad, 1.2, 120, 4, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(c + Vector3(0, 70, 0), Vector3(4, 4, 4), 4, 6, Color.WHITE)
	var node := Node3D.new()
	node.name = "Wheel"
	var mid := (lo + hi) * 0.5
	node.position = Vector3(hi.x + 1500.0, mid.y + 350.0, lo.z - 900.0)
	node.rotation = Vector3(deg_to_rad(62.0), deg_to_rad(28.0), 0.0)
	var mi := mk.instance("WheelMesh")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var spin := Spin.new()
	spin.target = node
	node.add_child(spin)
	root.add_child(node)


## Slow rotation for the wheel habitat.
class Spin extends Node:
	var target: Node3D

	func _process(delta: float) -> void:
		if target:
			target.rotate_object_local(Vector3.UP, delta * 0.04)


static func _gates(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var last := -1000.0
	var skip: Array[Vector2] = [_section(td, "The Corkscrew"), _section(td, "Truss Run")]
	for i in td.count:
		var s := i * td.step
		if s - last < 230.0 or s < 160.0:
			continue
		if td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 30, TrackData.F_TUNNEL) or td.flag_at_index(i - 30, TrackData.F_TUNNEL):
			continue
		var blocked := false
		for r in skip:
			if r.x >= 0.0 and s > r.x - 60.0 and s < r.y + 60.0:
				blocked = true
		if blocked:
			continue
		last = s
		var key := int(s / 500.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		HelixBay._gate(cells[key], td, i, int(s / 230.0) * 2)
	for key: int in cells:
		root.add_child((cells[key] as MeshKit).instance("Gates%02d" % key))
