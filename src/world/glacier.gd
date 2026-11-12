## GLACIER RING world: the Svalbard Ice Laboratory under the aurora.
##
## Snow terrain is a heightfield that always stays under the track corridor
## (the deck rides on pylons over the ice shelf and fjord). The glacier the
## Crevasse Tunnel goes through is separate geometry (a lofted ice ridge with
## portal faces), because a heightfield cannot contain a tunnel. The research
## station (domes, radar dishes, habitat modules on stilts, masts, turbines)
## sits around the Station Esses and the Radar Hairpin.
class_name Glacier
extends RefCounted

const GRID := 32.0
const MARGIN := 1400.0

static var rng := RandomNumberGenerator.new()


## Track proximity: horizontal hash of the centre line (every 3 m).
class Near:
	var cell: float = 48.0
	var map: Dictionary = {}
	var td: TrackData

	func _init(p_td: TrackData) -> void:
		td = p_td
		var i := 0
		while i < td.count:
			var p := td.pos[i]
			var k := Vector2i(floori(p.x / cell), floori(p.z / cell))
			if not map.has(k):
				map[k] = PackedInt32Array()
			(map[k] as PackedInt32Array).append(i)
			i += 3

	## [horizontal distance, track height there, half width] of the nearest sample.
	func query(x: float, z: float) -> Array:
		var cx := floori(x / cell)
		var cz := floori(z / cell)
		var best := INF
		var by := 0.0
		var bw := 15.0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var k := Vector2i(cx + dx, cz + dz)
				if not map.has(k):
					continue
				for i in (map[k] as PackedInt32Array):
					var p := td.pos[i]
					var dd := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
					if dd < best:
						best = dd
						by = p.y
						bw = maxf(td.half_l[i], td.half_r[i])
		return [sqrt(best) if best < INF else 1e6, by, bw]


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 7302
	var t0 := Time.get_ticks_msec()
	_environment(root)
	var near := Near.new(td)
	var hf := _terrain(td, root, near)
	_ice(root, hf)
	_ridge(td, root)
	_tunnel(td, root)
	_trackside(td, root, near, hf)
	HelixBay._start_gantry(td, root, "GLACIER RING  /  SVALBARD ICE LABORATORY")
	_station(td, root, near, hf)
	_snowfall(root)
	if DevArgs.has("--load-times"):
		print("glacier world %d ms" % (Time.get_ticks_msec() - t0))


static func _environment(root: Node3D) -> void:
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			var sm := ShaderMaterial.new()
			sm.shader = load("res://assets/shaders/sky_aurora.gdshader")
			env.sky.sky_material = sm
			env.ambient_light_energy = 1.0
			env.fog_light_color = Color(0.55, 0.65, 0.78)
			env.fog_density = 0.0007
			env.fog_aerial_perspective = 0.6
			env.fog_sky_affect = 0.0
			env.tonemap_exposure = 0.95
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.rotation = Vector3(deg_to_rad(-11.0), deg_to_rad(160.0), 0.0)
			sun.light_color = Color(1.0, 0.72, 0.6)
			sun.light_energy = 0.85
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-20.0), 0.0)
	fill.light_color = Color(0.45, 0.8, 0.7)
	fill.light_energy = 0.25
	root.add_child(fill)


## Height field data, kept for placing objects on the ground.
class HF:
	var x0: float
	var z0: float
	var nx: int
	var nz: int
	var h := PackedFloat32Array()

	func at(x: float, z: float) -> float:
		var fx := clampf((x - x0) / GRID, 0.0, nx - 1.001)
		var fz := clampf((z - z0) / GRID, 0.0, nz - 1.001)
		var ix := int(fx)
		var iz := int(fz)
		var tx := fx - ix
		var tz := fz - iz
		var a := lerpf(h[iz * nx + ix], h[iz * nx + ix + 1], tx)
		var b := lerpf(h[(iz + 1) * nx + ix], h[(iz + 1) * nx + ix + 1], tx)
		return lerpf(a, b, tz)


static func _terrain(td: TrackData, root: Node3D, near: Near) -> HF:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, td.count, 8):
		lo = Vector2(minf(lo.x, td.pos[i].x), minf(lo.y, td.pos[i].z))
		hi = Vector2(maxf(hi.x, td.pos[i].x), maxf(hi.y, td.pos[i].z))
	var hf := HF.new()
	hf.x0 = lo.x - MARGIN
	hf.z0 = lo.y - MARGIN
	hf.nx = int((hi.x - lo.x + 2.0 * MARGIN) / GRID) + 1
	hf.nz = int((hi.y - lo.y + 2.0 * MARGIN) / GRID) + 1
	hf.h.resize(hf.nx * hf.nz)
	var mtn := FastNoiseLite.new()
	mtn.seed = 11
	mtn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mtn.frequency = 0.0009
	mtn.fractal_type = FastNoiseLite.FRACTAL_FBM
	mtn.fractal_octaves = 4
	mtn.fractal_gain = 0.45
	var low := FastNoiseLite.new()
	low.seed = 3
	low.frequency = 0.0016
	var centre := (lo + hi) * 0.5
	for iz in hf.nz:
		for ix in hf.nx:
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var q: Array = near.query(x, z)
			var d: float = q[0]
			# Broad undulation: the fjord ice shows wherever this dips below 0.
			var base := 1.5 + 9.0 * (low.get_noise_2d(x, z) * 0.5 + 0.5)
			# Mountains grow away from the circuit and towards the edge of the map.
			var edge := clampf((Vector2(x, z) - centre).length() / (hi - lo).length() * 1.6 - 0.2, 0.0, 1.0)
			var far := smoothstep(70.0, 650.0, d) * (0.45 + 0.55 * edge)
			var m := pow(maxf(mtn.get_noise_2d(x, z) * 0.5 + 0.5, 0.0), 1.8)
			var hgt := base + m * 240.0 * far
			if d < 1e5:
				# Under the track corridor the ground stays below the deck.
				var limit: float = float(q[1]) - TrackMesh.DECK - 3.0
				var w: float = float(q[2]) + 45.0
				var k := 1.0 - smoothstep(w, w + 140.0, d)
				hgt = lerpf(hgt, minf(hgt, limit), k)
			hf.h[iz * hf.nx + ix] = hgt
	var mk := MeshKit.new()
	mk.use("snow")
	var base_i := mk.group_vertex_count()
	for iz in hf.nz:
		for ix in hf.nx:
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var hl := hf.h[iz * hf.nx + maxi(ix - 1, 0)]
			var hr := hf.h[iz * hf.nx + mini(ix + 1, hf.nx - 1)]
			var hd := hf.h[maxi(iz - 1, 0) * hf.nx + ix]
			var hu := hf.h[mini(iz + 1, hf.nz - 1) * hf.nx + ix]
			var n := Vector3(hl - hr, 2.0 * GRID, hd - hu).normalized()
			mk._vert(Vector3(x, hf.h[iz * hf.nx + ix], z), n, Color.WHITE, Vector2(x, z))
	for iz in hf.nz - 1:
		for ix in hf.nx - 1:
			var a := base_i + iz * hf.nx + ix
			# Clockwise seen from above (+Y, north up): a, a+1, a+1+nx, a+nx.
			mk._quad_i(a, a + 1, a + hf.nx + 1, a + hf.nx)
	var mi := mk.instance("Terrain", {"snow": Mats.shader_mat("snow")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return hf


static func _ice(root: Node3D, hf: HF) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hf.nx * GRID, hf.nz * GRID)
	mi.mesh = pm
	mi.position = Vector3(hf.x0 + hf.nx * GRID * 0.5, 0.0, hf.z0 + hf.nz * GRID * 0.5)
	mi.material_override = Mats.shader_mat("fjord_ice")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## The glacier ridge the Crevasse Tunnel passes through: a lofted mound over
## the tunnel with steep ice faces around the portals.
static func _ridge(td: TrackData, root: Node3D) -> void:
	var mk := MeshKit.new()
	var noise := FastNoiseLite.new()
	noise.seed = 21
	noise.frequency = 0.02
	var prev := PackedVector3Array()
	var first_sec := PackedVector3Array()
	var last_sec := PackedVector3Array()
	var i := 0
	var tunnel_rows := []
	while i < td.count:
		if td.flag_at_index(i, TrackData.F_TUNNEL):
			tunnel_rows.append(i)
		i += 6
	if tunnel_rows.is_empty():
		return
	# Extend the mound a little beyond the portals so the faces read as cliffs.
	var rows: Array = []
	for k in range(-3, 0):
		rows.append(td.wrap_i(int(tunnel_rows[0]) + k * 6))
	rows.append_array(tunnel_rows)
	for k in range(1, 4):
		rows.append(td.wrap_i(int(tunnel_rows[tunnel_rows.size() - 1]) + k * 6))
	var secs: Array[PackedVector3Array] = []
	for r in rows.size():
		var j: int = rows[r]
		var inside := td.flag_at_index(j, TrackData.F_TUNNEL)
		var c := td.pos[j]
		var right := Vector3(td.rgt[j].x, 0, td.rgt[j].z).normalized()
		var hw := maxf(td.half_l[j], td.half_r[j]) + 1.0
		var sec := PackedVector3Array()
		var crest := c.y + td.ceiling[j] + 14.0 + 10.0 * noise.get_noise_1d(r * 7.0) if inside else c.y + 6.0
		for k in 13:
			var a := PI * k / 12.0
			var spread := hw + 60.0 + 25.0 * noise.get_noise_2d(r * 3.0, k * 5.0)
			var x := cos(a) * spread
			var y := c.y - 30.0 + sin(a) * (crest - c.y + 30.0) * (1.0 + 0.08 * noise.get_noise_2d(k * 9.0, r * 2.0))
			sec.append(c + right * x + Vector3(0, y - c.y, 0))
		secs.append(sec)
	mk.use("snow")
	mk.loft(secs, Color(0.92, 0.95, 1.0), false, true)
	# Portal faces: a frame of ice around each tunnel mouth.
	for end in 2:
		var j: int = tunnel_rows[0] if end == 0 else tunnel_rows[tunnel_rows.size() - 1]
		var c := td.pos[j]
		var b := Basis(td.rgt[j], Vector3.UP, -td.tan[j])
		var hl := td.half_l[j] + TrackMesh.WALL_T + 0.5
		var hr := td.half_r[j] + TrackMesh.WALL_T + 0.5
		var ceil_h := td.ceiling[j] + 0.5
		var crest := c.y + ceil_h + 18.0
		var inner := [Vector3(-hl, -TrackMesh.DECK, 0), Vector3(-hl, ceil_h * 0.6, 0), Vector3(0, ceil_h + 0.5, 0), Vector3(hr, ceil_h * 0.6, 0), Vector3(hr, -TrackMesh.DECK, 0)]
		var outer := [Vector3(-hl - 70, -30, 0), Vector3(-hl - 40, crest - c.y - 8.0, 0), Vector3(0, crest - c.y, 0), Vector3(hr + 40, crest - c.y - 8.0, 0), Vector3(hr + 70, -30, 0)]
		mk.use("ice_face")
		for k in 4:
			var p0: Vector3 = c + b * inner[k]
			var p1: Vector3 = c + b * inner[k + 1]
			var q0: Vector3 = c + b * outer[k]
			var q1: Vector3 = c + b * outer[k + 1]
			mk.quad(p0, q0, q1, p1, Color.WHITE, Vector2.ONE, Vector2.ZERO, true)
	var mi := mk.instance("GlacierRidge", {"snow": Mats.shader_mat("snow"), "ice_face": Mats.shader_mat("ice_wall")})
	root.add_child(mi)


static func _tunnel(td: TrackData, root: Node3D) -> void:
	var mk := MeshKit.new()
	var prev := PackedVector3Array()
	var run := 0
	for j in td.count:
		if not td.flag_at_index(j, TrackData.F_TUNNEL):
			prev = PackedVector3Array()
			run = 0
			continue
		var ceil_h := td.ceiling[j]
		var hl := td.half_l[j] + TrackMesh.WALL_T
		var hr := td.half_r[j] + TrackMesh.WALL_T
		var y0 := TrackMesh.WALL_H + 0.18
		var sec := PackedVector3Array()
		for k in 11:
			var a := PI * k / 10.0
			var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
			sec.append(td.pos[j] + td.rgt[j] * d + td.nrm[j] * (y0 + sin(a) * (ceil_h - y0)))
		if prev.size() > 0:
			mk.use("ice_inner")
			var pair: Array[PackedVector3Array] = [prev, sec]
			mk.loft(pair, Color.WHITE, false, false)
		prev = sec
		if run % 10 == 0:
			mk.use("neon_white")
			var top := td.pos[j] + td.nrm[j] * (ceil_h - 0.2)
			mk.box_t(Transform3D(Basis(td.rgt[j], td.nrm[j], -td.tan[j]), top), Vector3(1.0, 0.15, 2.4), Color.WHITE)
		run += 1
	var mi := mk.instance("CrevasseTunnel", {"ice_inner": Mats.shader_mat("ice_wall")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _trackside(td: TrackData, root: Node3D, near: Near, hf: HF) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	for i in td.count:
		var s := i * td.step
		var key := int(s / 400.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 30, TrackData.F_TUNNEL) or td.flag_at_index(i - 30, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 6, TrackData.F_GAP) or td.flag_at_index(i - 6, TrackData.F_GAP)
		var p := td.pos[i]
		if i % 44 == 0 and not tunnel and not gap:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := maxf(hf.at(p.x, p.z), -1.0)
			if under.y - foot > 1.5:
				mk.use("concrete")
				var hgt := under.y - foot
				mk.box(Vector3(under.x, foot + hgt * 0.5, under.z), Vector3(2.6, hgt, 2.6), Color(0.85, 0.88, 0.92), 0.6, 0.25)
				# Snow cap on the cross beam.
				mk.box_t(Transform3D(Basis(td.rgt[i], td.nrm[i], -td.tan[i]), under - td.nrm[i] * 0.5), Vector3((td.half_l[i] + td.half_r[i]) * 0.8, 1.0, 3.0), Color(0.8, 0.82, 0.86))
		if s - last_gate > 210.0 and s > 150.0 and not tunnel and not gap:
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 210.0) * 3 + 2)
		# Reflector posts on the outside of corners (amber), every 18 m.
		if i % 18 == 0 and absf(td.curv_h[i]) > 1.0 / 400.0 and not gap:
			var side := -1.0 if td.curv_h[i] > 0.0 else 1.0
			var edge := (td.half_r[i] + TrackMesh.WALL_T + 0.6) if side > 0.0 else -(td.half_l[i] + TrackMesh.WALL_T + 0.6)
			var pp := p + td.rgt[i] * edge + td.nrm[i] * 2.2
			mk.use("neon_amber")
			mk.box_t(Transform3D(Basis(td.rgt[i], td.nrm[i], -td.tan[i]), pp), Vector3(0.3, 1.2, 0.3), Color.WHITE)
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Trackside%02d" % key))


static func _station(td: TrackData, root: Node3D, near: Near, hf: HF) -> void:
	var mk := MeshKit.new()
	# The station sits inside the loop of the Station Esses and Radar Hairpin.
	var anchor := Vector3.ZERO
	var n := 0
	for sc: Dictionary in td.sections:
		if sc["name"] in ["Station Esses", "Radar Hairpin"]:
			var i0 := int(float(sc["s0"]) / td.step)
			var i1 := int(float(sc["s1"]) / td.step)
			for i in range(i0, i1, 10):
				anchor += td.pos[i]
				n += 1
	anchor /= maxf(n, 1)
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(90.0, 520.0)
		var x := anchor.x + cos(a) * r
		var z := anchor.z + sin(a) * r
		var q: Array = near.query(x, z)
		if float(q[0]) < float(q[2]) + 40.0:
			continue
		var g := hf.at(x, z)
		if g < 0.5 or g > 40.0:
			continue
		var base := Vector3(x, g, z)
		match placed % 6:
			0:
				# Research dome with a lit window ring.
				var rad := rng.randf_range(14.0, 26.0)
				mk.use("dome")
				mk.sphere(base, Vector3(rad, rad * 0.75, rad), 10, 18, Color(0.92, 0.94, 0.97))
				mk.use("neon_cyan")
				mk.torus(base + Vector3(0, rad * 0.22, 0), Vector3.UP, rad * 0.97, 0.35, 32, 3, Color.WHITE)
			1:
				# Radar dish on a lattice tower.
				mk.use("metal")
				mk.cyl(base, base + Vector3(0, 22, 0), 1.6, 1.0, 8, Color.WHITE)
				var prof := PackedVector2Array()
				for k in 8:
					var t := float(k) / 7.0
					prof.append(Vector2(t * 12.0, t * t * 4.0))
				mk.use("dome")
				var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-55.0)).rotated(Vector3.UP, rng.randf() * TAU), base + Vector3(0, 23, 0))
				mk.push(tilt)
				mk.lathe(prof, 18, Color(0.9, 0.92, 0.95))
				mk.pop()
				mk.use("warn_red")
				mk.sphere(base + Vector3(0, 24, 0), Vector3(0.6, 0.6, 0.6), 4, 6, Color.WHITE)
			2, 3:
				# Habitat module on stilts with lit windows.
				var w := rng.randf_range(24.0, 40.0)
				var rot := rng.randf() * PI
				mk.use("metal_dark")
				for sx: float in [-0.4, 0.4]:
					for sz: float in [-0.35, 0.35]:
						var leg := Vector3(sx * w, 0, sz * 12.0).rotated(Vector3.UP, rot)
						mk.box(base + leg + Vector3(0, 3.0, 0), Vector3(0.8, 6.0, 0.8), Color.WHITE)
				mk.use("bld")
				HelixBay.block(mk, base + Vector3(0, 6.0, 0), Vector3(w, 7.0, 12.0), Color(0.75, 0.42, 0.18, 0.5), rot)
				mk.use("neon_amber")
				HelixBay.block(mk, base + Vector3(0, 13.0, 0), Vector3(w + 0.3, 0.4, 12.3), Color.WHITE, rot)
			4:
				# Antenna mast with a warning light.
				var h := rng.randf_range(40.0, 75.0)
				mk.use("metal")
				mk.cyl(base, base + Vector3(0, h, 0), 1.0, 0.25, 6, Color.WHITE)
				mk.use("warn_red")
				mk.sphere(base + Vector3(0, h + 0.6, 0), Vector3(0.8, 0.8, 0.8), 4, 6, Color.WHITE)
			5:
				# Wind turbine.
				mk.use("dome")
				mk.cyl(base, base + Vector3(0, 48, 0), 1.6, 0.9, 10, Color.WHITE)
				mk.box(base + Vector3(0, 48.5, 0), Vector3(2.0, 2.0, 5.0), Color.WHITE)
				for k in 3:
					var ang := TAU * k / 3.0 + rng.randf()
					var tip := base + Vector3(0, 48.5, -2.6) + Vector3(cos(ang), sin(ang), 0) * 22.0
					mk.beam(base + Vector3(0, 48.5, -2.6), tip, 1.2, 0.3, Color.WHITE, Vector3.FORWARD)
		placed += 1
	root.add_child(mk.instance("Station", {"dome": _dome_mat()}))


static func _dome_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.95, 0.96, 0.98)
	m.roughness = 0.35
	m.metallic = 0.1
	return m


## Light snowfall around whatever camera is active.
static func _snowfall(root: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "Snow"
	p.amount = int(700 * float(Quality.p["particles"]))
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-200, -100, -200), Vector3(400, 200, 400))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 30, 90)
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 15.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = Mats.tex("glow")
	mat.albedo_color = Color(1, 1, 1, 0.75)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	var follow := SnowFollow.new()
	follow.particles = p
	root.add_child(follow)


## Keeps the snow emitter centred on the active camera.
class SnowFollow extends Node:
	var particles: GPUParticles3D

	func _process(_d: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam and particles:
			particles.global_position = cam.global_position + Vector3(0, 20, 0) - cam.global_transform.basis.z * 40.0
