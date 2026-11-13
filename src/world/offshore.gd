## TEMPEST SHOALS world: offshore energy platforms in a night storm at sea.
##
## No land: the open sea is a camera-following polar grid displaced by a
## Gerstner swell (sea_swell.gdshader, swell.gdshaderinc), with baked chop and
## foam. The sky is a static storm deck (sky_storm.gdshader, baked clouds); the
## Storm controller fires lightning by updating uniforms and light energies
## only (sky brightness through the background energy multiplier, a flash
## light, the sea and a fog-free bolt mesh), so a strike never compiles a
## shader or adds a node. Rain streaks follow the camera.
##
## The track is elevated everywhere: concrete piers on the low viaducts (with
## spray where the swell hits them), lattice towers on the high ones, radial
## arms from the gasholder under the spiral. Platforms on jacket legs carry the
## start (Main Platform), the Machinery Hall, the Gasholder, the jump take-off
## and the Helideck. Around them: a wind farm with blinking red lights, gas
## flares, cranes, distant rigs and a lighthouse on a rocky shoal.
class_name Offshore
extends RefCounted

const WIND := Vector3(0.6, 0.0, 0.8)          ## Wind direction (as in swell.gdshaderinc).
const SWELL_AMP := 3.7                         ## Highest crest above mean sea level.
const SEA_FLOOR := -10.0                       ## Legs and piers end here, below the troughs.
const MOON_DIR := Vector3(0.25, 0.9, -0.36)    ## Toward the moon hidden in the clouds (high: no glare streaks on the wet deck).
const CELL := 450.0                            ## Merge cell for trackside meshes.
const FOG := Color(0.1, 0.12, 0.15)
const SODIUM := Color(1.0, 0.42, 0.08)

static var rng := RandomNumberGenerator.new()
static var _mat: Dictionary = {}
static var _occ: Occ
static var _plat: Array[Vector2] = []           ## Lap ranges carried by platforms (no piers).
static var _spray_pts: Dictionary = {}          ## cell key -> PackedVector3Array of pier feet.
static var _used: Array[Vector3] = []           ## (x, z, radius) taken on the rig decks.
static var _hall_xf := Transform3D()            ## Machinery Hall frame (centre on the deck) ...
static var _hall_ext := Vector3.ZERO            ## ... and its half extents (x, top, z); zero = none.


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 7341
	_spray_pts.clear()
	_used.clear()
	_hall_ext = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	_materials()
	_occ = Occ.new()
	_occ.build(td)
	_plat = _platform_ranges(td)
	var lap := {"t": Time.get_ticks_msec(), "log": ""}
	var mark := func(what: String) -> void:
		var now := Time.get_ticks_msec()
		lap["log"] += " %s %d" % [what, now - int(lap["t"])]
		lap["t"] = now
	var env := _environment(root)
	var sea := _sea(root)
	mark.call("env+sea")
	_trackside(td, root)
	mark.call("trackside")
	var fk := MeshKit.new()          # every flame, one additive mesh
	_main_platform(td, root, fk)
	_machinery_hall(td, root, fk)
	_gasholder(td, root, fk)
	_jump_rigs(td, root, fk)
	mark.call("platforms")
	_wind_farm(td, root)
	_lighthouse(td, root)
	_distant_rigs(td, root, fk)
	root.add_child(_inst(fk, "Flares", false))
	mark.call("farm+far")
	_spray(root)
	_rain(root)
	_storm(root, env, sea)
	mark.call("weather")
	HelixBay._start_gantry(td, root, "TEMPEST SHOALS  /  VELOCITY LEAGUE")
	if DevArgs.has("--load-times"):
		print("offshore world %d ms (%s )" % [Time.get_ticks_msec() - t0, lap["log"]])
	if DevArgs.has("--world-stats"):
		_stats(root)


## Development aid (--world-stats): triangles per world node, largest first.
static func _stats(root: Node3D) -> void:
	var rows: Array = []
	var total := 0
	for c in root.get_children():
		var n := 0
		var nodes: Array[Node] = [c]
		nodes.append_array(c.find_children("*", "", true, false))
		for x in nodes:
			var mesh: Mesh = null
			var count := 1
			if x is MeshInstance3D:
				mesh = (x as MeshInstance3D).mesh
			elif x is MultiMeshInstance3D:
				var mm := (x as MultiMeshInstance3D).multimesh
				mesh = mm.mesh
				count = mm.instance_count
			if mesh is ArrayMesh:
				for si in mesh.get_surface_count():
					var arr := (mesh as ArrayMesh).surface_get_arrays(si)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					n += idx.size() / 3 * count
		if n > 0:
			rows.append([n, c.name])
			total += n
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	print("world triangles total %d" % total)
	for r: Array in rows.slice(0, 24):
		print("  %8d  %s" % [r[0], r[1]])


# ------------------------------------------------------------------ helpers

static func _sec(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


static func _in_range(td: TrackData, s: float, r: Vector2) -> bool:
	return fposmod(s - r.x, td.length) <= fposmod(r.y - r.x, td.length)


## True inside the Machinery Hall (with a margin before each portal).
static func under_roof(p: Vector3) -> bool:
	if _hall_ext == Vector3.ZERO:
		return false
	var l := _hall_xf.affine_inverse() * p
	return absf(l.x) < _hall_ext.x and absf(l.z) < _hall_ext.z and l.y < _hall_ext.y


static func _on_platform(td: TrackData, s: float) -> bool:
	for r in _plat:
		if _in_range(td, s, r):
			return true
	return false


static func _inst(mk: MeshKit, name: String, shadows: bool = true) -> MeshInstance3D:
	var mi := mk.instance(name, _mat)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


const _FACES := [
	[Vector3(0, 0, 1), [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, -1, 1), Vector3(-1, -1, 1)]],
	[Vector3(0, 0, -1), [Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, -1), Vector3(1, -1, -1)]],
	[Vector3(1, 0, 0), [Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
	[Vector3(-1, 0, 0), [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(-1, -1, 1), Vector3(-1, -1, -1)]],
	[Vector3(0, 1, 0), [Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]],
	[Vector3(0, -1, 0), [Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, -1, -1)]],
]


## Lean box for structural members (no UVs: their materials are triplanar or
## plain), about 2.5x faster than MeshKit.beam; the world builds thousands.
static func _fbox(mk: MeshKit, t: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	for f: Array in _FACES:
		var nrm: Vector3 = t.basis * (f[0] as Vector3)
		var q: Array = f[1]
		var i0 := mk._vert(t * ((q[0] as Vector3) * h), nrm, col)
		mk._vert(t * ((q[1] as Vector3) * h), nrm, col)
		mk._vert(t * ((q[2] as Vector3) * h), nrm, col)
		mk._vert(t * ((q[3] as Vector3) * h), nrm, col)
		mk._quad_i(i0, i0 + 1, i0 + 2, i0 + 3)


## Beam of rectangular section from a to b (as MeshKit.beam, without UVs).
static func _beam(mk: MeshKit, a: Vector3, b: Vector3, w: float, h: float, col: Color, up_hint: Vector3 = Vector3.UP) -> void:
	var z := b - a
	var length := z.length()
	if length < 0.0001:
		return
	z /= length
	var x := up_hint.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	_fbox(mk, Transform3D(Basis(x, z.cross(x), z), (a + b) * 0.5), Vector3(w, h, length), col)


## Spatial hash of track samples, to keep scenery out of the racing corridor.
class Occ:
	var cell := 24.0
	var cells: Dictionary = {}
	var td: TrackData

	func key(x: float, z: float) -> Vector2i:
		return Vector2i(floori(x / cell), floori(z / cell))

	func build(t: TrackData) -> void:
		td = t
		for i in range(0, td.count, 3):
			var k := key(td.pos[i].x, td.pos[i].z)
			var arr: PackedInt32Array = cells.get(k, PackedInt32Array())
			arr.append(i)
			cells[k] = arr

	## True if a footprint of radius r at p (x, z), spanning heights y0..y1,
	## stays `margin` clear of the barriers and of the air above the deck.
	func clear(p: Vector3, r: float, y0: float, y1: float, margin: float = 4.0) -> bool:
		var n := int(ceil((r + 24.0 + margin) / cell))
		var k0 := key(p.x, p.z)
		for dz in range(-n, n + 1):
			for dx in range(-n, n + 1):
				var k := Vector2i(k0.x + dx, k0.y + dz)
				if not cells.has(k):
					continue
				for i: int in cells[k]:
					var q := td.pos[i]
					var half := maxf(td.half_l[i], td.half_r[i]) + TrackMesh.WALL_T
					if Vector2(p.x - q.x, p.z - q.z).length() > half + r + margin:
						continue
					if y1 < q.y - TrackMesh.DECK - 2.0 or y0 > q.y + 16.0:
						continue
					return false
		return true

	## Horizontal distance from p to the nearest track sample (searched within `reach`).
	func dist(p: Vector3, reach: float = 200.0) -> float:
		var best := INF
		var n := int(ceil(reach / cell))
		var k0 := key(p.x, p.z)
		for dz in range(-n, n + 1):
			for dx in range(-n, n + 1):
				var k := Vector2i(k0.x + dx, k0.y + dz)
				if not cells.has(k):
					continue
				for i: int in cells[k]:
					best = minf(best, Vector2(p.x - td.pos[i].x, p.z - td.pos[i].z).length())
		return best


static func _platform_ranges(td: TrackData) -> Array[Vector2]:
	var out: Array[Vector2] = []
	out.append(Vector2(td.length - 150.0, 295.0))                 # Main and Flare platforms
	var hall := _sec(td, "Machinery Hall")
	out.append(Vector2(hall.x - 40.0, hall.y + 40.0))             # Process platform
	var sp := _sec(td, "Gasholder Spiral")
	out.append(Vector2(sp.x, sp.y))                               # arms from the gasholder
	var jump := _sec(td, "Flare Jump")
	out.append(Vector2(jump.x - 90.0, jump.x + 100.0))            # take-off platform
	var ess := _sec(td, "Helideck Esses")
	out.append(Vector2(jump.x + 155.0, ess.x + 230.0))            # Helideck platform
	return out


# ------------------------------------------------------------------ materials

static func _std(col: Color, rough: float, metal: float, tex: String = "", scale: float = 0.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		m.albedo_texture = Mats.tex(tex)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	return m


static func _materials() -> void:
	_mat.clear()
	_mat["steel"] = _std(Color(0.62, 0.62, 0.6), 0.45, 0.45, "panel_albedo", 0.09)
	_mat["concrete"] = _std(Color(0.45, 0.46, 0.47), 0.7, 0.0, "panel_albedo", 0.07)
	_mat["sodium"] = Mats.glow(SODIUM, 3.2)
	_mat["lamp"] = Mats.get_mat("lamp")
	_mat["warn_red"] = Mats.get_mat("warn_red")
	_mat["neon_cyan"] = Mats.get_mat("neon_cyan")
	_mat["neon_magenta"] = Mats.get_mat("neon_magenta")
	_mat["metal_dark"] = Mats.get_mat("metal_dark")
	_mat["bld"] = Mats.get_mat("bld")
	_mat["beacon"] = Mats.shader_mat("beacon_blink")
	_mat["flame"] = Mats.shader_mat("flare_flame", {"noise_tex": Mats.tex("offshore_clouds")})
	var pool := StandardMaterial3D.new()
	pool.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	pool.albedo_texture = Mats.tex("glow")
	pool.albedo_color = Color(0.2, 0.105, 0.035, 1.0)
	pool.vertex_color_use_as_albedo = true
	pool.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat["pool"] = pool
	var hall := _std(Color(0.62, 0.64, 0.66), 0.5, 0.3, "panel_albedo", 0.12)
	hall.emission_enabled = true
	hall.emission = Color(0.22, 0.21, 0.18)
	_mat["hall"] = hall
	_mat["heli"] = Mats.glow(Color(0.3, 1.0, 0.45), 4.0)
	_mat["paint_yellow"] = Mats.get_mat("paint_yellow")
	_mat["rock"] = _std(Color(0.2, 0.21, 0.21), 0.3, 0.0, "panel_normal", 0.04)
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.vertex_color_use_as_albedo = true
	beam.albedo_color = Color(0.32, 0.3, 0.24)
	_mat["beam"] = beam
	for t: String in Catalog.team_ids():
		_mat["logo_" + t] = Mats.get_mat("logo_" + t)


# ------------------------------------------------------------------ environment

static func _environment(root: Node3D) -> Environment:
	var env: Environment = null
	for c in root.get_children():
		if c is WorldEnvironment:
			env = (c as WorldEnvironment).environment
			var sm := ShaderMaterial.new()
			sm.shader = load("res://assets/shaders/sky_storm.gdshader")
			sm.set_shader_parameter("clouds", Mats.tex("offshore_clouds"))
			sm.set_shader_parameter("moon_dir", MOON_DIR.normalized())
			sm.set_shader_parameter("horizon", FOG)
			env.sky.sky_material = sm
			env.sky.radiance_size = Sky.RADIANCE_SIZE_64
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.3, 0.36, 0.46)
			env.ambient_light_energy = 1.0
			env.fog_light_color = FOG
			env.fog_density = 0.001
			env.fog_sky_affect = 0.0
			env.fog_aerial_perspective = 0.25
			env.fog_height = 8.0
			env.fog_height_density = 0.012
			env.tonemap_exposure = 1.35
			env.glow_hdr_threshold = 0.9
			env.glow_intensity = 0.8
		elif c is DirectionalLight3D:
			var moon := c as DirectionalLight3D
			moon.transform = Transform3D(Basis.looking_at(-MOON_DIR.normalized(), Vector3.UP), Vector3.ZERO)
			moon.light_color = Color(0.62, 0.72, 0.95)
			moon.light_energy = 0.55
			# A sharp moon glint on the wet, normal-mapped deck reads as a wire grid.
			moon.light_specular = 0.1
			# No hard shadows under a storm deck at night (and none to render on mobile).
			moon.shadow_enabled = false
	# Wet everything: the shared track material carries the rain.
	(Mats.get_mat("track") as ShaderMaterial).set_shader_parameter("wetness", 0.95)
	return env


# ------------------------------------------------------------------ sea

## Polar grid around the origin, fine near the centre: rings spaced 2 m + 6 %
## of the radius, out to 3.6 km, 128 segments. Follows the camera (SeaFollow).
static func _sea(root: Node3D) -> ShaderMaterial:
	var radii := PackedFloat32Array([0.0])
	var r := 0.0
	while r < 3600.0:
		r += 2.0 + r * 0.06
		radii.append(r)
	var segs := 128
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for ri in radii.size():
		for k in segs:
			var a := TAU * k / segs
			v.append(Vector3(cos(a) * radii[ri], 0.0, sin(a) * radii[ri]))
			n.append(Vector3.UP)
	for ri in radii.size() - 1:
		for k in segs:
			var a := ri * segs + k
			var b := ri * segs + (k + 1) % segs
			var c := (ri + 1) * segs + (k + 1) % segs
			var d := (ri + 1) * segs + k
			# Clockwise seen from above (+Y), Godot's front face.
			idx.append_array(PackedInt32Array([a, c, b, a, d, c]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := Mats.shader_mat("sea_swell", {"detail": Mats.tex("offshore_sea"), "sky_col": FOG})
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0
	root.add_child(mi)
	var follow := SeaFollow.new()
	follow.sea = mi
	root.add_child(follow)
	return mat


## Keeps the sea grid centred under the active camera.
class SeaFollow extends Node:
	var sea: MeshInstance3D

	func _process(_d: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam and sea:
			var p := cam.global_position
			sea.global_position = Vector3(p.x, 0.0, p.z)


# ------------------------------------------------------------------ trackside

## Piers, girders, lamp posts with light pools, and gates, merged per 450 m cell.
static func _trackside(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var hit := TrackData.Hit.new()
	var start_clear := Vector2(td.length - 60.0, 60.0)
	var last_gate := -1000.0
	var last_pier := -1000.0
	var lamp_n := 0
	var s := 0.0
	while s < td.length:
		td.frame_at(s, hit)
		var i := hit.i
		var key := int(s / CELL)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 30, TrackData.F_TUNNEL) or td.flag_at_index(i - 30, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 10, TrackData.F_GAP) or td.flag_at_index(i - 6, TrackData.F_GAP)
		var plat := _on_platform(td, s)
		var b := Basis(hit.B, hit.N, -hit.T)
		# Box girder under the deck on the viaducts.
		if not plat and not tunnel and not td.flag_at_index(i, TrackData.F_GAP):
			var wdt := hit.half_l + hit.half_r - 4.0
			mk.use("concrete")
			mk.box_t(Transform3D(b, hit.c - hit.N * (TrackMesh.DECK + 1.2)), Vector3(wdt, 2.4, 10.2), Color(0.8, 0.8, 0.82))
			if s - last_pier >= 46.0 and not gap:
				last_pier = s
				_pier(mk, td, hit, key)
		# Sodium lamp posts on alternate sides every 40 m, with a pool on the deck.
		if int(s) % 40 == 0 and not tunnel and not gap:
			var side := 1.0 if lamp_n % 2 == 0 else -1.0
			lamp_n += 1
			_lamp_post(mk, hit, side)
		if s - last_gate > 230.0 and not tunnel and not gap and not _in_range(td, s, start_clear):
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 230.0) * 2)
		s += 10.0
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(_inst(mk, "Trackside%02d" % key))


## A pier under the deck at `hit`: twin concrete columns with a cap beam on the
## low viaducts, a braced steel lattice tower on the high ones.
static func _pier(mk: MeshKit, td: TrackData, hit: TrackData.Hit, key: int) -> void:
	var under := hit.c - hit.N * (TrackMesh.DECK + 2.4)
	var flat_b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
	var flat_t := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
	var top := under.y
	if top < 26.0:
		mk.use("concrete")
		mk.box_t(Transform3D(Basis(flat_b, Vector3.UP, -flat_t), under - Vector3(0, 0.9, 0)), Vector3(hit.half_l + hit.half_r - 2.0, 1.8, 3.2), Color(0.75, 0.75, 0.77))
		for side: float in [-1.0, 1.0]:
			var p := under + flat_b * side * 7.0
			mk.use("concrete")
			mk.cyl(Vector3(p.x, SEA_FLOOR, p.z), Vector3(p.x, top - 1.6, p.z), 1.7, 1.5, 10, Color(0.72, 0.72, 0.74), false, Color(0.82, 0.82, 0.84))
			# Dark, weed-stained splash zone.
			mk.cyl(Vector3(p.x, -2.0, p.z), Vector3(p.x, SWELL_AMP + 2.5, p.z), 1.85, 1.85, 10, Color(0.16, 0.18, 0.17), false)
			_add_spray_point(key, Vector3(p.x, 0.0, p.z))
	else:
		_lattice_tower(mk, under, flat_b, flat_t, 6.5, 3.5, top)
		for side: float in [-1.0, 1.0]:
			var p := under + flat_b * side * 9.0
			_add_spray_point(key, Vector3(p.x, 0.0, p.z))


static func _add_spray_point(key: int, p: Vector3) -> void:
	var arr: PackedVector3Array = _spray_pts.get(key, PackedVector3Array())
	arr.append(p)
	_spray_pts[key] = arr


## Four-legged braced tower from the sea floor to `top` under a deck point.
## `hw` / `hd` are the half spans across and along the track at the top; the
## legs spread by a third toward the sea.
static func _lattice_tower(mk: MeshKit, under: Vector3, across: Vector3, along: Vector3, hw: float, hd: float, top: float) -> void:
	var feet: Array[Vector3] = []
	var heads: Array[Vector3] = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var h := Vector3(under.x, top, under.z) + across * sx * hw + along * sz * hd
			var f := Vector3(under.x, SEA_FLOOR, under.z) + across * sx * hw * 1.35 + along * sz * hd * 1.35
			heads.append(h)
			feet.append(f)
	mk.use("steel")
	var col := Color(0.55, 0.52, 0.48)
	for k in 4:
		mk.cyl(feet[k], heads[k], 0.85, 0.7, 6, col, false)
		# Dark splash zone where the swell runs up the leg.
		var lo := feet[k].lerp(heads[k], (-2.0 - SEA_FLOOR) / (top - SEA_FLOOR))
		var hi := feet[k].lerp(heads[k], (SWELL_AMP + 2.0 - SEA_FLOOR) / (top - SEA_FLOOR))
		mk.cyl(lo, hi, 1.0, 1.0, 6, Color(0.14, 0.15, 0.14), false)
	var levels := maxi(2, int((top - 2.0) / 10.0))
	var order := [0, 1, 3, 2]
	var prev: Array[Vector3] = []
	for l in levels + 1:
		var t := float(l) / levels
		var y := lerpf(2.0, top - 1.0, t)
		var ring: Array[Vector3] = []
		for k in 4:
			var a := feet[order[k]]
			var b := heads[order[k]]
			ring.append(a.lerp(b, (y - SEA_FLOOR) / (top - SEA_FLOOR)))
		for k in 4:
			_beam(mk, ring[k], ring[(k + 1) % 4], 0.45, 0.45, col)
		if not prev.is_empty():
			# X braces on the two faces across the track.
			for k: int in [0, 2]:
				_beam(mk, prev[k], ring[k + 1], 0.32, 0.32, col)
				_beam(mk, prev[k + 1], ring[k], 0.32, 0.32, col)
		prev = ring


## Lamp post outside the barrier on `side`, arm over the deck, and an additive
## light pool on the wet surface under it.
static func _lamp_post(mk: MeshKit, hit: TrackData.Hit, side: float) -> void:
	var edge := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 0.6
	var foot := hit.c + hit.B * side * edge - hit.N * 0.3
	var head := foot + hit.N * 9.5
	var tip := head - hit.B * side * 3.2
	mk.use("metal_dark")
	_beam(mk, foot, head, 0.35, 0.35, Color.WHITE, hit.T)
	_beam(mk, head, tip, 0.25, 0.25, Color.WHITE, hit.T)
	mk.use("sodium")
	mk.box_t(Transform3D(Basis(hit.B, hit.N, -hit.T), tip - hit.N * 0.25), Vector3(1.2, 0.3, 0.6), Color.WHITE)
	var c := hit.c + hit.B * side * (edge - 7.0) + hit.N * 0.06
	var r := 9.0
	mk.use("pool")
	mk.quad(c - hit.B * r - hit.T * r, c + hit.B * r - hit.T * r, c + hit.B * r + hit.T * r, c - hit.B * r + hit.T * r, Color.WHITE)


# ------------------------------------------------------------------ structure kit

## Horizontal frame at lap distance s: origin on the centre line, x = right,
## y = up, z = backwards.
static func _flat(td: TrackData, s: float) -> Transform3D:
	var hit := TrackData.Hit.new()
	td.frame_at(s, hit)
	var t := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
	return Transform3D(Basis(t.cross(Vector3.UP), Vector3.UP, -t), hit.c)


## Point of a frame: x across, y absolute height, z along (backwards).
static func _at(xf: Transform3D, x: float, y: float, z: float) -> Vector3:
	var p := xf.origin + xf.basis.x * x + xf.basis.z * z
	return Vector3(p.x, y, p.z)


## A fixed platform: battered tubular jacket legs from the sea floor, a cellar
## deck and a main deck whose top is at deck_y, a yellow fascia, railings and
## sodium lamps round the edge. `xf` gives the centre (x, z) and heading;
## size = (across, along); `legs` = leg count across and along.
static func _rig(mk: MeshKit, xf: Transform3D, size: Vector2, deck_y: float, legs: Vector2i, spray_key: int = -1) -> void:
	var b := xf.basis
	var hw := size.x * 0.5
	var hl := size.y * 0.5
	mk.use("steel")
	mk.box_t(Transform3D(b, _at(xf, 0.0, deck_y - 1.0, 0.0)), Vector3(size.x, 2.0, size.y), Color(0.4, 0.41, 0.4))
	mk.box_t(Transform3D(b, _at(xf, 0.0, deck_y - 10.0, 0.0)), Vector3(size.x - 8.0, 1.6, size.y - 8.0), Color(0.36, 0.36, 0.35))
	mk.use("paint_yellow")
	for sz: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(b, _at(xf, 0.0, deck_y - 2.6, sz * (hl + 0.2))), Vector3(size.x + 0.4, 1.2, 0.3), Color(0.8, 0.8, 0.8))
	for sx: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(b, _at(xf, sx * (hw + 0.2), deck_y - 2.6, 0.0)), Vector3(0.3, 1.2, size.y + 0.4), Color(0.8, 0.8, 0.8))
	var heads: Array[Vector3] = []
	var feet: Array[Vector3] = []
	for iz in legs.y:
		for ix in legs.x:
			var lx := lerpf(-hw + 5.0, hw - 5.0, float(ix) / maxf(legs.x - 1, 1))
			var lz := lerpf(-hl + 5.0, hl - 5.0, float(iz) / maxf(legs.y - 1, 1))
			var head := _at(xf, lx, deck_y - 10.8, lz)
			var foot := _at(xf, lx * 1.18, SEA_FLOOR, lz * 1.08)
			heads.append(head)
			feet.append(foot)
			mk.use("steel")
			mk.cyl(foot, head, 2.4, 2.0, 10, Color(0.62, 0.55, 0.42), false)
			var span := head.y - SEA_FLOOR
			mk.cyl(foot.lerp(head, (-2.0 - SEA_FLOOR) / span), foot.lerp(head, (SWELL_AMP + 3.0 - SEA_FLOOR) / span), 2.7, 2.6, 10, Color(0.13, 0.14, 0.13), false)
			if spray_key >= 0:
				var w := foot.lerp(head, -SEA_FLOOR / span)
				_add_spray_point(spray_key, Vector3(w.x, 0.0, w.z))
	mk.use("steel")
	for lvl: float in [0.38, 0.75]:
		for iz in legs.y:
			for ix in legs.x:
				var k := iz * legs.x + ix
				var p0 := feet[k].lerp(heads[k], lvl)
				if ix + 1 < legs.x:
					_beam(mk, p0, feet[k + 1].lerp(heads[k + 1], lvl), 1.0, 1.0, Color(0.55, 0.5, 0.4))
				if iz + 1 < legs.y:
					_beam(mk, p0, feet[k + legs.x].lerp(heads[k + legs.x], lvl), 1.0, 1.0, Color(0.55, 0.5, 0.4))
	# Lamps under the main deck light the cellar deck and the tops of the legs.
	var nl := maxi(2, int(size.y / 30.0))
	for q in nl:
		var lz2 := lerpf(-hl + 8.0, hl - 8.0, (q + 0.5) / nl)
		for sx: float in [-1.0, 1.0]:
			var lp := _at(xf, sx * (hw - 6.0), deck_y - 2.4, lz2)
			mk.use("sodium")
			mk.box(lp, Vector3(0.8, 0.3, 0.8), Color.WHITE)
			_pool(mk, Vector3(lp.x, deck_y - 9.2, lp.z), 9.0, 0.8)
	var corners := [Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)]
	for e in 4:
		var a: Vector2 = corners[e]
		var c: Vector2 = corners[(e + 1) % 4]
		var pa := _at(xf, a.x, deck_y + 1.1, a.y)
		var pc := _at(xf, c.x, deck_y + 1.1, c.y)
		mk.use("metal_dark")
		_beam(mk, pa, pc, 0.12, 0.12, Color.WHITE)
		var n := maxi(1, int(pa.distance_to(pc) / 24.0))
		for q in n:
			var p := pa.lerp(pc, (q + 0.5) / n)
			mk.use("metal_dark")
			_beam(mk, p - Vector3(0, 1.1, 0), p + Vector3(0, 4.0, 0), 0.25, 0.25, Color.WHITE)
			mk.use("sodium")
			mk.box(p + Vector3(0, 4.2, 0), Vector3(0.8, 0.35, 0.8), Color.WHITE)


## Steel columns from a rig deck up to the track deck, every 24 m from s0 to s1.
static func _pedestals(mk: MeshKit, td: TrackData, s0: float, s1: float, deck_y: float) -> void:
	var hit := TrackData.Hit.new()
	var s := s0
	while s <= s1:
		td.frame_at(s, hit)
		if not td.flag_at_index(hit.i, TrackData.F_GAP):
			var flat_b := Vector3(hit.B.x, 0, hit.B.z).normalized()
			var under := hit.c - hit.N * TrackMesh.DECK
			mk.use("steel")
			mk.box_t(Transform3D(Basis(flat_b, Vector3.UP, flat_b.cross(Vector3.UP)), under - Vector3(0, 0.7, 0)), Vector3(hit.half_l + hit.half_r - 2.0, 1.4, 2.0), Color(0.45, 0.45, 0.43))
			for side: float in [-1.0, 1.0]:
				var p := under + flat_b * side * 8.0
				if p.y - deck_y > 1.5:
					mk.box(Vector3(p.x, (p.y - 1.4 + deck_y) * 0.5, p.z), Vector3(1.6, p.y - 1.4 - deck_y, 1.6), Color(0.5, 0.5, 0.48))
		s += 24.0


## A block on a rig frame at (x, z), standing at height y: facade windows
## (`style` 0.5 office, 1 residential, 0 plain), roof plant and a floodlight.
## Skipped (false) if it would enter the racing corridor.
static func _module(mk: MeshKit, xf: Transform3D, x: float, z: float, y: float, size: Vector3, style: float, col: Color) -> bool:
	var c := _at(xf, x, y, z)
	if not _box_clear(xf, c, size, 2.0):
		return false
	var b := xf.basis
	_used.append(Vector3(c.x, c.z, Vector2(size.x, size.z).length() * 0.5))
	mk.use("bld")
	mk.box_t(Transform3D(b, c + Vector3(0, size.y * 0.5, 0)), size, Color(col.r, col.g, col.b, style))
	mk.use("steel")
	mk.box_t(Transform3D(b, c + Vector3(0, size.y + 0.3, 0)), Vector3(size.x + 0.6, 0.6, size.z + 0.6), Color(0.33, 0.34, 0.34))
	for k in 2:
		var o := b.x * rng.randf_range(-0.3, 0.3) * size.x + b.z * rng.randf_range(-0.3, 0.3) * size.z
		mk.box_t(Transform3D(b, c + o + Vector3(0, size.y + 2.0, 0)), Vector3(4.0, 3.0, 5.0), Color(0.48, 0.48, 0.46))
	mk.use("sodium")
	for sx: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(b, c + Vector3(0, size.y - 0.8, 0) + b.x * sx * (size.x * 0.5 + 0.3)), Vector3(0.4, 0.4, 1.4), Color.WHITE)
	return true


## True if a block of `size` standing at c (oriented like xf) keeps clear of the
## racing corridor: its footprint is tested as a row of circles along its long side.
static func _box_clear(xf: Transform3D, c: Vector3, size: Vector3, margin: float) -> bool:
	var long_z := size.z >= size.x
	var short := minf(size.x, size.z)
	var long := maxf(size.x, size.z)
	var n := maxi(1, int(ceil(long / short)))
	var r := Vector2(short * 0.5, long / n * 0.5).length()
	var axis := xf.basis.z if long_z else xf.basis.x
	for k in n:
		var p := c + axis * ((k + 0.5) / n - 0.5) * long
		if not _occ.clear(p, r, c.y, c.y + size.y, margin):
			return false
	return true


## Deck clutter on a rig: containers, tanks, skids and small huts on a jittered
## 15 m grid, kept clear of the racing corridor and of what already stands there.
static func _clutter(mk: MeshKit, xf: Transform3D, size: Vector2, deck_y: float, fill: float = 0.55) -> void:
	var cols := [Color(0.75, 0.22, 0.12), Color(0.12, 0.35, 0.62), Color(0.85, 0.58, 0.1), Color(0.2, 0.48, 0.3), Color(0.62, 0.62, 0.64), Color(0.9, 0.9, 0.88)]
	var hw := size.x * 0.5 - 6.0
	var hl := size.y * 0.5 - 6.0
	var x := -hw
	while x <= hw:
		var z := -hl
		while z <= hl:
			var px := x + rng.randf_range(-3.0, 3.0)
			var pz := z + rng.randf_range(-3.0, 3.0)
			z += 15.0
			if rng.randf() > fill:
				continue
			var c := _at(xf, px, deck_y, pz)
			var free := true
			for u in _used:
				if Vector2(c.x - u.x, c.z - u.y).length() < u.z + 7.0:
					free = false
					break
			if not free:
				continue
			var kind := rng.randi() % 4
			var sz := Vector3(2.6, 2.6, 12.2)
			if kind == 1:
				sz = Vector3(7.0, rng.randf_range(5.0, 10.0), 7.0)
			elif kind == 2:
				sz = Vector3(8.0, 3.5, 11.0)
			elif kind == 3:
				sz = Vector3(9.0, 4.5, 7.0)
			if not _box_clear(xf, c, sz, 2.0):
				continue
			_used.append(Vector3(c.x, c.z, Vector2(sz.x, sz.z).length() * 0.5))
			var b := xf.basis
			var col: Color = cols[rng.randi() % cols.size()]
			match kind:
				0:      # a short stack of containers
					mk.use("steel")
					var n := rng.randi_range(1, 3)
					for q in n:
						mk.box_t(Transform3D(b, c + Vector3(0, 1.3 + q * 2.6, 0)), sz, cols[(rng.randi()) % cols.size()], 0.75)
				1:      # vertical tank with a lamp
					mk.use("steel")
					mk.cyl(c, c + Vector3(0, sz.y, 0), 3.4, 3.4, 12, Color(0.82, 0.82, 0.8))
					mk.use("sodium")
					mk.box(c + Vector3(0, sz.y + 0.4, 0), Vector3(0.6, 0.4, 0.6), Color.WHITE)
				2:      # pump skid with pipes
					mk.use("steel")
					mk.box_t(Transform3D(b, c + Vector3(0, 0.5, 0)), Vector3(sz.x, 1.0, sz.z), Color(0.3, 0.3, 0.3))
					mk.cyl(c + Vector3(0, 2.2, 0) - b.z * 4.5, c + Vector3(0, 2.2, 0) + b.z * 4.5, 1.2, 1.2, 10, col)
					mk.cyl(c + Vector3(0, 3.2, 0) - b.z * 5.0 + b.x * 2.5, c + Vector3(0, 3.2, 0) + b.z * 5.0 + b.x * 2.5, 0.5, 0.5, 8, Color(0.85, 0.65, 0.1))
				3:      # hut with lit windows
					mk.use("bld")
					mk.box_t(Transform3D(b, c + Vector3(0, sz.y * 0.5, 0)), sz, Color(col.r, col.g, col.b, 0.5))
		x += 15.0


## Pedestal crane at `base` (deck level): boom slewed to `dir` (horizontal) and
## luffed `elev` degrees, blinking tip light. Skipped if the boom would reach
## into the racing corridor.
static func _crane(mk: MeshKit, base: Vector3, dir: Vector3, boom: float, elev: float) -> bool:
	var pivot := base + Vector3(0, 12.0, 0)
	var e := deg_to_rad(elev)
	var tip := pivot + dir * boom * cos(e) + Vector3(0, boom * sin(e), 0)
	for k in 7:
		var p := pivot.lerp(tip, k / 6.0)
		if not _occ.clear(p, 3.0, p.y - 20.0, p.y + 3.0, 2.0):
			return false
	var side := dir.cross(Vector3.UP).normalized()
	_used.append(Vector3(base.x, base.z, 7.0))
	mk.use("paint_yellow")
	mk.cyl(base, base + Vector3(0, 9.0, 0), 2.2, 2.2, 10, Color.WHITE)
	var cab := Basis(side, Vector3.UP, -dir)
	mk.box_t(Transform3D(cab, base + Vector3(0, 11.2, 0)), Vector3(6.0, 4.5, 8.0), Color.WHITE)
	mk.box_t(Transform3D(cab, base + Vector3(0, 16.0, 0) - dir * 2.0), Vector3(1.6, 6.0, 1.6), Color.WHITE)
	var bd := (tip - pivot).normalized()
	var up := side.cross(bd).normalized()
	var cs: Array[Vector3] = [side * 1.1 + up * 1.1, -side * 1.1 + up * 1.1, -side * 1.1 - up * 1.1, side * 1.1 - up * 1.1]
	for c in cs:
		_beam(mk, pivot + c, tip + c * 0.3, 0.3, 0.3, Color.WHITE)
	var n := int(boom / 4.5)
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var a := pivot.lerp(tip, t0)
		var c2 := pivot.lerp(tip, t1)
		var s0 := lerpf(1.0, 0.3, t0)
		var s1 := lerpf(1.0, 0.3, t1)
		# Zigzag lacing on both side faces: right (0-3) and left (1-2).
		var ev := k % 2 == 0
		_beam(mk, a + cs[0 if ev else 3] * s0, c2 + cs[3 if ev else 0] * s1, 0.16, 0.16, Color.WHITE)
		_beam(mk, a + cs[1 if ev else 2] * s0, c2 + cs[2 if ev else 1] * s1, 0.16, 0.16, Color.WHITE)
	mk.use("metal_dark")
	_beam(mk, tip, tip - Vector3(0, 18.0, 0), 0.12, 0.12, Color.WHITE)
	mk.box(tip - Vector3(0, 19.0, 0), Vector3(1.2, 1.6, 1.2), Color.WHITE)
	mk.use("beacon")
	mk.box(tip + Vector3(0, 0.9, 0), Vector3(0.8, 0.8, 0.8), Color(0.5, 0, 0))
	return true


## Octagonal helideck, top centre `c`, radius r, on struts leaning back along
## `toward` to height strut_y. Yellow ring and H, green perimeter lights.
static func _helipad(mk: MeshKit, c: Vector3, r: float, strut_y: float, toward: Vector3) -> void:
	mk.use("steel")
	HelixBay.prism(mk, c - Vector3(0, 1.0, 0), r, 8, 1.0, Color(0.22, 0.27, 0.24, 0.0), -1.0, PI / 8.0)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var p := c + Vector3(cos(a), 0, sin(a)) * r * 0.75 - Vector3(0, 1.0, 0)
		_beam(mk, p, Vector3(p.x, strut_y, p.z) + toward * r * 0.9, 0.8, 0.8, Color(0.5, 0.5, 0.48))
	mk.use("paint_yellow")
	mk.torus(c + Vector3(0, 0.05, 0), Vector3.UP, r * 0.62, 0.3, 32, 3, Color.WHITE)
	var f := toward.normalized()
	var sd := f.cross(Vector3.UP)
	var hb := Basis(sd, Vector3.UP, -f)
	for sx: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(hb, c + sd * sx * 2.6 + Vector3(0, 0.05, 0)), Vector3(1.2, 0.12, 8.0), Color.WHITE)
	mk.box_t(Transform3D(hb, c + Vector3(0, 0.05, 0)), Vector3(5.2, 0.12, 1.2), Color.WHITE)
	mk.use("heli")
	for k in 16:
		var a := TAU * k / 16.0
		mk.box(c + Vector3(cos(a), 0, sin(a)) * r * 0.95 + Vector3(0, 0.2, 0), Vector3(0.5, 0.3, 0.5), Color.WHITE)


## Drilling derrick: four legs tapering to a crown, braced every 7 m.
static func _derrick(mk: MeshKit, base: Vector3, h: float, w: float) -> void:
	_used.append(Vector3(base.x, base.z, w * 0.8))
	var feet: Array[Vector3] = []
	var tops: Array[Vector3] = []
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		feet.append(base + d * w * 0.707)
		tops.append(base + d * w * 0.16 + Vector3(0, h, 0))
	mk.use("steel")
	var col := Color(0.75, 0.72, 0.65)
	for k in 4:
		_beam(mk, feet[k], tops[k], 0.6, 0.6, col)
	var levels := int(h / 7.0)
	for l in levels:
		var t0 := float(l) / levels
		var t1 := float(l + 1) / levels
		for k in 4:
			var a0 := feet[k].lerp(tops[k], t0)
			var b0 := feet[(k + 1) % 4].lerp(tops[(k + 1) % 4], t0)
			var a1 := feet[k].lerp(tops[k], t1)
			var b1 := feet[(k + 1) % 4].lerp(tops[(k + 1) % 4], t1)
			_beam(mk, a1, b1, 0.35, 0.35, col)
			if l % 2 == 0:
				_beam(mk, a0, b1, 0.22, 0.22, col)
			else:
				_beam(mk, b0, a1, 0.22, 0.22, col)
	mk.box(base + Vector3(0, h + 1.5, 0), Vector3(w * 0.4, 3.0, w * 0.4), col)
	mk.use("beacon")
	mk.box(base + Vector3(0, h + 3.6, 0), Vector3(0.9, 0.9, 0.9), Color(0.25, 0, 0))
	mk.use("sodium")
	for y: float in [h * 0.35, h * 0.7]:
		for k: int in [0, 2]:
			var p := feet[k].lerp(tops[k], y / h)
			mk.box(p + Vector3(0, 0.3, 0), Vector3(0.7, 0.5, 0.7), Color.WHITE)


## Flame of a gas flare: three crossed quads leaning downwind (flame shader).
static func _flame(fk: MeshKit, base: Vector3, h: float, w: float) -> void:
	var lean := WIND.normalized() * h * 0.35
	var r := rng.randf()
	fk.use("flame")
	for k in 3:
		var a := PI * k / 3.0
		var side := Vector3(cos(a), 0.0, sin(a)) * w * 0.5
		var top := base + Vector3(0, h, 0) + lean
		fk.quad(base - side, base + side, top + side * 0.7, top - side * 0.7, Color(1, r, 1))


## Lattice flare boom from `root_p` out along `dir`, luffed `elev` degrees,
## with a burner and flame at the tip. Returns the tip.
static func _flare_boom(mk: MeshKit, fk: MeshKit, root_p: Vector3, dir: Vector3, length: float, elev: float, flame_h: float) -> Vector3:
	var e := deg_to_rad(elev)
	var tip := root_p + dir * length * cos(e) + Vector3(0, length * sin(e), 0)
	var bd := (tip - root_p).normalized()
	var side := bd.cross(Vector3.UP).normalized()
	var up := side.cross(bd).normalized()
	var cs: Array[Vector3] = [side * 1.8 - up * 1.0, -side * 1.8 - up * 1.0, up * 2.0]
	mk.use("steel")
	var col := Color(0.72, 0.7, 0.66)
	for c in cs:
		_beam(mk, root_p + c, tip + c * 0.4, 0.4, 0.4, col)
	var n := int(length / 6.0)
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		var a := root_p.lerp(tip, t0)
		var b := root_p.lerp(tip, t1)
		var s0 := lerpf(1.0, 0.4, t0)
		var s1 := lerpf(1.0, 0.4, t1)
		for q in 3:
			_beam(mk, a + cs[q] * s0, b + cs[(q + 1) % 3] * s1, 0.2, 0.2, col)
	mk.use("metal_dark")
	mk.cyl(tip, tip + Vector3(0, 3.0, 0), 1.2, 0.9, 8, Color.WHITE)
	mk.use("beacon")
	mk.box(tip - up * 1.5, Vector3(0.7, 0.7, 0.7), Color(0.75, 0, 0))
	_flame(fk, tip + Vector3(0, 2.6, 0), flame_h, flame_h * 0.55)
	return tip


## Light pools (additive) on a horizontal deck around `c`.
static func _pool(mk: MeshKit, c: Vector3, r: float, bright: float = 1.0) -> void:
	mk.use("pool")
	var col := Color(bright, bright, bright)
	mk.quad(c + Vector3(-r, 0.08, -r), c + Vector3(r, 0.08, -r), c + Vector3(r, 0.08, r), c + Vector3(-r, 0.08, r), col)


# ------------------------------------------------------------------ main platform

## The start: the Main Platform (accommodation block with a helideck on its roof,
## process modules, derrick, cranes, lifeboats) and, after a truss bridge, the
## Flare Platform whose boom burns out over the Flare Bend.
static func _main_platform(td: TrackData, root: Node3D, fk: MeshKit) -> void:
	var mk := MeshKit.new()
	var ty := td.pos[0].y
	var deck_y := ty - 9.0
	# Rig A, centred behind the line and shifted left of the track.
	var xa := _flat(td, -15.0)
	xa.origin += xa.basis.x * -12.0
	_rig(mk, xa, Vector2(116.0, 250.0), deck_y, Vector2i(3, 4), 0)
	_pedestals(mk, td, td.length - 140.0, td.length - 1.0, deck_y)
	_pedestals(mk, td, 0.0, 108.0, deck_y)
	# xa coordinates: the track centre runs at x = +12, z < 0 is ahead.
	_module(mk, xa, -36.0, 25.0, deck_y, Vector3(28.0, 17.0, 86.0), 1.0, Color(0.88, 0.88, 0.85))
	_module(mk, xa, -38.0, -58.0, deck_y, Vector3(24.0, 10.0, 46.0), 0.5, Color(0.75, 0.38, 0.18))
	_module(mk, xa, 45.0, -72.0, deck_y, Vector3(20.0, 9.0, 40.0), 0.5, Color(0.55, 0.58, 0.6))
	_module(mk, xa, 45.0, 2.0, deck_y, Vector3(20.0, 12.0, 46.0), 0.5, Color(0.8, 0.82, 0.85))
	var heli := _at(xa, -66.0, deck_y + 21.0, 40.0)
	_helipad(mk, heli, 13.0, deck_y + 17.0, xa.basis.x)
	_derrick(mk, _at(xa, 46.0, deck_y, 82.0), 52.0, 12.0)
	_crane(mk, _at(xa, -52.0, deck_y, -112.0), (-xa.basis.x - xa.basis.z).normalized(), 46.0, 38.0)
	_crane(mk, _at(xa, 52.0, deck_y, 112.0), (xa.basis.x + xa.basis.z).normalized(), 40.0, 42.0)
	_used.append(Vector3(_at(xa, -66.0, 0.0, 40.0).x, _at(xa, -66.0, 0.0, 40.0).z, 14.0))
	# Gas turbine exhaust stacks on the process module, lifeboats along the left edge.
	for k in 3:
		var p := _at(xa, 41.0 + k * 4.5, deck_y, -18.0)
		mk.use("steel")
		mk.cyl(p, p + Vector3(0, 30.0, 0), 1.6, 1.6, 10, Color(0.5, 0.5, 0.5))
		mk.use("metal_dark")
		mk.cyl(p + Vector3(0, 30.0, 0), p + Vector3(0, 33.0, 0), 1.7, 1.7, 10, Color.WHITE)
	mk.use("paint_yellow")
	for k in 4:
		var p := _at(xa, -59.5, deck_y - 4.0, -20.0 + k * 13.0)
		mk.box_t(Transform3D(xa.basis, p), Vector3(3.2, 3.2, 9.0), Color(1.6, 0.55, 0.15))
	# Sodium pools on the deck either side of the track.
	for k in 6:
		_pool(mk, _at(xa, -20.0, deck_y, -100.0 + k * 40.0), 12.0)
		_pool(mk, _at(xa, 34.0, deck_y, -100.0 + k * 40.0), 11.0)
	# Truss bridge under the track to the Flare Platform.
	_truss_bridge(mk, td, 108.0, 172.0, 8.0)
	# Rig B: the Flare Platform.
	var xb := _flat(td, 230.0)
	_rig(mk, xb, Vector2(84.0, 120.0), deck_y, Vector2i(2, 3), 0)
	_pedestals(mk, td, 172.0, 288.0, deck_y)
	_flare_boom(mk, fk, _at(xb, -42.0, deck_y + 2.0, 10.0), -xb.basis.x, 112.0, 26.0, 22.0)
	mk.use("steel")
	for k in 3:
		var p := _at(xb, 30.0, deck_y + 4.0, -30.0 + k * 13.0)
		mk.cyl(p - xb.basis.z * 10.0, p + xb.basis.z * 10.0, 3.6, 3.6, 12, Color(0.85, 0.85, 0.82))
	_crane(mk, _at(xb, 34.0, deck_y, 52.0), (xb.basis.x + xb.basis.z * 0.3).normalized(), 38.0, 40.0)
	_used.append(Vector3(_at(xb, 30.0, 0.0, -17.0).x, _at(xb, 30.0, 0.0, -17.0).z, 24.0))
	_clutter(mk, xa, Vector2(116.0, 250.0), deck_y)
	_clutter(mk, xb, Vector2(84.0, 120.0), deck_y)
	for k in 3:
		_pool(mk, _at(xb, -24.0, deck_y, -40.0 + k * 40.0), 11.0)
	root.add_child(_inst(mk, "MainPlatform"))


## A pair of lattice side trusses under the track deck from s0 to s1.
static func _truss_bridge(mk: MeshKit, td: TrackData, s0: float, s1: float, depth: float) -> void:
	var hit := TrackData.Hit.new()
	var prev: Array[Vector3] = []
	var s := s0
	var k := 0
	mk.use("steel")
	var col := Color(0.6, 0.58, 0.52)
	while s <= s1 + 0.1:
		td.frame_at(s, hit)
		var fb := Vector3(hit.B.x, 0, hit.B.z).normalized()
		var top := hit.c - hit.N * TrackMesh.DECK
		var pts: Array[Vector3] = []
		for side: float in [-1.0, 1.0]:
			var t := top + fb * side * (hit.half_r - 1.0)
			pts.append(t)
			pts.append(t - Vector3(0, depth, 0))
		for q: int in [0, 2]:
			_beam(mk, pts[q], pts[q + 1], 0.6, 0.6, col)
		_beam(mk, pts[1], pts[3], 0.5, 0.5, col)
		if not prev.is_empty():
			for q: int in [0, 2]:
				_beam(mk, prev[q], pts[q], 0.7, 0.7, col)
				_beam(mk, prev[q + 1], pts[q + 1], 0.7, 0.7, col)
				if k % 2 == 0:
					_beam(mk, prev[q], pts[q + 1], 0.4, 0.4, col)
				else:
					_beam(mk, prev[q + 1], pts[q], 0.4, 0.4, col)
		prev = pts
		s += 8.0
		k += 1


# ------------------------------------------------------------------ machinery hall

## The Machinery Hall: a steel shed on its own rig that the track runs through.
## Inside: side bays with gas turbines and exhaust ducts, pipes along the walls,
## roof trusses, lamp rows and a gantry crane. Outside: window bands, stacks on
## the roof and a flare tower.
static func _machinery_hall(td: TrackData, root: Node3D, fk: MeshKit) -> void:
	var r := _sec(td, "Machinery Hall")
	if r.x < 0.0:
		return
	var mid := (r.x + r.y) * 0.5
	var xf := _flat(td, mid)
	var ty := xf.origin.y
	var hl := (r.y - r.x) * 0.5 + 1.0
	var hw := td.half_l[int(mid / td.step)] + TrackMesh.WALL_T
	var bay := 11.0
	var wx := hw + bay
	var roof := 13.5
	var b := xf.basis
	_hall_xf = xf
	_hall_ext = Vector3(wx + 2.0, roof + 2.0, hl + 25.0)
	var mk := MeshKit.new()
	var key := int(mid / CELL)
	_rig(mk, xf, Vector2(2.0 * wx + 34.0, 2.0 * hl + 70.0), ty - TrackMesh.DECK - 0.4, Vector2i(2, 5), key)
	var P := func(x: float, y: float, z: float) -> Vector3:
		return _at(xf, x, ty + y, z)
	# Shell: walls and roof are thick boxes; their inner faces are the hall.
	# Outside: grey-green cladding.
	var clad := Color(0.42, 0.47, 0.45)
	mk.use("steel")
	for sx: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(b, P.call(sx * (wx + 0.6), roof * 0.5 - 1.0, 0.0)), Vector3(1.2, roof + 2.4, 2.0 * hl), clad)
	mk.box_t(Transform3D(b, P.call(0.0, roof + 0.7, 0.0)), Vector3(2.0 * wx + 2.4, 1.4, 2.0 * hl), clad * 0.8)
	# End walls around the portals.
	var open_w := hw + 1.5
	var open_h := 12.5
	for sz: float in [-1.0, 1.0]:
		var z := sz * (hl - 0.6)
		mk.use("steel")
		for sx: float in [-1.0, 1.0]:
			mk.box_t(Transform3D(b, P.call(sx * (open_w + wx) * 0.5, roof * 0.5 - 1.0, z)), Vector3(wx - open_w + 1.2, roof + 2.4, 1.2), clad)
		mk.box_t(Transform3D(b, P.call(0.0, (open_h + roof) * 0.5 + 0.6, z)), Vector3(2.0 * open_w, roof - open_h + 1.2, 1.2), clad)
		# Sodium strip round the portal.
		mk.use("sodium")
		var zz := sz * (hl + 0.05)
		mk.box_t(Transform3D(b, P.call(0.0, open_h + 0.3, zz)), Vector3(2.0 * open_w, 0.35, 0.2), Color.WHITE)
		for sx: float in [-1.0, 1.0]:
			mk.box_t(Transform3D(b, P.call(sx * open_w, open_h * 0.5, zz)), Vector3(0.35, open_h, 0.2), Color.WHITE)
	# Inside: lit lining on the walls and the ceiling, facing the track.
	mk.use("hall")
	var y0 := -1.0
	var lz := hl - 1.2
	var lx := wx - 0.05
	var ly := roof - 0.05
	for sx: float in [-1.0, 1.0]:
		var a: Vector3 = P.call(sx * lx, y0, -lz)
		var b2: Vector3 = P.call(sx * lx, ly, -lz)
		var c2: Vector3 = P.call(sx * lx, ly, lz)
		var d2: Vector3 = P.call(sx * lx, y0, lz)
		if sx > 0.0:
			mk.quad(a, b2, c2, d2, Color(0.95, 0.95, 0.95))
		else:
			mk.quad(a, d2, c2, b2, Color(0.95, 0.95, 0.95))
	mk.quad(P.call(-lx, ly, -lz), P.call(-lx, ly, lz), P.call(lx, ly, lz), P.call(lx, ly, -lz), Color(0.8, 0.8, 0.8))
	# Bay floors beside the barriers.
	mk.use("steel")
	for sx: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(b, P.call(sx * (hw + bay * 0.5), -0.9, 0.0)), Vector3(bay, 0.6, 2.0 * hl), Color(0.3, 0.31, 0.3))
	# Roof trusses, columns, lamp rows and pools on the track.
	var z := -hl + 8.0
	var n := 0
	while z < hl - 4.0:
		mk.use("steel")
		mk.box_t(Transform3D(b, P.call(0.0, roof - 0.6, z)), Vector3(2.0 * wx, 1.2, 0.8), Color(0.5, 0.5, 0.5))
		for sx: float in [-1.0, 1.0]:
			_beam(mk, P.call(sx * wx, roof - 0.6, z), P.call(sx * wx * 0.45, roof - 3.0, z), 0.5, 0.5, Color(0.5, 0.5, 0.5))
			_beam(mk, P.call(sx * wx * 0.45, roof - 3.0, z), P.call(0.0, roof - 0.6, z), 0.5, 0.5, Color(0.5, 0.5, 0.5))
			mk.box_t(Transform3D(b, P.call(sx * (wx - 0.6), roof * 0.5 - 1.0, z)), Vector3(0.9, roof + 2.0, 0.9), Color(0.45, 0.46, 0.46))
		if n % 2 == 0:
			mk.use("lamp")
			for x: float in [-9.0, 0.0, 9.0]:
				mk.box_t(Transform3D(b, P.call(x, roof - 1.4, z + 8.0)), Vector3(0.6, 0.25, 7.0), Color.WHITE)
			mk.use("pool")
			for x: float in [-7.0, 7.0]:
				var c: Vector3 = P.call(x, 0.07, z + 8.0)
				var rr := 9.0
				mk.quad(c - b.x * rr - b.z * rr, c + b.x * rr - b.z * rr, c + b.x * rr + b.z * rr, c - b.x * rr + b.z * rr, Color(1.1, 1.3, 1.6))
		z += 16.0
		n += 1
	# Pipes along the walls with flanges.
	var pipes := [[wx - 1.3, 3.0, 0.7, Color(0.9, 0.65, 0.1)], [wx - 1.3, 6.2, 0.9, Color(0.25, 0.5, 0.3)], [wx - 2.8, 9.8, 0.55, Color(0.6, 0.6, 0.62)]]
	for sx: float in [-1.0, 1.0]:
		for pd: Array in pipes:
			var px: float = pd[0]
			var py: float = pd[1]
			var pr: float = pd[2]
			var pc: Color = pd[3]
			mk.use("steel")
			mk.cyl(P.call(sx * px, py, -hl + 1.0), P.call(sx * px, py, hl - 1.0), pr, pr, 8, pc, false)
			var fz := -hl + 6.0
			while fz < hl - 2.0:
				mk.cyl(P.call(sx * px, py, fz), P.call(sx * px, py, fz + 0.5), pr * 1.35, pr * 1.35, 8, pc * 0.8, false)
				fz += 24.0
	# Gas turbine units in the bays, alternating sides, with ducts to the roof.
	var tz := -hl + 30.0
	var side := 1.0
	while tz < hl - 25.0:
		var cx := side * (hw + 5.6)
		mk.use("steel")
		mk.box_t(Transform3D(b, P.call(cx, 0.2, tz)), Vector3(8.5, 1.0, 20.0), Color(0.3, 0.3, 0.3))
		mk.cyl(P.call(cx, 4.0, tz - 8.0), P.call(cx, 4.0, tz + 8.0), 3.2, 2.6, 14, Color(0.3, 0.42, 0.36))
		mk.box_t(Transform3D(b, P.call(cx, 3.6, tz + 11.0)), Vector3(7.0, 6.4, 4.0), Color(0.55, 0.57, 0.55))
		mk.cyl(P.call(cx, 6.8, tz - 5.0), P.call(cx, roof + 1.0, tz - 5.0), 1.8, 1.8, 10, Color(0.62, 0.6, 0.58))
		mk.use("heli")
		mk.box_t(Transform3D(b, P.call(cx - side * 3.7, 3.8, tz + 11.0)), Vector3(0.2, 0.4, 0.8), Color.WHITE)
		mk.use("warn_red")
		mk.box_t(Transform3D(b, P.call(cx - side * 3.7, 4.8, tz + 11.0)), Vector3(0.2, 0.4, 0.4), Color.WHITE)
		# Exhaust stack above the roof.
		mk.use("steel")
		mk.cyl(P.call(cx, roof + 1.0, tz - 5.0), P.call(cx, roof + 16.0, tz - 5.0), 2.0, 1.8, 10, Color(0.55, 0.55, 0.53))
		mk.use("metal_dark")
		mk.cyl(P.call(cx, roof + 16.0, tz - 5.0), P.call(cx, roof + 18.0, tz - 5.0), 1.9, 1.9, 10, Color.WHITE)
		mk.use("beacon")
		mk.box_t(Transform3D(b, P.call(cx, roof + 18.6, tz - 5.0)), Vector3(0.8, 0.8, 0.8), Color(0.6, 0, 0))
		tz += 58.0
		side = -side
	# Gantry crane girder across the middle.
	mk.use("paint_yellow")
	mk.box_t(Transform3D(b, P.call(0.0, roof - 2.6, 20.0)), Vector3(2.0 * wx - 2.0, 1.4, 2.0), Color.WHITE)
	mk.box_t(Transform3D(b, P.call(4.0, roof - 4.0, 20.0)), Vector3(3.0, 1.6, 2.6), Color.WHITE)
	# Lamps along the roof edges, washing the cladding below them.
	var ez := -hl + 10.0
	while ez < hl - 5.0:
		for sx: float in [-1.0, 1.0]:
			mk.use("sodium")
			mk.box_t(Transform3D(b, P.call(sx * (wx + 1.6), roof + 0.6, ez)), Vector3(0.6, 0.4, 1.2), Color.WHITE)
			mk.use("pool")
			var wc: Vector3 = P.call(sx * (wx + 1.3), roof - 6.0, ez)
			var up := Vector3(0, 7.5, 0)
			var al := b.z * 11.0
			mk.quad(wc - al - up, wc + al - up, wc + al + up, wc - al + up, Color(0.5, 0.5, 0.5))
		ez += 24.0
	# Window bands outside and a flare tower at the far corner.
	for sx: float in [-1.0, 1.0]:
		mk.use("bld")
		mk.box_t(Transform3D(b, P.call(sx * (wx + 1.25), 6.0, 0.0)), Vector3(0.1, 5.0, 2.0 * hl - 20.0), Color(0.6, 0.62, 0.66, 0.5))
	var ft: Vector3 = P.call(-(wx + 12.0), -TrackMesh.DECK - 0.4, -hl - 20.0)
	_derrick(mk, ft, 62.0, 7.0)
	_flame(fk, ft + Vector3(0, 64.0, 0), 14.0, 8.0)
	root.add_child(_inst(mk, "MachineryHall"))


# ------------------------------------------------------------------ gasholder

## Centre (x, z) and mean radius of the Gasholder Spiral, from its middle 360 degrees.
static func _spiral_centre(td: TrackData) -> Vector3:
	var r := _sec(td, "Gasholder Spiral")
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	var a := i0 + (i1 - i0) / 10
	var b := i1 - (i1 - i0) / 10
	var c := Vector3.ZERO
	var n := 0
	for i in range(a, b):
		c += td.pos[i]
		n += 1
	c /= maxf(n, 1)
	var rad := 0.0
	for i in range(a, b, 10):
		rad += Vector2(td.pos[i].x - c.x, td.pos[i].z - c.z).length()
	rad /= maxf(float(b - a) / 10.0, 1.0)
	return Vector3(c.x, rad, c.z)


## The gasholder inside the spiral: tank and dome in a lattice guide frame on a
## round platform, a flare stack on the crown, radial arms carrying the deck.
static func _gasholder(td: TrackData, root: Node3D, fk: MeshKit) -> void:
	var sp := _sec(td, "Gasholder Spiral")
	if sp.x < 0.0:
		return
	var cr := _spiral_centre(td)
	var c := Vector3(cr.x, 0.0, cr.z)
	var mk := MeshKit.new()
	var key := int(sp.x / CELL)
	var base := 16.0
	var tank_r := 74.0
	var frame_r := 80.0
	var top := 86.0
	_rig(mk, Transform3D(Basis.IDENTITY, c), Vector2(176.0, 176.0), base, Vector2i(3, 3), key)
	# Tank with vertical stiffeners, a pale band, and the dome.
	mk.use("steel")
	HelixBay.prism(mk, c + Vector3(0, base, 0), tank_r, 28, top - base, Color(0.5, 0.55, 0.52, 0.0), -1.0, 0.0, false)
	HelixBay.prism(mk, c + Vector3(0, top - 9.0, 0), tank_r + 0.3, 28, 4.0, Color(0.85, 0.82, 0.72, 0.0), -1.0, 0.0, false)
	var dome := PackedVector2Array()
	for k in 9:
		var a := PI * 0.5 * k / 8.0
		dome.append(Vector2(cos(a) * tank_r, top + sin(a) * 11.0))
	mk.lathe_at(Transform3D(Basis.IDENTITY, c), dome, 28, Color(0.46, 0.5, 0.48))
	# Guide frame: columns, ring girders, crossed bracing.
	var cols := 16
	var rings := [base + 2.0, 40.0, 62.0, top, top + 14.0]
	var col := Color(0.62, 0.6, 0.55)
	for k in cols:
		var a := TAU * k / cols
		var d := Vector3(cos(a), 0, sin(a))
		_beam(mk, c + d * frame_r + Vector3(0, base, 0), c + d * frame_r + Vector3(0, top + 14.0, 0), 1.6, 1.6, col)
		for ri in rings.size() - 1:
			var a2 := TAU * (k + 1) / cols
			var d2 := Vector3(cos(a2), 0, sin(a2))
			var y0: float = rings[ri]
			var y1: float = rings[ri + 1]
			if (k + ri) % 2 == 0:
				_beam(mk, c + d * frame_r + Vector3(0, y0, 0), c + d2 * frame_r + Vector3(0, y1, 0), 0.5, 0.5, col)
			else:
				_beam(mk, c + d2 * frame_r + Vector3(0, y0, 0), c + d * frame_r + Vector3(0, y1, 0), 0.5, 0.5, col)
	for y: float in rings:
		mk.torus(c + Vector3(0, y, 0), Vector3.UP, frame_r, 0.9, 64, 4, col)
	mk.use("sodium")
	for k in cols:
		var a := TAU * (k + 0.5) / cols
		var d := Vector3(cos(a), 0, sin(a))
		for y: float in [40.0, 62.0]:
			mk.box(c + d * (frame_r + 1.2) + Vector3(0, y + 1.0, 0), Vector3(0.8, 0.5, 0.8), Color.WHITE)
	# Washes of sodium light on the tank under the lamps.
	mk.use("pool")
	for k in cols:
		var a := TAU * (k + 0.5) / cols
		var d := Vector3(cos(a), 0, sin(a))
		var t := Vector3(-d.z, 0, d.x)
		for y: float in [40.0, 62.0]:
			var p := c + d * (tank_r + 0.4) + Vector3(0, y - 7.0, 0)
			mk.quad(p - t * 17.0 - Vector3(0, 13, 0), p + t * 17.0 - Vector3(0, 13, 0), p + t * 17.0 + Vector3(0, 13, 0), p - t * 17.0 + Vector3(0, 13, 0), Color(0.36, 0.36, 0.36))
	mk.use("beacon")
	for k in 4:
		var a := TAU * k / 4.0
		mk.box(c + Vector3(cos(a), 0, sin(a)) * frame_r + Vector3(0, top + 15.4, 0), Vector3(1.0, 1.0, 1.0), Color(0.1, 0, 0))
	# Flare stack on the crown.
	_derrick(mk, c + Vector3(0, top + 10.0, 0), 46.0, 6.0)
	_flame(fk, c + Vector3(0, top + 58.0, 0), 16.0, 9.0)
	# Radial arms under the deck every 32 m, each a beam with a strut below.
	var hit := TrackData.Hit.new()
	var s := sp.x + 12.0
	mk.use("steel")
	while s < sp.y - 6.0:
		td.frame_at(s, hit)
		var under := hit.c - hit.N * (TrackMesh.DECK + 0.6)
		var flat := Vector3(under.x - c.x, 0, under.z - c.z)
		var dir := flat.normalized()
		var root_p := c + dir * frame_r + Vector3(0, under.y - 1.0, 0)
		_beam(mk, root_p, under + Vector3(0, -1.0, 0) + dir * 4.0, 1.8, 2.2, col)
		var strut := Vector3(root_p.x, maxf(root_p.y - 16.0, base + 1.0), root_p.z)
		_beam(mk, strut, root_p.lerp(under, 0.62) - Vector3(0, 1.0, 0), 1.0, 1.0, col)
		var fb := Vector3(hit.B.x, 0, hit.B.z).normalized()
		mk.box_t(Transform3D(Basis(fb, Vector3.UP, fb.cross(Vector3.UP)), under - Vector3(0, 1.0, 0)), Vector3(hit.half_l + hit.half_r - 1.0, 1.4, 2.4), col)
		mk.use("sodium")
		mk.box(root_p + Vector3(0, -1.6, 0), Vector3(0.7, 0.5, 0.7), Color.WHITE)
		mk.use("steel")
		s += 32.0
	root.add_child(_inst(mk, "Gasholder"))


# ------------------------------------------------------------------ jump

## Lap range of the jump gap (F_GAP samples).
static func _gap_range(td: TrackData) -> Vector2:
	var g0 := -1.0
	var g1 := -1.0
	for i in td.count:
		if td.flag_at_index(i, TrackData.F_GAP):
			if g0 < 0.0:
				g0 = i * td.step
			g1 = i * td.step
	return Vector2(g0, g1)


## The take-off rig at the foot of the Crown Descent, a flare burning in the gap
## below the jump, and the Helideck platform the ships land on.
static func _jump_rigs(td: TrackData, root: Node3D, fk: MeshKit) -> void:
	var g := _gap_range(td)
	if g.x < 0.0:
		return
	var mk := MeshKit.new()
	var key := int(g.x / CELL)
	var hit := TrackData.Hit.new()
	# Take-off rig: its front edge is the lip.
	var xt := _flat(td, g.x - 86.0)
	var deck_t := xt.origin.y - 8.0
	_rig(mk, xt, Vector2(72.0, 172.0), deck_t, Vector2i(2, 3), key)
	_pedestals(mk, td, g.x - 170.0, g.x - 4.0, deck_t)
	_module(mk, xt, -28.0, 30.0, deck_t, Vector3(14.0, 8.0, 30.0), 0.5, Color(0.75, 0.4, 0.2))
	_crane(mk, _at(xt, 28.0, deck_t, 60.0), (xt.basis.x + xt.basis.z * 0.4).normalized(), 34.0, 40.0)
	_clutter(mk, xt, Vector2(72.0, 172.0), deck_t, 0.7)
	# Hazard lights along the lip.
	td.frame_at(g.x, hit)
	mk.use("warn_red")
	for k in 9:
		var d := lerpf(-hit.half_l, hit.half_r, k / 8.0)
		mk.box_t(Transform3D(Basis(hit.B, hit.N, -hit.T), hit.c + hit.B * d - hit.N * 0.9 + hit.T * 0.3), Vector3(0.9, 0.5, 0.3), Color.WHITE)
	# Flare stack in the gap, its flame well below the flight path.
	td.frame_at((g.x + g.y) * 0.5, hit)
	var fb := Vector3(hit.c.x, 0, hit.c.z) + Vector3(hit.B.x, 0, hit.B.z).normalized() * 6.0
	var stack_top := hit.c.y - 26.0
	_lattice_tower(mk, Vector3(fb.x, stack_top, fb.z), Vector3(hit.B.x, 0, hit.B.z).normalized(), Vector3(hit.T.x, 0, hit.T.z).normalized(), 1.6, 1.6, stack_top)
	mk.use("metal_dark")
	mk.cyl(Vector3(fb.x, stack_top, fb.z), Vector3(fb.x, stack_top + 3.0, fb.z), 1.6, 1.2, 8, Color.WHITE)
	_flame(fk, Vector3(fb.x, stack_top + 2.6, fb.z), 15.0, 9.0)
	# Helideck platform: two rigs following the landing and the first ess.
	var deck_h := hit.c.y - 14.0
	var x1 := _flat(td, g.y + 82.0)
	_rig(mk, x1, Vector2(96.0, 164.0), deck_h, Vector2i(2, 3), key)
	var ess := _sec(td, "Helideck Esses")
	var x2 := _flat(td, ess.x + 110.0)
	_rig(mk, x2, Vector2(96.0, 200.0), deck_h, Vector2i(2, 3), key)
	_pedestals(mk, td, g.y + 4.0, ess.x + 220.0, deck_h)
	for sx: float in [-1.0, 1.0]:
		var hp := _at(x1, sx * 60.0, deck_h + 5.0, 20.0)
		if _occ.clear(hp, 14.0, deck_h, deck_h + 6.0, 2.0):
			_helipad(mk, hp, 13.0, deck_h, -x1.basis.x * sx)
			_used.append(Vector3(hp.x, hp.z, 16.0))
	_module(mk, x2, -36.0, 40.0, deck_h, Vector3(18.0, 11.0, 36.0), 1.0, Color(0.85, 0.85, 0.82))
	_module(mk, x2, 38.0, -30.0, deck_h, Vector3(16.0, 8.0, 30.0), 0.5, Color(0.5, 0.55, 0.62))
	_crane(mk, _at(x2, 40.0, deck_h, 70.0), (x2.basis.x + x2.basis.z * 0.3).normalized(), 36.0, 45.0)
	_clutter(mk, x1, Vector2(96.0, 164.0), deck_h, 0.45)
	_clutter(mk, x2, Vector2(96.0, 200.0), deck_h, 0.6)
	for k in 4:
		_pool(mk, _at(x1, -30.0, deck_h, -60.0 + k * 40.0), 11.0)
		_pool(mk, _at(x2, 30.0, deck_h, -80.0 + k * 50.0), 11.0)
	root.add_child(_inst(mk, "JumpRigs"))


# ------------------------------------------------------------------ wind farm

## Offshore wind farm around the Turbine Kinks: instanced towers, nacelles,
## spinning rotors (turbine_rotor shader) and synchronised red lights.
static func _wind_farm(td: TrackData, root: Node3D) -> void:
	var kinks := _sec(td, "Turbine Kinks")
	if kinks.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at((kinks.x + kinks.y) * 0.5, hit)
	var centre := Vector3(hit.c.x, 0, hit.c.z)
	var w := WIND.normalized()
	var across := Vector3(-w.z, 0, w.x)
	var spacing := 230.0
	var density := float(Quality.p["city"])
	var xfs: Array[Transform3D] = []
	var gas := _spiral_centre(td)
	# The farm lies outside the circuit, beyond the causeway and the kinks:
	# keep sites farther from the circuit's middle than the kinks are.
	var mid := Vector3.ZERO
	for i in range(0, td.count, 20):
		mid += td.pos[i]
	mid /= float((td.count + 19) / 20)
	mid.y = 0.0
	var reach := centre.distance_to(mid)
	for j in range(-5, 6):
		for i in range(-7, 8):
			var p := centre + across * (i * spacing + (j % 2) * spacing * 0.5) + w * (j * spacing * 0.9)
			p += Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))
			if p.distance_to(centre) > 1250.0 or p.distance_to(mid) < reach - 60.0:
				continue
			if _occ.dist(p, 120.0) < 95.0:
				continue
			if Vector2(p.x - gas.x, p.z - gas.z).length() < 330.0:
				continue
			if rng.randf() > density:
				continue      # thinner farm on the lower presets
			var sc := rng.randf_range(0.92, 1.08)
			xfs.append(Transform3D(Basis.looking_at(-w, Vector3.UP).scaled(Vector3(sc, sc, sc)), p))
	if xfs.is_empty():
		return
	var mk := MeshKit.new()
	mk.use("steel")
	mk.cyl(Vector3(0, SEA_FLOOR, 0), Vector3(0, 14.0, 0), 3.4, 3.4, 10, Color(0.9, 0.7, 0.1), false)
	mk.cyl(Vector3(0, -2.0, 0), Vector3(0, SWELL_AMP + 2.0, 0), 3.55, 3.55, 10, Color(0.15, 0.15, 0.13), false)
	mk.box(Vector3(0, 14.4, 0), Vector3(9.0, 0.8, 9.0), Color(0.5, 0.5, 0.48))
	mk.cyl(Vector3(0, 14.0, 0), Vector3(0, 96.0, 0), 2.9, 1.8, 10, Color(0.86, 0.87, 0.88), false)
	mk.box(Vector3(0, 98.0, 2.0), Vector3(4.2, 4.4, 13.0), Color(0.86, 0.87, 0.88))
	mk.sphere(Vector3(0, 98.0, -5.6), Vector3(2.2, 2.2, 2.6), 4, 8, Color(0.86, 0.87, 0.88))
	mk.use("beacon")
	mk.box(Vector3(0, 100.6, 6.5), Vector3(0.9, 0.7, 0.9), Color(0, 0, 0))
	var tower := mk.commit(_mat)
	var rk := MeshKit.new()
	rk.use("rotor")
	for k in 3:
		var a := TAU * k / 3.0
		var d := Vector3(cos(a), sin(a), 0)
		var t := Vector3(-d.y, d.x, 0)
		var r0 := d * 2.0
		var r1 := d * 56.0
		rk.quad(r0 - t * 1.8, r0 + t * 1.4, r1 + t * 0.25, r1 - t * 0.35, Color.WHITE)
	var rotor := rk.commit({"rotor": Mats.shader_mat("turbine_rotor")})
	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.mesh = tower
	mm_t.instance_count = xfs.size()
	var mm_r := MultiMesh.new()
	mm_r.transform_format = MultiMesh.TRANSFORM_3D
	mm_r.use_custom_data = true
	mm_r.mesh = rotor
	mm_r.instance_count = xfs.size()
	for k in xfs.size():
		mm_t.set_instance_transform(k, xfs[k])
		var hub := xfs[k] * Transform3D(Basis.IDENTITY, Vector3(0, 98.0, -6.4))
		mm_r.set_instance_transform(k, hub)
		mm_r.set_instance_custom_data(k, Color(rng.randf(), rng.randf(), 0, 0))
	for pair: Array in [[mm_t, "WindTowers"], [mm_r, "WindRotors"]]:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = pair[1]
		mmi.multimesh = pair[0]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	if DevArgs.has("--load-times"):
		print("offshore turbines %d" % xfs.size())


# ------------------------------------------------------------------ lighthouse

## A lighthouse on a rocky shoal outside the Lighthouse Turn, its beam sweeping.
static func _lighthouse(td: TrackData, root: Node3D) -> void:
	var lt := _sec(td, "Lighthouse Turn")
	if lt.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at((lt.x + lt.y) * 0.5, hit)
	var out := -Vector3(hit.B.x, 0, hit.B.z).normalized()
	var c := Vector3(hit.c.x, 0, hit.c.z) + out * 560.0
	var mk := MeshKit.new()
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.9
	mk.use("rock")
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.3, 0.3)
		var d := 0.0 if k == 0 else rng.randf_range(25.0, 70.0)
		var rc := c + Vector3(cos(a), 0, sin(a)) * d
		var rr := rng.randf_range(10.0, 22.0) * (1.6 if k == 0 else 1.0)
		mk.blob(rc + Vector3(0, -2.0, 0), Vector3(rr, rr * 0.45 + (6.0 if k == 0 else 0.0), rr * 0.9), 2, noise, 0.35, Color(0.32, 0.33, 0.32), Color(0.1, 0.11, 0.1), true, Vector3(k, 0, 0))
	var foot := c + Vector3(0, 9.0, 0)
	# Tower: white with two red bands, gallery, lantern and cap.
	var bands := [[0.0, 10.0, Color(0.9, 0.9, 0.88)], [10.0, 16.0, Color(0.75, 0.12, 0.1)], [16.0, 26.0, Color(0.9, 0.9, 0.88)], [26.0, 32.0, Color(0.75, 0.12, 0.1)], [32.0, 38.0, Color(0.9, 0.9, 0.88)]]
	mk.use("steel")
	for bd: Array in bands:
		var y0: float = bd[0]
		var y1: float = bd[1]
		var bc: Color = bd[2]
		mk.cyl(foot + Vector3(0, y0, 0), foot + Vector3(0, y1, 0), lerpf(6.0, 3.8, y0 / 38.0), lerpf(6.0, 3.8, y1 / 38.0), 16, bc, false)
	mk.cyl(foot + Vector3(0, 38.0, 0), foot + Vector3(0, 39.0, 0), 5.6, 5.6, 16, Color(0.2, 0.2, 0.2))
	mk.use("lamp")
	mk.cyl(foot + Vector3(0, 39.0, 0), foot + Vector3(0, 43.0, 0), 3.0, 3.0, 12, Color.WHITE, false)
	mk.use("steel")
	mk.cyl(foot + Vector3(0, 43.0, 0), foot + Vector3(0, 46.5, 0), 3.4, 0.4, 12, Color(0.75, 0.12, 0.1))
	HelixBay.block(mk, foot + Vector3(14.0, -2.0, 6.0), Vector3(12.0, 6.0, 9.0), Color(0.85, 0.85, 0.82))
	# Lit windows up the tower, a lamp over the keeper's door and its pool.
	mk.use("lamp")
	for k in 4:
		var a := 1.3 * k
		var y := 6.0 + k * 8.0
		var rr := lerpf(6.0, 3.8, y / 38.0) + 0.05
		mk.box_t(Transform3D(Basis(Vector3.UP, -a), foot + Vector3(cos(a) * rr, y, sin(a) * rr)), Vector3(0.9, 1.6, 0.2), Color.WHITE)
	mk.use("sodium")
	mk.box(foot + Vector3(14.0, 2.6, 10.6), Vector3(0.6, 0.4, 0.4), Color.WHITE)
	_pool(mk, foot + Vector3(14.0, -2.2, 14.0), 9.0)
	root.add_child(_inst(mk, "Lighthouse"))
	# The beam: two long additive cones on a spinning pivot.
	var pivot := Node3D.new()
	pivot.name = "LighthouseBeam"
	pivot.position = foot + Vector3(0, 41.0, 0)
	var bk := MeshKit.new()
	bk.use("beam")
	for sgn: float in [-1.0, 1.0]:
		bk.cyl(Vector3.ZERO, Vector3(sgn * 320.0, -10.0, 0), 1.2, 24.0, 10, Color(0.8, 0.75, 0.55), false, Color(0, 0, 0))
	var bm := _inst(bk, "Beam", false)
	pivot.add_child(bm)
	var spin := Spin.new()
	spin.target = pivot
	spin.rate = 0.9
	pivot.add_child(spin)
	root.add_child(pivot)


## Turns a node about Y.
class Spin extends Node:
	var target: Node3D
	var rate: float = 0.5

	func _process(delta: float) -> void:
		if target:
			target.rotate_y(delta * rate)


# ------------------------------------------------------------------ distant rigs

## Production platforms on the horizon: lit decks, derricks and flares.
static func _distant_rigs(td: TrackData, root: Node3D, fk: MeshKit) -> void:
	var lo := td.pos[0]
	var hi := td.pos[0]
	for i in range(0, td.count, 10):
		lo = lo.min(td.pos[i])
		hi = hi.max(td.pos[i])
	var mid := Vector3((lo.x + hi.x) * 0.5, 0, (lo.z + hi.z) * 0.5)
	var rad := Vector2(hi.x - lo.x, hi.z - lo.z).length() * 0.5
	var mk := MeshKit.new()
	var count := clampi(int(round(6.0 * float(Quality.p["city"]))), 3, 6)
	for k in count:
		var a := TAU * k / count + 0.4 + rng.randf_range(-0.25, 0.25)
		var c := mid + Vector3(cos(a), 0, sin(a)) * (rad + rng.randf_range(700.0, 1600.0))
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c)
		var deck_y := rng.randf_range(24.0, 34.0)
		var size := Vector2(rng.randf_range(60.0, 90.0), rng.randf_range(80.0, 130.0))
		_rig(mk, xf, size, deck_y, Vector2i(2, 2))
		mk.use("bld")
		mk.box_t(Transform3D(xf.basis, _at(xf, -size.x * 0.2, deck_y + 9.0, size.y * 0.15)), Vector3(size.x * 0.45, 18.0, size.y * 0.5), Color(0.85, 0.85, 0.82, 1.0))
		mk.box_t(Transform3D(xf.basis, _at(xf, size.x * 0.25, deck_y + 5.0, -size.y * 0.2)), Vector3(size.x * 0.3, 10.0, size.y * 0.35), Color(0.7, 0.4, 0.2, 0.5))
		_derrick(mk, _at(xf, size.x * 0.25, deck_y, size.y * 0.3), 48.0, 10.0)
		_flare_boom(mk, fk, _at(xf, -size.x * 0.5, deck_y + 2.0, -size.y * 0.3), -xf.basis.x, 70.0, 30.0, 20.0)
	var mi := _inst(mk, "DistantRigs", false)
	mi.visibility_range_end = 6000.0
	root.add_child(mi)


# ------------------------------------------------------------------ spray

## Spray where the swell breaks on the piers: one emitter per cell, spawning
## at that cell's pier feet (emission points), so mist rises at the legs.
static func _spray(root: Node3D) -> void:
	var factor := float(Quality.p["particles"])
	for key: int in _spray_pts:
		var pts: PackedVector3Array = _spray_pts[key]
		if pts.size() < 2:
			continue
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var img := Image.create(pts.size(), 1, false, Image.FORMAT_RGBF)
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for k in pts.size():
			var q := pts[k] - c
			img.set_pixel(k, 0, Color(q.x, q.y, q.z))
			lo = lo.min(q)
			hi = hi.max(q)
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		pm.emission_point_texture = ImageTexture.create_from_image(img)
		pm.emission_point_count = pts.size()
		pm.direction = Vector3(WIND.x * 0.4, 1.0, WIND.z * 0.4)
		pm.spread = 35.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 8.0
		pm.gravity = Vector3(WIND.x * 3.0, -2.5, WIND.z * 3.0)
		pm.scale_min = 0.9
		pm.scale_max = 2.2
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.0))
		fade.add_point(0.15, Color(1, 1, 1, 0.5))
		fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = fade
		pm.color_ramp = gt
		var p := GPUParticles3D.new()
		p.name = "Spray%02d" % key
		p.amount = maxi(8, int(pts.size() * 3 * factor))
		p.lifetime = 2.2
		p.preprocess = 2.2
		p.position = c + Vector3(0, SWELL_AMP * 0.5, 0)
		p.process_material = pm
		p.visibility_aabb = AABB(lo - Vector3(20, 5, 20), hi - lo + Vector3(40, 40, 40))
		var qm := QuadMesh.new()
		qm.size = Vector2(8.0, 8.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = Mats.tex("smoke")
		mat.albedo_color = Color(0.36, 0.4, 0.43, 0.3)
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.material = mat
		p.draw_pass_1 = qm
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)


# ------------------------------------------------------------------ rain

## Wind-driven rain streaks in a box ahead of the active camera.
static func _rain(root: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = int(1900 * float(Quality.p["particles"]))
	p.lifetime = 1.2
	p.preprocess = 1.2
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-150, -80, -150), Vector3(300, 160, 300))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32, 16, 44)
	pm.direction = Vector3(WIND.x * 0.38, -1.0, WIND.z * 0.38)
	pm.spread = 4.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 33.0
	pm.gravity = Vector3(WIND.x * 3.0, -6.0, WIND.z * 3.0)
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 1.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.72, 0.78, 0.86, 0.34)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	var follow := RainFollow.new()
	follow.particles = p
	root.add_child(follow)


## Keeps the rain box around and just ahead of the active camera, so the
## streaks pass close enough to read even while the grid waits.
class RainFollow extends Node:
	var particles: GPUParticles3D

	func _process(_d: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam and particles:
			particles.global_position = cam.global_position + Vector3(0, 11, 0) - cam.global_transform.basis.z * 20.0
			# No rain under the Machinery Hall roof (or just before its portals).
			var dry := Offshore.under_roof(cam.global_position)
			particles.emitting = not dry
			particles.visible = not dry


# ------------------------------------------------------------------ lightning

## The bolt (two ribbons and a branch, local XY plane, foot at the origin) and
## a glow card in the cloud base, as one additive mesh.
static func _bolt_mesh() -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("bolt")
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var pts := PackedVector3Array()
	var p := Vector3(0, 620, 0)
	while p.y > 0.0:
		pts.append(p)
		p += Vector3(r.randf_range(-28.0, 28.0), -r.randf_range(26.0, 48.0), 0.0)
	pts.append(Vector3(p.x, -2.0, 0.0))
	_ribbon(mk, pts, 12.0, 1.0)
	var br := PackedVector3Array()
	var q := pts[5]
	for k in 7:
		br.append(q)
		q += Vector3(r.randf_range(12.0, 40.0), -r.randf_range(20.0, 40.0), 0.0)
	_ribbon(mk, br, 7.0, 0.55)
	# Glow card at the cloud base (COLOR.a = 0: radial falloff).
	var gc := Vector3(0, 640, -20)
	var gw := 1500.0
	var gh := 700.0
	mk.quad(gc + Vector3(-gw * 0.5, -gh * 0.5, 0), gc + Vector3(gw * 0.5, -gh * 0.5, 0), gc + Vector3(gw * 0.5, gh * 0.5, 0), gc + Vector3(-gw * 0.5, gh * 0.5, 0), Color(1, 1, 1, 0))
	var mat := Mats.shader_mat("lightning")
	return mk.commit({"bolt": mat})


static func _ribbon(mk: MeshKit, pts: PackedVector3Array, w: float, bright: float) -> void:
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var side := (b - a).cross(Vector3(0, 0, 1)).normalized() * w * 0.5
		var i0 := mk._vert(a - side, Vector3(0, 0, 1), Color(bright, 1, 1, 1), Vector2(0, 0))
		var i1 := mk._vert(a + side, Vector3(0, 0, 1), Color(bright, 1, 1, 1), Vector2(1, 0))
		var i2 := mk._vert(b + side, Vector3(0, 0, 1), Color(bright, 1, 1, 1), Vector2(1, 1))
		var i3 := mk._vert(b - side, Vector3(0, 0, 1), Color(bright, 1, 1, 1), Vector2(0, 1))
		mk._quad_i(i0, i1, i2, i3)


static func _storm(root: Node3D, env: Environment, sea: ShaderMaterial) -> void:
	var flash := DirectionalLight3D.new()
	flash.name = "LightningLight"
	flash.light_color = Color(0.78, 0.84, 1.0)
	flash.light_energy = 0.0
	flash.light_specular = 0.05
	flash.shadow_enabled = false
	root.add_child(flash)
	var bolt := MeshInstance3D.new()
	bolt.name = "Lightning"
	bolt.mesh = _bolt_mesh()
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.extra_cull_margin = 100.0
	root.add_child(bolt)
	var st := Storm.new()
	st.name = "Storm"
	st.env = env
	st.light = flash
	st.bolt = bolt
	st.bolt_mat = bolt.mesh.surface_get_material(0) as ShaderMaterial
	st.sea = sea
	st.fog_base = env.fog_light_color if env else FOG
	st.ambient_base = env.ambient_light_energy if env else 0.5
	for a in DevArgs.all():
		if a.begins_with("--strike-at="):
			for v in a.substr(12).split(","):
				st.forced.append(float(v))
	st.thunder = AudioStreamPlayer.new()
	st.thunder.name = "Thunder"
	st.thunder.stream = _thunder_stream()
	st.thunder.bus = "SFX"
	st.add_child(st.thunder)
	var rain := AudioStreamPlayer.new()
	rain.name = "RainHiss"
	rain.stream = _rain_stream()
	rain.bus = "SFX"
	rain.volume_db = -20.0
	rain.autoplay = true
	st.add_child(rain)
	root.add_child(st)


## Thunder, synthesised once: a short crack of white noise, then a rumble of
## low-passed brown noise that swells and dies away over three seconds.
static func _thunder_stream() -> AudioStreamWAV:
	var rate := 16000
	var n := int(rate * 3.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 515
	var brown := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var w := r.randf_range(-1.0, 1.0)
		brown = clampf(brown * 0.996 + w * 0.08, -1.0, 1.0)
		lp += (brown - lp) * 0.12
		lp2 += (lp - lp2) * 0.12
		var crack := w * exp(-t * 22.0) * 0.5
		var env := (1.0 - exp(-t * 7.0)) * exp(-t * 1.1) * (0.65 + 0.35 * sin(t * 4.1 + 1.0) * sin(t * 1.7))
		var v := crack + lp2 * env * 3.0
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s


## Rain on steel: a looping hiss (high-passed noise) over a low wind rumble.
static func _rain_stream() -> AudioStreamWAV:
	var rate := 16000
	var n := rate * 2
	var fade := rate / 10
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var prev := 0.0
	var lo := 0.0
	for i in n + fade:
		var w := r.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		lo += (w - lo) * 0.01
		buf[i] = hp * 0.35 + lo * 1.6
	# Seamless loop: the 0.1 s past the end fades into the start.
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := buf[i]
		if i < fade:
			var k := float(i) / fade
			v = buf[i] * k + buf[n + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s


## Fires lightning strikes at random intervals: sky, fog, ambient, a flash light,
## the sea and the bolt follow one envelope. Only uniforms and energies change.
class Storm extends Node:
	var env: Environment
	var light: DirectionalLight3D
	var bolt: MeshInstance3D
	var bolt_mat: ShaderMaterial
	var sea: ShaderMaterial
	var fog_base: Color
	var ambient_base: float
	var forced: PackedFloat32Array = []
	var thunder: AudioStreamPlayer
	var _thunder_at: float = INF
	var _thunder_db: float = -8.0
	var _t: float = 0.0
	var _next: float = 3.5
	var _strike_t: float = -100.0
	var _rng := RandomNumberGenerator.new()
	var _active := false

	func _ready() -> void:
		_rng.seed = 4242
		if not forced.is_empty():
			_next = INF

	func _envelope(t: float) -> float:
		var f := 0.0
		# Three return strokes, then a fading afterglow; never fully dark between.
		for pulse: Vector3 in [Vector3(0.0, 0.12, 1.0), Vector3(0.16, 0.08, 0.6), Vector3(0.28, 0.12, 0.9)]:
			if t >= pulse.x and t < pulse.x + pulse.y:
				f = maxf(f, pulse.z * (1.0 - (t - pulse.x) / pulse.y * 0.6))
		if t < 0.4:
			f = maxf(f, 0.3)
		else:
			f = maxf(f, 0.3 * exp(-(t - 0.4) * 5.0))
		return f

	func _strike(cam: Camera3D) -> void:
		_strike_t = _t
		_active = true
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var ang := _rng.randf_range(-0.55, 0.55)
		var dir := fwd.rotated(Vector3.UP, ang)
		var dist := _rng.randf_range(1100.0, 1900.0)
		var cp := cam.global_position
		var pos := Vector3(cp.x, 0.0, cp.z) + dir * dist
		var sx := 1.0 if _rng.randf() < 0.5 else -1.0
		var sc := Basis.from_scale(Vector3(sx, _rng.randf_range(0.85, 1.15), 1.0))
		bolt.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * sc, pos)
		light.global_transform = Transform3D(Basis.looking_at((-dir + Vector3(0, -0.7, 0)).normalized(), Vector3.UP), Vector3.ZERO)
		# Thunder follows after a (shortened) sound delay, quieter for far strikes.
		_thunder_at = _t + dist / 1100.0
		_thunder_db = lerpf(-5.0, -12.0, (dist - 1100.0) / 800.0)
		if DevArgs.has("--storm-log"):
			var top := pos + Vector3(0, 300, 0)
			print("strike t=%.2f bolt at %s, camera %s fwd %s, on screen %s behind %s fov %.0f far %.0f" % [_t, pos, cp, fwd, cam.unproject_position(top), cam.is_position_behind(top), cam.fov, cam.far])

	func _process(delta: float) -> void:
		_t += delta
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		if not forced.is_empty() and _t >= forced[0]:
			forced.remove_at(0)
			_strike(cam)
		elif _t >= _next and not Offshore.under_roof(cam.global_position):
			_next = _t + _rng.randf_range(7.0, 15.0)
			_strike(cam)
		if _t >= _thunder_at:
			_thunder_at = INF
			if thunder:
				thunder.volume_db = _thunder_db
				thunder.pitch_scale = _rng.randf_range(0.8, 1.1)
				thunder.play()
		if not _active:
			return
		var et := _t - _strike_t
		var f := _envelope(et)
		if et > 1.4:
			f = 0.0
			_active = false
		if env:
			env.background_energy_multiplier = 1.0 + 3.0 * f
			env.fog_light_color = fog_base.lerp(Color(0.45, 0.5, 0.62), clampf(f * 0.7, 0.0, 1.0))
			env.ambient_light_energy = ambient_base * (1.0 + 1.6 * f)
		light.light_energy = 2.4 * f
		sea.set_shader_parameter("flash", f)
		bolt_mat.set_shader_parameter("intensity", f * 7.0)
		bolt_mat.set_shader_parameter("bolt", 1.0 if et < 0.42 else 0.0)
