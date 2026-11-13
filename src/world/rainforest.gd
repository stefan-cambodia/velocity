## SERRA VERDE world: a rainforest gorge below a hydroelectric dam, in morning rain.
##
## Terrain: the shared height field (Glacier.HF) shaped as a forested plateau
## with mountains beyond, a lake basin behind the dam, the river gorge and the
## ravine of a side stream that passes under the Falls Jump. The river path is
## derived from the track: it leaves the foot of the dam, joins the gorge and
## runs 48 m off the River Run's right side, then carries on downstream. The
## stream starts at the Veil, a cascade off the plateau beside the jump.
##
## Structures: the gravity dam under the start straight (outlet falls,
## powerhouse, penstocks), the cable-stayed Sky Bridge, and the rock grotto
## with a waterfall curtain across its exit. Cascades run down the far gorge
## walls. Forest: instanced trees within ~600 m of the track; beyond that the
## terrain shader draws the canopy. Weather: rain, low mist, a wet track.
class_name Rainforest
extends RefCounted

const GRID := 32.0
const MARGIN := 1500.0
const RIVER_Y := 2.0          ## River and stream surface.
const LAKE_Y := 54.0          ## Reservoir surface (the crest deck is at 60).
const RIVER_OFF := 30.0       ## River centre, metres to the right of the River Run.

static var rng := RandomNumberGenerator.new()
static var last_hf: Glacier.HF
static var _fd := PackedFloat32Array()   ## Track distance per height-field node.
static var _fi := PackedInt32Array()     ## Nearest track sample per node.
static var _veil := PackedVector2Array() ## Veil cascade: [lip-side source, pool].
static var _rf := PackedFloat32Array()   ## River distance per height-field node.
static var _sf := PackedFloat32Array()   ## Stream distance per height-field node.
static var _keep_clear: Array[Vector3] = []   ## (x, z, radius) spots trees must leave open.


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 1500
	_keep_clear.clear()
	var t0 := Time.get_ticks_msec()
	_environment(root)
	var river := _river_path(td)
	var stream := _stream_path(td, river)
	var hf := _terrain(td, root, river, stream)
	last_hf = hf
	for a in DevArgs.all():
		if a.begins_with("--dump-terrain="):
			_debug_map(td, hf, river, stream, a.substr(15))
			var h := TrackData.Hit.new()
			for sx: float in [150.0, 2200.0]:
				td.frame_at(sx, h)
				var row := "s=%.0f deck y %.1f |" % [sx, h.c.y]
				for dd: float in [-800.0, -400.0, -200.0, -100.0, -50.0, -25.0, 16.0, 30.0, 60.0, 90.0]:
					var q := h.c + h.B * dd
					row += " %+.0f:%.1f" % [dd, hf.at(q.x, q.z)]
				print(row)
	_water(root, hf)
	_dam(td, root, hf)
	_bridge(td, root, hf)
	_grotto(td, root)
	_falls(root, hf, river)
	_forest(td, root, hf)
	_trackside(td, root, hf)
	_rain(root)
	HelixBay._start_gantry(td, root, "SERRA VERDE  /  VELOCITY LEAGUE")
	if DevArgs.has("--load-times"):
		print("rainforest world %d ms" % (Time.get_ticks_msec() - t0))


static func _environment(root: Node3D) -> void:
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			var sm := ProceduralSkyMaterial.new()
			sm.sky_top_color = Color(0.3, 0.42, 0.52)
			sm.sky_horizon_color = Color(0.78, 0.8, 0.76)
			sm.sky_curve = 0.18
			sm.ground_horizon_color = Color(0.55, 0.6, 0.55)
			sm.ground_bottom_color = Color(0.14, 0.2, 0.12)
			sm.sun_angle_max = 35.0
			sm.sun_curve = 0.3
			env.sky.sky_material = sm
			env.ambient_light_energy = 0.9
			env.fog_light_color = Color(0.72, 0.78, 0.74)
			env.fog_density = 0.0008
			env.fog_aerial_perspective = 0.6
			env.fog_sky_affect = 0.45
			env.fog_height = 24.0
			env.fog_height_density = 0.02
			env.tonemap_exposure = 1.05
			env.glow_hdr_threshold = 1.15
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(-60.0), 0.0)
			sun.light_color = Color(1.0, 0.94, 0.82)
			sun.light_energy = 1.15
	(Mats.get_mat("track") as ShaderMaterial).set_shader_parameter("wetness", 0.85)


static func _section(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


# ------------------------------------------------------------------ paths

## River centre line (x, z), upstream to downstream.
static func _river_path(td: TrackData) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hit := TrackData.Hit.new()
	var crest := _section(td, "Dam Crest")
	td.frame_at((crest.x + crest.y) * 0.5, hit)
	var foot := _xz(hit.c + hit.B * 75.0)
	var g0 := _section(td, "Gorge Esses").x
	var g1 := _section(td, "Falls Grotto").x
	td.frame_at(g0, hit)
	var first := _xz(hit.c + hit.B * RIVER_OFF)
	# Upstream reach: a quadratic curve from the dam foot, leaving it at right
	# angles to the crest and swinging into the gorge.
	td.frame_at((crest.x + crest.y) * 0.5, hit)
	var ctrl := foot + _xz(hit.B).normalized() * (first - foot).length() * 0.6
	for k in 24:
		var t := k / 24.0
		pts.append(foot.lerp(ctrl, t).lerp(ctrl.lerp(first, t), t))
	var s := g0
	while s <= g1:
		td.frame_at(s, hit)
		pts.append(_xz(hit.c + hit.B * RIVER_OFF))
		s += 15.0
	# Downstream: on in the last direction, meandering gently, out past the terrain.
	var last := pts[pts.size() - 1]
	var dir := (last - pts[pts.size() - 4]).normalized()
	var side := Vector2(-dir.y, dir.x)
	for k in range(1, 60):
		pts.append(last + dir * (k * 40.0) + side * sin(k * 0.13) * 35.0 * smoothstep(0.0, 6.0, float(k)))
	return pts


## Stream from the Veil's pool, under the Falls Jump gap, to the river.
static func _stream_path(td: TrackData, river: PackedVector2Array) -> PackedVector2Array:
	var hit := TrackData.Hit.new()
	var jump := _section(td, "Falls Jump")
	td.frame_at(jump.x + 130.0, hit)       # middle of the 60 m gap after the 100 m kicker
	var gap := _xz(hit.c)
	var left := -_xz(hit.B).normalized()
	var pool := gap + left * 85.0
	_veil = PackedVector2Array([gap + left * 140.0, pool])
	var out := gap - left * 120.0
	var join := river[0]
	for p in river:
		if p.distance_to(out) < join.distance_to(out):
			join = p
	return PackedVector2Array([pool, gap, out, out.lerp(join, 0.5) + (out - gap).normalized() * 40.0, join])


## Nearest point of a polyline for every height-field node (same two-pass
## propagation as Glacier.distance_field). Returns [dist, index into dense points].
static func _poly_field(line: PackedVector2Array, hf: Glacier.HF) -> Array:
	var dense := PackedVector2Array()
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var steps := maxi(1, int(a.distance_to(b) / 8.0))
		for q in steps:
			dense.append(a.lerp(b, float(q) / steps))
	dense.append(line[line.size() - 1])
	var n := hf.nx * hf.nz
	var dist := PackedFloat32Array()
	var idx := PackedInt32Array()
	dist.resize(n)
	idx.resize(n)
	dist.fill(1e9)
	idx.fill(-1)
	for i in dense.size():
		var p := dense[i]
		var gx := int(round((p.x - hf.x0) / GRID))
		var gz := int(round((p.y - hf.z0) / GRID))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var x := gx + dx
				var z := gz + dz
				if x < 0 or z < 0 or x >= hf.nx or z >= hf.nz:
					continue
				var k := z * hf.nx + x
				var d := Vector2(hf.x0 + x * GRID - p.x, hf.z0 + z * GRID - p.y).length()
				if d < dist[k]:
					dist[k] = d
					idx[k] = i
	var passes := [[[-1, 0], [0, -1], [-1, -1], [1, -1]], [[1, 0], [0, 1], [1, 1], [-1, 1]]]
	for pass_i in 2:
		var nbs: Array = passes[pass_i]
		for zz in hf.nz:
			var z := zz if pass_i == 0 else hf.nz - 1 - zz
			for xx in hf.nx:
				var x := xx if pass_i == 0 else hf.nx - 1 - xx
				var k := z * hf.nx + x
				var w := Vector2(hf.x0 + x * GRID, hf.z0 + z * GRID)
				for nb: Array in nbs:
					var x2: int = x + int(nb[0])
					var z2: int = z + int(nb[1])
					if x2 < 0 or z2 < 0 or x2 >= hf.nx or z2 >= hf.nz:
						continue
					var j := idx[z2 * hf.nx + x2]
					if j < 0 or j == idx[k]:
						continue
					var d := w.distance_to(dense[j])
					if d < dist[k]:
						dist[k] = d
						idx[k] = j
	return [dist, idx]


# ------------------------------------------------------------------ terrain

static func _terrain(td: TrackData, root: Node3D, river: PackedVector2Array, stream: PackedVector2Array) -> Glacier.HF:
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
	var hills := FastNoiseLite.new()
	hills.seed = 3
	hills.frequency = 0.003
	hills.fractal_octaves = 3
	var ridge := FastNoiseLite.new()
	ridge.seed = 8
	ridge.frequency = 0.0011
	ridge.fractal_octaves = 4
	var field := Glacier.distance_field(td, hf)
	_fd = field[0]
	_fi = field[1]
	var rf: PackedFloat32Array = _poly_field(river, hf)[0]
	var sf: PackedFloat32Array = _poly_field(stream, hf)[0]
	_rf = rf
	_sf = sf
	var hit := TrackData.Hit.new()
	var crest := _section(td, "Dam Crest")
	td.frame_at((crest.x + crest.y) * 0.5, hit)
	var dam_c := _xz(hit.c)
	var dam_b := _xz(hit.B).normalized()          # downstream direction
	var dam_t := _xz(hit.T).normalized()
	var pool := _veil[1]
	for iz in hf.nz:
		for ix in hf.nx:
			var k := iz * hf.nx + ix
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var pxz := Vector2(x, z)
			var j := _fi[k]
			var d: float = _fd[k] if j >= 0 else 1e6
			var n := hills.get_noise_2d(x, z)
			# Plateau, kept above the reservoir everywhere outside its basin.
			var h := 64.0 + 6.0 * n
			# Mountains away from the circuit.
			h += smoothstep(350.0, 1100.0, d) * (40.0 + 150.0 * maxf(0.0, ridge.get_noise_2d(x, z) + 0.2))
			# Below the dam: a broad valley along the river (the Sky Bridge flies over it).
			var up := (pxz - dam_c).dot(dam_b)
			h = lerpf(h, 18.0 + 5.0 * n, smoothstep(420.0, 200.0, rf[k]) * smoothstep(-60.0, 10.0, up))
			# Above the dam: the reservoir basin, a funnel that opens out from the dam.
			var along := (pxz - dam_c).dot(dam_t) + 70.0
			var halfw := 230.0 + 0.9 * maxf(0.0, -up)
			var basin := smoothstep(-25.0, -90.0, up) * (1.0 - smoothstep(halfw, halfw + 220.0, absf(along))) * (1.0 - smoothstep(1800.0, 2400.0, -up))
			h = lerpf(h, 30.0 + 6.0 * n, basin)
			# River gorge; a cliff behind the Veil; the stream's ravine, sharp at the pool.
			h = lerpf(RIVER_Y - 4.0, h, smoothstep(14.0, 60.0, rf[k]))
			h = maxf(h, lerpf(h, 74.0, smoothstep(95.0, 30.0, pxz.distance_to(_veil[0]))))
			var sharp := smoothstep(140.0, 60.0, pxz.distance_to(pool))
			h = lerpf(RIVER_Y - 3.0, h, smoothstep(9.0, lerpf(45.0, 24.0, sharp), sf[k]))
			# The circuit's corridor: never above the deck underside.
			if j >= 0:
				var w := maxf(td.half_l[j], td.half_r[j]) + 12.0
				var limit := td.pos[j].y - TrackMesh.DECK - 2.0
				h = lerpf(h, minf(h, limit), 1.0 - smoothstep(w, w + 45.0, d))
			hf.h[k] = h
	var mk := MeshKit.new()
	mk.use("jungle")
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
	var mi := mk.instance("Terrain", {"jungle": Mats.shader_mat("jungle", {"water_y": RIVER_Y})})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return hf


## Height-field slope (rise per metre) at a node.
static func _slope(hf: Glacier.HF, ix: int, iz: int) -> float:
	var hl := hf.h[iz * hf.nx + maxi(ix - 1, 0)]
	var hr := hf.h[iz * hf.nx + mini(ix + 1, hf.nx - 1)]
	var hd := hf.h[maxi(iz - 1, 0) * hf.nx + ix]
	var hu := hf.h[mini(iz + 1, hf.nz - 1) * hf.nx + ix]
	return Vector2(hr - hl, hu - hd).length() / (2.0 * GRID)


# ------------------------------------------------------------------ water

static func _water(root: Node3D, hf: Glacier.HF) -> void:
	# River and stream: one plane at river level, visible only where the gorge
	# and ravine are carved below it.
	var span := Vector2(hf.nx * GRID, hf.nz * GRID)
	var river := MeshInstance3D.new()
	river.name = "River"
	var pm := PlaneMesh.new()
	pm.size = span
	river.mesh = pm
	river.position = Vector3(hf.x0 + span.x * 0.5, RIVER_Y, hf.z0 + span.y * 0.5)
	river.material_override = Mats.shader_mat("water", {
		"deep": Color(0.035, 0.05, 0.03), "shallow": Color(0.1, 0.09, 0.05),
		"reflect_col": Color(0.1, 0.13, 0.12), "glints": Color(0.45, 0.5, 0.46), "ripple": 3.5, "chop": 0.45})
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(river)


## The reservoir: a plane upstream of the dam only (the gorge below the dam is
## lower than the lake), built in the crest's frame.
static func _lake(td: TrackData, root: Node3D) -> void:
	var hit := TrackData.Hit.new()
	var crest := _section(td, "Dam Crest")
	td.frame_at((crest.x + crest.y) * 0.5, hit)
	var b := Vector3(hit.B.x, 0, hit.B.z).normalized()
	var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
	var o := Vector3(hit.c.x, LAKE_Y, hit.c.z) - b * 19.0
	var mk := MeshKit.new()
	mk.use("lake")
	var a := o - t * 2600.0
	var c := o + t * 2600.0
	mk.quad(a, a - b * 3200.0, c - b * 3200.0, c, Color.WHITE)   # faces up
	var mi := mk.instance("Lake", {"lake": Mats.shader_mat("water", {
		"deep": Color(0.015, 0.045, 0.045), "shallow": Color(0.04, 0.08, 0.06),
		"reflect_col": Color(0.14, 0.18, 0.18), "glints": Color(0.45, 0.5, 0.48), "ripple": 3.0, "chop": 0.35})})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ the dam

static func _dam(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	_lake(td, root)
	var crest := _section(td, "Dam Crest")
	var mk := MeshKit.new()
	var hit := TrackData.Hit.new()
	var prev := PackedVector3Array()
	var s := crest.x - 160.0
	var toe_at := {}
	while s <= crest.y + 0.5:
		td.frame_at(s, hit)
		var top := hit.c.y - TrackMesh.DECK
		var half := maxf(hit.half_l, hit.half_r) + TrackMesh.WALL_T + 1.5
		var ground := hf.at(hit.c.x + hit.B.x * 40.0, hit.c.z + hit.B.z * 40.0)
		var bottom := minf(ground, top) - 4.0
		var toe := half + 0.75 * (top - bottom)
		toe_at[int(s)] = toe
		var sec := PackedVector3Array([
			hit.c - hit.B * (half + 2.0) + Vector3(0, bottom - hit.c.y, 0),
			hit.c - hit.B * half + Vector3(0, top - hit.c.y, 0),
			hit.c + hit.B * half + Vector3(0, top - hit.c.y, 0),
			hit.c + hit.B * toe + Vector3(0, bottom - hit.c.y, 0)])
		if prev.size() > 0:
			mk.use("dam")
			var pair: Array[PackedVector3Array] = [prev, sec]
			mk.loft(pair, Color.WHITE, false, false)
		prev = sec
		s += 10.0
	# Outlets: gates in the downstream face with water pouring down it.
	var falls := MeshKit.new()
	for f in 5:
		var so := lerpf(crest.x, crest.y, 0.26 + 0.12 * f)
		td.frame_at(so, hit)
		var top := hit.c.y - TrackMesh.DECK
		var half := maxf(hit.half_l, hit.half_r) + TrackMesh.WALL_T + 1.5
		var ground := hf.at(hit.c.x + hit.B.x * 40.0, hit.c.z + hit.B.z * 40.0)
		var bottom := minf(ground, top) - 4.0
		var y_out := top - 9.0
		var face_n := (hit.B * 1.0 + Vector3.UP * 0.75).normalized()
		var at := func(y: float) -> Vector3:
			return hit.c + hit.B * (half + 0.75 * (top - y)) + Vector3(0, y - hit.c.y, 0) + face_n * 0.5
		mk.use("metal_dark")
		mk.box_t(Transform3D(Basis(hit.T, face_n.cross(hit.T).normalized(), face_n), at.call(y_out + 2.5)), Vector3(9.0, 5.0, 1.2), Color.WHITE)
		var rows: Array[Vector3] = []
		var y := y_out
		while y > bottom + 2.0:
			rows.append(at.call(y))
			y -= 3.0
		rows.append(at.call(bottom + 2.0) + hit.B * 6.0)
		_strip(falls, rows, hit.T, 11.0)
	# Powerhouse at the toe, beside the river, with penstocks down the face.
	td.frame_at(lerpf(crest.x, crest.y, 0.82), hit)
	var top2 := hit.c.y - TrackMesh.DECK
	var ground2 := hf.at(hit.c.x + hit.B.x * 40.0, hit.c.z + hit.B.z * 40.0)
	var toe2: float = 17.0 + 0.75 * (top2 - minf(ground2, top2) + 4.0)
	var ph := hit.c + hit.B * (toe2 + 22.0)
	ph.y = hf.at(ph.x, ph.z)
	var bb := Basis(hit.B, Vector3.UP, -hit.T)
	mk.use("bld")
	mk.box_t(Transform3D(bb, ph + Vector3(0, 11, 0)), Vector3(36.0, 22.0, 70.0), Color(0.8, 0.82, 0.8, 0.5))
	mk.use("metal_dark")
	mk.box_t(Transform3D(bb, ph + Vector3(0, 22.6, 0)), Vector3(37.0, 1.2, 71.0), Color.WHITE)
	mk.use("metal")
	for k in 3:
		var along := (k - 1) * 18.0
		var a := hit.c + hit.B * 24.0 + hit.T * along + Vector3(0, top2 - 14.0 - hit.c.y, 0)
		var b := ph + hit.T * along - hit.B * 16.0 + Vector3(0, 8.0, 0)
		mk.cyl(a, b, 2.2, 2.2, 10, Color(0.55, 0.5, 0.45))
	mk.use("warn_red")
	for k in 4:
		mk.box(ph + Vector3(0, 23.5, 0) + hit.T * (k * 22.0 - 33.0), Vector3(0.5, 0.5, 0.5), Color.WHITE)
	var dam := StandardMaterial3D.new()
	dam.albedo_color = Color(0.74, 0.74, 0.7)
	dam.albedo_texture = Mats.tex("panel_albedo")
	dam.uv1_triplanar = true
	dam.uv1_scale = Vector3(0.05, 0.05, 0.05)
	dam.roughness = 0.75
	root.add_child(mk.instance("Dam", {"dam": dam}))
	var fm := falls.instance("DamFalls", {"water": Mats.shader_mat("waterfall")})
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fm)


## A strip of falling water through `rows` (top to bottom), `across` wide.
## UV.x 0..1 across, UV.y = metres down / 10, COLOR.r = 0..1 along.
static func _strip(mk: MeshKit, rows: Array[Vector3], across: Vector3, width: float) -> void:
	mk.use("water")
	var acc := 0.0
	var total := 0.0
	for k in rows.size() - 1:
		total += rows[k].distance_to(rows[k + 1])
	var prev_l := -1
	for k in rows.size():
		if k > 0:
			acc += rows[k - 1].distance_to(rows[k])
		var f := acc / maxf(total, 0.01)
		var dn := (rows[mini(k + 1, rows.size() - 1)] - rows[maxi(k - 1, 0)]).normalized()
		var nrm := across.cross(dn).normalized()
		var l := mk._vert(rows[k] - across * width * 0.5, nrm, Color(f, 0, 0), Vector2(0.0, acc / 10.0))
		mk._vert(rows[k] + across * width * 0.5, nrm, Color(f, 0, 0), Vector2(1.0, acc / 10.0))
		if prev_l >= 0:
			mk._quad_i(prev_l, prev_l + 1, l + 1, l)
		prev_l = l


## A cascade draped over the terrain from `top` to `bottom` (x, z).
static func _cascade(mk: MeshKit, hf: Glacier.HF, top: Vector2, bottom: Vector2, width: float) -> void:
	var dir := (bottom - top).normalized()
	var across := Vector3(-dir.y, 0, dir.x)
	var n := maxi(2, int(top.distance_to(bottom) / 3.0))
	var rows: Array[Vector3] = []
	for k in n + 1:
		var p := top.lerp(bottom, float(k) / n)
		var y := maxf(hf.at(p.x, p.y), RIVER_Y) + 0.8
		rows.append(Vector3(p.x, y, p.y))
	_strip(mk, rows, across, width)


# ------------------------------------------------------------------ the bridge

## The Sky Bridge: box girder, two H towers with fans of stays, twin-column piers.
static func _bridge(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var r := _section(td, "Sky Bridge")
	if r.x < 0.0:
		return
	var mk := MeshKit.new()
	var hit := TrackData.Hit.new()
	var s := r.x - 40.0
	while s < r.y + 40.0:
		td.frame_at(s + 5.0, hit)
		var b := Basis(hit.B, hit.N, -hit.T)
		var wdt := hit.half_l + hit.half_r + 2.0 * TrackMesh.WALL_T + 1.0
		mk.use("concrete")
		mk.box_t(Transform3D(b, hit.c - hit.N * (TrackMesh.DECK + 1.6)), Vector3(wdt - 3.0, 3.2, 10.2), Color(0.85, 0.85, 0.85))
		s += 10.0
	var span := r.y - r.x
	var towers := [r.x + span / 3.0, r.x + span * 2.0 / 3.0]
	for st: float in towers:
		td.frame_at(st, hit)
		_keep_clear.append(Vector3(hit.c.x, hit.c.z, 45.0))
		var deck := hit.c.y - TrackMesh.DECK - 3.2
		var top_y := hit.c.y + 72.0
		var legs: Array[Vector3] = []
		for side: float in [-1.0, 1.0]:
			var off := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 4.0
			var foot := hit.c + hit.B * side * off
			foot.y = hf.at(foot.x, foot.z) - 2.0
			var head := hit.c + hit.B * side * (off - 1.5)
			head.y = top_y
			mk.use("concrete")
			mk.beam(foot, head, 4.4, 4.4, Color(0.9, 0.9, 0.9), hit.T)
			legs.append(head)
			mk.use("warn_red")
			mk.box(head + Vector3(0, 2.8, 0), Vector3(0.9, 0.9, 0.9), Color.WHITE)
		var l0 := legs[0]
		var l1 := legs[1]
		mk.use("concrete")
		for y: float in [deck - 1.0, hit.c.y + 40.0, top_y - 2.0]:
			mk.beam(Vector3(l0.x, y, l0.z), Vector3(l1.x, y, l1.z), 3.0, 3.0, Color(0.9, 0.9, 0.9), hit.T)
		# Stays: eight a side, both directions, from the leg heads to the deck edges.
		mk.use("metal")
		for side_i in 2:
			var head := legs[side_i]
			var sgn := -1.0 if side_i == 0 else 1.0
			for dirn: float in [-1.0, 1.0]:
				for k in range(1, 9):
					var sa := st + dirn * k * 21.0
					var h2 := TrackData.Hit.new()
					td.frame_at(sa, h2)
					var edge := h2.c + h2.B * sgn * ((h2.half_r if sgn > 0.0 else h2.half_l) + TrackMesh.WALL_T + 0.6) + h2.N * 0.2
					var anchor := head + Vector3(0, -6.0 - k * 3.2, 0)
					mk.beam(anchor, edge, 0.32, 0.32, Color(0.92, 0.92, 0.95), Vector3.UP)
	# Piers between the towers and the abutments.
	var sp := r.x + 60.0
	while sp < r.y - 40.0:
		var near_tower := false
		for st: float in towers:
			if absf(sp - st) < 45.0:
				near_tower = true
		td.frame_at(sp, hit)
		var under := hit.c - hit.N * (TrackMesh.DECK + 3.2)
		var ground := hf.at(under.x, under.z)
		if not near_tower and under.y - ground > 4.0:
			mk.use("concrete")
			for side: float in [-1.0, 1.0]:
				var p := under + hit.B * side * 6.0
				mk.box(Vector3(p.x, (p.y + ground) * 0.5 - 1.0, p.z), Vector3(3.0, p.y - ground + 2.0, 3.0), Color(0.85, 0.85, 0.85), 0.6, 0.25)
		sp += 95.0
	root.add_child(mk.instance("SkyBridge"))


# ------------------------------------------------------------------ the grotto

## Half-ellipse cross-section of the grotto at sample j.
static func _arc(td: TrackData, j: int, extra: float, raise: float, steps: int = 12) -> PackedVector3Array:
	var ceil_h := td.ceiling[j] + raise
	var hl := td.half_l[j] + TrackMesh.WALL_T + extra
	var hr := td.half_r[j] + TrackMesh.WALL_T + extra
	var out := PackedVector3Array()
	for k in steps + 1:
		var a := PI * k / float(steps)
		var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
		var h := -0.3 - raise * 0.4 + sin(a) * (ceil_h + 0.3)
		out.append(td.pos[j] + td.rgt[j] * d + td.nrm[j] * h)
	return out


static func _grotto(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Falls Grotto")
	if r.x < 0.0:
		return
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	var lumps := FastNoiseLite.new()
	lumps.seed = 21
	lumps.frequency = 0.05
	var mk := MeshKit.new()
	var prev_in := PackedVector3Array()
	var prev_out := PackedVector3Array()
	for i in range(i0, i1 + 1, 3):
		var j := td.wrap_i(i)
		var sec_in := _arc(td, j, 0.8, 0.0)
		var sec_out := _arc(td, j, 9.0, 12.0)
		for k in sec_out.size():
			var p := sec_out[k]
			sec_out[k] = p + (p - td.pos[j]).normalized() * (lumps.get_noise_3dv(p) * 5.0)
		if prev_in.size() > 0:
			mk.use("grotto")
			var pi: Array[PackedVector3Array] = [prev_in, sec_in]
			mk.loft(pi, Color(0.75, 0.75, 0.72), false, false)
			mk.use("rock")
			var po: Array[PackedVector3Array] = [prev_out, sec_out]
			mk.loft(po, Color(0.55, 0.6, 0.5), false, true)
		prev_in = sec_in
		prev_out = sec_out
	# Lamps along the walls.
	var hit := TrackData.Hit.new()
	var s := r.x + 8.0
	var n := 0
	while s < r.y - 4.0:
		td.frame_at(s, hit)
		var side := 1.0 if n % 2 == 0 else -1.0
		var edge := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 0.5
		mk.use("lamp")
		mk.box_t(Transform3D(Basis(hit.B, hit.N, -hit.T), hit.c + hit.B * side * edge + hit.N * 6.0), Vector3(0.3, 0.5, 2.2), Color.WHITE)
		s += 16.0
		n += 1
	# A rock lip over the exit, and the curtain of water falling across it.
	td.frame_at(r.y - 1.0, hit)
	var lip := hit.c + hit.N * (td.ceiling[hit.i] + 10.0)
	mk.use("rock")
	mk.box_t(Transform3D(Basis(hit.B, hit.N, -hit.T), lip + hit.N * 6.0 - hit.T * 6.0), Vector3(hit.half_l + hit.half_r + 26.0, 14.0, 14.0), Color(0.55, 0.6, 0.5))
	var grotto := StandardMaterial3D.new()
	grotto.albedo_color = Color(0.2, 0.21, 0.19)
	grotto.albedo_texture = Mats.tex("panel_normal")
	grotto.uv1_triplanar = true
	grotto.uv1_scale = Vector3(0.08, 0.08, 0.08)
	grotto.roughness = 0.35
	grotto.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.3, 0.32, 0.27)
	rock.vertex_color_use_as_albedo = true
	rock.albedo_texture = Mats.tex("panel_normal")
	rock.uv1_triplanar = true
	rock.uv1_scale = Vector3(0.05, 0.05, 0.05)
	rock.roughness = 0.5
	var mi := mk.instance("Grotto", {"grotto": grotto, "rock": rock})
	root.add_child(mi)
	var falls := MeshKit.new()
	var rows: Array[Vector3] = []
	var y := lip.y + 6.0
	var base := hit.c.y - 3.0
	while y > base:
		rows.append(Vector3(hit.c.x, y, hit.c.z) + hit.T * 1.5)
		y -= 2.5
	rows.append(Vector3(hit.c.x, base, hit.c.z) + hit.T * 3.0)
	_strip(falls, rows, hit.B, hit.half_l + hit.half_r + 14.0)
	var fm := falls.instance("GrottoCurtain", {"water": Mats.shader_mat("waterfall", {"opacity": 0.7})})
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fm)
	_spray(root, Vector3(hit.c.x, hit.c.y, hit.c.z) + hit.T * 4.0, 18.0, 40)


# ------------------------------------------------------------------ waterfalls

static func _falls(root: Node3D, hf: Glacier.HF, river: PackedVector2Array) -> void:
	var mk := MeshKit.new()
	# The Veil: a broad cascade off the plateau into the stream's pool.
	_cascade(mk, hf, _veil[0], _veil[1], 46.0)
	for k in 5:
		var q := _veil[0].lerp(_veil[1], k / 4.0)
		_keep_clear.append(Vector3(q.x, q.y, 45.0))
	var pool := _veil[1]
	_spray(root, Vector3(pool.x, RIVER_Y + 2.0, pool.y), 26.0, 50)
	# Cascades down the far gorge wall, opposite the track.
	var picks := [0.12, 0.3, 0.42, 0.55, 0.66]
	for f: float in picks:
		var k := int(f * (river.size() - 60))
		var a := river[k]
		var b := river[mini(k + 1, river.size() - 1)]
		var dir := (b - a).normalized()
		var right := Vector2(-dir.y, dir.x)
		var w := rng.randf_range(6.0, 12.0)
		var top := a + right * rng.randf_range(85.0, 110.0)
		_cascade(mk, hf, top, a + right * 16.0, w)
		for q in 3:
			var c := top.lerp(a, q / 2.0)
			_keep_clear.append(Vector3(c.x, c.y, w + 10.0))
	var mi := mk.instance("Falls", {"water": Mats.shader_mat("waterfall")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Mist rising from the foot of a fall.
static func _spray(root: Node3D, at: Vector3, radius: float, amount: int) -> void:
	var p := GPUParticles3D.new()
	p.name = "Spray"
	p.amount = maxi(6, int(amount * float(Quality.p["particles"])))
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.position = at
	p.visibility_aabb = AABB(Vector3(-radius * 2, -5, -radius * 2), Vector3(radius * 4, 40, radius * 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius, 1.0, radius * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 0.35))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(9.0, 9.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = Mats.tex("smoke")
	mat.albedo_color = Color(0.9, 0.93, 0.93, 0.6)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)


# ------------------------------------------------------------------ forest

## Three low-poly tree shapes: emergent giant, broadleaf, palm.
static func _tree_meshes() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.3, 0.24, 0.18)
	bark.roughness = 0.95
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.2, 0.42, 0.12)
	leaf.vertex_color_use_as_albedo = true
	leaf.roughness = 0.8
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mats := {"bark": bark, "leaf": leaf}
	# Emergent: tall straight trunk, flat umbrella crown.
	var a := MeshKit.new()
	a.use("bark")
	a.cyl(Vector3.ZERO, Vector3(0, 24, 0), 0.9, 0.45, 5, Color.WHITE, false)
	a.use("leaf")
	a.sphere(Vector3(0, 25.5, 0), Vector3(8.0, 3.2, 8.0), 3, 7, Color(0.85, 0.95, 0.8), Color(0.45, 0.5, 0.4))
	a.sphere(Vector3(3.0, 23.5, 2.0), Vector3(4.5, 2.4, 4.5), 3, 6, Color(0.75, 0.85, 0.7), Color(0.4, 0.45, 0.35))
	out.append(a.commit(mats))
	# Broadleaf: shorter, two lumpy crowns.
	var b := MeshKit.new()
	b.use("bark")
	b.cyl(Vector3.ZERO, Vector3(0, 9, 0), 0.6, 0.35, 5, Color.WHITE, false)
	b.use("leaf")
	b.sphere(Vector3(0, 11, 0), Vector3(5.5, 4.2, 5.5), 3, 7, Color(1.0, 1.0, 1.0), Color(0.45, 0.5, 0.45))
	b.sphere(Vector3(-2.5, 9.5, 1.5), Vector3(3.5, 3.0, 3.5), 3, 6, Color(0.9, 0.95, 0.85), Color(0.4, 0.45, 0.4))
	out.append(b.commit(mats))
	# Palm: slender trunk and drooping fronds.
	var c := MeshKit.new()
	c.use("bark")
	c.cyl(Vector3.ZERO, Vector3(0.6, 14, 0), 0.3, 0.22, 5, Color.WHITE, false)
	c.use("leaf")
	var crown := Vector3(0.6, 14, 0)
	for k in 7:
		var ang := TAU * k / 7.0
		var o := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-o.z, 0, o.x) * 0.9
		var tip := crown + o * 5.5 + Vector3(0, -2.6, 0)
		var mid := crown + o * 2.8 + Vector3(0, 0.6, 0)
		c.tri(crown, mid + side, tip, Color(0.8, 1.0, 0.75), true)
		c.tri(crown, tip, mid - side, Color(0.7, 0.9, 0.65), true)
	out.append(c.commit(mats))
	return out


static func _forest(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var meshes := _tree_meshes()
	var density := float(Quality.p["city"])
	var cells: Dictionary = {}        # Vector2i -> [Array[Transform3D] x3, Array[Color] x3]
	var hit := TrackData.Hit.new()
	var crest := _section(td, "Dam Crest")
	td.frame_at((crest.x + crest.y) * 0.5, hit)
	var dam_c := _xz(hit.c)
	var dam_b := _xz(hit.B).normalized()
	var dam_t := _xz(hit.T).normalized()
	var half_len := (crest.y - crest.x) * 0.5 + 170.0
	var spacing := 15.0 / sqrt(maxf(density, 0.3))
	var z := hf.z0
	while z < hf.z0 + (hf.nz - 1) * GRID:
		var x := hf.x0
		while x < hf.x0 + (hf.nx - 1) * GRID:
			var px := x + rng.randf_range(-0.45, 0.45) * spacing
			var pz := z + rng.randf_range(-0.45, 0.45) * spacing
			x += spacing
			var ix := clampi(int(round((px - hf.x0) / GRID)), 0, hf.nx - 1)
			var iz := clampi(int(round((pz - hf.z0) / GRID)), 0, hf.nz - 1)
			var k := iz * hf.nx + ix
			var j := _fi[k]
			if j < 0:
				continue
			var d := _fd[k]
			var far := smoothstep(220.0, 650.0, d)
			if d > 650.0 or rng.randf() < far * 0.85:
				continue
			if d < maxf(td.half_l[j], td.half_r[j]) + 12.0:
				continue
			var y := hf.at(px, pz)
			if y < RIVER_Y + 1.5 or _slope(hf, ix, iz) > 1.1:
				continue
			var pxz := Vector2(px, pz)
			var rel := pxz - dam_c
			if y < LAKE_Y + 0.6 and rel.dot(dam_b) < -15.0:
				continue      # under the reservoir
			if absf(rel.dot(dam_t)) < half_len and rel.dot(dam_b) > -30.0 and rel.dot(dam_b) < 240.0:
				continue      # dam body, toe, powerhouse and the view of the face
			if _rf[k] < 36.0 or _sf[k] < 22.0:
				continue      # open banks along the river and the stream
			var blocked := false
			for kc in _keep_clear:
				if pxz.distance_squared_to(Vector2(kc.x, kc.y)) < kc.z * kc.z:
					blocked = true
					break
			if blocked:
				continue
			# Keep clear of any part of the deck above (bridge, elevated curves).
			if td.pos[j].y - TrackMesh.DECK - y < 30.0 and d < maxf(td.half_l[j], td.half_r[j]) + 22.0:
				continue
			var kind := 1
			var roll := rng.randf()
			if roll < 0.18:
				kind = 0
			elif roll < 0.42:
				kind = 2
			var sc := rng.randf_range(0.75, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
			var key := Vector2i(floori(px / 400.0), floori(pz / 400.0))
			if not cells.has(key):
				cells[key] = [[[], [], []], [[], [], []]]
			var cell: Array = cells[key]
			(cell[0][kind] as Array).append(Transform3D(basis, Vector3(px, y - 0.6, pz)))
			var g := rng.randf_range(0.75, 1.15)
			var tint := Color(g * rng.randf_range(0.85, 1.15), g, g * rng.randf_range(0.75, 1.05))
			if kind == 0 and rng.randf() < 0.08:
				tint = Color(2.6, 1.35, 0.45)     # a flowering crown (yellow)
			(cell[1][kind] as Array).append(tint)
		z += spacing
	var total := 0
	for key: Vector2i in cells:
		var cell: Array = cells[key]
		for kind in 3:
			var xf: Array = cell[0][kind]
			if xf.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = meshes[kind]
			mm.instance_count = xf.size()
			for q in xf.size():
				mm.set_instance_transform(q, xf[q])
				mm.set_instance_color(q, cell[1][kind][q])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees_%d_%d_%d" % [key.x, key.y, kind]
			mmi.multimesh = mm
			mmi.visibility_range_end = 900.0 * float(Quality.p["view"])
			mmi.visibility_range_end_margin = 60.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
			total += xf.size()
	if DevArgs.has("--load-times"):
		print("rainforest trees %d in %d cells" % [total, cells.size()])


# ------------------------------------------------------------------ trackside

static func _trackside(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	var crest := _section(td, "Dam Crest")
	var bridge := _section(td, "Sky Bridge")
	for i in td.count:
		var s := i * td.step
		var key := int(s / 400.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 40, TrackData.F_TUNNEL) or td.flag_at_index(i - 40, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 8, TrackData.F_GAP) or td.flag_at_index(i - 8, TrackData.F_GAP)
		var on_dam := s > crest.x - 170.0 and s < crest.y + 10.0
		var on_bridge := s > bridge.x - 50.0 and s < bridge.y + 50.0
		var p := td.pos[i]
		if i % 46 == 0 and not tunnel and not gap and not on_dam and not on_bridge:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := hf.at(p.x, p.z)
			if under.y - foot > 1.5:
				mk.use("concrete")
				var hgt := under.y - foot
				mk.box(Vector3(under.x, foot + hgt * 0.5, under.z), Vector3(2.8, hgt, 2.8), Color(0.75, 0.78, 0.72), 0.6, 0.25)
		if s - last_gate > 230.0 and s > 160.0 and not tunnel and not gap:
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 230.0) * 2)
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Trackside%02d" % key))


# ------------------------------------------------------------------ weather

## Rain streaks in a box ahead of the active camera.
static func _rain(root: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = int(1400 * float(Quality.p["particles"]))
	p.lifetime = 1.4
	p.preprocess = 1.4
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-150, -80, -150), Vector3(300, 160, 300))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45, 18, 60)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -4.0, 0)
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.035, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.84, 0.88, 0.32)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	var follow := RainFollow.new()
	follow.particles = p
	root.add_child(follow)


## Keeps the rain box ahead of the active camera.
class RainFollow extends Node:
	var particles: GPUParticles3D

	func _process(_d: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam and particles:
			particles.global_position = cam.global_position + Vector3(0, 14, 0) - cam.global_transform.basis.z * 35.0


## Development aid (--dump-terrain=out.png): heights, track (white), river
## (red) and stream (yellow) from above, 4 px per height-field node.
static func _debug_map(td: TrackData, hf: Glacier.HF, river: PackedVector2Array, stream: PackedVector2Array, path: String) -> void:
	var img := Image.create(hf.nx, hf.nz, false, Image.FORMAT_RGB8)
	for iz in hf.nz:
		for ix in hf.nx:
			var h := hf.h[iz * hf.nx + ix]
			var c := Color(0.1, 0.25, 0.6) if h < RIVER_Y else Color.from_hsv(0.33 - clampf(h / 250.0, 0.0, 0.25), 0.6, clampf(0.15 + h / 110.0, 0.0, 1.0))
			if h < LAKE_Y and h >= RIVER_Y:
				c = c.lerp(Color(0.3, 0.2, 0.1), 0.3)
			img.set_pixel(ix, iz, c)
	img.resize(hf.nx * 4, hf.nz * 4, Image.INTERPOLATE_NEAREST)
	var to_px := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x - hf.x0) / GRID * 4.0), int((p.y - hf.z0) / GRID * 4.0))
	var put := func(q: Vector2i, c: Color, r: int) -> void:
		if q.x >= r and q.y >= r and q.x < img.get_width() - r and q.y < img.get_height() - r:
			img.fill_rect(Rect2i(q.x - r, q.y - r, 2 * r + 1, 2 * r + 1), c)
	for i in range(0, td.count, 3):
		put.call(to_px.call(_xz(td.pos[i])), Color.WHITE, 0)
	for p in river:
		put.call(to_px.call(p), Color(1, 0.3, 0.2), 1)
	for p in stream:
		put.call(to_px.call(p), Color(1, 1, 0), 2)
	img.save_png(path)
	print("terrain map ", path, " ", hf.nx, "x", hf.nz)

