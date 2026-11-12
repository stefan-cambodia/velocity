## ATACAMA SPACEPORT world: a high-desert launch complex in full daylight.
##
## Terrain: the shared heightfield (Glacier.HF / Glacier.Near) shaped as salt
## flats, red sand and terraced mesas, with canyon walls raised beside the
## Canyon Entry .. Canyon Drop stretch. Landmarks: the rocket on its launch
## tower inside the Launch Pad Loop, the flame trench under the jump, the
## vehicle assembly hall the track passes through, tracking dishes, the
## control tower and hangars along the runway, solar fields on the salar,
## the crawler, and volcanoes on the horizon.
class_name Spaceport
extends RefCounted

const GRID := 32.0
const MARGIN := 1300.0

static var rng := RandomNumberGenerator.new()
static var last_hf: Glacier.HF       ## For debugging probes (--probe-terrain).
static var last_near: Glacier.Near


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 1969
	var t0 := Time.get_ticks_msec()
	_environment(root)
	var near := Glacier.Near.new(td)
	var canyon := _section_range(td, "Canyon Entry", "Canyon Drop")
	var hf := _terrain(td, root, near, canyon)
	last_hf = hf
	last_near = near
	_volcanoes(root, hf)
	_trackside(td, root, hf)
	HelixBay._start_gantry(td, root, "ATACAMA SPACEPORT  /  VELOCITY LEAGUE")
	_runway(td, root, hf)
	_launch_pad(td, root, hf)
	_trench(td, root)
	_assembly_hall(td, root)
	_site(td, root, near, hf)
	if DevArgs.has("--load-times"):
		print("spaceport world %d ms" % (Time.get_ticks_msec() - t0))


static func _environment(root: Node3D) -> void:
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			var sm := ProceduralSkyMaterial.new()
			sm.sky_top_color = Color(0.08, 0.22, 0.55)
			sm.sky_horizon_color = Color(0.62, 0.72, 0.84)
			sm.sky_curve = 0.18
			sm.ground_horizon_color = Color(0.75, 0.62, 0.52)
			sm.ground_bottom_color = Color(0.45, 0.32, 0.25)
			sm.sun_angle_max = 6.0
			sm.sun_curve = 0.08
			env.sky.sky_material = sm
			env.ambient_light_energy = 0.75
			env.fog_light_color = Color(0.78, 0.72, 0.66)
			env.fog_density = 0.00032
			env.fog_aerial_perspective = 0.7
			env.fog_sky_affect = 0.0
			env.tonemap_exposure = 0.85
			env.glow_hdr_threshold = 1.3
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
			sun.light_color = Color(1.0, 0.95, 0.88)
			sun.light_energy = 1.55


## Lap-distance range [s0, s1] covering the named sections (inclusive).
static func _section_range(td: TrackData, first: String, last: String) -> Vector2:
	var r := Vector2(-1, -1)
	for sc: Dictionary in td.sections:
		if sc["name"] == first:
			r.x = sc["s0"]
		if sc["name"] == last:
			r.y = sc["s1"]
	return r


static func _terrain(td: TrackData, root: Node3D, near: Glacier.Near, canyon: Vector2) -> Glacier.HF:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, td.count, 8):
		lo = Vector2(minf(lo.x, td.pos[i].x), minf(lo.y, td.pos[i].z))
		hi = Vector2(maxf(hi.x, td.pos[i].x), maxf(hi.y, td.pos[i].z))
	var hf := Glacier.HF.new()
	hf.x0 = lo.x - MARGIN
	hf.z0 = lo.y - MARGIN
	hf.nx = int((hi.x - lo.x + 2.0 * MARGIN) / GRID) + 1
	hf.nz = int((hi.y - lo.y + 2.0 * MARGIN) / GRID) + 1
	hf.h.resize(hf.nx * hf.nz)
	var mesa := FastNoiseLite.new()
	mesa.seed = 5
	mesa.frequency = 0.0014
	mesa.fractal_octaves = 3
	var low := FastNoiseLite.new()
	low.seed = 9
	low.frequency = 0.0021
	var centre := (lo + hi) * 0.5
	var pad := _pad_centre(td)
	var field := Glacier.distance_field(td, hf)
	var fd: PackedFloat32Array = field[0]
	var fi: PackedInt32Array = field[1]
	for iz in hf.nz:
		for ix in hf.nx:
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var j := fi[iz * hf.nx + ix]
			var d: float = fd[iz * hf.nx + ix] if j >= 0 else 1e6
			var q: Array = [d, td.pos[j].y if j >= 0 else 0.0, maxf(td.half_l[j], td.half_r[j]) if j >= 0 else 15.0, j]
			var base := 0.6 + 4.0 * (low.get_noise_2d(x, z) * 0.5 + 0.5)
			var edge := clampf((Vector2(x, z) - centre).length() / (hi - lo).length() * 1.5 - 0.15, 0.0, 1.0)
			# Mesas: thresholded noise, flat tops, terraced in 14 m steps.
			var m := mesa.get_noise_2d(x, z) * 0.5 + 0.5
			var mesa_h := smoothstep(0.55, 0.62, m) * (40.0 + 90.0 * edge)
			mesa_h = floorf(mesa_h / 14.0) * 14.0 + fmod(mesa_h, 14.0) * 0.25
			var far := smoothstep(220.0, 620.0, d)
			var hgt := base + mesa_h * far
			# Flat launch apron inside the pad loop.
			var dp := Vector2(x - pad.x, z - pad.z).length()
			hgt = lerpf(1.2, hgt, smoothstep(240.0, 320.0, dp))
			var idx: int = q[3]
			if idx >= 0 and d < 1e5:
				var s := idx * td.step
				var w: float = float(q[2]) + 30.0
				if canyon.x >= 0.0 and s >= canyon.x - 40.0 and s <= canyon.y + 40.0:
					# Canyon walls: rise steeply just outside the corridor.
					var wall := smoothstep(w, w + 70.0, d)
					hgt = maxf(hgt, float(q[1]) + 8.0 + 46.0 * wall * (1.0 - smoothstep(w + 260.0, w + 420.0, d)))
				var limit: float = float(q[1]) - TrackMesh.DECK - 2.0
				var k := 1.0 - smoothstep(w, w + 40.0, d)
				hgt = lerpf(hgt, minf(hgt, limit), k)
			hf.h[iz * hf.nx + ix] = hgt
	var mk := MeshKit.new()
	mk.use("desert")
	var base_i := mk.group_vertex_count()
	for iz in hf.nz:
		for ix in hf.nx:
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var hl := hf.h[iz * hf.nx + maxi(ix - 1, 0)]
			var hr := hf.h[iz * hf.nx + mini(ix + 1, hf.nx - 1)]
			var hd := hf.h[maxi(iz - 1, 0) * hf.nx + ix]
			var hu := hf.h[mini(iz + 1, hf.nz - 1) * hf.nx + ix]
			mk._vert(Vector3(x, hf.h[iz * hf.nx + ix], z), Vector3(hl - hr, 2.0 * GRID, hd - hu).normalized(), Color.WHITE, Vector2(x, z))
	for iz in hf.nz - 1:
		for ix in hf.nx - 1:
			var a := base_i + iz * hf.nx + ix
			mk._quad_i(a, a + 1, a + hf.nx + 1, a + hf.nx)
	var mi := mk.instance("Terrain", {"desert": Mats.shader_mat("desert")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return hf


## Snow-capped volcanoes on the horizon (the Andes behind the salar).
static func _volcanoes(root: Node3D, hf: Glacier.HF) -> void:
	var mk := MeshKit.new()
	var c := Vector3(hf.x0 + hf.nx * GRID * 0.5, 0, hf.z0 + hf.nz * GRID * 0.5)
	for k in 7:
		var a := lerpf(-2.4, -0.6, k / 6.0) + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(5200.0, 6800.0)
		var base := c + Vector3(cos(a) * r, -20.0, sin(a) * r)
		var rad := rng.randf_range(1400.0, 2200.0)
		var hgt := rng.randf_range(900.0, 1500.0)
		var prof := PackedVector2Array([Vector2(rad, 0), Vector2(rad * 0.55, hgt * 0.45), Vector2(rad * 0.2, hgt * 0.88), Vector2(rad * 0.08, hgt)])
		mk.use("rock")
		mk.push(Transform3D(Basis.IDENTITY, base))
		mk.lathe(prof, 20, Color(1.6, 1.0, 0.85))
		mk.pop()
		var cap := PackedVector2Array([Vector2(rad * 0.24, hgt * 0.84), Vector2(rad * 0.2, hgt * 0.88), Vector2(rad * 0.08, hgt + 2.0)])
		mk.use("snowcap")
		mk.push(Transform3D(Basis.IDENTITY, base))
		mk.lathe(cap, 20, Color.WHITE)
		mk.pop()
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.95, 0.96, 1.0)
	snow.roughness = 0.6
	var mi := mk.instance("Volcanoes", {"snowcap": snow})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _trackside(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	for i in td.count:
		var s := i * td.step
		var key := int(s / 400.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 40, TrackData.F_TUNNEL) or td.flag_at_index(i - 40, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 8, TrackData.F_GAP) or td.flag_at_index(i - 8, TrackData.F_GAP)
		var p := td.pos[i]
		if i % 46 == 0 and not tunnel and not gap:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := hf.at(p.x, p.z)
			if under.y - foot > 1.5:
				mk.use("concrete")
				var hgt := under.y - foot
				mk.box(Vector3(under.x, foot + hgt * 0.5, under.z), Vector3(2.8, hgt, 2.8), Color(1.0, 0.9, 0.8), 0.6, 0.25)
		if s - last_gate > 230.0 and s > 160.0 and not tunnel and not gap:
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 230.0) * 2)
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Trackside%02d" % key))


## Runway furniture along the start straights: edge lights, control tower, hangars.
static func _runway(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var mk := MeshKit.new()
	for i in td.count:
		if not td.flag_at_index(i, TrackData.F_START):
			continue
		if i % 25 == 0:
			for side: float in [-1.0, 1.0]:
				var edge := (td.half_r[i] + TrackMesh.WALL_T + 3.0) if side > 0.0 else -(td.half_l[i] + TrackMesh.WALL_T + 3.0)
				var pp := td.pos[i] + td.rgt[i] * edge
				var g := hf.at(pp.x, pp.z)
				mk.use("metal_dark")
				mk.box(Vector3(pp.x, (g + pp.y) * 0.5, pp.z), Vector3(0.3, maxf(pp.y - g, 0.5), 0.3), Color.WHITE)
				mk.use("lamp" if side > 0.0 else "neon_amber")
				mk.box(Vector3(pp.x, pp.y + 0.3, pp.z), Vector3(0.6, 0.4, 0.6), Color.WHITE)
	# Control tower and hangars on the outside (west) of the runway.
	var i0 := td.wrap_i(int(150.0 / td.step))
	var west := -td.rgt[i0]
	var tower := td.pos[i0] + west * 180.0
	tower.y = hf.at(tower.x, tower.z)
	mk.use("concrete")
	mk.cyl(tower, tower + Vector3(0, 70, 0), 5.0, 3.8, 12, Color(1.0, 0.95, 0.9))
	mk.use("glass")
	mk.cyl(tower + Vector3(0, 70, 0), tower + Vector3(0, 78, 0), 7.5, 9.0, 12, Color.WHITE)
	mk.use("concrete")
	mk.cyl(tower + Vector3(0, 78, 0), tower + Vector3(0, 80, 0), 9.4, 6.0, 12, Color(0.9, 0.9, 0.92))
	mk.use("warn_red")
	mk.sphere(tower + Vector3(0, 86, 0), Vector3(0.8, 0.8, 0.8), 4, 6, Color.WHITE)
	mk.use("metal")
	mk.cyl(tower + Vector3(0, 80, 0), tower + Vector3(0, 86, 0), 0.4, 0.2, 6, Color.WHITE)
	for k in 4:
		var j := td.wrap_i(int((-220.0 + k * 140.0) / td.step))
		var hc := td.pos[j] + -td.rgt[j] * 120.0
		hc.y = hf.at(hc.x, hc.z)
		var b := Basis(td.rgt[j], Vector3.UP, -Vector3(td.tan[j].x, 0, td.tan[j].z).normalized())
		# Barrel-roofed hangar: a half cylinder lying across the runway direction.
		mk.use("hangar")
		mk.push(Transform3D(b, hc))
		var prof := PackedVector2Array()
		for q in 9:
			var a := PI * q / 8.0
			prof.append(Vector2(cos(a) * 28.0, sin(a) * 22.0))
		for q in 8:
			var p0 := prof[q]
			var p1 := prof[q + 1]
			mk.quad(Vector3(p0.x, p0.y, -45), Vector3(p1.x, p1.y, -45), Vector3(p1.x, p1.y, 45), Vector3(p0.x, p0.y, 45), Color(0.85, 0.86, 0.88), Vector2.ONE, Vector2.ZERO, true)
		mk.use("metal_dark")
		mk.box(Vector3(0, 9, -45.2), Vector3(44, 18, 0.5), Color.WHITE)
		mk.use("lamp")
		mk.box(Vector3(0, 19.5, -45.4), Vector3(30, 0.4, 0.3), Color.WHITE)
		mk.pop()
	var hangar := StandardMaterial3D.new()
	hangar.vertex_color_use_as_albedo = true
	hangar.roughness = 0.4
	hangar.metallic = 0.6
	root.add_child(mk.instance("Runway", {"hangar": hangar}))


## Centre of the Launch Pad Loop (horizontal), where the rocket stands.
static func _pad_centre(td: TrackData) -> Vector3:
	var r := _section_range(td, "Launch Pad Loop", "Launch Pad Loop")
	var c := Vector3.ZERO
	var n := 0
	var i := int(r.x / td.step) + int((r.y - r.x) / td.step * 0.2)
	while i < int(r.y / td.step) - int((r.y - r.x) / td.step * 0.2):
		c += td.pos[i]
		n += 1
		i += 5
	return c / maxf(n, 1)


## The rocket on its pad in the middle of the Launch Pad Loop, with its tower.
static func _launch_pad(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var c := _pad_centre(td)
	c.y = hf.at(c.x, c.z)
	var mk := MeshKit.new()
	mk.use("concrete")
	mk.cyl(c, c + Vector3(0, 6, 0), 46.0, 40.0, 24, Color(0.9, 0.86, 0.8))
	var pad := c + Vector3(0, 6, 0)
	# Rocket: two stages and a payload fairing, interstage bands, grid fins.
	mk.use("rocket")
	mk.cyl(pad + Vector3(0, 4, 0), pad + Vector3(0, 70, 0), 5.2, 5.2, 20, Color(0.95, 0.95, 0.96))
	mk.cyl(pad + Vector3(0, 70.5, 0), pad + Vector3(0, 98, 0), 5.2, 5.2, 20, Color(0.95, 0.95, 0.96))
	var fair := PackedVector2Array([Vector2(5.4, 0), Vector2(5.4, 8), Vector2(4.6, 14), Vector2(2.8, 19), Vector2(0.05, 22)])
	mk.push(Transform3D(Basis.IDENTITY, pad + Vector3(0, 98.5, 0)))
	mk.lathe(fair, 20, Color(0.97, 0.97, 0.98))
	mk.pop()
	mk.use("metal_dark")
	for y: float in [4.0, 69.8, 98.2]:
		mk.cyl(pad + Vector3(0, y, 0), pad + Vector3(0, y + 0.9, 0), 5.35, 5.35, 20, Color.WHITE, false)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		mk.box_t(Transform3D(Basis(Vector3.UP, -a), pad + Vector3(0, 66, 0) + d * 5.8), Vector3(0.3, 3.0, 2.6), Color.WHITE)
		# Landing legs folded along the first stage.
		mk.beam(pad + Vector3(0, 4.5, 0) + d * 5.4, pad + Vector3(0, 26, 0) + d * 5.5, 0.9, 0.5, Color.WHITE)
	mk.use("engine_glow")
	mk.cyl(pad + Vector3(0, 0.5, 0), pad + Vector3(0, 4, 0), 4.6, 5.0, 20, Color.WHITE)
	# Launch tower: lattice frame with service arms.
	var tw := pad + Vector3(15.0, 0, 0)
	mk.use("tower_red")
	for corner: Vector3 in [Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3)]:
		mk.beam(tw + corner, tw + corner + Vector3(0, 125, 0), 0.8, 0.8, Color.WHITE)
	var y := 0.0
	while y < 125.0:
		for e in 4:
			var a0: Vector3 = [Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3)][e]
			var a1: Vector3 = [Vector3(3, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, 3), Vector3(-3, 0, -3)][e]
			mk.beam(tw + a0 + Vector3(0, y, 0), tw + a1 + Vector3(0, y + 8.0, 0), 0.35, 0.35, Color.WHITE)
			mk.beam(tw + a0 + Vector3(0, y, 0), tw + a1 + Vector3(0, y, 0), 0.4, 0.4, Color.WHITE)
		y += 8.0
	for arm_y: float in [62.0, 96.0]:
		mk.box(tw + Vector3(-7.5, arm_y, 0), Vector3(9.0, 2.2, 2.4), Color.WHITE)
	mk.use("warn_red")
	mk.sphere(tw + Vector3(0, 127, 0), Vector3(1.0, 1.0, 1.0), 4, 6, Color.WHITE)
	var rocket := StandardMaterial3D.new()
	rocket.vertex_color_use_as_albedo = true
	rocket.roughness = 0.35
	rocket.metallic = 0.2
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.18, 0.1)
	red.roughness = 0.55
	red.metallic = 0.5
	root.add_child(mk.instance("LaunchPad", {"rocket": rocket, "tower_red": red}))
	# Venting vapour at the base.
	var vent := GPUParticles3D.new()
	vent.amount = int(60 * float(Quality.p["particles"]))
	vent.lifetime = 5.0
	vent.preprocess = 5.0
	vent.position = pad + Vector3(0, 6, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = 6.0
	pm.emission_ring_inner_radius = 4.0
	pm.emission_ring_height = 1.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(1.5, 0.4, 0)
	pm.scale_min = 4.0
	pm.scale_max = 9.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.5))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	vent.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	var vm := StandardMaterial3D.new()
	vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vm.albedo_texture = Mats.tex("smoke")
	vm.vertex_color_use_as_albedo = true
	vm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = vm
	vent.draw_pass_1 = qm
	vent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(vent)


## Concrete flame trench under the jump gap, scorched dark.
static func _trench(td: TrackData, root: Node3D) -> void:
	var gap_c := Vector3.ZERO
	var dir := Vector3.FORWARD
	var n := 0
	for i in td.count:
		if td.flag_at_index(i, TrackData.F_GAP):
			gap_c += td.pos[i]
			dir = td.tan[i]
			n += 1
	if n == 0:
		return
	gap_c /= n
	var across := Vector3(-dir.z, 0, dir.x).normalized()
	var along := Vector3(dir.x, 0, dir.z).normalized()
	var b := Basis(across, Vector3.UP, -along)
	var floor_y := gap_c.y - 22.0
	var mk := MeshKit.new()
	mk.use("concrete")
	# Two long walls and a floor running across the track.
	for side: float in [-1.0, 1.0]:
		mk.box_t(Transform3D(b, gap_c + along * side * 34.0 + Vector3(0, (floor_y - gap_c.y) * 0.5, 0)), Vector3(260.0, absf(floor_y - gap_c.y) + 4.0, 4.0), Color(0.75, 0.72, 0.68))
	mk.use("scorch")
	mk.box_t(Transform3D(b, Vector3(gap_c.x, floor_y, gap_c.z)), Vector3(260.0, 1.0, 64.0), Color.WHITE)
	var sc := StandardMaterial3D.new()
	sc.albedo_color = Color(0.08, 0.07, 0.06)
	sc.roughness = 0.9
	root.add_child(mk.instance("FlameTrench", {"scorch": sc}))


## The vehicle assembly hall: a vast box the track runs through, lit inside,
## with a rocket stage standing in a bay beside the track.
static func _assembly_hall(td: TrackData, root: Node3D) -> void:
	var idx: Array = []
	for i in td.count:
		if td.flag_at_index(i, TrackData.F_TUNNEL):
			idx.append(i)
	if idx.is_empty():
		return
	var i0: int = idx[0]
	var i1: int = idx[idx.size() - 1]
	var a := td.pos[i0]
	var bpos := td.pos[i1]
	var mid := (a + bpos) * 0.5
	var along := Vector3(bpos.x - a.x, 0, bpos.z - a.z)
	var length := along.length() + 16.0
	along = along.normalized()
	var across := Vector3(-along.z, 0, along.x)
	var basis := Basis(across, Vector3.UP, -along)
	var floor_y := minf(a.y, bpos.y) - TrackMesh.DECK - 6.0
	var w := 110.0
	var h := td.ceiling[i0] + (a.y - floor_y) + 30.0
	var inner_h := td.ceiling[i0] + (a.y - floor_y)
	var mk := MeshKit.new()
	var xf := Transform3D(basis, Vector3(mid.x, floor_y, mid.z))
	var hw := w * 0.5
	var hl := length * 0.5
	# Outer shell (facing out) and inner shell (facing in), except the end walls' openings.
	mk.use("hall_out")
	mk.push(xf)
	mk.quad(Vector3(-hw, h, -hl), Vector3(hw, h, -hl), Vector3(hw, h, hl), Vector3(-hw, h, hl), Color.WHITE)   # roof
	for side: float in [-1.0, 1.0]:
		var x := hw * side
		if side > 0.0:
			mk.quad(Vector3(x, h, -hl), Vector3(x, 0, -hl), Vector3(x, 0, hl), Vector3(x, h, hl), Color.WHITE)
		else:
			mk.quad(Vector3(x, h, hl), Vector3(x, 0, hl), Vector3(x, 0, -hl), Vector3(x, h, -hl), Color.WHITE)
	# End walls with a portal opening around the track (track ~30 m wide, opening 40 x inner_h).
	var ow := 20.0
	for end: float in [-1.0, 1.0]:
		var z := hl * end
		var pts := [[Vector3(-hw, 0, z), Vector3(-ow, 0, z), Vector3(-ow, h, z), Vector3(-hw, h, z)],
			[Vector3(ow, 0, z), Vector3(hw, 0, z), Vector3(hw, h, z), Vector3(ow, h, z)],
			[Vector3(-ow, inner_h, z), Vector3(ow, inner_h, z), Vector3(ow, h, z), Vector3(-ow, h, z)]]
		for q: Array in pts:
			mk.quad(q[0], q[1], q[2], q[3], Color.WHITE, Vector2.ONE, Vector2.ZERO, true)
	mk.pop()
	# Interior: lit ceiling, side walls seen from inside, light rows, a rocket stage in a side bay.
	mk.use("hall_in")
	mk.push(xf)
	var ih := inner_h
	mk.quad(Vector3(-hw + 1, ih, hl), Vector3(hw - 1, ih, hl), Vector3(hw - 1, ih, -hl), Vector3(-hw + 1, ih, -hl), Color(0.8, 0.8, 0.82))
	for side: float in [-1.0, 1.0]:
		var x := (hw - 1.0) * side
		if side > 0.0:
			mk.quad(Vector3(x, ih, hl), Vector3(x, 0, hl), Vector3(x, 0, -hl), Vector3(x, ih, -hl), Color(0.7, 0.72, 0.75))
		else:
			mk.quad(Vector3(x, ih, -hl), Vector3(x, 0, -hl), Vector3(x, 0, hl), Vector3(x, ih, hl), Color(0.7, 0.72, 0.75))
	mk.use("lamp")
	var z := -hl + 10.0
	while z < hl - 5.0:
		for x: float in [-30.0, -10.0, 10.0, 30.0]:
			mk.box(Vector3(x, ih - 0.6, z), Vector3(6.0, 0.3, 1.2), Color.WHITE)
		z += 14.0
	mk.use("rocket")
	for k in 2:
		var bay := Vector3(-38.0 if k == 0 else 38.0, 0, -hl * 0.3 + k * hl * 0.6)
		mk.cyl(bay + Vector3(0, 2, 0), bay + Vector3(0, ih - 6.0, 0), 5.0, 5.0, 16, Color(0.93, 0.93, 0.95))
	mk.use("tower_red")
	for side: float in [-1.0, 1.0]:
		mk.box(Vector3(side * 30.0, ih * 0.55, 0), Vector3(1.5, 1.0, length - 10.0), Color.WHITE)
	mk.pop()
	var out := StandardMaterial3D.new()
	out.albedo_color = Color(0.82, 0.8, 0.76)
	out.albedo_texture = Mats.tex("panel_albedo")
	out.uv1_triplanar = true
	out.uv1_scale = Vector3(0.05, 0.05, 0.05)
	out.roughness = 0.7
	var inn := StandardMaterial3D.new()
	inn.vertex_color_use_as_albedo = true
	inn.albedo_texture = Mats.tex("panel_albedo")
	inn.uv1_triplanar = true
	inn.uv1_scale = Vector3(0.08, 0.08, 0.08)
	inn.roughness = 0.5
	inn.metallic = 0.4
	inn.emission_enabled = true
	inn.emission = Color(0.12, 0.13, 0.15)
	var rocket := StandardMaterial3D.new()
	rocket.vertex_color_use_as_albedo = true
	rocket.roughness = 0.35
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.18, 0.1)
	red.roughness = 0.55
	var mi := mk.instance("AssemblyHall", {"hall_out": out, "hall_in": inn, "rocket": rocket, "tower_red": red})
	root.add_child(mi)
	# Big painted mission mark on the hall's side.
	var lbl := Label3D.new()
	lbl.text = "VELOCITY  ASSEMBLY  HALL  2"
	lbl.font = load("res://assets/fonts/Orbitron.ttf")
	lbl.font_size = 128
	lbl.pixel_size = 0.06
	lbl.modulate = Color(0.25, 0.3, 0.45)
	lbl.shaded = true
	lbl.transform = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(hw + 0.3, h * 0.6, 0))
	root.add_child(lbl)


## Dishes, fuel tanks, solar fields and the crawler, placed clear of the circuit.
static func _site(td: TrackData, root: Node3D, near: Glacier.Near, hf: Glacier.HF) -> void:
	var mk := MeshKit.new()
	# Tracking dishes beside the chicane.
	var r := _section_range(td, "Tracking Chicane", "Dish Bend")
	var placed := 0
	var tries := 0
	while placed < 3 and tries < 200:
		tries += 1
		var i := td.wrap_i(int(rng.randf_range(r.x, r.y) / td.step))
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := td.pos[i] + td.rgt[i] * side * rng.randf_range(70.0, 140.0)
		var q: Array = near.query(p.x, p.z)
		if float(q[0]) < float(q[2]) + 45.0:
			continue
		var base := Vector3(p.x, hf.at(p.x, p.z), p.z)
		mk.use("concrete")
		mk.cyl(base, base + Vector3(0, 14, 0), 4.0, 3.0, 10, Color(0.9, 0.88, 0.85))
		var prof := PackedVector2Array()
		for k in 10:
			var t := float(k) / 9.0
			prof.append(Vector2(t * 24.0, t * t * 8.0))
		mk.use("dish")
		mk.push(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-50.0)).rotated(Vector3.UP, rng.randf() * TAU), base + Vector3(0, 16, 0)))
		mk.lathe(prof, 24, Color.WHITE)
		mk.pop()
		placed += 1
	# Fuel tank farm and solar arrays on the salt flats inside the first sweep.
	var sweep := _section_range(td, "Salar Sweep", "Salt Flat Run")
	var count := 0
	tries = 0
	while count < 14 and tries < 600:
		tries += 1
		var i := td.wrap_i(int(rng.randf_range(sweep.x, sweep.y) / td.step))
		var p := td.pos[i] + td.rgt[i] * rng.randf_range(80.0, 420.0)
		var q: Array = near.query(p.x, p.z)
		if float(q[0]) < float(q[2]) + 50.0:
			continue
		var g := hf.at(p.x, p.z)
		if g > 4.0:
			continue
		var base := Vector3(p.x, g, p.z)
		if count % 3 == 0:
			mk.use("dish")
			mk.sphere(base + Vector3(0, 12, 0), Vector3(10, 10, 10), 8, 16, Color.WHITE)
			mk.use("metal_dark")
			for k in 4:
				var a := TAU * k / 4.0
				mk.beam(base + Vector3(cos(a) * 8, 0, sin(a) * 8), base + Vector3(cos(a) * 6, 10, sin(a) * 6), 0.6, 0.6, Color.WHITE)
		else:
			# A solar array: rows of tilted panels.
			var yaw := rng.randf() * PI
			mk.use("solar")
			for row in 6:
				for col in 8:
					var o := Vector3((col - 3.5) * 5.0, 1.6, (row - 2.5) * 6.0).rotated(Vector3.UP, yaw)
					var t := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-28.0)), base + o)
					mk.box_t(t, Vector3(4.6, 0.1, 3.0), Color.WHITE)
		count += 1
	# The crawler, parked beside the crawlerway.
	var cr := _section_range(td, "Crawlerway", "Crawlerway")
	var ci := td.wrap_i(int((cr.x + cr.y) * 0.5 / td.step))
	var cp := td.pos[ci] + td.rgt[ci] * 80.0
	var cb := Vector3(cp.x, hf.at(cp.x, cp.z), cp.z)
	var yawb := Basis(td.rgt[ci], Vector3.UP, -Vector3(td.tan[ci].x, 0, td.tan[ci].z).normalized())
	mk.use("metal_dark")
	for sx: float in [-14.0, 14.0]:
		for sz: float in [-14.0, 14.0]:
			mk.box_t(Transform3D(yawb, cb + yawb * Vector3(sx, 2.5, sz)), Vector3(8, 5, 12), Color.WHITE)
	mk.use("concrete")
	mk.box_t(Transform3D(yawb, cb + Vector3(0, 8, 0)), Vector3(40, 6, 36), Color(0.75, 0.75, 0.78))
	var dish := StandardMaterial3D.new()
	dish.vertex_color_use_as_albedo = true
	dish.albedo_color = Color(0.95, 0.95, 0.96)
	dish.roughness = 0.4
	dish.cull_mode = BaseMaterial3D.CULL_DISABLED
	var solar := StandardMaterial3D.new()
	solar.albedo_color = Color(0.05, 0.1, 0.25)
	solar.roughness = 0.15
	solar.metallic = 0.6
	root.add_child(mk.instance("Site", {"dish": dish, "solar": solar}))
