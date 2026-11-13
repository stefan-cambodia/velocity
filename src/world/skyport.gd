## CIRRUS HEIGHTS world: a sky port above a sea of clouds at sunrise.
##
## No terrain. The "ground" is the top of a continuous cloud layer far below
## (CLOUD_Y): one plane that follows the camera, shaded from a baked texture
## (tools/gen_skyport_textures.py) lit by the low sun, fading into the sky's
## below-horizon colour at its edge. The sky (sky_dawn) runs from deep blue
## overhead to rose and gold at the horizon, with the sun 9 degrees up in the
## east. Cumulus heads rise out of the cloud sea and snowy peaks pierce it.
##
## The circuit rides on slender viaducts (box girder, V piers dropping into
## the clouds) between white stone and glass towers: the terminal and its
## platform deck at the start, the Gate Tower the Gantry Viaduct passes
## through, the Spire inside the Spire Spiral with a cone of stay cables, the
## two towers of the Skygap Jump, and the airship hangar the lap runs through.
## Airships of an original design ride at mooring masts and cruise in the
## distance. The Cloud Bank is a mound of cloud the track dives into: inside
## it the fog thickens (FogBank) and wisps stream past.
class_name Skyport
extends RefCounted

const SUN_AZ := 90.0          ## Degrees from north towards east. Must match the texture generator.
const SUN_EL := 9.0           ## Degrees above the horizon. Must match the texture generator.
const CLOUD_Y := 10.0         ## Top of the sea of clouds.
const CLOUD_TILE := 2400.0    ## Metres per repeat of the baked cloud texture.
const CELL := 450.0           ## Static props are merged per cell of this size.
const FOG_BASE := 0.00016
const WIND := Vector3(-0.6, 0.0, 0.8)   ## Moored airships point into this (towards south-west).

static var rng := RandomNumberGenerator.new()
static var _grid: Dictionary = {}            ## Vector2i -> PackedInt32Array of track samples (every 4 m).
static var _mats: Dictionary = {}
static var _bank_blobs: Array[Vector4] = []  ## Cloud bank ellipsoids: (x, y, z, r); vertical radius r * BANK_FLAT.
static var _occupied: Array[Vector3] = []    ## (x, z, radius) kept clear by landmarks.
static var _sea_mat: ShaderMaterial
const BANK_FLAT := 0.5


static func sun_dir() -> Vector3:
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_EL)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 7021
	var t0 := Time.get_ticks_msec()
	_mats.clear()
	_bank_blobs.clear()
	_occupied.clear()
	_index_track(td)
	_environment(root)
	_cloud_sea(root)
	# --skyport-skip=<part>,... leaves parts out (development aid for profiling).
	var skip := PackedStringArray()
	for a in DevArgs.all():
		if a.begins_with("--skyport-skip="):
			skip = a.substr(15).split(",")
	var parts := [["supports", _supports], ["terminal", _terminal], ["gate_tower", _gate_tower], ["spire", _spire],
		["jump_towers", _jump_towers], ["hangar", _hangar], ["cloud_bank", _cloud_bank], ["gantries", _gantries],
		["gates", _gates], ["masts", _masts], ["towers", _towers], ["far", _far], ["cruisers", _cruisers]]
	for part: Array in parts:
		if not skip.has(part[0]):
			(part[1] as Callable).call(td, root)
	HelixBay._start_gantry(td, root, "CIRRUS HEIGHTS  /  VELOCITY LEAGUE")
	# The meshes and nodes hold what they need; drop the build-time statics.
	_mats.clear()
	_grid.clear()
	_sea_mat = null
	if DevArgs.has("--load-times"):
		print("skyport world %d ms" % (Time.get_ticks_msec() - t0))


# ------------------------------------------------------------------ helpers

static func _section(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


static func _index_track(td: TrackData) -> void:
	_grid.clear()
	for i in range(0, td.count, 4):
		var k := Vector2i(floori(td.pos[i].x / 40.0), floori(td.pos[i].z / 40.0))
		var arr: PackedInt32Array = _grid.get(k, PackedInt32Array())
		arr.append(i)
		_grid[k] = arr


## Horizontal distance from (x, z) to the nearest track sample whose height is
## within [y0, y1], searched up to `r` metres (INF if none that close).
static func _track_dist(td: TrackData, p: Vector2, r: float, y0: float = -INF, y1: float = INF) -> float:
	var best := INF
	var n := int(ceil(r / 40.0))
	var cx := floori(p.x / 40.0)
	var cz := floori(p.y / 40.0)
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := Vector2i(cx + dx, cz + dz)
			if not _grid.has(k):
				continue
			var arr: PackedInt32Array = _grid[k]
			for i in arr:
				var q := td.pos[i]
				if q.y < y0 or q.y > y1:
					continue
				var d := Vector2(q.x - p.x, q.z - p.y).length()
				if d < best:
					best = d
	return best if best <= r else INF


## True if no other part of the track (more than `ds` metres away along the
## lap from s) runs within `r` metres horizontally below `y`.
static func _clear_below(td: TrackData, s: float, p: Vector3, r: float, ds: float = 150.0) -> bool:
	var n := int(ceil(r / 40.0))
	var cx := floori(p.x / 40.0)
	var cz := floori(p.z / 40.0)
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := Vector2i(cx + dx, cz + dz)
			if not _grid.has(k):
				continue
			var arr: PackedInt32Array = _grid[k]
			for i in arr:
				var q := td.pos[i]
				if q.y > p.y or absf(td.delta_s(s, i * td.step)) < ds:
					continue
				if Vector2(q.x - p.x, q.z - p.z).length() < r:
					return false
	return true


## True if the segment a-b passes through the deck of another part of the
## track (more than 100 m from s along the lap).
static func _crosses_deck(td: TrackData, a: Vector3, b: Vector3, s: float) -> bool:
	for q in range(1, 40):
		var p := a.lerp(b, q / 40.0)
		var k := Vector2i(floori(p.x / 40.0), floori(p.z / 40.0))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var kk := k + Vector2i(dx, dz)
				if not _grid.has(kk):
					continue
				var arr: PackedInt32Array = _grid[kk]
				for i in arr:
					if absf(td.delta_s(s, i * td.step)) < 100.0:
						continue
					var c := td.pos[i]
					if absf(p.y - (c.y - 2.0)) > 5.0:
						continue
					if Vector2(p.x - c.x, p.z - c.z).length() < maxf(td.half_l[i], td.half_r[i]) + 3.0:
						return true
	return false


static func _free(p: Vector2, r: float) -> bool:
	for o in _occupied:
		if p.distance_to(Vector2(o.x, o.y)) < r + o.z:
			return false
	return true


static func _cell_mk(cells: Dictionary, p: Vector3) -> MeshKit:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if not cells.has(key):
		cells[key] = MeshKit.new()
	return cells[key]


static func _flush(cells: Dictionary, root: Node3D, prefix: String, shadows: bool = false, vis_end: float = 0.0) -> void:
	for key: Vector2i in cells:
		var mk: MeshKit = cells[key]
		if mk.is_empty():
			continue
		var mi := mk.instance("%s_%d_%d" % [prefix, key.x, key.y], _mats)
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = 80.0
		root.add_child(mi)


## Local materials (the shared Mats keys are used as well).
static func _make_mats() -> void:
	var sd := sun_dir()
	_mats["stone"] = Mats.shader_mat("skyport_tower", {"cloud_y": CLOUD_Y})
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.albedo_color = Color(0.92, 0.9, 0.86)
	wm.roughness = 0.45
	wm.metallic = 0.35
	_mats["white_metal"] = wm
	_mats["white_concrete"] = Mats.shader_mat("skyport_tower", {"plain": true, "cloud_y": CLOUD_Y})
	var pv := StandardMaterial3D.new()
	pv.vertex_color_use_as_albedo = true
	pv.albedo_color = Color(1.25, 1.2, 1.12)
	pv.albedo_texture = Mats.tex("panel_albedo")
	pv.uv1_triplanar = true
	pv.uv1_scale = Vector3(0.2, 0.2, 0.2)
	pv.roughness = 0.7
	_mats["paving"] = pv
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.82, 0.83, 0.86)
	cable.metallic = 0.8
	cable.roughness = 0.3
	_mats["cable"] = cable
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.roughness = 0.9
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["cloth"] = cloth
	var hull := StandardMaterial3D.new()
	hull.vertex_color_use_as_albedo = true
	hull.roughness = 0.5
	hull.metallic = 0.15
	hull.rim_enabled = true
	hull.rim = 0.25
	hull.rim_tint = 0.6
	_mats["hull"] = hull
	var hangar := StandardMaterial3D.new()
	hangar.vertex_color_use_as_albedo = true
	hangar.albedo_color = Color(0.93, 0.92, 0.9)
	hangar.roughness = 0.55
	hangar.metallic = 0.1
	hangar.cull_mode = BaseMaterial3D.CULL_DISABLED
	hangar.emission_enabled = true
	hangar.emission = Color(0.1, 0.085, 0.08)
	_mats["hangar"] = hangar
	_mats["cloud"] = Mats.shader_mat("cloud_puff", {"sun_dir": sd, "base_y": CLOUD_Y})
	_mats["bank"] = Mats.shader_mat("cloud_puff", {"sun_dir": sd, "base_y": CLOUD_Y})
	var rock := StandardMaterial3D.new()
	rock.vertex_color_use_as_albedo = true
	rock.roughness = 0.95
	_mats["peak"] = rock


# ------------------------------------------------------------------ environment

static func _environment(root: Node3D) -> void:
	_make_mats()
	var sd := sun_dir()
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			var sm := ShaderMaterial.new()
			sm.shader = load("res://assets/shaders/sky_dawn.gdshader")
			sm.set_shader_parameter("sun_dir", sd)
			sm.set_shader_parameter("cirrus_tex", Mats.tex("skyport_cirrus"))
			env.sky.sky_material = sm
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_energy = 0.8
			env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			env.fog_enabled = true
			env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			env.fog_density = FOG_BASE
			env.fog_light_color = Color(0.93, 0.76, 0.72)
			env.fog_aerial_perspective = 0.85
			env.fog_sky_affect = 0.0
			env.fog_sun_scatter = 0.15
			env.fog_height_density = 0.0
			env.tonemap_exposure = 1.0
			env.glow_hdr_threshold = 1.05
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.transform = Transform3D(Basis.looking_at(-sd, Vector3.UP), Vector3.ZERO)
			sun.light_color = Color(1.0, 0.77, 0.55)
			sun.light_energy = 1.75


## The sea of clouds: one plane under the whole world that follows the camera.
static func _cloud_sea(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "CloudSea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(17600, 17600)
	mi.mesh = pm
	_sea_mat = Mats.shader_mat("cloud_sea", {"clouds_tex": Mats.tex("skyport_clouds"), "sun_dir": sun_dir(), "tile": CLOUD_TILE})
	mi.material_override = _sea_mat
	mi.position = Vector3(0, CLOUD_Y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var f := Follow.new()
	f.target = mi
	root.add_child(f)


## Keeps a node under the active camera (x and z only).
class Follow extends Node:
	var target: Node3D

	func _process(_d: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam and target:
			var p := cam.global_position
			target.global_position = Vector3(p.x, target.global_position.y, p.z)


# ------------------------------------------------------------------ viaduct

## Box girder under every open stretch of deck, and V piers dropping into the
## clouds wherever nothing else runs below.
static func _supports(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var skip: Array[Vector2] = [Vector2(-200.0, 240.0)]       # terminal platform (s may be negative)
	var hg := _section(td, "Airship Hangar")
	skip.append(Vector2(hg.x - 30.0, hg.y + 30.0))
	var jump := _section(td, "Skygap Jump")
	var hit := TrackData.Hit.new()
	var s := 0.0
	while s < td.length:
		td.frame_at(s + 5.0, hit)
		var blocked := false
		for r in skip:
			if td.delta_s(r.x, s) >= 0.0 and td.delta_s(s, r.y) >= 0.0:
				blocked = true
		if not blocked and (hit.flags & (TrackData.F_GAP | TrackData.F_TUNNEL)) == 0:
			var mk := _cell_mk(cells, hit.c)
			var b := Basis(hit.B, hit.N, -hit.T)
			var w := hit.half_l + hit.half_r - 4.0
			mk.use("white_concrete")
			mk.box_t(Transform3D(b, hit.c - hit.N * (TrackMesh.DECK + 1.6) + hit.B * (hit.half_r - hit.half_l) * 0.5), Vector3(w, 3.2, 10.3), Color(1, 1, 1), 0.8)
		s += 10.0
	# Piers.
	s = 40.0
	while s < td.length:
		td.frame_at(s, hit)
		var blocked := (hit.flags & (TrackData.F_GAP | TrackData.F_TUNNEL)) != 0
		for r in skip:
			if td.delta_s(r.x, s) >= -20.0 and td.delta_s(s, r.y) >= -20.0:
				blocked = true
		if jump.x >= 0.0 and absf(td.delta_s(s, (jump.x + jump.y) * 0.5)) < 90.0:
			blocked = true
		var top := hit.c - hit.N * (TrackMesh.DECK + 3.2)
		if not blocked and _clear_below(td, s, top, 26.0):
			_pier(_cell_mk(cells, hit.c), hit, top)
			s += 105.0
		else:
			s += 15.0
	_flush(cells, root, "Viaduct")


static func _pier(mk: MeshKit, hit: TrackData.Hit, top: Vector3) -> void:
	var flat_b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
	var fork := top + Vector3(0, -26.0, 0)
	var bottom := Vector3(top.x, CLOUD_Y - 45.0, top.z)
	mk.use("white_concrete")
	mk.cyl(bottom, fork, 3.4, 2.4, 10, Color(0.92, 0.9, 0.88), false)
	var span := minf(hit.half_l, hit.half_r) - 3.0
	for side: float in [-1.0, 1.0]:
		var head := top + flat_b * side * span
		mk.beam(fork, head, 1.8, 1.8, Color(0.95, 0.93, 0.9), hit.T)
	mk.box_t(Transform3D(Basis(hit.B, hit.N, -hit.T), top + hit.N * 0.2), Vector3(span * 2.0 + 3.0, 1.2, 3.0), Color(0.9, 0.88, 0.85))
	# A ring of warm lamps where the legs fork.
	mk.use("lamp")
	mk.torus(fork + Vector3(0, 1.0, 0), Vector3.UP, 2.6, 0.18, 10, 3, Color.WHITE)


# ------------------------------------------------------------------ the terminal

## Quad a-b-c-d with its front face towards `dir` (winding flipped if needed).
static func _quad_facing(mk: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, dir: Vector3, col: Color) -> void:
	if (c - a).cross(b - a).dot(dir) >= 0.0:
		mk.quad(a, b, c, d, col)
	else:
		mk.quad(a, d, c, b, col)


## A slab beside the track between lateral offsets d0..d1 (outside the
## barriers), following the track frames from s0 to s1.
static func _apron(mk: MeshKit, td: TrackData, s0: float, s1: float, d0: float, d1: float, thick: float, col: Color) -> void:
	var hit := TrackData.Hit.new()
	var prev: Array = []
	var s := s0
	while s <= s1 + 0.1:
		td.frame_at(s, hit)
		var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
		var top := hit.c.y - 0.12
		var a := Vector3(hit.c.x, top, hit.c.z) + b * d0
		var c := Vector3(hit.c.x, top, hit.c.z) + b * d1
		var a2 := a - Vector3(0, thick, 0)
		var c2 := c - Vector3(0, thick, 0)
		var row := [a, c, a2, c2]
		if not prev.is_empty():
			var pa: Vector3 = prev[0]
			var pc: Vector3 = prev[1]
			var pa2: Vector3 = prev[2]
			var pc2: Vector3 = prev[3]
			var outer := (c - a).normalized()
			_quad_facing(mk, pa, pc, c, a, Vector3.UP, col)
			_quad_facing(mk, pc, pc2, c2, c, outer, col * 0.9)
			_quad_facing(mk, pa, pa2, a2, a, -outer, col * 0.9)
			_quad_facing(mk, pa2, pc2, c2, a2, Vector3.DOWN, col * 0.7)
		prev = row
		s += 10.0


static func _terminal(td: TrackData, root: Node3D) -> void:
	var mk := MeshKit.new()
	var e := 16.7    # barrier outer face (half width 16 + wall)
	mk.use("paving")
	_apron(mk, td, -150.0, 195.0, -e, -38.0, 4.0, Color(1, 1, 1))
	_apron(mk, td, -145.0, 230.0, e, 70.0, 4.0, Color(1, 1, 1))
	var hit := TrackData.Hit.new()
	# Keep airships and towers off the platform and the hall.
	for s: float in range(-140, 240, 30):
		td.frame_at(s, hit)
		var bo := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
		for dd: Vector2 in [Vector2(46.0, 32.0), Vector2(-28.0, 16.0)]:
			var q := hit.c + bo * dd.x
			_occupied.append(Vector3(q.x, q.z, dd.y))
	# Platform piers.
	for s: float in [-120.0, -40.0, 40.0, 120.0, 190.0]:
		td.frame_at(s, hit)
		var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
		for d: float in [-28.0, 30.0, 58.0]:
			var p := Vector3(hit.c.x, hit.c.y - 4.0, hit.c.z) + b * d
			mk.use("white_concrete")
			mk.cyl(Vector3(p.x, CLOUD_Y - 40.0, p.z), p, 4.5, 3.0, 12, Color(0.92, 0.9, 0.88), false)
	# Terminal hall on the right, its glass front facing the grid.
	td.frame_at(30.0, hit)
	var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
	var t := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
	var base := Vector3(hit.c.x, hit.c.y - 0.12, hit.c.z)
	var hb := Basis(b, Vector3.UP, -t)
	mk.use("stone")
	mk.box_t(Transform3D(hb, base + b * 46.0 + Vector3(0, 8.0, 0)), Vector3(36.0, 16.0, 300.0), Color(0.93, 0.9, 0.85, 1.0))
	mk.box_t(Transform3D(hb, base + b * 45.0 + Vector3(0, 16.8, 0)), Vector3(42.0, 1.6, 306.0), Color(0.96, 0.95, 0.92, 0.0))
	# Canopy over the front of the hall, on slim columns.
	mk.use("white_metal")
	mk.box_t(Transform3D(hb, base + b * 24.0 + Vector3(0, 11.0, 0)), Vector3(10.0, 0.6, 280.0), Color(1, 1, 1))
	for k in 15:
		var along := (k - 7) * 19.0
		mk.cyl(base + b * 20.5 + t * along, base + b * 20.5 + t * along + Vector3(0, 11.0, 0), 0.35, 0.35, 6, Color(1, 1, 1), false)
	# Terminal tower: round shaft, glass control cab, crown and mast.
	var tb := base + b * 46.0 + t * 20.0
	_occupied.append(Vector3(tb.x, tb.z, 80.0))
	mk.use("stone")
	HelixBay.prism(mk, tb + Vector3(0, 16.0, 0), 15.0, 16, 150.0, Color(0.93, 0.91, 0.86, 0.5), 13.0)
	HelixBay.prism(mk, tb + Vector3(0, 166.0, 0), 22.0, 20, 12.0, Color(0.9, 0.9, 0.9, 1.0), 25.0)
	HelixBay.prism(mk, tb + Vector3(0, 178.0, 0), 25.0, 20, 2.0, Color(0.95, 0.94, 0.9, 0.0), 14.0)
	mk.use("metal")
	mk.cyl(tb + Vector3(0, 180.0, 0), tb + Vector3(0, 225.0, 0), 1.4, 0.3, 6, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(tb + Vector3(0, 226.0, 0), Vector3(1.2, 1.2, 1.2), 3, 6, Color.WHITE)
	mk.use("lamp")
	mk.torus(tb + Vector3(0, 165.5, 0), Vector3.UP, 22.3, 0.35, 32, 3, Color.WHITE)
	# Banners along the left apron, in the team colours.
	var ids := Catalog.team_ids()
	var k := 0
	var s := -130.0
	while s < 185.0:
		td.frame_at(s, hit)
		var bb := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
		var tt := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
		var foot := Vector3(hit.c.x, hit.c.y - 0.12, hit.c.z) - bb * 24.0
		mk.use("white_metal")
		mk.cyl(foot, foot + Vector3(0, 21.0, 0), 0.22, 0.16, 6, Color.WHITE, false)
		mk.beam(foot + Vector3(0, 20.2, 0), foot + Vector3(0, 20.2, 0) + tt * 3.7, 0.2, 0.2, Color.WHITE)
		var liv: Dictionary = Catalog.team(ids[k % ids.size()])["livery"]
		var p: Color = liv["primary"]
		var q: Color = liv["secondary"]
		mk.use("cloth")
		var top := foot + Vector3(0, 20.0, 0) + tt * 0.35
		var w := tt * 3.2
		var y1 := Vector3(0, 10.0, 0)
		var y2 := Vector3(0, 12.5, 0)
		mk.quad(top, top + w, top + w - y1, top - y1, p, Vector2.ONE, Vector2.ZERO, true)
		mk.quad(top - y1, top + w - y1, top + w * 0.5 - y2, top + w * 0.5 - y2, q, Vector2.ONE, Vector2.ZERO, true)
		s += 30.0
		k += 1
	var mi := mk.instance("Terminal", _mats)
	root.add_child(mi)


# ------------------------------------------------------------------ the gate tower

## A tower straddling the Gantry Viaduct: the deck passes through a portal in it.
static func _gate_tower(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Gantry Viaduct")
	if r.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at(lerpf(r.x, r.y, 0.68), hit)
	var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
	var t := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
	var hb := Basis(b, Vector3.UP, -t)
	var deck := hit.c.y
	var half := maxf(hit.half_l, hit.half_r) + 5.0
	var depth := 32.0
	var wide := 28.0
	var top := deck + 190.0
	var bottom := CLOUD_Y - 40.0
	var open_h := 24.0
	var mk := MeshKit.new()
	var c := Vector3(hit.c.x, 0.0, hit.c.z)
	_occupied.append(Vector3(c.x, c.z, 90.0))
	mk.use("stone")
	var tint := Color(0.94, 0.9, 0.84, 0.5)
	for side: float in [-1.0, 1.0]:
		var cx := c + b * side * (half + wide * 0.5)
		mk.box_t(Transform3D(hb, cx + Vector3(0, (top + bottom) * 0.5, 0)), Vector3(wide, top - bottom, depth), tint)
	# Below the deck and above the portal.
	mk.box_t(Transform3D(hb, c + Vector3(0, (deck - 6.0 + bottom) * 0.5, 0)), Vector3(half * 2.0, deck - 6.0 - bottom, depth), tint)
	mk.box_t(Transform3D(hb, c + Vector3(0, (top + deck + open_h) * 0.5, 0)), Vector3(half * 2.0, top - deck - open_h, depth), tint)
	# Crown: a stepped glass lantern and a mast.
	mk.box_t(Transform3D(hb, c + Vector3(0, top + 9.0, 0)), Vector3(half * 2.0 + wide * 1.4, 18.0, depth * 0.8), Color(0.9, 0.9, 0.92, 1.0))
	mk.box_t(Transform3D(hb, c + Vector3(0, top + 18.6, 0)), Vector3(half * 2.0 + wide * 1.5, 1.2, depth * 0.85), Color(0.95, 0.94, 0.9, 0.0))
	mk.use("metal")
	mk.cyl(c + Vector3(0, top + 19.0, 0), c + Vector3(0, top + 60.0, 0), 1.0, 0.25, 6, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(c + Vector3(0, top + 61.0, 0), Vector3(1, 1, 1), 3, 6, Color.WHITE)
	# Portal lining: warm light strips on the soffit and jambs.
	mk.use("lamp")
	for k in 5:
		var along := (k - 2) * 7.0
		mk.box_t(Transform3D(hb, c + t * along + Vector3(0, deck + open_h - 0.3, 0)), Vector3(half * 2.0 - 4.0, 0.25, 0.8), Color.WHITE)
	for side: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			mk.box_t(Transform3D(hb, c + b * side * (half - 0.1) + t * z * (depth * 0.5 - 0.6) + Vector3(0, deck + open_h * 0.5, 0)), Vector3(0.25, open_h - 2.0, 0.4), Color.WHITE)
	var mi := mk.instance("GateTower", _mats)
	root.add_child(mi)


# ------------------------------------------------------------------ the spire

static func _spiral_centre(td: TrackData) -> Vector3:
	var r := _section(td, "Spire Spiral")
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	var n := i1 - i0
	var c := Vector3.ZERO
	var m := 0
	for i in range(i0 + n / 6, i1 - n / 6, 3):
		c += td.pos[i]
		m += 1
	return c / maxf(m, 1)


## The tallest tower, inside the Spire Spiral, holding the spiral deck up with
## a cone of stay cables from its upper shaft.
static func _spire(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Spire Spiral")
	if r.x < 0.0:
		return
	var c := _spiral_centre(td)
	c.y = 0.0
	_occupied.append(Vector3(c.x, c.z, 180.0))
	var mk := MeshKit.new()
	var bottom := CLOUD_Y - 60.0
	mk.use("stone")
	HelixBay.prism(mk, c + Vector3(0, bottom, 0), 26.0, 20, 210.0 - bottom, Color(0.95, 0.91, 0.85, 0.5), 23.0)
	HelixBay.prism(mk, c + Vector3(0, 210.0, 0), 25.0, 20, 6.0, Color(0.96, 0.95, 0.92, 0.0), 25.0)
	HelixBay.prism(mk, c + Vector3(0, 216.0, 0), 21.0, 20, 90.0, Color(0.93, 0.92, 0.9, 1.0), 18.0)
	HelixBay.prism(mk, c + Vector3(0, 306.0, 0), 30.0, 24, 4.0, Color(0.96, 0.95, 0.92, 0.0), 30.0)
	HelixBay.prism(mk, c + Vector3(0, 310.0, 0), 28.0, 24, 10.0, Color(0.9, 0.9, 0.92, 1.0), 26.0)
	HelixBay.prism(mk, c + Vector3(0, 320.0, 0), 26.0, 24, 3.0, Color(0.96, 0.95, 0.92, 0.0), 12.0)
	HelixBay.prism(mk, c + Vector3(0, 323.0, 0), 12.0, 12, 70.0, Color(0.95, 0.93, 0.88, 0.0), 1.5)
	mk.use("lamp")
	mk.torus(c + Vector3(0, 309.0, 0), Vector3.UP, 30.3, 0.4, 40, 3, Color.WHITE)
	mk.torus(c + Vector3(0, 213.0, 0), Vector3.UP, 25.3, 0.35, 40, 3, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(c + Vector3(0, 394.0, 0), Vector3(1.4, 1.4, 1.4), 3, 6, Color.WHITE)
	# Stay cables from the shaft to the inner edge of the spiral deck.
	mk.use("cable")
	var hit := TrackData.Hit.new()
	var s := r.x + 20.0
	var k := 0
	while s < r.y - 10.0:
		td.frame_at(s, hit)
		var side := 1.0 if hit.B.dot(Vector3(c.x - hit.c.x, 0.0, c.z - hit.c.z)) > 0.0 else -1.0
		var edge := hit.c + hit.B * side * ((hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T * 0.5) + hit.N * TrackMesh.WALL_H
		var dir := Vector3(edge.x - c.x, 0.0, edge.z - c.z).normalized()
		var anchor := c + dir * 22.0 + Vector3(0, 236.0 + 56.0 * float(k % 3) / 2.0, 0)
		if not _crosses_deck(td, anchor, edge, s):
			mk.beam(anchor, edge, 0.32, 0.32, Color.WHITE)
		s += 26.0
		k += 1
	var mi := mk.instance("Spire", _mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ the jump

## The two towers of the Skygap Jump: the kicker ends on one roof, the
## landing starts on the next.
static func _jump_towers(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Skygap Jump")
	if r.x < 0.0:
		return
	var mk := MeshKit.new()
	var hit := TrackData.Hit.new()
	for k in 2:
		var s := r.x - 24.0 if k == 0 else r.y + 26.0
		td.frame_at(s, hit)
		var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
		var t := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
		var hb := Basis(b, Vector3.UP, -t)
		var roof := hit.c.y - TrackMesh.DECK - 3.4
		var c := Vector3(hit.c.x, 0.0, hit.c.z) + t * (8.0 if k == 1 else -8.0)
		_occupied.append(Vector3(c.x, c.z, 60.0))
		var bottom := CLOUD_Y - 40.0
		mk.use("stone")
		var tint := Color(0.93, 0.88, 0.82, 0.5) if k == 0 else Color(0.88, 0.89, 0.92, 0.5)
		mk.box_t(Transform3D(hb, c + Vector3(0, (roof + bottom) * 0.5, 0)), Vector3(52.0, roof - bottom, 44.0), tint)
		mk.box_t(Transform3D(hb, c + Vector3(0, roof + 0.6, 0)), Vector3(56.0, 1.2, 48.0), Color(0.96, 0.95, 0.92, 0.0))
		# Roof edge lights and a beacon on each corner.
		mk.use("lamp")
		for sx: float in [-1.0, 1.0]:
			mk.box_t(Transform3D(hb, c + b * sx * 28.2 + Vector3(0, roof + 1.0, 0)), Vector3(0.3, 0.3, 46.0), Color.WHITE)
		mk.use("warn_red")
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				mk.box(c + b * sx * 27.0 + t * sz * 23.0 + Vector3(0, roof + 2.0, 0), Vector3(0.7, 0.7, 0.7), Color.WHITE)
	var mi := mk.instance("JumpTowers", _mats)
	root.add_child(mi)


# ------------------------------------------------------------------ airships

## An airship of our own design, the "Cirrus" liner: a slim teardrop hull
## with a coral band behind the nose and a teal tail, four tail fins in an X,
## a long glazed gondola and four ducted engines on outriggers. Built along
## `fwd` (nose direction) with its nose at `nose`. Length `L`.
static func _airship(mk: MeshKit, nose: Vector3, fwd: Vector3, L: float, hull_col: Color, band_col: Color) -> void:
	var f := fwd.normalized()
	var side := f.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(f).normalized()
	var R := L * 0.1
	var tail := nose - f * L
	# lathe_at maps the profile's +Y onto the hull axis, tail to nose.
	var xf := Transform3D(Basis(side, f, up), tail)
	mk.use("hull")
	for part: Array in [[0, 3, Color(0.25, 0.55, 0.6)], [3, 7, hull_col], [7, 8, band_col], [8, 12, hull_col]]:
		var prof := PackedVector2Array()
		for k in range(int(part[0]), int(part[1]) + 1):
			prof.append(Vector2(maxf(float(HULL_F[k]) * R, 0.05), float(HULL_X[k]) * L))
		mk.lathe_at(xf, prof, 16, part[2])
	# Fins in an X: root along the hull from 4 % to 20 %, swept tips with coral edges.
	for q in 4:
		var a := PI * 0.25 + q * PI * 0.5
		var dir := side * cos(a) + up * sin(a)
		var r0: float = _hull_r(R, 0.05)
		var r1: float = _hull_r(R, 0.2)
		var p0 := tail + f * (L * 0.03) + dir * r0 * 0.9
		var p1 := tail + f * (L * 0.2) + dir * r1 * 0.95
		var p2 := tail + f * (L * 0.1) + dir * (r1 + R * 0.55)
		var p3 := tail + f * (L * 0.01) + dir * (r0 + R * 0.5)
		mk.use("hull")
		mk.quad(p0, p1, p2, p3, hull_col.darkened(0.08), Vector2.ONE, Vector2.ZERO, true)
		mk.quad(p3, p2, p2 + dir * R * 0.12, p3 + dir * R * 0.12, band_col, Vector2.ONE, Vector2.ZERO, true)
	# Gondola under the forward hull, with a band of windows.
	var g := tail + f * (L * 0.7) - up * (_hull_r(R, 0.7) + R * 0.12)
	mk.use("white_metal")
	mk.push(Transform3D(Basis(side, up, -f), g))
	mk.sphere(Vector3.ZERO, Vector3(R * 0.16, R * 0.13, L * 0.09), 4, 10, Color(0.95, 0.94, 0.9), Color(0.75, 0.74, 0.72))
	mk.pop()
	mk.use("glass")
	mk.box_t(Transform3D(Basis(side, up, -f), g + up * (R * 0.02)), Vector3(R * 0.33, R * 0.06, L * 0.14), Color.WHITE)
	# Engines on outriggers.
	for x: float in [0.4, 0.58]:
		for s: float in [-1.0, 1.0]:
			var hub := tail + f * (L * x) + side * s * (_hull_r(R, x) + R * 0.45) - up * (R * 0.35)
			var root_p := tail + f * (L * x) + side * s * _hull_r(R, x) * 0.8 - up * (R * 0.2)
			mk.use("white_metal")
			mk.beam(root_p, hub, R * 0.06, R * 0.04, Color(0.9, 0.9, 0.9), f)
			mk.cyl(hub + f * (R * 0.35), hub - f * (R * 0.35), R * 0.11, R * 0.08, 8, Color(0.92, 0.92, 0.9))
			mk.use("hull")
			mk.torus(hub - f * (R * 0.42), f, R * 0.2, R * 0.045, 14, 4, band_col)
	# Mooring cone on the nose.
	mk.use("metal")
	mk.cyl(nose - f * 1.5, nose + f * 2.0, 1.4, 0.4, 8, Color.WHITE)


const HULL_X := [0.0, 0.04, 0.1, 0.2, 0.35, 0.5, 0.65, 0.78, 0.84, 0.88, 0.94, 0.98, 1.0]
const HULL_F := [0.05, 0.2, 0.42, 0.68, 0.9, 0.99, 1.0, 0.95, 0.88, 0.8, 0.6, 0.34, 0.0]


## Hull radius at x (0 tail .. 1 nose) for a maximum radius R.
static func _hull_r(R: float, x: float) -> float:
	for k in HULL_X.size() - 1:
		var x0: float = HULL_X[k]
		var x1: float = HULL_X[k + 1]
		if x <= x1:
			return lerpf(float(HULL_F[k]), float(HULL_F[k + 1]), (x - x0) / (x1 - x0)) * R
	return 0.0


## A lattice mooring mast from the clouds up to `top`, with a lit head.
static func _mast(mk: MeshKit, top: Vector3) -> void:
	var base := Vector3(top.x, CLOUD_Y - 30.0, top.z)
	var legs: Array[Vector3] = []
	for k in 3:
		var a := TAU * k / 3.0
		legs.append(Vector3(cos(a), 0.0, sin(a)))
	mk.use("white_metal")
	var h := top.y - base.y
	var levels := int(h / 14.0)
	var prev: Array[Vector3] = []
	for lv in levels + 1:
		var t := float(lv) / levels
		var y := base.y + h * t
		var w := lerpf(9.0, 2.2, t)
		var ring: Array[Vector3] = []
		for k in 3:
			ring.append(Vector3(top.x, y, top.z) + legs[k] * w)
		if not prev.is_empty():
			for k in 3:
				mk.beam(prev[k], ring[k], 0.7, 0.7, Color.WHITE)
				mk.beam(prev[k], ring[(k + 1) % 3], 0.3, 0.3, Color.WHITE)
		for k in 3:
			mk.beam(ring[k], ring[(k + 1) % 3], 0.3, 0.3, Color.WHITE)
		prev = ring
	mk.use("metal")
	mk.cyl(top, top + Vector3(0, 6.0, 0), 2.6, 1.6, 10, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(top + Vector3(0, 7.0, 0), Vector3(0.9, 0.9, 0.9), 3, 6, Color.WHITE)
	mk.use("lamp")
	mk.torus(top + Vector3(0, 0.6, 0), Vector3.UP, 2.9, 0.2, 12, 3, Color.WHITE)


const HULLS := [Color(0.95, 0.93, 0.88), Color(0.86, 0.88, 0.9), Color(0.96, 0.9, 0.82)]
const BANDS := [Color(0.95, 0.4, 0.3), Color(0.15, 0.5, 0.62), Color(0.9, 0.62, 0.2)]


## Airships moored at masts, mostly around the Mooring Turn, nose into the wind.
static func _masts(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var hit := TrackData.Hit.new()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, td.count, 10):
		lo = Vector2(minf(lo.x, td.pos[i].x), minf(lo.y, td.pos[i].z))
		hi = Vector2(maxf(hi.x, td.pos[i].x), maxf(hi.y, td.pos[i].z))
	var wind := WIND.normalized()
	var cands: Array[Vector2] = []
	for k in 600:
		cands.append(Vector2(rng.randf_range(lo.x - 700.0, hi.x + 700.0), rng.randf_range(lo.y - 700.0, hi.y + 700.0)))
	# Three ships around the Mooring Turn, two in view of the terminal, two anywhere.
	var groups := [["Mooring Turn", 3], ["Terminal Deck", 2], ["", 2]]
	var placed := 0
	var L := 190.0
	for g: Array in groups:
		var want: int = g[1]
		var order := cands.duplicate()
		var r := _section(td, g[0]) if g[0] != "" else Vector2(-1, -1)
		if r.x >= 0.0:
			td.frame_at((r.x + r.y) * 0.5, hit)
			var focus := Vector2(hit.c.x, hit.c.z)
			order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(focus) < b.distance_to(focus))
		var got := 0
		for p: Vector2 in order:
			if got >= want:
				break
			var top := Vector3(p.x, rng.randf_range(70.0, 115.0), p.y)
			var ok := true
			for k in 9:
				var q := top - wind * (L * k / 8.0)
				if _track_dist(td, Vector2(q.x, q.z), 70.0) < INF or not _free(Vector2(q.x, q.z), 30.0):
					ok = false
					break
			if not ok:
				continue
			var mk := _cell_mk(cells, top)
			_mast(mk, top)
			var c := placed % HULLS.size()
			_airship(mk, top + wind * 2.0, wind, L, HULLS[c], BANDS[c])
			for k in 5:
				var q := top - wind * (L * k / 4.0)
				_occupied.append(Vector3(q.x, q.z, 40.0))
			placed += 1
			got += 1
	_flush(cells, root, "Moored", false)
	if DevArgs.has("--load-times"):
		print("skyport moored airships %d" % placed)


## Two airships cruising slowly far out.
static func _cruisers(td: TrackData, root: Node3D) -> void:
	var c := Vector3.ZERO
	var n := 0
	for i in range(0, td.count, 20):
		c += td.pos[i]
		n += 1
	c /= maxf(n, 1)
	for k in 2:
		var mk := MeshKit.new()
		_airship(mk, Vector3(0, 0, -110.0), Vector3(0, 0, -1), 220.0, HULLS[(k + 1) % 3], BANDS[(k + 2) % 3])
		var node := Node3D.new()
		node.name = "Cruiser%d" % k
		var mi := mk.instance("CruiserMesh", _mats)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		var cr := Cruise.new()
		cr.target = node
		cr.centre = Vector3(c.x, 0.0, c.z)
		cr.radius = 2600.0 + k * 900.0
		cr.height = 230.0 - k * 60.0
		cr.speed = 11.0 + k * 3.0
		cr.angle = 2.2 + k * 2.6
		cr.dir = 1.0 if k == 0 else -1.0
		node.add_child(cr)
		root.add_child(node)
		cr.place()


class Cruise extends Node:
	var target: Node3D
	var centre := Vector3.ZERO
	var radius := 2500.0
	var height := 200.0
	var speed := 12.0
	var angle := 0.0
	var dir := 1.0

	func place() -> void:
		var p := centre + Vector3(cos(angle) * radius, height, sin(angle) * radius)
		var tangent := Vector3(-sin(angle), 0.0, cos(angle)) * dir
		target.global_transform = Transform3D(Basis.looking_at(tangent, Vector3.UP), p)

	func _process(delta: float) -> void:
		angle += dir * speed * delta / radius
		place()


# ------------------------------------------------------------------ the hangar

## The airship hangar the lap runs through: a long vaulted shed on piers, the
## track along its south side and an airship in the cradles beside it.
static func _hangar(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Airship Hangar")
	if r.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at((r.x + r.y) * 0.5, hit)
	var mid := hit.c
	var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
	var t := Vector3(hit.T.x, 0.0, hit.T.z).normalized()
	var hl := r.y - r.x + 36.0
	var dl := -(hit.half_l + TrackMesh.WALL_T + 7.0)
	var dr := hit.half_r + TrackMesh.WALL_T + 66.0
	var wall_h := 16.0
	var crown := 50.0
	var floor_y := mid.y - 0.3
	var dm := (dl + dr) * 0.5
	var hw := (dr - dl) * 0.5
	var arc := func(k: int, n: int, inset: float) -> Vector3:
		# Cross-section point k of n: up the left wall, over the vault, down the right wall.
		var pts := n - 2
		if k == 0:
			return mid + b * (dl + inset) + Vector3(0, -6.0, 0)
		if k == n:
			return mid + b * (dr - inset) + Vector3(0, -6.0, 0)
		var u := float(k - 1) / pts
		var d := lerpf(dl, dr, u)
		var x := (d - dm) / hw
		var h := wall_h + (crown - wall_h) * (1.0 - x * x)
		var dd := d + (inset if u < 0.5 else -inset)
		return mid + b * dd + Vector3(0, h - inset, 0)
	var mk := MeshKit.new()
	var n := 18
	var secs: Array[PackedVector3Array] = []
	for e in 2:
		var along := t * (hl * (e - 0.5))
		var sec := PackedVector3Array()
		for k in n + 1:
			sec.append(arc.call(k, n, 0.0) + along)
		secs.append(sec)
	mk.use("hangar")
	mk.loft(secs, Color(0.9, 0.88, 0.85), false, true)
	# Floor either side of the track, and the slab under the shed.
	mk.use("paving")
	var e0 := hit.half_l + TrackMesh.WALL_T
	var e1 := hit.half_r + TrackMesh.WALL_T
	for side in [[-e0, dl], [e1, dr]]:
		var a: float = side[0]
		var c: float = side[1]
		var p0 := mid + b * a - t * (hl * 0.5) + Vector3(0, -0.3, 0)
		var p1 := mid + b * c - t * (hl * 0.5) + Vector3(0, -0.3, 0)
		var q0 := p0 + t * hl
		var q1 := p1 + t * hl
		if c > a:
			mk.quad(p0, q0, q1, p1, Color(0.85, 0.84, 0.82))
		else:
			mk.quad(p0, p1, q1, q0, Color(0.85, 0.84, 0.82))
	mk.use("white_concrete")
	mk.box_t(Transform3D(Basis(b, Vector3.UP, -t), mid + b * dm + Vector3(0, -3.5, 0)), Vector3(dr - dl + 2.0, 6.0, hl + 2.0), Color(0.9, 0.88, 0.85))
	for k in 4:
		for d: float in [dl + 6.0, dm, dr - 6.0]:
			var p := mid + b * d + t * (hl * ((k + 0.5) / 4.0 - 0.5)) + Vector3(0, -6.0, 0)
			mk.cyl(Vector3(p.x, CLOUD_Y - 40.0, p.z), p, 4.0, 3.0, 10, Color(0.9, 0.88, 0.85), false)
	# Ribs, roof lamps, portal frames.
	var ribs := int(hl / 20.0)
	for q in ribs + 1:
		var along := t * (hl * (float(q) / ribs - 0.5))
		var portal := q == 0 or q == ribs
		mk.use("white_metal")
		for k in n:
			var a: Vector3 = arc.call(k, n, 0.9) + along
			var c: Vector3 = arc.call(k + 1, n, 0.9) + along
			mk.beam(a, c, 1.6 if portal else 0.8, 1.6 if portal else 1.0, Color(0.95, 0.94, 0.92), t)
		mk.use("lamp")
		for k: int in [5, 9, 13]:
			var p: Vector3 = arc.call(k, n, 2.2) + along
			mk.box_t(Transform3D(Basis(b, Vector3.UP, -t), p), Vector3(2.4, 0.3, 1.0), Color.WHITE)
		if portal:
			mk.use("neon_amber")
			for k in n:
				mk.beam(arc.call(k, n, 0.1) + along, arc.call(k + 1, n, 0.1) + along, 0.4, 0.4, Color.WHITE, t)
	# The airship in its cradles, nose towards the exit, and a gantry walkway beside it.
	var L := 170.0
	var ship_d := dr - 30.0
	var ship_h := 22.0
	var axis := mid + b * ship_d + Vector3(0, ship_h, 0)
	_airship(mk, axis + t * (L * 0.5), t, L, HULLS[0], BANDS[0])
	mk.use("white_metal")
	for k in 3:
		var x := (k - 1) * 50.0
		var under := axis + t * x + Vector3(0, -L * 0.1 * 0.95, 0)
		for s: float in [-1.0, 1.0]:
			mk.beam(mid + b * (ship_d + s * 9.0) + t * x + Vector3(0, -0.3, 0), under + b * s * 2.0, 1.0, 1.0, Color(0.9, 0.9, 0.9), t)
	var walk := mid + b * (ship_d - 22.0) + Vector3(0, ship_h - 4.0, 0)
	mk.box_t(Transform3D(Basis(b, Vector3.UP, -t), walk), Vector3(3.0, 0.4, L * 0.8), Color(0.85, 0.85, 0.85))
	for k in 5:
		var x := (k - 2) * L * 0.18
		mk.beam(walk + t * x, walk + t * x + Vector3(0, -(ship_h - 4.0), 0), 0.5, 0.5, Color.WHITE)
	mk.use("neon_amber")
	mk.box_t(Transform3D(Basis(b, Vector3.UP, -t), walk + Vector3(0, 1.1, 0) + b * 1.4), Vector3(0.1, 0.1, L * 0.8), Color.WHITE)
	var mi := mk.instance("Hangar", _mats)
	root.add_child(mi)
	var c2 := mid + b * dm
	_occupied.append(Vector3(c2.x, c2.z, hl * 0.5 + 40.0))


# ------------------------------------------------------------------ the cloud bank

## A mound of cloud rising out of the sea around the Cloud Bank section. The
## track dives into it; inside, FogBank thickens the fog and wisps stream past.
static func _cloud_bank(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Cloud Bank")
	if r.x < 0.0:
		return
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.9
	var mk := MeshKit.new()
	mk.use("bank")
	var hit := TrackData.Hit.new()
	var s := r.x + 40.0
	var k := 0
	while s < r.y - 30.0:
		td.frame_at(s, hit)
		var b := Vector3(hit.B.x, 0.0, hit.B.z).normalized()
		var rad := rng.randf_range(68.0, 84.0)
		var c := hit.c + b * rng.randf_range(-14.0, 14.0) + Vector3(0, -14.0, 0)
		_bank_blobs.append(Vector4(c.x, c.y, c.z, rad))
		mk.blob(c, Vector3(rad, rad * BANK_FLAT, rad), 3, noise, 0.26, Color(1, 1, 1), Color(0.85, 0.82, 0.86), false, Vector3(k * 3.1, 0, 0))
		# Cauliflower heads on top.
		for q in 3:
			var a := rng.randf() * TAU
			var pr := rad * rng.randf_range(0.28, 0.4)
			var pc := c + Vector3(cos(a), 0.0, sin(a)) * rad * rng.randf_range(0.2, 0.55) + Vector3(0, rad * BANK_FLAT * 0.72, 0)
			mk.blob(pc, Vector3(pr, pr * 0.75, pr), 1, noise, 0.3, Color(1, 1, 1), Color(0.88, 0.85, 0.88), false, Vector3(k, q, 5))
		# Flanking heads make the mound broad and lumpy.
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.75:
				var r2 := rng.randf_range(50.0, 80.0)
				var c2 := hit.c + b * side * rng.randf_range(75.0, 120.0) + Vector3(0, -rng.randf_range(20.0, 34.0), 0)
				mk.blob(c2, Vector3(r2, r2 * 0.6, r2), 2, noise, 0.25, Color(1, 1, 1), Color(0.85, 0.82, 0.86), false, Vector3(k * 1.7, side, 0))
		s += 52.0
		k += 1
	var mi := mk.instance("CloudBank", _mats)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Wisps: soft billboards around the camera, only inside the bank.
	var p := GPUParticles3D.new()
	p.name = "Wisps"
	p.amount = maxi(8, int(36 * float(Quality.p["particles"])))
	p.lifetime = 2.2
	p.preprocess = 0.0
	p.local_coords = false
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-120, -60, -120), Vector3(240, 120, 240))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 12, 40)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.3, Color(1, 1, 1, 0.3))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(16.0, 10.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = Mats.tex("smoke")
	mat.albedo_color = Color(1.0, 0.95, 0.92, 0.55)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	var we: WorldEnvironment = null
	for c in root.get_children():
		if c is WorldEnvironment:
			we = c
	var fb := FogBank.new()
	fb.env = we.environment if we else null
	fb.blobs = _bank_blobs.duplicate()
	fb.wisps = p
	fb.bank_mat = _mats["bank"]
	fb.sea_mat = _sea_mat
	root.add_child(fb)


## Thickens the fog while the camera is inside the cloud bank and keeps the
## wisps in front of it.
class FogBank extends Node:
	var env: Environment
	var blobs: Array[Vector4] = []
	var wisps: GPUParticles3D
	var bank_mat: ShaderMaterial
	var sea_mat: ShaderMaterial
	var inside := 0.0

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or env == null:
			return
		var p := cam.global_position
		var f := -INF
		for b in blobs:
			var d := Vector3(p.x - b.x, (p.y - b.y) / Skyport.BANK_FLAT, p.z - b.z).length() / b.w
			f = maxf(f, 1.0 - d)
		var target := smoothstep(-0.2, 0.3, f)
		inside = move_toward(inside, target, delta * 3.0)
		env.fog_density = lerpf(Skyport.FOG_BASE, 0.0034, inside)
		if bank_mat:
			bank_mat.set_shader_parameter("dissolve", clampf((inside - 0.2) / 0.5, 0.0, 1.0))
		if sea_mat:
			sea_mat.set_shader_parameter("bank_fog", inside)
		env.fog_aerial_perspective = lerpf(0.85, 0.0, inside)
		env.fog_sky_affect = inside
		env.fog_light_color = Color(0.93, 0.76, 0.72).lerp(Color(1.0, 0.9, 0.84), inside)
		if wisps:
			wisps.amount_ratio = inside
			wisps.global_position = p - cam.global_transform.basis.z * 40.0


# ------------------------------------------------------------------ trackside

## Lighting gantries (white arches with warm lamps) every 40 m along the fast
## viaducts: the rhythm that sells the speed.
static func _gantries(td: TrackData, root: Node3D) -> void:
	var ranges := _gantry_ranges(td)
	var gt := _section(td, "Gantry Viaduct")
	var gate_s := lerpf(gt.x, gt.y, 0.68)
	var cells: Dictionary = {}
	var hit := TrackData.Hit.new()
	var k := 0
	for rg in ranges:
		var s := rg.x + 20.0
		while s < rg.y - 10.0:
			if absf(s - gate_s) > 45.0:
				td.frame_at(s, hit)
				var mk := _cell_mk(cells, hit.c)
				_arch(mk, hit, k)
				k += 1
			s += 40.0
	_flush(cells, root, "Gantries", true)


static func _gantry_ranges(td: TrackData) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var a := _section(td, "Gantry Viaduct")
	var sp := _section(td, "Spire Spiral")
	if a.x >= 0.0 and sp.x >= 0.0:
		out.append(Vector2(a.x, sp.x - 30.0))
	for nm: String in ["Cloudfall", "Cloud Bank"]:
		var r := _section(td, nm)
		if r.x >= 0.0:
			out.append(r)
	return out


static func _arch(mk: MeshKit, hit: TrackData.Hit, k: int) -> void:
	var xl := -(hit.half_l + TrackMesh.WALL_T + 1.0)
	var xr := hit.half_r + TrackMesh.WALL_T + 1.0
	var spring_h := 7.5
	var rise := 6.0
	var foot_l := hit.c + hit.B * xl - hit.N * 0.5
	var foot_r := hit.c + hit.B * xr - hit.N * 0.5
	var pts: Array[Vector3] = []
	var steps := 8
	for q in steps + 1:
		var a := PI * q / steps
		var d := lerpf(xl, xr, 0.5 - cos(a) * 0.5)
		pts.append(hit.c + hit.B * d + hit.N * (spring_h + sin(a) * rise))
	mk.use("white_metal")
	mk.beam(foot_l, pts[0], 0.7, 0.9, Color(0.97, 0.96, 0.94), hit.T)
	mk.beam(foot_r, pts[steps], 0.7, 0.9, Color(0.97, 0.96, 0.94), hit.T)
	for q in steps:
		mk.beam(pts[q], pts[q + 1], 0.6, 0.9, Color(0.97, 0.96, 0.94), hit.T)
	# Lamps under the arch, a coloured band on every fourth.
	mk.use("lamp")
	for q: int in [2, 4, 6]:
		mk.box_t(Transform3D(Basis(hit.B, hit.N, -hit.T), pts[q] - hit.N * 0.65), Vector3(1.4, 0.25, 0.5), Color.WHITE)
	if k % 4 == 0:
		mk.use("neon_cyan" if k % 8 == 0 else "neon_magenta")
		for q in steps:
			mk.beam(pts[q] + hit.T * 0.5, pts[q + 1] + hit.T * 0.5, 0.18, 0.18, Color.WHITE, hit.T)


## The shared light gates with team boards, away from the gantry viaducts.
static func _gates(td: TrackData, root: Node3D) -> void:
	var ranges := _gantry_ranges(td)
	var jump := _section(td, "Skygap Jump")
	ranges.append(Vector2(jump.x - 160.0, jump.y + 60.0))
	var cells: Dictionary = {}
	var last := -1000.0
	for i in td.count:
		var s := i * td.step
		if s - last < 230.0 or s < 260.0 or s > td.length - 120.0:
			continue
		if td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 40, TrackData.F_TUNNEL) or td.flag_at_index(i - 40, TrackData.F_TUNNEL):
			continue
		var blocked := false
		for r in ranges:
			if s > r.x - 30.0 and s < r.y + 30.0:
				blocked = true
		if blocked:
			continue
		last = s
		var key := Vector2i(floori(td.pos[i].x / CELL), floori(td.pos[i].z / CELL))
		if not cells.has(key):
			cells[key] = MeshKit.new()
		HelixBay._gate(cells[key], td, i, int(s / 230.0) * 2)
	_flush(cells, root, "Gates", true)


# ------------------------------------------------------------------ towers

## Slender towers rising out of the clouds around the circuit.
static func _towers(td: TrackData, root: Node3D) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, td.count, 10):
		lo = Vector2(minf(lo.x, td.pos[i].x), minf(lo.y, td.pos[i].z))
		hi = Vector2(maxf(hi.x, td.pos[i].x), maxf(hi.y, td.pos[i].z))
	var cells: Dictionary = {}
	var want := int(80 * float(Quality.p["city"]))
	var placed := 0
	var tries := 0
	while placed < want and tries < 3000:
		tries += 1
		var p := Vector2(rng.randf_range(lo.x - 1300.0, hi.x + 1300.0), rng.randf_range(lo.y - 1300.0, hi.y + 1300.0))
		var rr := rng.randf_range(9.0, 20.0)
		var near := _track_dist(td, p, 400.0)
		if near < rr + 48.0:
			continue
		# Denser near the track, thinning out beyond.
		if near == INF and rng.randf() < 0.55:
			continue
		if not _free(p, rr + 25.0):
			continue
		_occupied.append(Vector3(p.x, p.y, rr + 6.0))
		var base := Vector3(p.x, CLOUD_Y - 45.0, p.y)
		var h := rng.randf_range(150.0, 330.0) + (60.0 if near < 200.0 else 0.0)
		_tower(_cell_mk(cells, base), base, rr, h)
		placed += 1
	_flush(cells, root, "Towers", false)
	if DevArgs.has("--load-times"):
		print("skyport towers %d (%d tries)" % [placed, tries])


const STONES := [Color(0.95, 0.92, 0.86), Color(0.9, 0.88, 0.86), Color(0.96, 0.9, 0.82), Color(0.86, 0.87, 0.9), Color(0.93, 0.86, 0.8)]


static func _tower(mk: MeshKit, base: Vector3, r: float, h: float) -> void:
	var tint: Color = STONES[rng.randi() % STONES.size()]
	var glass := Color(tint.r, tint.g, tint.b, 0.5 if rng.randf() < 0.6 else 1.0)
	var plain := Color(tint.r, tint.g, tint.b, 0.0)
	var kind := rng.randi() % 4
	mk.use("stone")
	match kind:
		0:
			# Needle: round shaft, platform discs, tapering crown and spire.
			var sides := 10
			HelixBay.prism(mk, base, r, sides, h, glass, r * 0.85)
			var discs := rng.randi_range(1, 2)
			for q in discs:
				var y := base.y + h * rng.randf_range(0.55, 0.92)
				HelixBay.prism(mk, Vector3(base.x, y, base.z), r + rng.randf_range(5.0, 10.0), 14, 2.5, plain)
				mk.use("lamp")
				mk.torus(Vector3(base.x, y + 0.2, base.z), Vector3.UP, r * 0.9 + 0.3, 0.2, 12, 3, Color.WHITE)
				mk.use("stone")
			HelixBay.prism(mk, base + Vector3(0, h, 0), r * 0.85, sides, r * 1.6, plain, 1.2)
			mk.use("warn_red")
			mk.sphere(base + Vector3(0, h + r * 1.6 + 0.8, 0), Vector3(0.8, 0.8, 0.8), 3, 6, Color.WHITE)
		1:
			# Slab: glass curtain wall with a stone crown.
			var rot := rng.randf() * PI
			var sz := Vector3(r * 2.0, h, r * 1.2)
			HelixBay.block(mk, base, sz, Color(tint.r, tint.g, tint.b, 1.0), rot)
			HelixBay.block(mk, base + Vector3(0, h, 0), Vector3(sz.x * 0.7, 10.0, sz.z * 0.7), plain, rot)
			mk.use("lamp")
			HelixBay.block(mk, base + Vector3(0, h - 0.6, 0), Vector3(sz.x + 0.3, 0.4, sz.z + 0.3), Color.WHITE, rot)
		2:
			# Twin shafts joined by sky bridges.
			var off := Vector3(r * 1.3, 0, 0).rotated(Vector3.UP, rng.randf() * PI)
			var h2 := h * rng.randf_range(0.75, 0.95)
			HelixBay.prism(mk, base + off, r * 0.6, 8, h, glass, r * 0.5)
			HelixBay.prism(mk, base - off, r * 0.6, 8, h2, glass, r * 0.5)
			for y: float in [h2 * 0.55, h2 * 0.85]:
				mk.beam(base + off + Vector3(0, y, 0), base - off + Vector3(0, y, 0), 5.0, 4.0, plain)
			HelixBay.prism(mk, base + off + Vector3(0, h, 0), r * 0.5, 8, 3.0, plain, r * 0.2)
			HelixBay.prism(mk, base - off + Vector3(0, h2, 0), r * 0.5, 8, 3.0, plain, r * 0.2)
		3:
			# Pad tower: shaft with a broad landing disc on top.
			HelixBay.prism(mk, base, r * 0.8, 10, h, glass, r * 0.6)
			HelixBay.prism(mk, base + Vector3(0, h - 6.0, 0), r * 0.6, 10, 6.0, plain, r * 2.4)
			HelixBay.prism(mk, base + Vector3(0, h, 0), r * 2.4, 18, 1.5, plain)
			mk.use("lamp")
			mk.torus(base + Vector3(0, h + 1.6, 0), Vector3.UP, r * 2.2, 0.25, 18, 3, Color.WHITE)
			mk.use("warn_red")
			mk.sphere(base + Vector3(r * 2.3, h + 2.2, 0), Vector3(0.6, 0.6, 0.6), 3, 6, Color.WHITE)
	mk.use("stone")


# ------------------------------------------------------------------ far scenery

## Snowy peaks piercing the clouds far out, cumulus heads around the circuit
## and small puffs drifting below the decks.
static func _far(td: TrackData, root: Node3D) -> void:
	var c := Vector3.ZERO
	var n := 0
	for i in range(0, td.count, 20):
		c += td.pos[i]
		n += 1
	c /= maxf(n, 1)
	c.y = CLOUD_Y
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 1.3
	# Peaks.
	var pk := MeshKit.new()
	pk.use("peak")
	for k in 11:
		var az := TAU * (k + rng.randf_range(-0.3, 0.3)) / 11.0
		var dist := rng.randf_range(5400.0, 7800.0)
		var hgt := rng.randf_range(600.0, 1500.0)
		var p := c + Vector3(cos(az) * dist, -80.0, sin(az) * dist)
		# A massif: the main summit and two or three lower shoulders around it.
		_peak(pk, p, hgt, hgt * rng.randf_range(0.65, 0.85), noise, k * 4)
		for q in rng.randi_range(2, 3):
			var off := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * hgt * rng.randf_range(0.5, 0.9)
			var h2 := hgt * rng.randf_range(0.45, 0.75)
			_peak(pk, p + off, h2, h2 * rng.randf_range(0.7, 0.95), noise, k * 4 + q + 1)
	var pmi := pk.instance("Peaks", _mats)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pmi)
	# Cumulus heads.
	var cu := MeshKit.new()
	cu.use("cloud")
	var heads := 0
	var tries := 0
	while heads < 30 and tries < 400:
		tries += 1
		var az := rng.randf() * TAU
		var dist := rng.randf_range(1100.0, 6500.0)
		var p := c + Vector3(cos(az) * dist, 0.0, sin(az) * dist)
		var base_r := rng.randf_range(110.0, 260.0)
		if _track_dist(td, Vector2(p.x, p.z), base_r + 250.0) < INF or not _free(Vector2(p.x, p.z), base_r):
			continue
		var y := CLOUD_Y - base_r * 0.25
		var r := base_r
		var lumps := rng.randi_range(2, 5)
		for q in lumps:
			var off := Vector3(rng.randf_range(-0.3, 0.3) * r, 0.0, rng.randf_range(-0.3, 0.3) * r)
			cu.blob(p + off + Vector3(0, y, 0), Vector3(r, r * 0.62, r), 2 if dist < 3500.0 else 1, noise, 0.28, Color(1, 1, 1), Color(0.9, 0.86, 0.9), false, Vector3(heads * 2.3, q, 0))
			for side in 2:
				var sr := r * rng.randf_range(0.45, 0.65)
				var so := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * r * 0.75
				cu.blob(p + off + so + Vector3(0, y - r * 0.1, 0), Vector3(sr, sr * 0.7, sr), 1, noise, 0.3, Color(1, 1, 1), Color(0.9, 0.86, 0.9), false, Vector3(heads, q, side))
			y += r * rng.randf_range(0.5, 0.75)
			r *= rng.randf_range(0.6, 0.78)
		heads += 1
	# Puffs drifting below the decks, between the towers.
	var puffs := 0
	tries = 0
	while puffs < 40 and tries < 600:
		tries += 1
		var i := rng.randi() % td.count
		var b := Vector3(td.rgt[i].x, 0.0, td.rgt[i].z).normalized()
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := td.pos[i] + b * side * rng.randf_range(90.0, 320.0)
		var r := rng.randf_range(14.0, 36.0)
		p.y = rng.randf_range(CLOUD_Y + 8.0, minf(td.pos[i].y - 30.0, CLOUD_Y + 60.0))
		if _track_dist(td, Vector2(p.x, p.z), r + 40.0) < INF or not _free(Vector2(p.x, p.z), r):
			continue
		cu.blob(p, Vector3(r * 1.6, r * 0.6, r), 1, noise, 0.3, Color(1, 1, 1), Color(0.9, 0.86, 0.9), false, Vector3(puffs, 7, 0))
		puffs += 1
	var cmi := cu.instance("Cumulus", _mats)
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cmi)


## A faceted mountain: a noisy cone with snow above the shoulder.
static func _peak(mk: MeshKit, base: Vector3, h: float, r: float, noise: FastNoiseLite, seed_k: int) -> void:
	var sides := 12
	var rings := 6
	var ridge_ph := seed_k * 1.7
	var pts: Array[PackedVector3Array] = []
	for j in rings + 1:
		var t := float(j) / rings
		var ring := PackedVector3Array()
		for k in sides:
			var a := TAU * k / sides
			var dir := Vector3(cos(a), 0.0, sin(a))
			# Spurs (ridges) radiating from the summit, broken up by noise.
			var spur := 0.55 + 0.45 * absf(cos(a * 1.5 + ridge_ph))
			var rr := r * pow(1.0 - t, 1.15) * spur * (0.6 + 0.8 * (noise.get_noise_3d(cos(a) * 2.5, t * 3.0, seed_k * 5.0 + sin(a) * 2.5) * 0.5 + 0.5))
			var y := h * pow(t, 0.8) + noise.get_noise_2d(a * 4.0 + seed_k * 7.0, t * 5.0) * h * 0.08 * (1.0 - t)
			if j == rings:
				rr = 0.0
				y = h
			ring.append(base + dir * rr + Vector3(0, y, 0))
		pts.append(ring)
	for j in rings:
		for k in sides:
			var a := pts[j][k]
			var b := pts[j][(k + 1) % sides]
			var c := pts[j + 1][(k + 1) % sides]
			var d := pts[j + 1][k]
			for tri: Array in [[a, d, c], [a, c, b]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var nn := (p2 - p0).cross(p1 - p0)
				if nn.length() < 0.001:
					continue
				nn = nn.normalized()
				if nn.dot((p0 + p1 + p2) / 3.0 - (base + Vector3(0, h * 0.4, 0))) < 0.0:
					nn = -nn
					var tmp := p1
					p1 = p2
					p2 = tmp
				var my := ((p0.y + p1.y + p2.y) / 3.0 - base.y) / h
				var snow := smoothstep(0.3, 0.45, my + noise.get_noise_2d(p0.x * 0.01, p0.z * 0.01) * 0.15 + nn.y * 0.25)
				var col := Color(0.24, 0.21, 0.26).lerp(Color(0.98, 0.96, 0.98), snow)
				var i0 := mk._vert(p0, nn, col)
				var i1 := mk._vert(p1, nn, col)
				var i2 := mk._vert(p2, nn, col)
				mk._tri(i0, i1, i2)
