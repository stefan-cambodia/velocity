## THALASSA DEEP world: an undersea research city on the edge of a continental
## shelf. Everything is underwater: the background is the water column
## (sky_abyss), the fog is blue and darkens with depth (DepthTint), and the
## seabed carries animated caustics and, in the deep, bioluminescence.
##
## Terrain: a height field on a 16 m grid (Abyssal.Ground). The shelf lies at
## about 0 m; a blue hole is sunk into it around The Drop, and a canyon runs
## from the hole along the Abyss Run and the Wreck Bend, opening out to the
## south-east into the abyss. The canyon's centre line is the track itself, so
## the canyon meanders with the Abyss Esses. Under the track the ground is kept
## below the deck, tube hull or hall; over the Ascent tunnel it is raised above
## the roof, so the tunnel runs through the shelf. Open sections on the shelf
## sit on a reef bank a few metres below the deck.
##
## Structures: the Atrium (start hall, a vaulted habitat with windows outside
## and a dome over the line), glass tubes (Fresnel glass over an opaque hull,
## ribs every 24 m, a lamp every 8 m in step with the tunnel light sweep), the
## lined rock tunnel of the Ascent with portal facades, causeway arches and
## marker posts on the open sections, cradles and pylons to the seabed.
##
## Life and props: domes of the research city, instanced kelp (swaying in the
## shader), coral and rocks, fish schools (GPU particles), sun shafts, the Spine
## in the blue hole, jellyfish, a wreck, the submarine pens and the Drifters
## (an original giant creature) over the trench. See docs/TRACK_THALASSA_DEEP.md.
class_name Abyssal
extends RefCounted

const GRID := 16.0
const MARGIN := 760.0
const SHELF_Y := 0.0
const FLOOR_Y := -57.0
const CHUNK_CELLS := 32              ## Terrain chunk size in grid cells (512 m).
const TUBE_SIDE := 2.4              ## Glass foot beyond the barrier.
const HULL := 5.0                    ## Depth of the tube hull below the deck.
const HALL_SIDE := 17.0              ## Width of the Atrium's side decks.
const SUN_DIR := Vector3(0.25, 0.92, -0.3)
## Sorting offset that keeps this world's transparent surfaces (glass, shafts,
## jellyfish, marine snow) drawn after SpeedFX's post quad. That quad reads the
## screen texture, which holds only opaque geometry, and its sort position is
## the world origin with an offset of 1000, so transparents sorted before it
## vanish at speed within about 1 km of the origin (the Atrium, Ring Sweep and
## Kelp Run here).
const SORT_AFTER_POST := 2500.0

enum Kind { OPEN, TUBE, HALL, ROCK }

static var rng := RandomNumberGenerator.new()
static var ground: Ground
static var kind := PackedByteArray()        ## Kind per track sample.
static var _fd := PackedFloat32Array()      ## Track distance per ground node.
static var _fi := PackedInt32Array()        ## Nearest track sample per ground node.
static var _cd := PackedFloat32Array()      ## Canyon distance per ground node.
static var _ca := PackedFloat32Array()      ## Distance along the canyon's abyss reach per node.
static var hole_c := Vector3.ZERO           ## Blue hole centre (floor level).
static var hole_r := 0.0
static var _keep_clear: Array[Vector3] = [] ## (x, z, radius) spots props leave open.


## Ground height field (same layout as Glacier.HF, on this world's grid).
class Ground:
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

	func normal(x: float, z: float) -> Vector3:
		var e := GRID
		return Vector3(at(x - e, z) - at(x + e, z), 2.0 * e, at(x, z - e) - at(x, z + e)).normalized()


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 7100
	_keep_clear.clear()
	var t0 := Time.get_ticks_msec()
	_classify(td)
	_environment(td, root)
	_terrain(td, root)
	var t1 := Time.get_ticks_msec()
	if not _skip("tubes"):
		_tubes(td, root)
	if not _skip("hall"):
		_hall(td, root)
	if not _skip("rock_tunnel"):
		_rock_tunnel(td, root)
	if not _skip("trackside"):
		_trackside(td, root)
	if not _skip("spine"):
		_spine(root)
	if not _skip("wreck"):
		_wreck(td, root)
	if not _skip("sub_pen"):
		_sub_pen(td, root)
	if not _skip("city"):
		_city(td, root)
	if not _skip("kelp"):
		_kelp(td, root)
	if not _skip("reef"):
		_reef(td, root)
	if not _skip("fish"):
		_fish(td, root)
	if not _skip("jellies"):
		_jellies(td, root)
	if not _skip("shafts"):
		_shafts(td, root)
	if not _skip("drifters"):
		_drifters(td, root)
	var tint := root.get_node_or_null("DepthTint") as DepthTint
	if tint:
		tint.snow = _snow(root)
	HelixBay._start_gantry(td, root, "THALASSA DEEP  /  VELOCITY LEAGUE")
	_draw_distance(root)
	if DevArgs.has("--load-times"):
		print("abyssal world %d ms (terrain %d ms)" % [Time.get_ticks_msec() - t0, t1 - t0])
		_stats(root)


## The water hides everything beyond about 1 km (fog over 95 %), and
## nothing occludes in the renderer, so far track chunks, tubes and tunnels are
## given a draw distance too.
static func _draw_distance(root: Node3D) -> void:
	var far := 1000.0 * float(Quality.p["view"])
	var nodes: Array[Node] = []
	var track := root.get_node_or_null("Track")
	if track:
		nodes.append_array(track.get_children())
	nodes.append_array(root.get_children())
	for c in nodes:
		var gi := c as GeometryInstance3D
		if gi and gi.visibility_range_end <= 0.0 and not (gi is GPUParticles3D) and c.name != "Shafts":
			gi.visibility_range_end = far


## Development aid: --abyss-skip=kelp,reef,... leaves parts of the world out
## (for measuring what each costs).
static func _skip(part: String) -> bool:
	for a in DevArgs.all():
		if a.begins_with("--abyss-skip=") and part in a.substr(13).split(","):
			return true
	return false


## Development aid (--load-times): triangles and nodes per kind of node.
static func _stats(root: Node3D) -> void:
	var tris: Dictionary = {}
	var nodes: Dictionary = {}
	var nodes_list: Array[Node] = []
	for c in root.get_children():
		nodes_list.append(c)
		if c.name == "Track":
			nodes_list.append_array(c.get_children())
	for c in nodes_list:
		var key := String(c.name).get_slice("_", 0).rstrip("0123456789")
		var n := 0
		var mesh: Mesh = null
		var mult := 1
		if c is MeshInstance3D:
			mesh = (c as MeshInstance3D).mesh
		elif c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			mult = mm.instance_count
		elif c is GPUParticles3D:
			mesh = (c as GPUParticles3D).draw_pass_1
			mult = (c as GPUParticles3D).amount
		if mesh is ArrayMesh:
			for si in (mesh as ArrayMesh).get_surface_count():
				var arr := (mesh as ArrayMesh).surface_get_arrays(si)
				var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				n += (ix.size() if ix.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		tris[key] = int(tris.get(key, 0)) + n * mult
		nodes[key] = int(nodes.get(key, 0)) + 1
	for key: String in tris:
		print("  %-14s %3d nodes %8d tris" % [key, nodes[key], tris[key]])


# ------------------------------------------------------------------ helpers

static func _section(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _kind_at(td: TrackData, i: int) -> int:
	return kind[td.wrap_i(i)]


## Track samples by structure: the Atrium hall spans the Grid Straight and the
## Atrium; the Ascent (and the segment after it) is a rock tunnel; the other
## tunnel-flagged sections are glass tubes; the rest is open.
static func _classify(td: TrackData) -> void:
	kind.resize(td.count)
	kind.fill(Kind.OPEN)
	var hall_a := _section(td, "Grid Straight")
	var hall_b := _section(td, "Atrium")
	var rock := _section(td, "The Ascent")
	var after := _section(td, "Dock Turn")
	for i in td.count:
		var s := i * td.step
		if not td.flag_at_index(i, TrackData.F_TUNNEL):
			continue
		if s >= hall_a.x or s < hall_b.y:
			kind[i] = Kind.HALL
		elif s >= rock.x and s < after.x:
			kind[i] = Kind.ROCK
		else:
			kind[i] = Kind.TUBE
	# Blue hole: centre of The Drop's spiral.
	var r := _section(td, "The Drop")
	var c := Vector3.ZERO
	var n := 0
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	for i in range(i0 + (i1 - i0) / 10, i1 - (i1 - i0) / 10, 4):
		c += td.pos[i]
		n += 1
	c /= maxf(n, 1)
	var rad := 0.0
	for i in range(i0 + (i1 - i0) / 10, i1 - (i1 - i0) / 10, 4):
		rad += _xz(td.pos[i]).distance_to(_xz(c))
	hole_r = rad / maxf(n, 1)
	hole_c = Vector3(c.x, FLOOR_Y, c.z)


## Ranges of consecutive samples of one kind: Array of Vector2i(i0, i1), i1 inclusive.
static func _runs(td: TrackData, k: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := -1
	# Start scanning where the kind changes, so a run never straddles the wrap.
	var origin := 0
	for i in td.count:
		if kind[i] != kind[td.wrap_i(i - 1)]:
			origin = i
			break
	for q in td.count + 1:
		var i := td.wrap_i(origin + q)
		var inside := q < td.count and kind[i] == k
		if inside and start < 0:
			start = origin + q
		elif not inside and start >= 0:
			out.append(Vector2i(start, origin + q - 1))
			start = -1
	return out


static func _std(col: Color, rough: float, metal: float = 0.0, emit: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
	return m


# ------------------------------------------------------------------ environment

static func _environment(td: TrackData, root: Node3D) -> void:
	var env: Environment = null
	var sun: DirectionalLight3D = null
	for c in root.get_children():
		if c is WorldEnvironment:
			env = (c as WorldEnvironment).environment
		elif c is DirectionalLight3D:
			sun = c as DirectionalLight3D
	if env:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/sky_abyss.gdshader")
		sm.set_shader_parameter("caustic_tex", Mats.tex("abyss_caustics"))
		sm.set_shader_parameter("sun_dir", SUN_DIR.normalized())
		env.sky.sky_material = sm
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_energy = 1.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.003
		env.fog_sky_affect = 0.55
		env.fog_aerial_perspective = 0.0
		env.fog_sun_scatter = 0.0
		env.tonemap_exposure = 1.1
		env.glow_hdr_threshold = 0.9
		env.glow_intensity = 0.8
	if sun:
		sun.transform = Transform3D(Basis.looking_at(-SUN_DIR.normalized(), Vector3.FORWARD), Vector3.ZERO)
		sun.light_color = Color(0.62, 0.9, 0.92)
		sun.light_energy = 1.2
	var tint := DepthTint.new()
	tint.name = "DepthTint"
	tint.env = env
	tint.sun = sun
	tint.td = td
	tint.kinds = kind
	root.add_child(tint)
	tint.apply(SHELF_Y + 12.0, 0.0)


## Darkens and blues the fog, ambient light and sun as the camera goes deeper,
## thins the fog and warms the ambient light inside the Atrium and the rock
## tunnel (air, lamps), and moves the marine snow with the camera
## (off inside the tubes, the hall and the tunnel, where there is air).
class DepthTint extends Node:
	var env: Environment
	var sun: DirectionalLight3D
	var td: TrackData
	var kinds := PackedByteArray()
	var snow: GPUParticles3D
	var _hall := 0.0
	var _hit := TrackData.Hit.new()
	var _hint := -1

	func apply(y: float, hall: float) -> void:
		var k := smoothstep(4.0, -42.0, y)
		if env:
			var fog := Color(0.05, 0.24, 0.29).lerp(Color(0.01, 0.06, 0.13), k)
			env.fog_light_color = fog
			env.ambient_light_color = Color(0.26, 0.44, 0.48).lerp(Color(0.1, 0.17, 0.3), k).lerp(Color(0.42, 0.4, 0.36), hall * 0.6)
			env.fog_density = lerpf(0.003, 0.0038, k) * lerpf(1.0, 0.35, hall)
		if sun:
			sun.light_energy = lerpf(1.2, 0.35, k)

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null or td == null:
			return
		var p := cam.global_position
		td.project(p, _hint, _hit)
		_hint = _hit.i
		var kd: int = kinds[_hit.i] if _hit.i < kinds.size() else 0
		var inside := absf(_hit.d) < 40.0 and _hit.h > -4.0 and _hit.h < 30.0
		_hall = move_toward(_hall, 1.0 if (inside and kd >= 2) else 0.0, delta * 1.5)
		apply(p.y, _hall)
		if snow:
			snow.emitting = not (inside and kd != 0)
			snow.global_position = p - cam.global_transform.basis.z * 45.0

# ------------------------------------------------------------------ terrain

## Distance from each ground node to the nearest of `pts` (two-pass
## propagation, as Glacier.distance_field). Returns [dist, index].
static func _field(pts: PackedVector2Array, g: Ground) -> Array:
	var n := g.nx * g.nz
	var dist := PackedFloat32Array()
	var idx := PackedInt32Array()
	dist.resize(n)
	idx.resize(n)
	dist.fill(1e9)
	idx.fill(-1)
	for i in pts.size():
		var p := pts[i]
		var gx := int(round((p.x - g.x0) / GRID))
		var gz := int(round((p.y - g.z0) / GRID))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var x := gx + dx
				var z := gz + dz
				if x < 0 or z < 0 or x >= g.nx or z >= g.nz:
					continue
				var k := z * g.nx + x
				var d := Vector2(g.x0 + x * GRID - p.x, g.z0 + z * GRID - p.y).length()
				if d < dist[k]:
					dist[k] = d
					idx[k] = i
	var passes := [[[-1, 0], [0, -1], [-1, -1], [1, -1]], [[1, 0], [0, 1], [1, 1], [-1, 1]]]
	for pass_i in 2:
		var nbs: Array = passes[pass_i]
		for zz in g.nz:
			var z := zz if pass_i == 0 else g.nz - 1 - zz
			for xx in g.nx:
				var x := xx if pass_i == 0 else g.nx - 1 - xx
				var k := z * g.nx + x
				var w := Vector2(g.x0 + x * GRID, g.z0 + z * GRID)
				for nb: Array in nbs:
					var x2: int = x + int(nb[0])
					var z2: int = z + int(nb[1])
					if x2 < 0 or z2 < 0 or x2 >= g.nx or z2 >= g.nz:
						continue
					var j := idx[z2 * g.nx + x2]
					if j < 0 or j == idx[k]:
						continue
					var d := w.distance_to(pts[j])
					if d < dist[k]:
						dist[k] = d
						idx[k] = j
	return [dist, idx]


## Canyon centre line: the track from the foot of The Drop to the end of the
## Wreck Bend, then on to the south-east into the abyss. Returns the dense
## points and, per point, the distance travelled along the abyss reach (0 on
## the track part).
static func _canyon_line(td: TrackData) -> Array:
	var pts := PackedVector2Array()
	var along := PackedFloat32Array()
	var a := _section(td, "The Drop")
	var b := _section(td, "Wreck Bend")
	var s := lerpf(a.x, a.y, 0.75)
	var hit := TrackData.Hit.new()
	while s < lerpf(b.x, b.y, 0.55):
		td.frame_at(s, hit)
		pts.append(_xz(hit.c))
		along.append(0.0)
		s += 8.0
	var last := pts[pts.size() - 1]
	var dir := (last - pts[pts.size() - 6]).normalized()
	# Swing from the bend's heading toward the south-east, then straight on.
	var target := Vector2(0.75, 0.66).normalized()
	var p := last
	var t := 0.0
	for k in 260:
		dir = dir.lerp(target, 0.03).normalized()
		p += dir * 8.0
		t += 8.0
		pts.append(p)
		along.append(t)
	return [pts, along]


static func _terrain(td: TrackData, root: Node3D) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, td.count, 8):
		lo = Vector2(minf(lo.x, td.pos[i].x), minf(lo.y, td.pos[i].z))
		hi = Vector2(maxf(hi.x, td.pos[i].x), maxf(hi.y, td.pos[i].z))
	var g := Ground.new()
	g.x0 = floorf((lo.x - MARGIN) / GRID) * GRID
	g.z0 = floorf((lo.y - MARGIN) / GRID) * GRID
	g.nx = int((hi.x - lo.x + 2.0 * MARGIN) / GRID) + 2
	g.nz = int((hi.y - lo.y + 2.0 * MARGIN) / GRID) + 2
	g.h.resize(g.nx * g.nz)
	ground = g
	var track_pts := PackedVector2Array()
	for i in range(0, td.count, 2):
		track_pts.append(_xz(td.pos[i]))
	var tf := _field(track_pts, g)
	_fd = tf[0]
	_fi = tf[1]
	for k in _fi.size():
		if _fi[k] >= 0:
			_fi[k] *= 2
	var cl := _canyon_line(td)
	var cpts: PackedVector2Array = cl[0]
	var calong: PackedFloat32Array = cl[1]
	var cf := _field(cpts, g)
	_cd = cf[0]
	var cidx: PackedInt32Array = cf[1]
	_ca.resize(_cd.size())
	for k in _ca.size():
		_ca[k] = calong[cidx[k]] if cidx[k] >= 0 else 0.0
	var n1 := FastNoiseLite.new()
	n1.seed = 4
	n1.frequency = 0.004
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = 9
	n2.frequency = 0.03
	n2.fractal_octaves = 2
	var n3 := FastNoiseLite.new()
	n3.seed = 13
	n3.frequency = 0.012
	var hole_xz := _xz(hole_c)
	var rim := hole_r + 30.0
	for iz in g.nz:
		for ix in g.nx:
			var k := iz * g.nx + ix
			var x := g.x0 + ix * GRID
			var z := g.z0 + iz * GRID
			var a := n1.get_noise_2d(x, z)
			var b := n2.get_noise_2d(x, z)
			var w := n3.get_noise_2d(x, z)
			# Shelf: gentle swells, sand waves, the odd rocky rise.
			var h := SHELF_Y + 3.0 * a + 0.9 * b + maxf(0.0, a - 0.35) * 18.0
			# Deep: the blue hole and the canyon, which opens into the abyss.
			var dh := Vector2(x, z).distance_to(hole_xz) + 16.0 * w
			var hole := 1.0 - smoothstep(rim, rim + 42.0, dh)
			var reach := _ca[k]
			var cw := 120.0 + 0.25 * reach
			var canyon := 1.0 - smoothstep(cw, cw + 60.0, _cd[k] + 20.0 * w)
			var floor_y := FLOOR_Y + 2.5 * a + 1.2 * b - 70.0 * smoothstep(0.0, 1400.0, reach)
			h = lerpf(h, floor_y, maxf(hole, canyon))
			# The circuit's corridor.
			var j := _fi[k]
			if j >= 0:
				var d := _fd[k]
				var half := maxf(td.half_l[j], td.half_r[j])
				var y := td.pos[j].y
				match kind[j]:
					Kind.ROCK:
						# Bored through the shelf: the ground stays above the roof.
						var roof := y + td.ceiling[j] + 4.0
						h = lerpf(h, maxf(h, roof), 1.0 - smoothstep(half + 30.0, half + 70.0, d))
					Kind.TUBE:
						var lim := y - TrackMesh.DECK - HULL - 1.0
						h = lerpf(h, minf(h, lim), 1.0 - smoothstep(half + 5.0, half + 40.0, d))
					Kind.HALL:
						var lim2 := y - 12.0
						h = lerpf(h, minf(h, lim2), 1.0 - smoothstep(half + HALL_SIDE + 4.0, half + HALL_SIDE + 40.0, d))
					_:
						if y > SHELF_Y + 4.0:
							# A reef bank under the causeway, a few metres below the deck.
							var bank := y - 8.5 + 3.0 * b
							h = lerpf(h, maxf(h, bank), 1.0 - smoothstep(half + 12.0, half + 80.0, d))
						var lim3 := y - TrackMesh.DECK - 4.0
						h = lerpf(h, minf(h, lim3), 1.0 - smoothstep(half + 8.0, half + 40.0, d))
			g.h[k] = h
	if not _skip("seabed"):
		_terrain_mesh(root, g)


## Terrain in chunks, each with a full-resolution mesh up close and a
## half-resolution one further out (visibility ranges, no overlap).
static func _terrain_mesh(root: Node3D, g: Ground) -> void:
	var mat := Mats.shader_mat("seabed", {"tex": Mats.tex("abyss_caustics"), "shelf_y": SHELF_Y, "deep_y": FLOOR_Y + 7.0})
	var view := float(Quality.p["view"])
	var near_end := 700.0 * view
	var far_end := 1150.0 * view
	var cx := ceili(float(g.nx - 1) / CHUNK_CELLS)
	var cz := ceili(float(g.nz - 1) / CHUNK_CELLS)
	for qz in cz:
		for qx in cx:
			for lod in 2:
				var stride := 1 if lod == 0 else 2
				var x0 := qx * CHUNK_CELLS
				var z0 := qz * CHUNK_CELLS
				var x1 := mini(x0 + CHUNK_CELLS, g.nx - 1)
				var z1 := mini(z0 + CHUNK_CELLS, g.nz - 1)
				var v := PackedVector3Array()
				var nn := PackedVector3Array()
				var uv := PackedVector2Array()
				var idx := PackedInt32Array()
				var cols := 0
				var rows := 0
				var iz := z0
				while true:
					cols = 0
					var ix := x0
					while true:
						var k := iz * g.nx + ix
						var hl := g.h[iz * g.nx + maxi(ix - 1, 0)]
						var hr := g.h[iz * g.nx + mini(ix + 1, g.nx - 1)]
						var hd := g.h[maxi(iz - 1, 0) * g.nx + ix]
						var hu := g.h[mini(iz + 1, g.nz - 1) * g.nx + ix]
						var x := g.x0 + ix * GRID
						var z := g.z0 + iz * GRID
						v.append(Vector3(x, g.h[k], z))
						nn.append(Vector3(hl - hr, 2.0 * GRID, hd - hu).normalized())
						uv.append(Vector2(x, z))
						cols += 1
						if ix >= x1:
							break
						ix = mini(ix + stride, x1)
					rows += 1
					if iz >= z1:
						break
					iz = mini(iz + stride, z1)
				for r in rows - 1:
					for c in cols - 1:
						var a := r * cols + c
						idx.append_array(PackedInt32Array([a, a + 1, a + cols + 1, a, a + cols + 1, a + cols]))
				var arr := []
				arr.resize(Mesh.ARRAY_MAX)
				arr[Mesh.ARRAY_VERTEX] = v
				arr[Mesh.ARRAY_NORMAL] = nn
				arr[Mesh.ARRAY_TEX_UV] = uv
				arr[Mesh.ARRAY_INDEX] = idx
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mesh.surface_set_material(0, mat)
				var mi := MeshInstance3D.new()
				mi.name = "Seabed_%d_%d_%d" % [qx, qz, lod]
				mi.mesh = mesh
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if lod == 0:
					mi.visibility_range_end = near_end
				else:
					mi.visibility_range_begin = near_end
					mi.visibility_range_end = far_end
				root.add_child(mi)


# ------------------------------------------------------------------ glass tubes

## A point of the tube's cross-section at sample j: phi 0..PI is the glass
## (right, over the crown, to the left), PI..TAU the hull under the deck.
static func _tube_pt(td: TrackData, j: int, phi: float, grow: float = 0.0) -> Vector3:
	var ca := cos(phi)
	var sa := sin(phi)
	var side := (td.half_r[j] if ca >= 0.0 else td.half_l[j]) + TrackMesh.WALL_T + TUBE_SIDE + grow
	var up := (td.ceiling[j] + 0.3 + grow) * sa if sa >= 0.0 else (HULL + grow) * sa
	return td.pos[j] + td.rgt[j] * (side * ca) + td.nrm[j] * (up - 0.3)


static func _tubes(td: TrackData, root: Node3D) -> void:
	var glass_cells: Dictionary = {}
	var cells: Dictionary = {}
	var rib_cells: Dictionary = {}
	var steps_g := 14
	var steps_h := 8
	var step := 4
	for run: Vector2i in _runs(td, Kind.TUBE):
		var prev_g := PackedVector3Array()
		var prev_h := PackedVector3Array()
		var prev_s := 0.0
		var prev_j := -1
		var i := run.x
		while true:
			var j := td.wrap_i(i)
			var s := float(i) * td.step
			var key := int(s / 192.0)
			if not cells.has(key):
				cells[key] = MeshKit.new()
				glass_cells[key] = MeshKit.new()
				rib_cells[key] = MeshKit.new()
			var mk: MeshKit = cells[key]
			var gk: MeshKit = glass_cells[key]
			var sec_g := PackedVector3Array()
			for k in steps_g + 1:
				sec_g.append(_tube_pt(td, j, PI * k / steps_g))
			var sec_h := PackedVector3Array()
			for k in steps_h + 1:
				sec_h.append(_tube_pt(td, j, PI + PI * k / steps_h))
			if prev_g.size() > 0:
				_glass_band(gk, prev_g, sec_g, prev_s, s, prev_j, j, td)
				mk.use("hull")
				var ph: Array[PackedVector3Array] = [prev_h, sec_h]
				mk.loft(ph, Color(0.8, 0.82, 0.85), false, true)
				# Side walkways between the barriers and the glass.
				mk.use("grating")
				for sd: float in [-1.0, 1.0]:
					var e0 := (td.half_r[prev_j] if sd > 0.0 else td.half_l[prev_j]) + TrackMesh.WALL_T
					var e1 := (td.half_r[j] if sd > 0.0 else td.half_l[j]) + TrackMesh.WALL_T
					var a0 := td.pos[prev_j] + td.rgt[prev_j] * sd * e0 - td.nrm[prev_j] * 0.3
					var a1 := td.pos[j] + td.rgt[j] * sd * e1 - td.nrm[j] * 0.3
					var b0 := td.pos[prev_j] + td.rgt[prev_j] * sd * (e0 + TUBE_SIDE) - td.nrm[prev_j] * 0.3
					var b1 := td.pos[j] + td.rgt[j] * sd * (e1 + TUBE_SIDE) - td.nrm[j] * 0.3
					if sd > 0.0:
						mk.quad(a0, a1, b1, b0, Color.WHITE, Vector2(1, 1))
					else:
						mk.quad(a0, b0, b1, a1, Color.WHITE, Vector2(1, 1))
			prev_g = sec_g
			prev_h = sec_h
			prev_s = s
			prev_j = j
			if i >= run.y + 1:
				break
			i = mini(i + step, run.y + 1)
		# Crown lamps every 8 m of lap distance (in step with the light sweep)
		# and a rib every 24 m.
		var s8 := ceilf(run.x * td.step / 8.0) * 8.0
		while s8 <= run.y * td.step:
			var j := td.wrap_i(int(round(s8 / td.step)))
			var key := int(s8 / 192.0)
			var b := Basis(td.rgt[j], td.nrm[j], -td.tan[j])
			var mk: MeshKit = cells[key]
			mk.use("tube_lamp")
			mk.box_t(Transform3D(b, td.pos[j] + td.nrm[j] * (td.ceiling[j] - 0.1)), Vector3(2.6, 0.18, 0.9), Color.WHITE)
			if int(round(td.wrap_s(s8) / 8.0)) % 3 == 0:
				_rib(rib_cells[key], mk, td, j)
			s8 += 8.0
	var mats := _tube_mats()
	for key: int in cells:
		var mi := (cells[key] as MeshKit).instance("Tube%02d" % key, mats)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var rk: MeshKit = rib_cells[key]
		if not rk.is_empty():
			root.add_child(rk.instance("Ribs%02d" % key, mats))
		var gi := (glass_cells[key] as MeshKit).instance("Glass%02d" % key, {"glass": Mats.shader_mat("glass_tube")})
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.sorting_offset = SORT_AFTER_POST + 500.0
		root.add_child(gi)
	_cradles(td, root)


## One band of glass between two cross-sections, normals into the tube,
## UV = metres around / along.
static func _glass_band(mk: MeshKit, a: PackedVector3Array, b: PackedVector3Array, sa: float, sb: float, ja: int, jb: int, td: TrackData) -> void:
	mk.use("glass")
	var base := mk.group_vertex_count()
	var axis_a := td.pos[ja] + td.nrm[ja] * 4.0
	var axis_b := td.pos[jb] + td.nrm[jb] * 4.0
	var around := 0.0
	for k in a.size():
		if k > 0:
			around += a[k].distance_to(a[k - 1])
		mk._vert(a[k], (axis_a - a[k]).normalized(), Color.WHITE, Vector2(around, sa))
	around = 0.0
	for k in b.size():
		if k > 0:
			around += b[k].distance_to(b[k - 1])
		mk._vert(b[k], (axis_b - b[k]).normalized(), Color.WHITE, Vector2(around, sb))
	var n := a.size()
	for k in n - 1:
		mk._quad_i(base + k, base + n + k, base + n + k + 1, base + k + 1)


## A structural ring round the tube, just outside the glass and hull (into
## `rk`, which casts shadows), and small amber lights at its feet (into `mk`).
static func _rib(rk: MeshKit, mk: MeshKit, td: TrackData, j: int) -> void:
	rk.use("rib")
	var n := 14
	var prev := _tube_pt(td, j, 0.0, 0.25)
	for k in range(1, n + 1):
		var p := _tube_pt(td, j, TAU * k / n, 0.25)
		rk.beam(prev, p, 0.8, 0.45, Color.WHITE, td.tan[j])
		prev = p
	mk.use("neon_amber")
	for sd: float in [-1.0, 1.0]:
		var e := (td.half_r[j] if sd > 0.0 else td.half_l[j]) + TrackMesh.WALL_T + TUBE_SIDE - 0.4
		mk.box(td.pos[j] + td.rgt[j] * sd * e + td.nrm[j] * 0.1, Vector3(0.3, 0.3, 0.3), Color.WHITE)


static func _tube_mats() -> Dictionary:
	var hull := _std(Color(0.42, 0.45, 0.48), 0.45, 0.6)
	hull.albedo_texture = Mats.tex("panel_albedo")
	hull.uv1_triplanar = true
	hull.uv1_scale = Vector3(0.1, 0.1, 0.1)
	var rib := _std(Color(0.55, 0.57, 0.6), 0.35, 0.8)
	var grating := _std(Color(0.22, 0.24, 0.26), 0.6, 0.6)
	grating.albedo_texture = Mats.tex("panel_normal")
	grating.uv1_triplanar = true
	grating.uv1_scale = Vector3(0.5, 0.5, 0.5)
	return {"hull": hull, "rib": rib, "grating": grating, "tube_lamp": Mats.glow(Color(0.75, 0.95, 1.0), 4.0)}


## Cradles from the tube hulls to the seabed every 48 m.
static func _cradles(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	for run: Vector2i in _runs(td, Kind.TUBE):
		var i := run.x + 20
		while i < run.y - 10:
			var j := td.wrap_i(i)
			var bottom := _tube_pt(td, j, PI * 1.5, 0.2)
			var foot_y := ground.at(bottom.x, bottom.z)
			if bottom.y - foot_y > 1.0:
				var key := int(i * td.step / 400.0)
				if not cells.has(key):
					cells[key] = MeshKit.new()
				var mk: MeshKit = cells[key]
				mk.use("metal_dark")
				for sd: float in [-1.0, 1.0]:
					var top := _tube_pt(td, j, PI * (1.5 + sd * 0.2), 0.2)
					var foot := Vector3(top.x, 0, top.z) + td.rgt[j] * sd * 4.0
					foot.y = ground.at(foot.x, foot.z) - 0.5
					mk.beam(top, foot, 1.1, 1.1, Color.WHITE, td.tan[j])
					mk.use("concrete")
					mk.box(foot + Vector3(0, 0.4, 0), Vector3(3.0, 1.6, 3.0), Color(0.7, 0.72, 0.7))
					mk.use("metal_dark")
				mk.beam(_tube_pt(td, j, PI * 1.3, 0.2), _tube_pt(td, j, PI * 1.7, 0.2), 0.8, 0.8, Color.WHITE, td.tan[j])
			i += 48
	for key: int in cells:
		root.add_child((cells[key] as MeshKit).instance("Cradles%02d" % key))


# ------------------------------------------------------------------ the Atrium

## Half-ellipse cross-section of the hall at sample j (right floor edge over
## the roof to the left), `grow` outward.
static func _vault(td: TrackData, j: int, side: float, grow: float, steps: int = 16, height: float = -1.0) -> PackedVector3Array:
	var ceil_h := (td.ceiling[j] if height < 0.0 else height) + grow
	var hl := td.half_l[j] + TrackMesh.WALL_T + side + grow
	var hr := td.half_r[j] + TrackMesh.WALL_T + side + grow
	var out := PackedVector3Array()
	for k in steps + 1:
		var a := PI * k / float(steps)
		var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
		var h := -0.6 + sin(a) * (ceil_h + 0.6)
		out.append(td.pos[j] + td.rgt[j] * d + td.nrm[j] * h)
	return out


static func _hall(td: TrackData, root: Node3D) -> void:
	var runs := _runs(td, Kind.HALL)
	if runs.is_empty():
		return
	var ir: Vector2i = runs[0]
	var s_begin := ir.x * td.step
	var chunks: Dictionary = {}
	var outer := MeshKit.new()
	var prev_in := PackedVector3Array()
	var prev_out := PackedVector3Array()
	for i in range(ir.x, ir.y + 2, 2):
		var j := td.wrap_i(i)
		var key := int((i * td.step - s_begin) / 200.0)
		if not chunks.has(key):
			chunks[key] = MeshKit.new()
		var mk: MeshKit = chunks[key]
		var sec_in := _vault(td, j, HALL_SIDE, 0.0)
		var sec_out := _vault(td, j, HALL_SIDE, 1.5)
		if prev_in.size() > 0:
			mk.use("hall_in")
			var pi: Array[PackedVector3Array] = [prev_in, sec_in]
			mk.loft(pi, Color.WHITE, false, false)
			_outer_band(outer, prev_out, sec_out, (i - 2) * td.step, i * td.step)
		prev_in = sec_in
		prev_out = sec_out
	# Every 8 m: side decks, grandstands, the skylight along the crown and lit
	# bands along the walls. Every 16 m: ribs and portholes.
	var s := s_begin
	var s_end := ir.y * td.step
	var k := 0
	var hit := TrackData.Hit.new()
	var nxt := TrackData.Hit.new()
	while s < s_end:
		td.frame_at(s, hit)
		td.frame_at(s + 8.0, nxt)
		var mk: MeshKit = chunks[mini(int((s - s_begin) / 200.0), chunks.size() - 1)]
		var j := hit.i
		var b := Basis(hit.B, hit.N, -hit.T)
		var start_zone := absf(td.delta_s(s + 4.0, 0.0)) < 40.0
		for sd: float in [-1.0, 1.0]:
			var e := (hit.half_r if sd > 0.0 else hit.half_l) + TrackMesh.WALL_T
			var a0 := hit.c + hit.B * sd * e - hit.N * 0.5
			var a1 := nxt.c + nxt.B * sd * e - nxt.N * 0.5
			var b0 := hit.c + hit.B * sd * (e + HALL_SIDE) - hit.N * 0.5
			var b1 := nxt.c + nxt.B * sd * (e + HALL_SIDE) - nxt.N * 0.5
			mk.use("hall_floor")
			if sd > 0.0:
				mk.quad(a0, a1, b1, b0, Color.WHITE)
			else:
				mk.quad(a0, b0, b1, a1, Color.WHITE)
			if not start_zone:
				for t in 3:
					var off := e + 6.0 + t * 3.2
					var hh := 1.2 + t * 1.3
					mk.use("stand")
					mk.box_t(Transform3D(b, hit.c + hit.B * sd * off + hit.N * (hh * 0.5 - 0.5) + hit.T * 4.0), Vector3(3.2, hh, 7.6), Color(0.85, 0.85, 0.9))
					mk.use("neon_amber" if (k + t) % 3 != 0 else "neon_cyan")
					mk.box_t(Transform3D(b, hit.c + hit.B * sd * (off - 1.55) + hit.N * (hh - 0.45) + hit.T * 4.0), Vector3(0.12, 0.12, 7.4), Color.WHITE)
			mk.use("neon_amber")
			mk.box_t(Transform3D(b, hit.c + hit.B * sd * (e + 0.5) - hit.N * 0.4 + hit.T * 4.0), Vector3(0.25, 0.1, 7.0), Color.WHITE)
		# Skylight strip along the crown and warm bands along the walls.
		var arc0 := _vault(td, j, HALL_SIDE, -0.15, 16)
		var arc1 := _vault(td, nxt.i, HALL_SIDE, -0.15, 16)
		mk.use("skylight")
		for q: int in [7, 8]:
			mk.quad(arc0[q], arc1[q], arc1[q + 1], arc0[q + 1], Color.WHITE)
		mk.use("neon_amber")
		for q: int in [2, 4, 12, 14]:
			mk.beam(arc0[q], arc1[q], 0.35, 0.2, Color.WHITE, (arc0[q] - hit.c).normalized())
		if k % 2 == 0:
			var arc := _vault(td, j, HALL_SIDE, -0.4, 16)
			mk.use("rib")
			for q in arc.size() - 1:
				mk.beam(arc[q], arc[q + 1], 1.0, 0.8, Color.WHITE, hit.T)
			mk.use("lamp")
			for q: int in [5, 11]:
				mk.box_t(Transform3D(b, arc[q] - (arc[q] - hit.c).normalized() * 0.6), Vector3(1.6, 0.5, 1.6), Color.WHITE)
			for sd2: float in [-1.0, 1.0]:
				var w := hit.c + hit.B * sd2 * ((hit.half_r if sd2 > 0.0 else hit.half_l) + TrackMesh.WALL_T + HALL_SIDE - 1.2) + hit.N * 9.0 + hit.T * 8.0
				var nrm := -hit.B * sd2
				mk.use("porthole")
				mk.cyl(w - nrm * 0.3, w + nrm * 0.05, 2.6, 2.6, 12, Color.WHITE)
				mk.use("neon_amber")
				mk.torus(w + nrm * 0.1, nrm, 2.8, 0.18, 12, 3, Color.WHITE)
		s += 8.0
		k += 1
	# Team gates over the Atrium.
	for gs: float in [150.0, 300.0]:
		var gi := td.wrap_i(int(gs / td.step))
		var us := gs + td.length if gs < s_begin else gs
		HelixBay._gate(chunks[clampi(int((us - s_begin) / 200.0), 0, chunks.size() - 1)], td, gi, 2 + int(gs / 150.0) * 2)
	var hall_in := _std(Color(0.84, 0.82, 0.78), 0.45, 0.25, Color(0.2, 0.18, 0.15))
	hall_in.albedo_texture = Mats.tex("panel_albedo")
	hall_in.uv1_triplanar = true
	hall_in.uv1_scale = Vector3(0.12, 0.12, 0.12)
	hall_in.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floor_m := _std(Color(0.34, 0.33, 0.32), 0.45, 0.5)
	floor_m.albedo_texture = Mats.tex("panel_albedo")
	floor_m.uv1_triplanar = true
	floor_m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	var stand := _std(Color(0.32, 0.34, 0.38), 0.6, 0.3)
	var rib := _std(Color(0.55, 0.53, 0.5), 0.35, 0.8)
	var mats := {"hall_in": hall_in, "hall_floor": floor_m, "stand": stand, "porthole": _porthole_mat(), "rib": rib,
		"skylight": Mats.glow(Color(1.0, 0.93, 0.8), 2.2)}
	for key: int in chunks:
		var mi := (chunks[key] as MeshKit).instance("Atrium%d" % key, mats)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 700.0 * float(Quality.p["view"])
		root.add_child(mi)
	# Outside: the vault, and a dome over the start line.
	td.frame_at(0.0, hit)
	var dome_c := hit.c - hit.N * 12.0
	outer.use("bld_dense")
	var prof := PackedVector2Array()
	for q in 9:
		var a := PI * 0.5 * q / 8.0
		prof.append(Vector2(maxf(cos(a) * 72.0, 0.01), sin(a) * 52.0))
	outer.push(Transform3D(Basis.IDENTITY, dome_c))
	outer.lathe(prof, 32, Color(0.75, 0.78, 0.8, 0.9), TAU * 72.0)
	outer.pop()
	outer.use("neon_amber")
	outer.torus(dome_c + Vector3(0, 30.0, 0), Vector3.UP, 62.5, 0.5, 48, 4, Color.WHITE)
	outer.use("warn_red")
	outer.sphere(dome_c + Vector3(0, 53.5, 0), Vector3(1.2, 1.2, 1.2), 4, 6, Color.WHITE)
	var om := outer.instance("AtriumOuter")
	om.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	om.visibility_range_end = 1150.0 * float(Quality.p["view"])
	root.add_child(om)
	_keep_clear.append(Vector3(dome_c.x, dome_c.z, 80.0))


## One band of the Atrium's outer vault between two cross-sections, facing
## out, UV = metres along / around, so the facade shader draws window rows on
## the steep lower sides.
static func _outer_band(mk: MeshKit, a: PackedVector3Array, b: PackedVector3Array, sa: float, sb: float) -> void:
	mk.use("bld_dense")
	var base := mk.group_vertex_count()
	var n := a.size()
	for row: Array in [[a, sa], [b, sb]]:
		var sec: PackedVector3Array = row[0]
		var around := 0.0
		for k in n:
			if k > 0:
				around += sec[k].distance_to(sec[k - 1])
			var tang := sec[mini(k + 1, n - 1)] - sec[maxi(k - 1, 0)]
			var nrm := (b[k] - a[k]).cross(tang).normalized()
			mk._vert(sec[k], nrm, Color(0.72, 0.74, 0.78, 0.9), Vector2(float(row[1]), around))
	for k in n - 1:
		mk._quad_i(base + k, base + k + 1, base + n + k + 1, base + n + k)


static func _porthole_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.03, 0.22, 0.28)
	return m


# ------------------------------------------------------------------ the Ascent

## The rock tunnel of the Ascent: a lined bore through the shelf (the ground
## is kept above its roof), wall lamps every 16 m and a crown lamp every 8 m in
## step with the light sweep, and a concrete facade at each portal.
static func _rock_tunnel(td: TrackData, root: Node3D) -> void:
	for ir: Vector2i in _runs(td, Kind.ROCK):
		var mk := MeshKit.new()
		var prev_in := PackedVector3Array()
		for i in range(ir.x, ir.y + 3, 3):
			var j := td.wrap_i(i)
			var sec_in := _vault(td, j, 1.0, 0.0, 12)
			if prev_in.size() > 0:
				mk.use("bore")
				var pi: Array[PackedVector3Array] = [prev_in, sec_in]
				mk.loft(pi, Color.WHITE, false, false)
			prev_in = sec_in
		var hit := TrackData.Hit.new()
		var s := ceilf(ir.x * td.step / 8.0) * 8.0
		var k := 0
		var prev_arc := PackedVector3Array()
		while s < ir.y * td.step:
			td.frame_at(s, hit)
			var b := Basis(hit.B, hit.N, -hit.T)
			mk.use("tube_lamp")
			mk.box_t(Transform3D(b, hit.c + hit.N * (td.ceiling[hit.i] - 0.15)), Vector3(3.0, 0.2, 1.0), Color.WHITE)
			# Continuous light lines along both walls.
			var arc := _vault(td, hit.i, 1.0, -0.25, 12)
			if prev_arc.size() > 0:
				mk.use("neon_amber")
				for q: int in [2, 10]:
					mk.beam(prev_arc[q], arc[q], 0.3, 0.3, Color.WHITE, hit.N)
				mk.use("tube_lamp")
				for q: int in [4, 8]:
					mk.beam(prev_arc[q], arc[q], 0.12, 0.12, Color.WHITE, hit.N)
			prev_arc = arc
			if k % 6 == 3:
				# Ribs of the lining.
				var rib := _vault(td, hit.i, 1.0, -0.2, 12)
				mk.use("portal")
				for q in rib.size() - 1:
					mk.beam(rib[q], rib[q + 1], 0.9, 0.5, Color(0.7, 0.7, 0.7), hit.T)
			s += 8.0
			k += 1
		_portal(mk, td, td.wrap_i(ir.x), -1.0)
		_portal(mk, td, td.wrap_i(ir.y), 1.0)
		var bore := _std(Color(0.55, 0.53, 0.5), 0.6, 0.15, Color(0.13, 0.12, 0.1))
		bore.albedo_texture = Mats.tex("panel_albedo")
		bore.uv1_triplanar = true
		bore.uv1_scale = Vector3(0.08, 0.08, 0.08)
		bore.cull_mode = BaseMaterial3D.CULL_DISABLED
		var portal := _std(Color(0.5, 0.5, 0.48), 0.8)
		portal.albedo_texture = Mats.tex("panel_albedo")
		portal.uv1_triplanar = true
		portal.uv1_scale = Vector3(0.1, 0.1, 0.1)
		var mi := mk.instance("AscentTunnel", {"bore": bore, "portal": portal, "tube_lamp": Mats.glow(Color(0.75, 0.95, 1.0), 4.0)})
		root.add_child(mi)


## Portal facade at sample j, facing `dir` along the track (-1 = the tunnel is
## ahead, +1 = behind): an annulus from the bore's arch out to a wide rounded
## rectangle, a skirt down into the ground, a lit arch and beacons.
static func _portal(mk: MeshKit, td: TrackData, j: int, dir: float) -> void:
	var inner := _vault(td, j, 1.0, 0.0, 16)
	var c := td.pos[j]
	var B := td.rgt[j]
	var N := td.nrm[j]
	var T := td.tan[j]
	var w := maxf(td.half_l[j], td.half_r[j]) + 46.0
	var hgt := td.ceiling[j] + 24.0
	var outer := PackedVector3Array()
	for k in inner.size():
		var a := PI * k / float(inner.size() - 1)
		var lat := w * clampf(cos(a) * 1.5, -1.0, 1.0)
		var up := hgt * clampf(sin(a) * 1.6, 0.0, 1.0) - 0.6
		outer.append(c + B * lat + N * up)
	var off := T * dir * 0.3
	for k in inner.size():
		inner[k] += off
		outer[k] += off
	mk.use("portal")
	var ring: Array[PackedVector3Array] = [inner, outer]
	mk.loft(ring, Color(0.75, 0.75, 0.73), false, dir < 0.0)
	# Skirt into the ground on both sides, and under the facade's lower edge.
	for sd: float in [-1.0, 1.0]:
		var e := (td.half_r[j] if sd > 0.0 else td.half_l[j]) + TrackMesh.WALL_T + 1.0
		var a0 := c + B * sd * e - N * 0.6 + off
		var a1 := c + B * sd * w - N * 0.6 + off
		var b0 := a0 - Vector3(0, 30, 0)
		var b1 := a1 - Vector3(0, 30, 0)
		if (sd > 0.0) != (dir > 0.0):
			mk.quad(a0, a1, b1, b0, Color(0.6, 0.6, 0.58))
		else:
			mk.quad(a0, b0, b1, a1, Color(0.6, 0.6, 0.58))
	mk.use("neon_amber")
	var arc := _vault(td, j, 1.0, 0.6, 16)
	for q in arc.size() - 1:
		mk.beam(arc[q] + off * 2.0, arc[q + 1] + off * 2.0, 0.35, 0.35, Color.WHITE, T)
	mk.use("warn_red")
	for sd: float in [-1.0, 1.0]:
		mk.box(c + B * sd * (w - 4.0) + N * (hgt - 1.5) + off * 2.0, Vector3(0.8, 0.8, 0.8), Color.WHITE)


# ------------------------------------------------------------------ trackside

## Open sections: pylons to the seabed, causeway arches on the shelf, marker
## posts with blue lamps in the deep, light gates.
static func _trackside(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	for i in td.count:
		var s := i * td.step
		var key := int(s / 400.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var open := kind[i] == Kind.OPEN and _kind_at(td, i + 30) == Kind.OPEN and _kind_at(td, i - 30) == Kind.OPEN
		if kind[i] != Kind.OPEN:
			continue
		var p := td.pos[i]
		var deep := p.y < SHELF_Y - 20.0
		if i % 46 == 0:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := ground.at(p.x, p.z)
			if under.y - foot > 1.5:
				mk.use("concrete")
				var hgt := under.y - foot
				mk.box(Vector3(under.x, foot + hgt * 0.5, under.z), Vector3(2.8, hgt, 2.8), Color(0.6, 0.66, 0.66), 0.5, 0.25)
		if not open:
			continue
		if fposmod(s, 24.0) < td.step:
			var b := Basis(td.rgt[i], td.nrm[i], -td.tan[i])
			if deep:
				# Marker posts with blue lamps either side.
				for sd: float in [-1.0, 1.0]:
					var e := (td.half_r[i] if sd > 0.0 else td.half_l[i]) + TrackMesh.WALL_T + 1.2
					var base := p + td.rgt[i] * sd * e
					mk.use("metal_dark")
					mk.box_t(Transform3D(b, base + td.nrm[i] * 2.2), Vector3(0.5, 4.4, 0.5), Color.WHITE)
					mk.use("neon_cyan")
					mk.box_t(Transform3D(b, base + td.nrm[i] * 4.6), Vector3(0.7, 0.5, 0.7), Color.WHITE)
			elif s - last_gate > 60.0:
				# Causeway arch.
				var arc := _vault(td, i, 2.0, 0.0, 12, 12.0)
				mk.use("rib")
				for q in arc.size() - 1:
					mk.beam(arc[q], arc[q + 1], 0.6, 0.6, Color.WHITE, td.tan[i])
				mk.use("tube_lamp")
				mk.box_t(Transform3D(b, p + td.nrm[i] * 11.6), Vector3(2.0, 0.2, 0.7), Color.WHITE)
		if s - last_gate > 230.0 and s > 160.0:
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 230.0) * 2)
	var rib := _std(Color(0.55, 0.57, 0.6), 0.35, 0.8)
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Trackside%02d" % key, {"rib": rib, "tube_lamp": Mats.glow(Color(0.75, 0.95, 1.0), 4.0)}))


# ------------------------------------------------------------------ placement

## Ground node under (x, z).
static func _node(x: float, z: float) -> int:
	var ix := clampi(int(round((x - ground.x0) / GRID)), 0, ground.nx - 1)
	var iz := clampi(int(round((z - ground.z0) / GRID)), 0, ground.nz - 1)
	return iz * ground.nx + ix


## Free ground for a prop of radius r: clear of the track corridor (by kind)
## and of reserved spots.
static func _free(td: TrackData, x: float, z: float, r: float) -> bool:
	var k := _node(x, z)
	var j := _fi[k]
	if j < 0:
		return true
	var half := maxf(td.half_l[j], td.half_r[j])
	var need := half + r + 14.0
	match kind[j]:
		Kind.TUBE:
			need += TUBE_SIDE + 4.0
		Kind.HALL:
			need += HALL_SIDE + 8.0
		Kind.ROCK:
			need += 30.0
	if _fd[k] < need:
		return false
	for kc in _keep_clear:
		if Vector2(x, z).distance_squared_to(Vector2(kc.x, kc.y)) < (kc.z + r) * (kc.z + r):
			return false
	return true


static func _cell_key(x: float, z: float, size: float = 400.0) -> Vector2i:
	return Vector2i(floori(x / size), floori(z / size))


## MultiMesh instances per cell: cells[key] = [Array[Transform3D], Array[Color]].
static func _multimesh_cells(root: Node3D, prefix: String, mesh: Mesh, cells: Dictionary, view_end: float, shadows: bool = false) -> int:
	var total := 0
	for key: Vector2i in cells:
		var cell: Array = cells[key]
		var xf: Array = cell[0]
		if xf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = xf.size()
		for q in xf.size():
			mm.set_instance_transform(q, xf[q])
			mm.set_instance_color(q, cell[1][q])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [prefix, key.x, key.y]
		mmi.multimesh = mm
		mmi.visibility_range_end = view_end * float(Quality.p["view"])
		mmi.visibility_range_end_margin = 40.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		total += xf.size()
	return total


static func _add_inst(cells: Dictionary, xf: Transform3D, col: Color, size: float = 400.0) -> void:
	var key := _cell_key(xf.origin.x, xf.origin.z, size)
	if not cells.has(key):
		cells[key] = [[], []]
	(cells[key][0] as Array).append(xf)
	(cells[key][1] as Array).append(col)


# ------------------------------------------------------------------ the research city

## A habitat dome: a windowed drum and a cap, a ring of lights, an airlock.
static func _dome(mk: MeshKit, base: Vector3, r: float, wall_h: float, cap_h: float, style: float) -> void:
	var prof := PackedVector2Array([Vector2(r, -2.0), Vector2(r, wall_h)])
	for q in range(1, 7):
		var a := PI * 0.5 * q / 6.0
		prof.append(Vector2(maxf(r * cos(a), 0.01), wall_h + cap_h * sin(a)))
	mk.use("bld_dense")
	mk.push(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), base))
	mk.lathe(prof, 20 if r > 18.0 else 14, Color(0.78, 0.8, 0.82, style), TAU * r)
	mk.pop()
	mk.use("neon_amber")
	mk.torus(base + Vector3(0, wall_h + 0.3, 0), Vector3.UP, r + 0.2, 0.25, 24, 3, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(base + Vector3(0, wall_h + cap_h + 0.8, 0), Vector3(0.6, 0.6, 0.6), 3, 5, Color.WHITE)
	var a := rng.randf() * TAU
	var out := Vector3(cos(a), 0, sin(a))
	mk.use("metal_dark")
	mk.box_t(Transform3D(Basis(Vector3.UP, -a), base + out * (r + 2.0) + Vector3(0, 2.5, 0)), Vector3(5.0, 5.0, 5.0), Color.WHITE)
	mk.use("lamp")
	mk.box_t(Transform3D(Basis(Vector3.UP, -a), base + out * (r + 4.6) + Vector3(0, 4.0, 0)), Vector3(0.3, 0.8, 2.4), Color.WHITE)


## Clusters of domes joined by walkway pipes, placed by lap position and offset.
static func _city(td: TrackData, root: Node3D) -> void:
	var sites := [
		["Ring Sweep", 0.55, 150.0, 5, 110.0],
		["Kelp Run", 0.5, -130.0, 3, 70.0],
		["Shelf Edge", 0.3, -95.0, 2, 40.0],
		["Grid Straight", 0.2, 170.0, 4, 90.0],
		["Return", 0.3, -120.0, 3, 70.0],
		["Abyss Run", 0.5, 120.0, 3, 60.0],
	]
	var hit := TrackData.Hit.new()
	var cells: Dictionary = {}
	for site: Array in sites:
		var r := _section(td, site[0])
		if r.x < 0.0:
			continue
		td.frame_at(lerpf(r.x, r.y, site[1]), hit)
		var c := hit.c + hit.B * float(site[2])
		var placed: Array[Vector3] = []
		var tries := 0
		while placed.size() < int(site[3]) and tries < 60:
			tries += 1
			var rad := rng.randf_range(12.0, 30.0) if placed.size() > 0 else rng.randf_range(26.0, 38.0)
			var ang := rng.randf() * TAU
			var dist := 0.0 if placed.is_empty() else rng.randf_range(0.3, 1.0) * float(site[4])
			var p := c + Vector3(cos(ang), 0, sin(ang)) * dist
			if not _free(td, p.x, p.z, rad):
				continue
			var ok := true
			for q in placed:
				if Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) < rad + q.y + 14.0:
					ok = false
			if not ok:
				continue
			p.y = ground.at(p.x, p.z)
			placed.append(Vector3(p.x, rad, p.z))
			var key := _cell_key(p.x, p.z)
			if not cells.has(key):
				cells[key] = MeshKit.new()
			var mk: MeshKit = cells[key]
			var style := 0.9 if rng.randf() < 0.6 else 0.5
			_dome(mk, Vector3(p.x, p.y - 1.0, p.z), rad, rng.randf_range(5.0, 9.0), rad * rng.randf_range(0.5, 0.8), style)
			_keep_clear.append(Vector3(p.x, p.z, rad + 6.0))
			# Walkway pipe to the previous dome.
			if placed.size() > 1:
				var q := placed[placed.size() - 2]
				var a := Vector3(q.x, ground.at(q.x, q.z) + 3.0, q.z)
				var b := Vector3(p.x, p.y + 3.0, p.z)
				var dir := (b - a).normalized()
				a += dir * q.y
				b -= dir * rad
				if a.distance_to(b) > 4.0:
					mk.use("hull")
					mk.cyl(a, b, 2.4, 2.4, 8, Color.WHITE, false)
					mk.use("neon_amber")
					var n := int(a.distance_to(b) / 8.0)
					for w in range(1, n):
						mk.box(a.lerp(b, float(w) / n) + Vector3(0, 2.4, 0), Vector3(0.6, 0.2, 0.6), Color.WHITE)
	var hull := _std(Color(0.5, 0.53, 0.56), 0.45, 0.6)
	for key: Vector2i in cells:
		var mi := (cells[key] as MeshKit).instance("City_%d_%d" % [key.x, key.y], {"hull": hull})
		mi.visibility_range_end = 1300.0 * float(Quality.p["view"])
		root.add_child(mi)


# ------------------------------------------------------------------ kelp

static func _kelp_mesh() -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("kelp")
	var h := 18.0
	var n := 5
	var prev := Vector3.ZERO
	var stem := Vector3.ZERO
	for k in range(1, n + 1):
		var y := h * k / n
		var p := Vector3(sin(k * 1.7) * 0.35, y, cos(k * 2.3) * 0.35)
		var side := Vector3(0.14, 0, 0)
		if k % 2 == 0 or k == n:
			mk.quad(stem - side, p - side, p + side, stem + side, Color(1, 1, 1))
			stem = p
		# A blade from this node, out and up, at the golden angle.
		var a := k * 2.4
		var out := Vector3(cos(a), 0.55, sin(a)).normalized()
		var across := Vector3(-sin(a), 0, cos(a)) * 0.8
		var tip := p + out * 3.6 + Vector3(0, -0.8, 0)
		mk.quad(p - across, tip - across * 0.4, tip + across * 0.4, p + across, Color(0.9, 1, 0.85))
		prev = p
	# Fronds floating at the top.
	for q in 2:
		var a := q * 3.1 + 0.6
		var out := Vector3(cos(a), 0.3, sin(a)).normalized()
		var across := Vector3(-sin(a), 0, cos(a)) * 0.7
		mk.quad(prev - across, prev + out * 4.0 - across * 0.3, prev + out * 4.0 + across * 0.3, prev + across, Color(1, 0.95, 0.8))
	return mk.commit({"kelp": Mats.shader_mat("kelp")})


static func _kelp(td: TrackData, root: Node3D) -> void:
	var density := float(Quality.p["city"])
	var spacing := 11.0 / sqrt(maxf(density, 0.3))
	var cells: Dictionary = {}
	var forest_a := _section(td, "Ring Sweep").x
	var forest_b := _section(td, "Kelp Run").y + 80.0
	var patch := FastNoiseLite.new()
	patch.seed = 77
	patch.frequency = 0.008
	var g := ground
	var z := g.z0 + 20.0
	while z < g.z0 + (g.nz - 2) * GRID:
		var x := g.x0 + 20.0
		while x < g.x0 + (g.nx - 2) * GRID:
			var px := x + rng.randf_range(-0.45, 0.45) * spacing
			var pz := z + rng.randf_range(-0.45, 0.45) * spacing
			x += spacing
			var k := _node(px, pz)
			var j := _fi[k]
			if j < 0:
				continue
			var d := _fd[k]
			if d > 340.0:
				continue
			var s := j * td.step
			var forest := s >= forest_a and s <= forest_b and d < 240.0
			var pn := patch.get_noise_2d(px, pz)
			var want := 0.9 if forest else smoothstep(0.25, 0.5, pn) * 0.6
			want *= 1.0 - smoothstep(200.0, 340.0, d)
			if rng.randf() > want:
				continue
			var y := g.at(px, pz)
			if y < SHELF_Y - 7.0 or g.normal(px, pz).y < 0.85:
				continue
			if not _free(td, px, pz, 3.0):
				continue
			var sc := rng.randf_range(0.55, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.2), sc))
			var tone := rng.randf_range(0.75, 1.15)
			_add_inst(cells, Transform3D(basis, Vector3(px, y - 0.3, pz)), Color(tone, tone * rng.randf_range(0.9, 1.05), tone * 0.9))
		z += spacing
	var total := _multimesh_cells(root, "Kelp", _kelp_mesh(), cells, 350.0)
	if DevArgs.has("--load-times"):
		print("abyssal kelp %d" % total)


# ------------------------------------------------------------------ reef

static func _brain(mk: MeshKit, o: Vector3, col: Color) -> void:
	mk.sphere(o + Vector3(0, 0.1, 0), Vector3(2.2, 1.5, 2.2), 3, 7, col, col * 0.55)


static func _branch(mk: MeshKit, o: Vector3, col: Color) -> void:
	for q in 5:
		var ang := q * 1.26
		var lean := Vector3(cos(ang), 0, sin(ang)) * (0.6 + 0.25 * (q % 3))
		var p0 := o + lean * 0.3
		var p1 := p0 + Vector3(0, 1.4, 0) + lean * 0.9
		var p2 := p1 + Vector3(0, 1.3, 0) + lean * 0.6
		mk.tube(PackedVector3Array([p0, p1, p2]), PackedFloat32Array([0.3, 0.2, 0.1]), 3, col, false)


static func _fan(mk: MeshKit, o: Vector3, col: Color, yaw: float) -> void:
	var r := Vector3(cos(yaw), 0, sin(yaw))
	var hub := o + Vector3(0, 0.8, 0)
	var prev := hub - r * 2.4
	for q in range(1, 8):
		var ang := PI * q / 7.0
		var p := hub - r * cos(ang) * 2.4 + Vector3(0, sin(ang) * 3.0, 0)
		mk.tri(hub, prev, p, col)
		prev = p
	mk.cyl(o, hub, 0.15, 0.12, 4, col * 0.7, false)


static func _sponges(mk: MeshKit, o: Vector3, col: Color) -> void:
	for q in 3:
		var c := o + Vector3(cos(q * 2.1), 0, sin(q * 2.1)) * 0.7
		var hh := 1.6 + q * 0.9
		mk.cyl(c, c + Vector3(0, hh, 0), 0.35, 0.5, 6, col, false, col * 0.6)


## Reef patches (two arrangements of a brain coral, a branching coral, a sea
## fan and tube sponges, coloured in the mesh) and a rock: three meshes, so a
## cell costs three draw calls.
static func _reef_meshes() -> Array[ArrayMesh]:
	var coral := StandardMaterial3D.new()
	coral.vertex_color_use_as_albedo = true
	coral.roughness = 0.7
	coral.emission_enabled = true
	coral.emission = Color(0.06, 0.05, 0.05)
	coral.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rock := StandardMaterial3D.new()
	rock.vertex_color_use_as_albedo = true
	rock.albedo_color = Color(0.36, 0.38, 0.37)
	rock.albedo_texture = Mats.tex("panel_normal")
	rock.uv1_triplanar = true
	rock.uv1_scale = Vector3(0.15, 0.15, 0.15)
	rock.roughness = 0.95
	var mats := {"coral": coral, "rock": rock}
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.9
	var out: Array[ArrayMesh] = []
	var a := MeshKit.new()
	a.use("coral")
	_brain(a, Vector3.ZERO, Color(1.0, 0.5, 0.3))
	_branch(a, Vector3(2.8, 0, 1.2), Color(1.0, 0.35, 0.6))
	_sponges(a, Vector3(-2.4, 0, 1.6), Color(0.65, 0.4, 1.0))
	_fan(a, Vector3(0.8, 0, -2.6), Color(0.85, 0.3, 0.9), 0.3)
	out.append(a.commit(mats))
	var b := MeshKit.new()
	b.use("coral")
	_branch(b, Vector3.ZERO, Color(1.0, 0.8, 0.3))
	_brain(b, Vector3(-2.8, 0, -1.0), Color(0.3, 0.85, 0.75))
	_fan(b, Vector3(2.6, 0, 1.6), Color(1.0, 0.3, 0.55), 1.2)
	_sponges(b, Vector3(1.0, 0, -2.8), Color(1.0, 0.55, 0.15))
	out.append(b.commit(mats))
	var e := MeshKit.new()
	e.use("rock")
	e.blob(Vector3(0, 0.6, 0), Vector3(3.0, 2.0, 2.6), 0, noise, 0.35, Color(1, 1, 1), Color(0.55, 0.57, 0.6), true)
	out.append(e.commit(mats))
	return out


static func _reef(td: TrackData, root: Node3D) -> void:
	var meshes := _reef_meshes()
	var cells: Array[Dictionary] = [{}, {}, {}]
	var density := float(Quality.p["city"])
	var spacing := 16.0 / sqrt(maxf(density, 0.3))
	var reef_a := _section(td, "Coral Esses").x - 60.0
	var reef_b := _section(td, "Shelf Edge").x + 60.0
	var patch := FastNoiseLite.new()
	patch.seed = 19
	patch.frequency = 0.012
	var g := ground
	var z := g.z0 + 20.0
	while z < g.z0 + (g.nz - 2) * GRID:
		var x := g.x0 + 20.0
		while x < g.x0 + (g.nx - 2) * GRID:
			var px := x + rng.randf_range(-0.45, 0.45) * spacing
			var pz := z + rng.randf_range(-0.45, 0.45) * spacing
			x += spacing
			var k := _node(px, pz)
			var j := _fi[k]
			if j < 0 or _fd[k] > 380.0:
				continue
			var s := j * td.step
			var y := g.at(px, pz)
			var deep := y < SHELF_Y - 12.0
			var on_reef := s >= reef_a and s <= reef_b and _fd[k] < 200.0 and not deep
			var pn := patch.get_noise_2d(px, pz)
			var want := 0.6 if on_reef else (0.1 if deep else smoothstep(0.3, 0.6, pn) * 0.45)
			want *= 1.0 - smoothstep(220.0, 380.0, _fd[k])
			if rng.randf() > want:
				continue
			if not _free(td, px, pz, 4.0):
				continue
			var n := g.normal(px, pz)
			var kind_i := 2
			if not deep and n.y > 0.8 and rng.randf() < 0.8:
				kind_i = 0 if rng.randf() < 0.5 else 1
			var sc := rng.randf_range(0.7, 1.3) * (rng.randf_range(1.2, 2.6) if kind_i == 2 else 1.0)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			if kind_i == 2:
				basis = Basis(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized(), rng.randf() * TAU)
			basis = basis.scaled(Vector3(sc, sc, sc))
			var t := rng.randf_range(0.8, 1.15)
			var col := Color(t * rng.randf_range(0.85, 1.15), t, t * rng.randf_range(0.85, 1.15))
			if kind_i == 2:
				col = Color(t, t, t * 1.04) if not deep else Color(t * 0.75, t * 0.78, t * 0.82)
			_add_inst(cells[kind_i], Transform3D(basis, Vector3(px, y - 0.2, pz)), col)
		z += spacing
	var names := ["ReefA", "ReefB", "Rock"]
	var total := 0
	for q in 3:
		total += _multimesh_cells(root, names[q], meshes[q], cells[q], 420.0 if q == 2 else 280.0)
	if DevArgs.has("--load-times"):
		print("abyssal reef %d" % total)


# ------------------------------------------------------------------ fish

static func _fish_mesh() -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("fish")
	var nose := Vector3(0, 0.0, 0.5)
	var ring := [Vector3(0, 0.15, 0.05), Vector3(0.08, 0.0, 0.05), Vector3(0, -0.12, 0.05), Vector3(-0.08, 0.0, 0.05)]
	var tail := Vector3(0, 0.0, -0.38)
	for q in 4:
		var a: Vector3 = ring[q]
		var b: Vector3 = ring[(q + 1) % 4]
		mk.tri(nose, b, a, Color.WHITE)
		mk.tri(tail, a, b, Color.WHITE)
	mk.tri(tail, Vector3(0, 0.2, -0.6), Vector3(0, -0.2, -0.6), Color.WHITE)
	return mk.commit({"fish": Mats.shader_mat("fish")})


## A school circling `centre`: `count` fish (scaled by the particle preset).
static func _school(root: Node3D, mesh: ArrayMesh, centre: Vector3, radius: float, speed: float, count: int, size: float, spread: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "School"
	p.amount = maxi(6, int(count * float(Quality.p["particles"])))
	p.lifetime = 30.0
	p.explosiveness = 1.0
	p.local_coords = true
	p.position = centre
	var ext := radius + spread * 2.0 + 4.0
	p.visibility_aabb = AABB(Vector3(-ext, -spread - 6.0, -ext), Vector3(ext * 2.0, spread * 2.0 + 12.0, ext * 2.0))
	var pm := ShaderMaterial.new()
	pm.shader = load("res://assets/shaders/fish_school.gdshader")
	pm.set_shader_parameter("radius", radius)
	pm.set_shader_parameter("speed", speed)
	pm.set_shader_parameter("spread", spread)
	pm.set_shader_parameter("size", size)
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = 450.0 * float(Quality.p["view"])
	root.add_child(p)


static func _fish(td: TrackData, root: Node3D) -> void:
	var mesh := _fish_mesh()
	var hit := TrackData.Hit.new()
	# (section, fraction, lateral offset, height above ground, radius, count, size)
	var spots := [
		["Ring Sweep", 0.3, -60.0, 10.0, 22.0, 60, 1.2],
		["Kelp Run", 0.2, 55.0, 9.0, 18.0, 50, 1.0],
		["Kelp Run", 0.8, -50.0, 12.0, 26.0, 70, 1.1],
		["Coral Esses", 0.3, 45.0, 7.0, 16.0, 60, 1.0],
		["Coral Esses", 0.85, -42.0, 6.0, 14.0, 50, 0.9],
		["Shelf Edge", 0.5, 60.0, 14.0, 30.0, 70, 1.4],
		["The Drop", 0.35, 0.0, 0.0, 70.0, 80, 1.8],
		["Abyss Run", 0.6, -45.0, 10.0, 22.0, 40, 1.6],
		["Wreck Bend", 0.5, -70.0, 14.0, 30.0, 60, 1.3],
		["Dock Turn", 0.4, -60.0, 12.0, 20.0, 50, 1.0],
		["Return", 0.6, 50.0, 10.0, 18.0, 50, 1.0],
	]
	for sp: Array in spots:
		var r := _section(td, sp[0])
		if r.x < 0.0:
			continue
		td.frame_at(lerpf(r.x, r.y, sp[1]), hit)
		var c := hit.c + hit.B * float(sp[2])
		if sp[0] == "The Drop":
			c = Vector3(hole_c.x, -18.0, hole_c.z)
		else:
			c.y = maxf(ground.at(c.x, c.z), c.y - 14.0) + float(sp[3])
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		_school(root, mesh, c, sp[4], sgn * rng.randf_range(0.22, 0.32) * 18.0 / float(sp[4]), sp[5], sp[6], 5.0 + float(sp[4]) * 0.2)


# ------------------------------------------------------------------ light

## Sun shafts over the shelf (one mesh, camera-facing in the shader).
static func _shafts(td: TrackData, root: Node3D) -> void:
	var mk := MeshKit.new()
	mk.use("shaft")
	var axis := -SUN_DIR.normalized()
	var n := 0
	var tries := 0
	while n < 70 and tries < 600:
		tries += 1
		var i := rng.randi() % td.count
		var p := td.pos[i] + td.rgt[i] * rng.randf_range(-320.0, 320.0) + td.tan[i] * rng.randf_range(-60.0, 60.0)
		var gy := ground.at(p.x, p.z)
		if gy < SHELF_Y - 30.0 and rng.randf() < 0.7:
			continue
		var bottom := Vector3(p.x, gy + rng.randf_range(0.0, 10.0), p.z)
		var top := bottom - axis * rng.randf_range(130.0, 200.0)
		var w := rng.randf_range(0.4, 1.4)
		var ph := rng.randf()
		var base := mk.group_vertex_count()
		mk._vert(top, axis, Color(w, ph, 0), Vector2(-0.5, 0.0))
		mk._vert(top, axis, Color(w, ph, 0), Vector2(0.5, 0.0))
		mk._vert(bottom, axis, Color(w, ph, 0), Vector2(0.5, 1.0))
		mk._vert(bottom, axis, Color(w, ph, 0), Vector2(-0.5, 1.0))
		mk._quad_i(base, base + 1, base + 2, base + 3)
		n += 1
	var mi := mk.instance("Shafts", {"shaft": Mats.shader_mat("light_shaft")})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = SORT_AFTER_POST
	mi.extra_cull_margin = 40.0
	root.add_child(mi)


# ------------------------------------------------------------------ the deep

static func _jelly_mesh() -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("jelly")
	var prof := PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.95, 0.35), Vector2(0.75, 0.75), Vector2(0.4, 1.0), Vector2(0.01, 1.08)])
	mk.lathe(prof, 10, Color.WHITE)
	for q in 6:
		var a := TAU * q / 6.0
		var o := Vector3(cos(a), 0, sin(a)) * 0.6
		var across := Vector3(-sin(a), 0, cos(a)) * 0.08
		mk.quad(o - across, o - across + Vector3(0, -3.5, 0), o + across + Vector3(0, -3.5, 0), o + across, Color.WHITE)
	return mk.commit({"jelly": Mats.shader_mat("jelly")})


static func _jellies(td: TrackData, root: Node3D) -> void:
	var cells: Dictionary = {}
	var hues := [Color(0.2, 0.9, 1.0), Color(0.75, 0.3, 1.0), Color(1.0, 0.35, 0.7), Color(0.4, 1.0, 0.6)]
	var n := int(220 * float(Quality.p["particles"]))
	var a := _section(td, "The Drop")
	var b := _section(td, "The Ascent")
	var hit := TrackData.Hit.new()
	for q in n:
		var p: Vector3
		if q % 3 == 0:
			var ang := rng.randf() * TAU
			var rr := rng.randf_range(20.0, hole_r + 10.0)
			p = Vector3(hole_c.x + cos(ang) * rr, rng.randf_range(FLOOR_Y + 6.0, -4.0), hole_c.z + sin(ang) * rr)
		else:
			td.frame_at(rng.randf_range(lerpf(a.x, a.y, 0.6), b.x), hit)
			p = hit.c + hit.B * rng.randf_range(-160.0, 160.0) + Vector3(0, rng.randf_range(-6.0, 34.0), 0)
		# Not inside a tube or over the deck.
		var k := _node(p.x, p.z)
		if _fi[k] >= 0 and _fd[k] < 34.0 and absf(p.y - td.pos[_fi[k]].y) < 22.0:
			continue
		if p.y < ground.at(p.x, p.z) + 3.0:
			continue
		var sc := rng.randf_range(0.8, 2.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc))
		_add_inst(cells, Transform3D(basis, p), hues[rng.randi() % hues.size()])
	_multimesh_cells(root, "Jelly", _jelly_mesh(), cells, 520.0)
	for c in root.get_children():
		if c.name.begins_with("Jelly_"):
			(c as GeometryInstance3D).sorting_offset = SORT_AFTER_POST


## The Spine: the station's lift shaft standing in the blue hole, from the
## floor to above the shelf, with lit decks and glowing collars.
static func _spine(root: Node3D) -> void:
	var mk := MeshKit.new()
	var c := hole_c
	var top := 46.0
	mk.use("bld_dense")
	mk.push(Transform3D(Basis.IDENTITY, Vector3(c.x, FLOOR_Y - 4.0, c.z)))
	mk.lathe(PackedVector2Array([Vector2(26.0, 0.0), Vector2(18.0, 10.0), Vector2(15.0, 14.0), Vector2(15.0, top - FLOOR_Y + 4.0)]), 20, Color(0.7, 0.74, 0.78, 0.5), TAU * 15.0)
	mk.pop()
	var y := FLOOR_Y + 22.0
	var k := 0
	while y < top:
		mk.use("metal")
		mk.cyl(Vector3(c.x, y - 0.8, c.z), Vector3(c.x, y + 0.8, c.z), 24.0, 24.0, 24, Color.WHITE)
		mk.use("neon_cyan" if k % 2 == 0 else "neon_amber")
		mk.torus(Vector3(c.x, y, c.z), Vector3.UP, 24.2, 0.45, 32, 4, Color.WHITE)
		y += 18.0
		k += 1
	mk.use("metal")
	mk.sphere(Vector3(c.x, top, c.z), Vector3(17.0, 9.0, 17.0), 5, 16, Color.WHITE)
	mk.cyl(Vector3(c.x, top + 7.0, c.z), Vector3(c.x, top + 30.0, c.z), 1.2, 0.5, 6, Color.WHITE)
	mk.use("warn_red")
	mk.sphere(Vector3(c.x, top + 31.0, c.z), Vector3(1.4, 1.4, 1.4), 4, 6, Color.WHITE)
	var mi := mk.instance("Spine")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_keep_clear.append(Vector3(c.x, c.z, 40.0))


## A freighter wrecked on the trench floor outside the Wreck Bend, broken in
## two, listing.
static func _wreck(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Wreck Bend")
	if r.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at(lerpf(r.x, r.y, 0.45), hit)
	var c := hit.c - hit.B * 95.0
	c.y = ground.at(c.x, c.z)
	var fwd := Vector3(hit.T.x, 0, hit.T.z).normalized().rotated(Vector3.UP, 0.5)
	var mk := MeshKit.new()
	# Two pieces: bow and stern, each lofted from U-shaped frames.
	for piece in 2:
		var z0 := -55.0 if piece == 0 else 6.0
		var z1 := -4.0 if piece == 0 else 58.0
		var yaw := 0.0 if piece == 0 else 0.35
		var roll := 0.22 if piece == 0 else -0.3
		var sink := 3.0 if piece == 0 else 5.0
		var b := (Basis(Vector3.UP, atan2(fwd.x, fwd.z) + yaw) * Basis(Vector3.BACK, roll)).scaled(Vector3(1.35, 1.35, 1.35))
		var o := c + Vector3(0, -sink, 0)
		mk.push(Transform3D(b, o))
		var secs: Array[PackedVector3Array] = []
		var z := z0
		while z <= z1 + 0.01:
			var bow := clampf((z - 40.0) / 18.0, 0.0, 1.0) if piece == 1 else 0.0
			var stern := clampf((-48.0 - z) / 7.0, 0.0, 1.0) if piece == 0 else 0.0
			var w := 9.0 * (1.0 - bow * bow * 0.95) * (1.0 - stern * 0.25)
			var sec := PackedVector3Array()
			for q in 7:
				var a := PI * q / 6.0
				sec.append(Vector3(-cos(a) * w, -sin(a) * 6.0 * (1.0 - bow * 0.5) + 6.0, z))
			secs.append(sec)
			z += 4.0
		mk.use("rust")
		mk.loft(secs, Color(0.75, 0.55, 0.42), false, false)
		mk.box(Vector3(0, 6.2, (z0 + z1) * 0.5), Vector3(17.0, 0.4, z1 - z0 - 6.0), Color(0.45, 0.35, 0.3))
		if piece == 1:
			# Superstructure, funnel, mast.
			mk.box(Vector3(0, 11.0, 12.0), Vector3(14.0, 9.0, 10.0), Color(0.7, 0.62, 0.55))
			mk.box(Vector3(0, 16.5, 12.0), Vector3(10.0, 2.5, 7.0), Color(0.6, 0.55, 0.5))
			mk.cyl(Vector3(0, 15.0, 20.0), Vector3(0, 23.0, 21.0), 2.2, 1.9, 8, Color(0.5, 0.25, 0.2))
			mk.use("metal_dark")
			mk.cyl(Vector3(0, 6.0, 40.0), Vector3(0, 22.0, 41.0), 0.4, 0.3, 5, Color.WHITE)
		else:
			mk.use("metal_dark")
			for hz: float in [-40.0, -26.0, -12.0]:
				mk.box(Vector3(0, 7.0, hz), Vector3(9.0, 1.6, 8.0), Color(0.5, 0.45, 0.4))
			mk.cyl(Vector3(0, 6.0, -30.0), Vector3(2.0, 20.0, -31.0), 0.4, 0.3, 5, Color.WHITE)
		# Glowing growth on the hull.
		mk.use("neon_cyan")
		for q in 8:
			mk.sphere(Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(1.0, 6.0), rng.randf_range(z0 + 3.0, z1 - 3.0)), Vector3(0.35, 0.35, 0.35), 3, 4, Color.WHITE)
		mk.pop()
	var rust := _std(Color(0.42, 0.3, 0.24), 0.9, 0.2)
	rust.albedo_texture = Mats.tex("panel_normal")
	rust.uv1_triplanar = true
	rust.uv1_scale = Vector3(0.12, 0.12, 0.12)
	rust.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Survey floodlights on masts between the wreck and the track, and a lamp
	# that lights the hull.
	var to_track := (Vector3(hit.c.x, 0, hit.c.z) - Vector3(c.x, 0, c.z)).normalized()
	var side := to_track.cross(Vector3.UP)
	for sd: float in [-1.0, 1.0]:
		var foot := c + to_track * 45.0 + side * sd * 50.0
		foot.y = ground.at(foot.x, foot.z)
		var head := foot + Vector3(0, 22.0, 0)
		mk.use("metal_dark")
		mk.beam(foot, head, 0.8, 0.8, Color.WHITE)
		mk.box(foot + Vector3(0, 0.6, 0), Vector3(4.0, 1.2, 4.0), Color.WHITE)
		var aim := (c + Vector3(0, 8.0, 0) - head).normalized()
		mk.use("lamp")
		mk.box_t(Transform3D(Basis.looking_at(aim, Vector3.UP), head + aim * 0.8), Vector3(2.4, 1.4, 0.3), Color.WHITE)
		mk.use("warn_red")
		mk.box(head + Vector3(0, 1.6, 0), Vector3(0.6, 0.6, 0.6), Color.WHITE)
	root.add_child(mk.instance("Wreck", {"rust": rust}))
	var lamp := OmniLight3D.new()
	lamp.name = "WreckLight"
	lamp.position = c + to_track * 20.0 + Vector3(0, 30.0, 0)
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 14.0
	lamp.omni_range = 120.0
	lamp.omni_attenuation = 0.6
	lamp.shadow_enabled = false
	root.add_child(lamp)
	_keep_clear.append(Vector3(c.x, c.z, 90.0))


## Submarine pens outside the Dock Turn: a docking tower, a pier and two
## submarines moored alongside.
static func _sub_pen(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Dock Turn")
	if r.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at(lerpf(r.x, r.y, 0.55), hit)
	var out := -Vector3(hit.B.x, 0, hit.B.z).normalized()
	var c := hit.c + out * 110.0
	c.y = ground.at(c.x, c.z)
	var along := out.cross(Vector3.UP).normalized()
	var mk := MeshKit.new()
	mk.use("bld_dense")
	mk.push(Transform3D(Basis.IDENTITY, c - Vector3(0, 2, 0)))
	mk.lathe(PackedVector2Array([Vector2(14.0, 0.0), Vector2(11.0, 6.0), Vector2(11.0, 46.0), Vector2(14.0, 50.0), Vector2(0.01, 56.0)]), 16, Color(0.75, 0.78, 0.8, 0.9), TAU * 11.0)
	mk.pop()
	mk.use("warn_red")
	mk.sphere(c + Vector3(0, 56.0, 0), Vector3(1.0, 1.0, 1.0), 3, 5, Color.WHITE)
	# Pier: a long deck on legs, pointing away from the track.
	var b := Basis(along, Vector3.UP, out)
	var pier_y := c.y + 14.0
	mk.use("metal_dark")
	mk.box_t(Transform3D(b, Vector3(c.x, pier_y, c.z) + out * 70.0), Vector3(8.0, 2.0, 120.0), Color.WHITE)
	for q in 6:
		var leg := Vector3(c.x, 0, c.z) + out * (20.0 + q * 22.0)
		var gy := ground.at(leg.x, leg.z)
		mk.box(Vector3(leg.x, (gy + pier_y) * 0.5, leg.z), Vector3(1.6, pier_y - gy, 1.6), Color.WHITE)
	mk.use("neon_amber")
	mk.box_t(Transform3D(b, Vector3(c.x, pier_y + 1.1, c.z) + out * 70.0), Vector3(0.3, 0.2, 118.0), Color.WHITE)
	# Two submarines either side of the pier.
	for side: float in [-1.0, 1.0]:
		var sc := Vector3(c.x, pier_y - 1.0, c.z) + out * (75.0 + side * 8.0) + along * side * 14.0
		var hb := Basis(along, Vector3.UP, out)
		var hull_xf := Transform3D(hb * Basis(Vector3.RIGHT, PI * 0.5), sc)
		var prof := PackedVector2Array()
		for q in 13:
			var t := float(q) / 12.0
			var rr := 5.2 * pow(sin(PI * clampf(t * 1.08, 0.0, 1.0)), 0.55) + 0.05
			prof.append(Vector2(rr, -26.0 + t * 52.0))
		mk.use("sub" if side > 0.0 else "sub2")
		mk.lathe_at(hull_xf, prof, 14, Color.WHITE)
		mk.box_t(Transform3D(hb, sc + Vector3(0, 6.5, 0) - out * 4.0), Vector3(2.8, 5.0, 9.0), Color(0.9, 0.9, 0.9))
		mk.box_t(Transform3D(hb, sc - out * 23.0), Vector3(0.4, 7.0, 4.0), Color(0.9, 0.9, 0.9))
		mk.box_t(Transform3D(hb, sc - out * 23.0), Vector3(9.0, 0.4, 4.0), Color(0.9, 0.9, 0.9))
		mk.use("lamp")
		for q in 7:
			mk.box_t(Transform3D(hb, sc + along * side * 4.3 + out * (q * 5.0 - 15.0) + Vector3(0, 1.2, 0)), Vector3(0.2, 0.6, 0.9), Color.WHITE)
		mk.use("nav_red" if side > 0.0 else "neon_cyan")
		mk.box_t(Transform3D(hb, sc + Vector3(0, 9.2, 0) - out * 4.0), Vector3(0.4, 0.4, 0.4), Color.WHITE)
	var sub := _std(Color(0.95, 0.55, 0.12), 0.5, 0.3)
	var sub2 := _std(Color(0.85, 0.85, 0.82), 0.5, 0.3)
	root.add_child(mk.instance("SubPen", {"sub": sub, "sub2": sub2}))
	_keep_clear.append(Vector3(c.x + out.x * 70.0, c.z + out.z * 70.0, 85.0))
	_keep_clear.append(Vector3(c.x, c.z, 30.0))
	_school(root, _fish_mesh(), Vector3(c.x, pier_y + 8.0, c.z) + out * 60.0, 28.0, 0.18, 40, 1.2, 8.0)


# ------------------------------------------------------------------ marine snow

## Drifting specks in a box ahead of the camera (DepthTint moves it and turns
## it off inside the tubes, the hall and the tunnel).
static func _snow(root: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "MarineSnow"
	p.amount = int(700 * float(Quality.p["particles"]))
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-120, -60, -120), Vector3(240, 120, 240))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 18, 55)
	pm.direction = Vector3(0.3, -0.2, 0.1)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -0.15, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = Mats.tex("glow")
	mat.albedo_color = Color(0.75, 0.9, 0.88, 0.6)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Specks right in front of the lens would be big blurred squares: fade them.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.8
	mat.distance_fade_max_distance = 4.0
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.sorting_offset = SORT_AFTER_POST
	root.add_child(p)
	return p


# ------------------------------------------------------------------ the Drifter

## The Drifter: an original filter-feeder about 70 m long, flattened, with
## wide swept wings and a horizontal fluke. +Z forward. Vertex colour: r =
## photophore, g = wing weight (for drifter.gdshader).
static func _drifter_mesh() -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("drifter")
	var prof := PackedVector2Array()
	for q in 15:
		var t := float(q) / 14.0
		var r := 7.0 * pow(sin(PI * clampf(t * 0.92 + 0.04, 0.0, 1.0)), 0.7) * (1.0 - 0.55 * t * t) + 0.3
		if q == 14:
			r = 0.05
		prof.append(Vector2(r, -36.0 + t * 72.0))
	# Lathe about Y, mapped so the profile runs along +Z and the body is flattened.
	mk.push(Transform3D(Basis(Vector3(1.35, 0, 0), Vector3(0, 0, 1.0), Vector3(0, -0.75, 0)), Vector3.ZERO))
	mk.lathe(prof, 14, Color(0, 0, 0))
	mk.pop()
	# Wings, swept back, two triangles a side.
	for sd: float in [-1.0, 1.0]:
		var root_f := Vector3(sd * 6.0, 0.6, 16.0)
		var root_b := Vector3(sd * 6.0, 0.2, -8.0)
		var mid := Vector3(sd * 18.0, 0.4, 6.0)
		var tip := Vector3(sd * 32.0, -0.5, -8.0)
		var c_root := Color(0, 0, 0)
		var c_mid := Color(0, 0.45, 0)
		var c_tip := Color(0, 1.0, 0)
		var n := Vector3.UP
		var base := mk.group_vertex_count()
		mk._vert(root_f, n, c_root)
		mk._vert(mid, n, c_mid)
		mk._vert(tip, n, c_tip)
		mk._vert(root_b, n, c_root)
		mk._tri(base, base + 1, base + 2)
		mk._tri(base, base + 2, base + 3)
		# Photophores along the wing's leading edge.
		for q in 5:
			var p := root_f.lerp(mid, (q + 0.5) / 5.0) + Vector3(0, 0.25, 0)
			var col := Color(1, (q + 0.5) / 5.0 * 0.45, 0)
			mk.sphere(p, Vector3(0.45, 0.25, 0.45), 2, 4, col)
	# Fluke.
	var b2 := mk.group_vertex_count()
	mk._vert(Vector3(0, 0, -31.0), Vector3.UP, Color(0, 0, 0))
	mk._vert(Vector3(11.0, 0, -42.0), Vector3.UP, Color(0, 0, 0))
	mk._vert(Vector3(0, 0, -38.0), Vector3.UP, Color(0, 0, 0))
	mk._vert(Vector3(-11.0, 0, -42.0), Vector3.UP, Color(0, 0, 0))
	mk._tri(b2, b2 + 1, b2 + 2)
	mk._tri(b2, b2 + 2, b2 + 3)
	# Rows of photophores along the flanks and two eye spots.
	for sd: float in [-1.0, 1.0]:
		for q in 12:
			var z := 26.0 - q * 5.0
			var t := (z + 36.0) / 72.0
			var r := 7.0 * pow(sin(PI * clampf(t * 0.92 + 0.04, 0.0, 1.0)), 0.7) * (1.0 - 0.55 * t * t) + 0.3
			mk.sphere(Vector3(sd * r * 1.3, 0.8, z), Vector3(0.5, 0.5, 0.5), 2, 4, Color(1, 0, 0))
		mk.sphere(Vector3(sd * 4.2, 1.5, 30.0), Vector3(0.9, 0.9, 0.9), 3, 6, Color(1, 0, 0))
	return mk.commit({"drifter": Mats.shader_mat("drifter")})


## The Drifter and its calf swim a slow loop over the Abyss Run, 25-30 m above
## the deck, inside the canyon.
static func _drifters(td: TrackData, root: Node3D) -> void:
	var a := _section(td, "Abyss Run")
	var b := _section(td, "Wreck Bend")
	if a.x < 0.0 or b.x < 0.0:
		return
	var ctrl := PackedVector3Array()
	var hit := TrackData.Hit.new()
	var s0 := a.x + 80.0
	var s1 := b.x + 40.0
	var n := 8
	for q in n + 1:
		td.frame_at(lerpf(s0, s1, float(q) / n), hit)
		ctrl.append(Vector3(hit.c.x, 0, hit.c.z) + Vector3(hit.B.x, 0, hit.B.z).normalized() * 65.0 + Vector3(0, hit.c.y + 26.0, 0))
	for q in range(n, -1, -1):
		td.frame_at(lerpf(s0, s1, float(q) / n), hit)
		ctrl.append(Vector3(hit.c.x, 0, hit.c.z) - Vector3(hit.B.x, 0, hit.B.z).normalized() * 65.0 + Vector3(0, hit.c.y + 34.0, 0))
	# Close the loop for the spline: wrap two points each way.
	var loop := PackedVector3Array([ctrl[ctrl.size() - 1]])
	loop.append_array(ctrl)
	loop.append(ctrl[0])
	loop.append(ctrl[1])
	var pts := MeshKit.curve(loop, 10)
	var mesh := _drifter_mesh()
	var swim := Swim.new()
	swim.name = "Drifters"
	swim.path = pts
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.name = "Drifter%d" % k
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 700.0 * float(Quality.p["view"])
		var mat := (mesh.surface_get_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("phase", k * 2.1)
		mi.material_override = mat
		swim.add_child(mi)
		swim.bodies.append(mi)
	swim.offsets = [0.0, -55.0]
	swim.scales = [1.0, 0.45]
	swim.lifts = [0.0, 7.0]
	root.add_child(swim)


## Moves the Drifters along their loop at a steady pace, facing along it.
class Swim extends Node3D:
	var path := PackedVector3Array()
	var bodies: Array[MeshInstance3D] = []
	var offsets: Array = []
	var scales: Array = []
	var lifts: Array = []
	var speed := 11.0
	var _cum := PackedFloat32Array()
	var _d := 0.0

	func _ready() -> void:
		_cum.resize(path.size())
		_cum[0] = 0.0
		for i in range(1, path.size()):
			_cum[i] = _cum[i - 1] + path[i].distance_to(path[i - 1])
		_d = _cum[_cum.size() - 1] * 0.3
		_place()

	func _process(delta: float) -> void:
		_d += speed * delta
		_place()

	func _at(d: float) -> Vector3:
		var total := _cum[_cum.size() - 1]
		var x := fposmod(d, total)
		var i := _cum.bsearch(x)
		i = clampi(i, 1, path.size() - 1)
		var t := (x - _cum[i - 1]) / maxf(_cum[i] - _cum[i - 1], 0.001)
		return path[i - 1].lerp(path[i], t)

	func _place() -> void:
		for k in bodies.size():
			var d := _d + float(offsets[k])
			var p := _at(d) + Vector3(0, float(lifts[k]), 0)
			var ahead := _at(d + 6.0) + Vector3(0, float(lifts[k]), 0)
			var fwd := (ahead - p).normalized()
			var sc := float(scales[k])
			var basis := Basis.looking_at(-fwd, Vector3.UP).scaled(Vector3(sc, sc, sc))
			bodies[k].global_transform = Transform3D(basis, p)
