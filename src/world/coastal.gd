## COSTA BRANCA world: a whitewashed Mediterranean town above its harbour, on a
## bright summer afternoon.
##
## Geography (all derived from the track): the coastline is a polyline built
## from offsets to the right of the coastal sections (Cliff Road .. Harbour
## Front), extended north along the open coast and east past the harbour; the
## sea is on its right. A signed distance to it shapes cliffs, rocky shores,
## the beach and the quay. The town climbs the hill from the harbour; olive
## groves and cypresses cover the slopes behind; the Headland Tunnel runs
## under a spur of the hill; a natural rock arch carries the track over a sea
## inlet; the lighthouse stands inside the Lighthouse Bend; a dry ravine runs
## under the Ravine Jump down to the sea.
##
## Water: one sea surface whose colour comes from a depth texture baked from
## the height field (turquoise shallows over sand, deep blue offshore, foam at
## the shore). Houses use a daytime facade shader (windows, shutters, doors and
## painted plinths drawn per floor and bay).
class_name Coastal
extends RefCounted

const GRID := 32.0
const MARGIN := 1500.0
const DEPTH_SCALE := 30.0
const CELL := 400.0

static var rng := RandomNumberGenerator.new()
static var last_hf: Glacier.HF
static var _fd := PackedFloat32Array()    ## Track distance per height-field node.
static var _fi := PackedInt32Array()      ## Nearest track sample per node.
static var _cd := PackedFloat32Array()    ## Signed distance to the coast (+ land, - sea).
static var _ci := PackedInt32Array()      ## Nearest dense coast point per node.
static var _rd := PackedFloat32Array()    ## Ravine distance per node.
static var _coast := PackedVector2Array() ## Dense coastline, lap order, sea on the right.
static var _c_land := PackedFloat32Array()  ## Land-side slope at each coast point.
static var _c_sea := PackedFloat32Array()   ## Sea-floor slope at each coast point.
static var _ravine := PackedVector2Array()
static var _ravine_y := PackedFloat32Array()
static var _keep_clear: Array[Vector3] = []   ## (x, z, radius) kept free of trees and houses.
static var _occ: Dictionary = {}              ## 4 m cells taken by buildings.
static var _lighthouse := Vector3.ZERO
static var _church := Vector3.ZERO
static var _town_s := Vector2.ZERO           ## Lap range of the town (harbour .. church).
static var _grove := FastNoiseLite.new()     ## Where the olive groves are (> 0).


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 1987
	_grove.seed = 12
	_grove.frequency = 0.006
	_grove.fractal_octaves = 2
	_keep_clear.clear()
	_occ.clear()
	var t0 := Time.get_ticks_msec()
	_environment(root)
	_town_s = Vector2(-60.0, _sec(td, "Church Square").y + 40.0)
	_coast_path(td)
	_ravine_path(td)
	_landmarks(td)
	var hf := _terrain(td, root)
	last_hf = hf
	var t1 := Time.get_ticks_msec()
	for a in DevArgs.all():
		if a.begins_with("--dump-terrain="):
			_debug_map(td, hf, a.substr(15))
	var steps := {}
	var tk := Time.get_ticks_msec()
	_sea(root, hf)
	_harbour(td, root, hf)
	_tunnel(td, root, hf)
	_arch(td, root)
	_lighthouse_build(root, hf)
	_church_build(td, root, hf)
	steps["sea+structures"] = Time.get_ticks_msec() - tk
	tk = Time.get_ticks_msec()
	_town(td, root, hf)
	steps["town"] = Time.get_ticks_msec() - tk
	tk = Time.get_ticks_msec()
	_beach(td, root, hf)
	_trees(td, root, hf)
	steps["beach+trees"] = Time.get_ticks_msec() - tk
	tk = Time.get_ticks_msec()
	_trackside(td, root, hf)
	_far(root, hf)
	HelixBay._start_gantry(td, root, "COSTA BRANCA  /  VELOCITY LEAGUE")
	steps["trackside"] = Time.get_ticks_msec() - tk
	if DevArgs.has("--load-times"):
		print("coastal steps ms ", steps)
	if DevArgs.has("--load-times"):
		print("coastal world %d ms (terrain %d ms)" % [Time.get_ticks_msec() - t0, t1 - t0])
		_triangle_report(root)


static func _environment(root: Node3D) -> void:
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			env.sky.sky_material = Mats.shader_mat("sky_coastal", {"clouds": Mats.tex("coastal_clouds")})
			env.sky.radiance_size = Sky.RADIANCE_SIZE_64
			env.ambient_light_energy = 0.6
			env.ambient_light_sky_contribution = 0.75
			env.ambient_light_color = Color(0.6, 0.6, 0.55)
			env.fog_light_color = Color(0.7, 0.8, 0.9)
			env.fog_density = 0.00028
			env.fog_aerial_perspective = 0.75
			env.fog_sky_affect = 0.0
			env.tonemap_exposure = 0.82
			env.glow_hdr_threshold = 1.35
		elif c is DirectionalLight3D:
			var sun := c as DirectionalLight3D
			sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-25.0), 0.0)
			sun.light_color = Color(1.0, 0.95, 0.86)
			sun.light_energy = 1.45


static func _sec(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _hit(td: TrackData, s: float) -> TrackData.Hit:
	var h := TrackData.Hit.new()
	td.frame_at(s, h)
	return h


# ------------------------------------------------------------------ paths

## Coastline: offsets to the right of the coastal sections, in lap order from
## inside the Headland Tunnel to the end of the Harbour Front, extended along
## the open coast to the north and past the harbour to the east.
static func _coast_path(td: TrackData) -> void:
	var tun := _sec(td, "Headland Tunnel")
	var cl0 := _sec(td, "Cliff Road").x
	var ab := _sec(td, "Arch Bridge")
	var lb := _sec(td, "Lighthouse Bend")
	var rr := _sec(td, "Ravine Run").x
	var cd := _sec(td, "Cove Descent")
	var bs := _sec(td, "Beach Straight")
	var hf1 := _sec(td, "Harbour Front").y
	var L := td.length
	var ab_mid := (ab.x + ab.y) * 0.5
	var pts := PackedVector2Array()
	var land := PackedFloat32Array()
	var sea := PackedFloat32Array()
	# Lap-distance keys: [s, offset, land slope, sea slope].
	var keys := [
		[tun.y - 220.0, 75.0, 2.4, 0.5], [cl0, 62.0, 2.6, 0.5],
		[ab_mid - 70.0, 60.0, 2.6, 0.5],
		[ab.y + 60.0, 62.0, 2.6, 0.5], [lb.x, 66.0, 2.4, 0.45],
		[(lb.x + lb.y) * 0.5, 92.0, 2.0, 0.4], [lb.y, 80.0, 1.6, 0.35],
		[rr, 86.0, 1.2, 0.3], [cd.x, 96.0, 0.8, 0.2], [cd.y, 110.0, 0.35, 0.1],
		[bs.x, 96.0, 0.06, 0.035], [L - 60.0, 84.0, 0.06, 0.035],
		[L - 18.0, 44.0, 1.0, 0.3], [L + 6.0, 24.0, 5.0, 1.0],
		[L + hf1 + 40.0, 24.0, 5.0, 1.0],
	]
	var s := float(keys[0][0])
	var k := 0
	while s <= float(keys[keys.size() - 1][0]):
		while k < keys.size() - 2 and s > float(keys[k + 1][0]):
			k += 1
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		var u := smoothstep(float(a[0]), float(b[0]), s)
		var off := lerpf(float(a[1]), float(b[1]), u)
		# The inlet under the Arch Bridge: the shore swings in under the track.
		var inl := absf(s - ab_mid)
		if inl < 70.0:
			off = lerpf(off, -75.0, smoothstep(70.0, 22.0, inl))
		var h := _hit(td, s)
		pts.append(_xz(h.c) + _xz(h.B).normalized() * off)
		land.append(lerpf(float(a[2]), float(b[2]), u))
		sea.append(lerpf(float(a[3]), float(b[3]), u))
		s += 8.0
	# Extensions: north along the open coast, east past the harbour.
	var p0 := pts[0]
	var hcl := _hit(td, cl0)
	var d0 := -Vector2(hcl.T.x, hcl.T.z).normalized().rotated(deg_to_rad(-30.0))
	var north := PackedVector2Array()
	for q in range(60, 0, -1):
		var dir := d0.rotated(deg_to_rad(-8.0) * smoothstep(0.0, 60.0, float(q)))
		north.append(p0 + dir * (q * 40.0) + Vector2(-dir.y, dir.x) * sin(q * 0.3) * 18.0)
	var pe := pts[pts.size() - 1]
	var de := (pts[pts.size() - 1] - pts[pts.size() - 6]).normalized()
	var all := PackedVector2Array(north)
	var all_land := PackedFloat32Array()
	var all_sea := PackedFloat32Array()
	for q in north.size():
		all_land.append(2.2)
		all_sea.append(0.45)
	all.append_array(pts)
	all_land.append_array(land)
	all_sea.append_array(sea)
	for q in range(1, 60):
		var dir := de.rotated(deg_to_rad(10.0) * smoothstep(0.0, 30.0, float(q)))
		all.append(pe + dir * (q * 40.0) + Vector2(-dir.y, dir.x) * sin(q * 0.4) * 15.0)
		all_land.append(lerpf(1.2, 0.9, smoothstep(0.0, 10.0, float(q))))
		all_sea.append(0.3)
	# Densify (every ~8 m) so the propagation finds the true nearest point.
	_coast = PackedVector2Array()
	_c_land = PackedFloat32Array()
	_c_sea = PackedFloat32Array()
	for q in all.size() - 1:
		var a := all[q]
		var b := all[q + 1]
		var n := maxi(1, int(a.distance_to(b) / 8.0))
		for m in n:
			var t := float(m) / n
			_coast.append(a.lerp(b, t))
			_c_land.append(lerpf(all_land[q], all_land[q + 1], t))
			_c_sea.append(lerpf(all_sea[q], all_sea[q + 1], t))
	_coast.append(all[all.size() - 1])
	_c_land.append(all_land[all_land.size() - 1])
	_c_sea.append(all_sea[all_sea.size() - 1])


## Ravine under the Ravine Jump: from the hills on the left, through the gap,
## down to the sea on the right. Floor heights descend towards the sea.
static func _ravine_path(td: TrackData) -> void:
	var rj := _sec(td, "Ravine Jump")
	var h := _hit(td, rj.x + 130.0)     # middle of the 60 m gap after the 100 m kicker
	var g := _xz(h.c)
	var right := _xz(h.B).normalized()
	var fwd := _xz(h.T).normalized()
	_ravine = PackedVector2Array([g - right * 320.0 - fwd * 40.0, g - right * 160.0 - fwd * 10.0, g, g + right * 70.0 + fwd * 8.0, g + right * 160.0 + fwd * 25.0])
	_ravine_y = PackedFloat32Array([h.c.y - 8.0, h.c.y - 20.0, h.c.y - 34.0, 2.0, -6.0])


## Lighthouse inside the Lighthouse Bend, church inside the Church Square bend.
static func _landmarks(td: TrackData) -> void:
	var lb := _sec(td, "Lighthouse Bend")
	var h := _hit(td, (lb.x + lb.y) * 0.5)
	_lighthouse = h.c - h.B * 95.0
	_keep_clear.append(Vector3(_lighthouse.x, _lighthouse.z, 34.0))
	var cs := _sec(td, "Church Square")
	h = _hit(td, (cs.x + cs.y) * 0.5)
	_church = h.c - h.B * (h.half_l + 34.0)
	_keep_clear.append(Vector3(_church.x, _church.z, 40.0))


## Nearest point of a polyline for every height-field node (two-pass
## propagation, as Glacier.distance_field). Returns [dist, index into dense].
static func _poly_field(dense: PackedVector2Array, hf: Glacier.HF) -> Array:
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


static func _densify(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in line.size() - 1:
		var n := maxi(1, int(line[k].distance_to(line[k + 1]) / step))
		for m in n:
			out.append(line[k].lerp(line[k + 1], float(m) / n))
	out.append(line[line.size() - 1])
	return out


## Signed coast distance at a world point (+ land), from the dense coastline.
static func _coast_side(p: Vector2, i: int) -> float:
	var a := _coast[maxi(i - 1, 0)]
	var b := _coast[mini(i + 1, _coast.size() - 1)]
	var dir := (b - a).normalized()
	var right := Vector2(-dir.y, dir.x)
	return -1.0 if (p - _coast[i]).dot(right) > 0.0 else 1.0


# ------------------------------------------------------------------ terrain

static func _terrain(td: TrackData, root: Node3D) -> Glacier.HF:
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
	hills.seed = 12
	hills.frequency = 0.0035
	hills.fractal_octaves = 3
	var ridge := FastNoiseLite.new()
	ridge.seed = 4
	ridge.frequency = 0.0012
	ridge.fractal_octaves = 3
	var field := Glacier.distance_field(td, hf)
	_fd = field[0]
	_fi = field[1]
	var cf: Array = _poly_field(_coast, hf)
	var cdist: PackedFloat32Array = cf[0]
	_ci = cf[1]
	_rd = _poly_field(_densify(_ravine, 6.0), hf)[0]
	_cd.resize(hf.nx * hf.nz)
	var tun := _sec(td, "Headland Tunnel")
	var tun_mid := _hit(td, (tun.x + tun.y) * 0.5)
	var ab := _sec(td, "Arch Bridge")
	var ab_mid := (ab.x + ab.y) * 0.5
	var rj := _sec(td, "Ravine Jump")
	var gap := Vector2(rj.x + 95.0, rj.x + 165.0)
	var church_xz := _xz(_church)
	var lh_xz := _xz(_lighthouse)
	var cols := PackedColorArray()
	cols.resize(hf.nx * hf.nz)
	for iz in hf.nz:
		for ix in hf.nx:
			var k := iz * hf.nx + ix
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var pxz := Vector2(x, z)
			var j := _fi[k]
			var d: float = _fd[k] if j >= 0 else 1e6
			var ty: float = td.pos[j].y if j >= 0 else 0.0
			var s: float = j * td.step if j >= 0 else -1.0
			var ci := _ci[k]
			var cd: float = cdist[k] * _coast_side(pxz, ci) if ci >= 0 else 1e6
			_cd[k] = cd
			var n := hills.get_noise_2d(x, z) * 0.5 + 0.5
			var r := ridge.get_noise_2d(x, z) * 0.5 + 0.5
			# Hills rising away from the circuit; mountains inland.
			var h := ty - TrackMesh.DECK - 0.4
			h += smoothstep(25.0, 450.0, d) * (30.0 + 60.0 * r + 14.0 * n)
			h += smoothstep(450.0, 1500.0, d) * (90.0 + 260.0 * r)
			# The spur the Headland Tunnel runs under.
			h += 52.0 * (1.0 - smoothstep(120.0, 330.0, pxz.distance_to(_xz(tun_mid.c)))) * smoothstep(20.0, 70.0, d)
			# Knolls for the lighthouse and the church.
			h = lerpf(h, maxf(h, ty + 6.0), 1.0 - smoothstep(30.0, 70.0, pxz.distance_to(lh_xz)))
			# Corridor: cut and fill to the deck, except over the inlet and the ravine.
			# The target is the lowest point of the deck underside (banked corners).
			var low := ty - TrackMesh.DECK - 0.4
			if j >= 0:
				low -= absf(sin(td.bank[j])) * (maxf(td.half_l[j], td.half_r[j]) + 1.5)
			if j >= 0:
				var w := maxf(td.half_l[j], td.half_r[j]) + 9.0
				var target := low
				var open := (s > ab.x - 30.0 and s < ab.y + 30.0) or (s > gap.x and s < gap.y)
				if s >= tun.x - 10.0 and s <= tun.y + 10.0:
					w += 5.0
				if open:
					h = lerpf(h, minf(h, target - 2.0), 1.0 - smoothstep(w, w + 40.0, d))
				else:
					h = lerpf(target, h, smoothstep(w, w + 55.0, d))
			# The coast: cliffs, rocky shores, the beach and the quay.
			if cd < 1e5:
				var sl: float = _c_land[ci]
				var ss: float = _c_sea[ci]
				var cap: float
				if cd >= 0.0:
					cap = cd * sl + maxf(0.0, cd - 70.0) * 1.5
				else:
					cap = maxf(maxf(cd, -40.0) * ss + minf(0.0, cd + 40.0) * 0.06, -42.0)
				if ss >= 0.9 and cd < 0.0:
					cap = minf(cap, -5.5)        # harbour basin
				if cd < 0.0 and s > ab.x - 60.0 and s < ab.y + 60.0:
					cap = minf(cap, -7.0)        # the inlet under the arch is deep
				h = minf(h, cap)
			# The inlet itself and the water in front of it (the nearest-coast sign
			# is unreliable around the inlet's U-turn).
			if j >= 0 and absf(s - ab_mid) < 36.0:
				var lat := (pxz - _xz(td.pos[j])).dot(_xz(td.rgt[j]).normalized())
				if lat > -60.0:
					h = minf(h, -7.0)
			# Ravine: a V-shaped gully down to the sea.
			var rdk := _rd[k]
			if rdk < 90.0:
				var fl := _ravine_floor(pxz)
				h = lerpf(minf(h, fl), h, smoothstep(10.0, 52.0, rdk))
			# Never above the deck underside in the corridor.
			if j >= 0 and d < maxf(td.half_l[j], td.half_r[j]) + 4.0:
				h = minf(h, low + 0.1)
			hf.h[k] = h
			# Vertex colour: R olive-grove soil, G town paving.
			var olive := 0.0
			if cd > 50.0 and d > 18.0 and d < 640.0 and h > 30.0:
				olive = smoothstep(0.04, 0.18, _grove.get_noise_2d(x, z)) * smoothstep(640.0, 450.0, d)
			var town := 0.0
			if s >= 0.0 and (s < _town_s.y or s > td.length + _town_s.x) and cd > 12.0:
				town = (1.0 - smoothstep(60.0, 170.0, d)) * 0.8
			town = maxf(town, 1.0 - smoothstep(35.0, 60.0, pxz.distance_to(church_xz)))
			cols[k] = Color(olive * (1.0 - town), town, 0.0)
	_smooth_seabed(hf)
	var mk := MeshKit.new()
	mk.use("ground")
	var base_i := mk.group_vertex_count()
	for iz in hf.nz:
		for ix in hf.nx:
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var hl := hf.h[iz * hf.nx + maxi(ix - 1, 0)]
			var hr := hf.h[iz * hf.nx + mini(ix + 1, hf.nx - 1)]
			var hd := hf.h[maxi(iz - 1, 0) * hf.nx + ix]
			var hu := hf.h[mini(iz + 1, hf.nz - 1) * hf.nx + ix]
			mk._vert(Vector3(x, hf.h[iz * hf.nx + ix], z), Vector3(hl - hr, 2.0 * GRID, hd - hu).normalized(), cols[iz * hf.nx + ix], Vector2(x, z))
	for iz in hf.nz - 1:
		for ix in hf.nx - 1:
			var a := iz * hf.nx + ix
			# Skip cells entirely under water (the sea surface is opaque).
			if maxf(maxf(hf.h[a], hf.h[a + 1]), maxf(hf.h[a + hf.nx], hf.h[a + hf.nx + 1])) < -1.0:
				continue
			mk._quad_i(base_i + a, base_i + a + 1, base_i + a + hf.nx + 1, base_i + a + hf.nx)
	var mi := mk.instance("Terrain", {"ground": _ground_mat()})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return hf


## Box-blurs the sea floor away from the shore, so the depth (and the water
## colour) changes smoothly where the nearest stretch of coast switches from
## cliff to beach.
static func _smooth_seabed(hf: Glacier.HF) -> void:
	var r := 3
	for it in 2:
		for axis in 2:
			var src := hf.h.duplicate()
			var n_outer := hf.nz if axis == 0 else hf.nx
			var n_inner := hf.nx if axis == 0 else hf.nz
			for o in n_outer:
				var acc := 0.0
				var line := PackedFloat32Array()
				line.resize(n_inner)
				for q in n_inner:
					# Land counts as shallow water, so cliffs do not lift the sea floor.
					line[q] = minf(src[o * hf.nx + q] if axis == 0 else src[q * hf.nx + o], -3.0)
				for q in range(-r, r + 1):
					acc += line[clampi(q, 0, n_inner - 1)]
				for q in n_inner:
					var k := o * hf.nx + q if axis == 0 else q * hf.nx + o
					if _cd[k] < -30.0:
						hf.h[k] = minf(acc / (2 * r + 1), -1.5)
					acc += line[clampi(q + r + 1, 0, n_inner - 1)] - line[clampi(q - r, 0, n_inner - 1)]


static func _ground_mat() -> ShaderMaterial:
	return Mats.shader_mat("coastal_ground", {"noise_tex": Mats.tex("coastal_noise")})


static func _ravine_floor(p: Vector2) -> float:
	var best := INF
	var y := 0.0
	for k in _ravine.size() - 1:
		var a := _ravine[k]
		var b := _ravine[k + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var dd := p.distance_squared_to(a + ab * t)
		if dd < best:
			best = dd
			y = lerpf(_ravine_y[k], _ravine_y[k + 1], t)
	return y


static func _slope(hf: Glacier.HF, x: float, z: float) -> float:
	var e := GRID * 0.5
	return Vector2(hf.at(x + e, z) - hf.at(x - e, z), hf.at(x, z + e) - hf.at(x, z - e)).length() / (2.0 * e)


## Signed coast distance at a world point, from the nearest height-field node.
static func _coast_at(hf: Glacier.HF, x: float, z: float) -> float:
	var ix := clampi(int(round((x - hf.x0) / GRID)), 0, hf.nx - 1)
	var iz := clampi(int(round((z - hf.z0) / GRID)), 0, hf.nz - 1)
	return _cd[iz * hf.nx + ix]


static func _node(hf: Glacier.HF, x: float, z: float) -> int:
	var ix := clampi(int(round((x - hf.x0) / GRID)), 0, hf.nx - 1)
	var iz := clampi(int(round((z - hf.z0) / GRID)), 0, hf.nz - 1)
	return iz * hf.nx + ix


# ------------------------------------------------------------------ sea

## The sea: a grid over the height field plus a skirt to the horizon. Its
## colour comes from the water depth, baked into a small R8 texture.
static func _sea(root: Node3D, hf: Glacier.HF) -> void:
	var img := Image.create(hf.nx, hf.nz, false, Image.FORMAT_R8)
	for iz in hf.nz:
		for ix in hf.nx:
			var h := hf.h[iz * hf.nx + ix]
			img.set_pixel(ix, iz, Color(clampf(-h / DEPTH_SCALE + 0.1, 0.0, 1.0), 0, 0))
	var tex := ImageTexture.create_from_image(img)
	# Texel centres sit on the nodes: the rect spans half a cell beyond them.
	var rect := Vector4(hf.x0 - GRID * 0.5, hf.z0 - GRID * 0.5, hf.nx * GRID, hf.nz * GRID)
	var mat := Mats.shader_mat("sea", {"depth_tex": tex, "ripples": Mats.tex("coastal_ripples"), "hf_rect": rect, "depth_scale": DEPTH_SCALE})
	var mk := MeshKit.new()
	mk.use("sea")
	var x0 := hf.x0
	var z0 := hf.z0
	var x1 := hf.x0 + (hf.nx - 1) * GRID
	var z1 := hf.z0 + (hf.nz - 1) * GRID
	var step := 128.0
	var z := z0
	while z < z1 - 0.1:
		var x := x0
		while x < x1 - 0.1:
			var xa := minf(x + step, x1)
			var za := minf(z + step, z1)
			# Skip squares that are dry land everywhere.
			var dry := true
			for q: Vector2 in [Vector2(x, z), Vector2(xa, z), Vector2(x, za), Vector2(xa, za), Vector2((x + xa) * 0.5, (z + za) * 0.5)]:
				if hf.at(q.x, q.y) < 6.0:
					dry = false
			if not dry:
				mk.quad(Vector3(x, 0, z), Vector3(xa, 0, z), Vector3(xa, 0, za), Vector3(x, 0, za), Color.WHITE)
			x += step
		z += step
	# Skirt out to the horizon (faces up: quad normal is (c - a) x (b - a)).
	var far := 9000.0
	var o0 := Vector3(x0 - far, 0, z0 - far)
	var o1 := Vector3(x1 + far, 0, z1 + far)
	mk.quad(Vector3(o0.x, 0, o0.z), Vector3(o1.x, 0, o0.z), Vector3(o1.x, 0, z0), Vector3(o0.x, 0, z0), Color.WHITE)
	mk.quad(Vector3(o0.x, 0, z1), Vector3(o1.x, 0, z1), Vector3(o1.x, 0, o1.z), Vector3(o0.x, 0, o1.z), Color.WHITE)
	mk.quad(Vector3(o0.x, 0, z0), Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(o0.x, 0, z1), Color.WHITE)
	mk.quad(Vector3(x1, 0, z0), Vector3(o1.x, 0, z0), Vector3(o1.x, 0, z1), Vector3(x1, 0, z1), Color.WHITE)
	var mi := mk.instance("Sea", {"sea": mat})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ materials

static func _std(col: Color, rough: float, vcol: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = vcol
	m.vertex_color_is_srgb = true     # colours in this file are picked as sRGB
	m.roughness = rough
	return m


static func _stone_mat() -> StandardMaterial3D:
	var m := _std(Color(0.86, 0.82, 0.74), 0.85)
	m.albedo_texture = Mats.tex("panel_albedo")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	return m


static func _facade_mat() -> ShaderMaterial:
	return Mats.shader_mat("facade_day", {"noise_tex": Mats.tex("coastal_noise")})


# ------------------------------------------------------------------ harbour

## Quay along the Harbour Front, the moles with their beacons, and the boats.
static func _harbour(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var mk := MeshKit.new()
	var hf1 := _sec(td, "Harbour Front").y
	var quay := 24.0
	# Quay apron and wall from the groyne to past the Quay Bend's start.
	var s := -24.0
	var prev := PackedVector3Array()
	while s <= hf1 + 40.0:
		var h := _hit(td, s)
		var top := h.c.y - TrackMesh.DECK - 0.25
		var b := Vector3(h.B.x, 0, h.B.z).normalized()
		var inner := h.c + b * 6.0
		var edge := h.c + b * quay
		var sec := PackedVector3Array([Vector3(inner.x, top, inner.z), Vector3(edge.x, top, edge.z), Vector3(edge.x, -4.0, edge.z)])
		if prev.size() > 0:
			mk.use("quay")
			var pair: Array[PackedVector3Array] = [prev, sec]
			mk.loft(pair, Color(0.9, 0.87, 0.8), false, false)
		prev = sec
		if int(s + 24.0) % 15 == 0:
			# Bollard and a coping stone.
			mk.use("metal_dark")
			mk.cyl(Vector3(edge.x, top, edge.z) - b * 0.9, Vector3(edge.x, top + 0.8, edge.z) - b * 0.9, 0.3, 0.25, 6, Color.WHITE)
		s += 3.0
	# Jetties on piles reaching into the basin, with boats moored along both
	# sides (far enough out to be seen over the barrier from the track).
	var hulls := [Color(0.1, 0.3, 0.7), Color(0.85, 0.2, 0.15), Color(0.95, 0.95, 0.92), Color(0.15, 0.55, 0.45), Color(0.95, 0.7, 0.15), Color(0.2, 0.45, 0.8)]
	s = 60.0
	while s < hf1 - 40.0:
		var h := _hit(td, s)
		var b := Vector3(h.B.x, 0, h.B.z).normalized()
		var t := Vector3(h.T.x, 0, h.T.z).normalized()
		var root_p := Vector3(h.c.x, 1.3, h.c.z) + b * quay
		var jl := 56.0
		mk.use("wood")
		mk.box_t(Transform3D(Basis(t, Vector3.UP, -b), root_p + b * jl * 0.5), Vector3(3.2, 0.35, jl), Color(0.62, 0.48, 0.34))
		var q := 6.0
		while q < jl:
			for side: float in [-1.0, 1.0]:
				mk.box(root_p + b * q + t * side * 1.4 + Vector3(0, -2.0, 0), Vector3(0.35, 4.4, 0.35), Color(0.4, 0.32, 0.24))
				var length := rng.randf_range(7.0, 10.5)
				if rng.randf() < 0.85:
					var bc := Vector3(root_p.x, 0.0, root_p.z) + b * (q + 2.0) + t * side * (length * 0.5 + 2.4)
					_boat(mk, bc, t * side, length, hulls[rng.randi() % hulls.size()], rng.randf() < 0.25)
			q += 8.5
		s += 100.0
	# Moles: the west one from the groyne, the long east breakwater.
	var h0 := _hit(td, td.length - 10.0)
	var b0 := Vector3(h0.B.x, 0, h0.B.z).normalized()
	var t0 := Vector3(h0.T.x, 0, h0.T.z).normalized()
	var west := [h0.c + b0 * 30.0, h0.c + b0 * 120.0 + t0 * 10.0, h0.c + b0 * 190.0 + t0 * 40.0]
	var h1 := _hit(td, hf1 + 30.0)
	var b1 := Vector3(h1.B.x, 0, h1.B.z).normalized()
	var t1 := Vector3(h1.T.x, 0, h1.T.z).normalized()
	var east := [h1.c + b1 * 26.0 + t1 * 30.0, h1.c + b1 * 150.0 + t1 * 30.0, h1.c + b1 * 210.0 - t1 * 40.0, h1.c + b1 * 215.0 - t1 * 130.0]
	_mole(mk, west, 3.5, Color(0.85, 0.2, 0.15))
	_mole(mk, east, 4.0, Color(0.15, 0.6, 0.3))
	# A few boats at anchor in the basin.
	for q in 7:
		var u := rng.randf_range(0.15, 0.85)
		var hb := _hit(td, lerpf(20.0, hf1, u))
		var bb := Vector3(hb.B.x, 0, hb.B.z).normalized()
		var p := hb.c + bb * rng.randf_range(70.0, 150.0)
		if hf.at(p.x, p.z) < -2.0:
			_boat(mk, Vector3(p.x, 0.0, p.z), bb.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)), rng.randf_range(8.0, 14.0), hulls[rng.randi() % hulls.size()], q % 3 == 0)
	var mi := mk.instance("Harbour", {"quay": _stone_mat(), "boat": _std(Color.WHITE, 0.5), "rubble": _rubble_mat(), "wood": _std(Color.WHITE, 0.9)})
	root.add_child(mi)


static func _rubble_mat() -> StandardMaterial3D:
	return _std(Color(0.86, 0.84, 0.78), 0.95)


## A rubble-mound mole along `pts` (y ignored) with a walkway and a beacon at its end.
static func _mole(mk: MeshKit, pts: Array, top: float, beacon: Color) -> void:
	var line := PackedVector3Array()
	for p: Vector3 in pts:
		line.append(Vector3(p.x, 0, p.z))
	var dense := PackedVector3Array()
	for k in line.size() - 1:
		var n := maxi(1, int(line[k].distance_to(line[k + 1]) / 6.0))
		for m in n:
			dense.append(line[k].lerp(line[k + 1], float(m) / n))
	dense.append(line[line.size() - 1])
	var lumps := FastNoiseLite.new()
	lumps.seed = 9
	lumps.frequency = 0.15
	var prev := PackedVector3Array()
	for k in dense.size():
		var dir := (dense[mini(k + 1, dense.size() - 1)] - dense[maxi(k - 1, 0)]).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var c := dense[k]
		var sec := PackedVector3Array()
		for q in 7:
			var a := PI * q / 6.0
			var rr := 1.0 + lumps.get_noise_2d(c.x + q * 7.0, c.z) * 0.25
			sec.append(c + side * cos(a) * 11.0 * rr + Vector3(0, -6.0 + sin(a) * (top + 6.0) * rr, 0))
		if prev.size() > 0:
			mk.use("rubble")
			var pair: Array[PackedVector3Array] = [prev, sec]
			mk.loft(pair, Color(0.95, 0.93, 0.88), false, true)
		prev = sec
		if k % 2 == 0:
			mk.use("quay")
			mk.box_t(Transform3D(Basis(side, Vector3.UP, -dir), c + Vector3(0, top + 0.4, 0)), Vector3(4.0, 0.6, 6.4), Color(0.92, 0.9, 0.85))
	var end := dense[dense.size() - 1]
	mk.use("quay")
	mk.cyl(end + Vector3(0, top, 0), end + Vector3(0, top + 9.0, 0), 1.4, 1.1, 10, Color(0.97, 0.97, 0.95))
	mk.use("boat")
	mk.cyl(end + Vector3(0, top + 9.0, 0), end + Vector3(0, top + 11.5, 0), 1.2, 1.2, 10, beacon)
	mk.cyl(end + Vector3(0, top + 11.5, 0), end + Vector3(0, top + 12.5, 0), 0.5, 0.1, 6, beacon)


## A small fishing boat: hull, gunwale stripe, wheelhouse. `fwd` points to the bow.
static func _boat(mk: MeshKit, c: Vector3, fwd: Vector3, length: float, hull: Color, sail: bool = false) -> void:
	var f := Vector3(fwd.x, 0, fwd.z).normalized()
	var side := Vector3(-f.z, 0, f.x)
	var w := length * 0.32
	var secs: Array[PackedVector3Array] = []
	for q in 5:
		var u := float(q) / 4.0                       # 0 stern .. 1 bow
		var along := lerpf(-0.5, 0.5, u) * length
		var half := w * 0.5 * (1.0 - pow(u, 2.2) * 0.96) * (0.85 + 0.15 * sin(u * PI))
		var sheer := 1.0 + 0.5 * u * u
		var o := c + f * along
		secs.append(PackedVector3Array([o + side * half + Vector3(0, sheer, 0), o + side * half * 0.85 + Vector3(0, -0.3, 0), o + Vector3(0, -0.9, 0), o - side * half * 0.85 + Vector3(0, -0.3, 0), o - side * half + Vector3(0, sheer, 0)]))
	mk.use("boat")
	mk.loft(secs, hull, false, false)
	# Deck and stripe.
	mk.box_t(Transform3D(Basis(side, Vector3.UP, -f), c + Vector3(0, 0.75, -0.0) - f * length * 0.05), Vector3(w * 0.8, 0.15, length * 0.8), Color(0.75, 0.62, 0.45))
	if sail:
		mk.cyl(c + Vector3(0, 0.8, 0), c + Vector3(0, length * 1.4, 0), 0.1, 0.07, 4, Color(0.9, 0.9, 0.9), false)
		mk.cyl(c + Vector3(0, 2.4, 0) + f * 0.3, c + Vector3(0, 2.4, 0) - f * length * 0.45, 0.22, 0.18, 5, Color(0.96, 0.96, 0.94), false)
	else:
		mk.box_t(Transform3D(Basis(side, Vector3.UP, -f), c + Vector3(0, 1.8, 0) - f * length * 0.15), Vector3(w * 0.55, 1.8, length * 0.22), Color(0.96, 0.96, 0.94))
		mk.box_t(Transform3D(Basis(side, Vector3.UP, -f), c + Vector3(0, 2.75, 0) - f * length * 0.15), Vector3(w * 0.62, 0.12, length * 0.26), hull)


# ------------------------------------------------------------------ tunnel

## Arch cross-section of the tunnel at sample j (`extra` widens it, `raise` lifts the crown).
static func _arc(td: TrackData, j: int, extra: float, raise: float, steps: int = 12) -> PackedVector3Array:
	var ceil_h := td.ceiling[j] + raise
	var hl := td.half_l[j] + TrackMesh.WALL_T + extra
	var hr := td.half_r[j] + TrackMesh.WALL_T + extra
	var out := PackedVector3Array()
	for k in steps + 1:
		var a := PI * k / float(steps)
		var d := lerpf(hr, -hl, 0.5 - cos(a) * 0.5)
		var h := -0.3 + sin(a) * (ceil_h + 0.3)
		out.append(td.pos[j] + td.rgt[j] * d + td.nrm[j] * h)
	return out


## Rock over the tunnel: a broad hump, buried in the cutting's slopes.
static func _hump(td: TrackData, j: int, lumps: FastNoiseLite, hf: Glacier.HF, steps: int = 12) -> PackedVector3Array:
	var out := PackedVector3Array()
	var hl := td.half_l[j] + 34.0
	var hr := td.half_r[j] + 34.0
	var up := Vector3.UP
	var right := Vector3(td.rgt[j].x, 0, td.rgt[j].z).normalized()
	for k in steps + 1:
		var u := float(k) / steps
		var d := lerpf(hr, -hl, u)
		var crown := td.ceiling[j] + 5.5
		var y := crown - 0.32 * maxf(0.0, absf(d) - 14.0) - 0.004 * d * d
		var p := td.pos[j] + right * d + up * y
		p += up * lumps.get_noise_2d(p.x, p.z) * 2.0
		# Away from the tube, never stand more than a little above the ground.
		if absf(d) > maxf(td.half_l[j], td.half_r[j]) + 8.0:
			p.y = minf(p.y, hf.at(p.x, p.z) + 1.0)
		out.append(p)
	return out


static func _tunnel(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var r := _sec(td, "Headland Tunnel")
	if r.x < 0.0:
		return
	var i0 := int(r.x / td.step)
	var i1 := int(r.y / td.step)
	var lumps := FastNoiseLite.new()
	lumps.seed = 31
	lumps.frequency = 0.03
	var mk := MeshKit.new()
	var prev_in := PackedVector3Array()
	var prev_out := PackedVector3Array()
	for i in range(i0, i1 + 1, 3):
		var j := td.wrap_i(i)
		var sec_in := _arc(td, j, 0.6, 0.0)
		var sec_out := _hump(td, j, lumps, hf)
		if prev_in.size() > 0:
			mk.use("tunnel")
			var pi: Array[PackedVector3Array] = [prev_in, sec_in]
			var shade := PackedColorArray()
			for k in sec_in.size():
				var c := lerpf(0.42, 0.95, sin(PI * k / float(sec_in.size() - 1)))
				shade.append(Color(c, c * 0.92, c * 0.8))
			var cols: Array[PackedColorArray] = [shade, shade]
			mk.loft_colored(pi, cols, false, true)
			mk.use("ground")
			var po: Array[PackedVector3Array] = [prev_out, sec_out]
			mk.loft(po, Color(0, 0, 0), false, true)
		prev_in = sec_in
		prev_out = sec_out
	# Portals: a masonry headwall around the opening (taller than the hump
	# behind it), with a voussoir ring and a cornice.
	for end: int in [i0, i1]:
		var j := td.wrap_i(end)
		var inner := _arc(td, j, 0.6, 0.0)
		var t := td.tan[j] * (-1.0 if end == i0 else 1.0)
		var hw := (td.half_l[j] + td.half_r[j]) * 0.5 + TrackMesh.WALL_T + 0.6
		var cw := hw + 9.0
		var ch := td.ceiling[j] + 9.0
		var mid := (td.half_r[j] - td.half_l[j]) * 0.5
		var outer := PackedVector3Array()
		for k in inner.size():
			var a := PI * k / float(inner.size() - 1)
			var dx := cos(a) * hw
			var dy := sin(a) * td.ceiling[j]
			var f := minf(cw / maxf(absf(dx), 1e-3), ch / maxf(dy, 1e-3))
			outer.append(td.pos[j] + td.rgt[j] * (mid + dx * f) + td.nrm[j] * (dy * f - 0.3))
		mk.use("portal")
		for k in inner.size() - 1:
			var a := inner[k]
			var b := inner[k + 1]
			var c := outer[k + 1]
			var d := outer[k]
			var nrm := (c - a).cross(b - a)
			if nrm.dot(t) > 0.0:
				mk.quad(a, b, c, d, Color(0.95, 0.94, 0.9))
			else:
				mk.quad(a, d, c, b, Color(0.95, 0.94, 0.9))
		mk.use("quay")
		var ring := _arc(td, j, 1.6, 1.0)
		for k in ring.size() - 1:
			mk.beam(ring[k] + t * 0.4, ring[k + 1] + t * 0.4, 1.6, 1.0, Color(0.82, 0.76, 0.64), t)
		var top := td.pos[j] + td.rgt[j] * mid + td.nrm[j] * (ch - 0.3) + t * 0.3
		mk.box_t(Transform3D(Basis(td.rgt[j], td.nrm[j], -td.tan[j]), top), Vector3(cw * 2.0 + 1.0, 1.0, 1.6), Color(0.82, 0.76, 0.64))
	# Lamps: a strip along the crown and warm lamps low on both walls.
	var s := r.x + 6.0
	var n := 0
	while s < r.y - 4.0:
		var hit := _hit(td, s)
		var b := Basis(hit.B, hit.N, -hit.T)
		mk.use("lamp")
		mk.box_t(Transform3D(b, hit.c + hit.N * (td.ceiling[hit.i] - 0.25)), Vector3(1.2, 0.15, 3.2), Color.WHITE)
		if n % 2 == 0:
			for side: float in [-1.0, 1.0]:
				var edge := ((hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T) * 0.93
				mk.box_t(Transform3D(b, hit.c + hit.B * side * edge + hit.N * 4.0), Vector3(0.3, 0.35, 1.6), Color.WHITE)
		s += 12.0
		n += 1
	var inner_m := _std(Color(1.45, 1.4, 1.3), 0.9)
	inner_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_m.albedo_texture = Mats.tex("panel_albedo")
	inner_m.uv1_triplanar = true
	inner_m.uv1_scale = Vector3(0.1, 0.1, 0.1)
	inner_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var portal := _stone_mat()
	portal.albedo_color = Color(0.98, 0.94, 0.86)
	portal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := mk.instance("HeadlandTunnel", {"tunnel": inner_m, "ground": _ground_mat(), "portal": portal, "quay": _stone_mat()})
	root.add_child(mi)


# ------------------------------------------------------------------ the sea arch

## A natural limestone arch carrying the track over the inlet.
static func _arch(td: TrackData, root: Node3D) -> void:
	var r := _sec(td, "Arch Bridge")
	if r.x < 0.0:
		return
	var mid := (r.x + r.y) * 0.5
	var span := 78.0
	var lumps := FastNoiseLite.new()
	lumps.seed = 44
	lumps.frequency = 0.06
	var mk := MeshKit.new()
	var prev := PackedVector3Array()
	var s := r.x - 30.0
	while s <= r.y + 30.0:
		var h := _hit(td, s)
		var right := Vector3(h.B.x, 0, h.B.z).normalized()
		var deck := h.c.y - TrackMesh.DECK
		var u := (s - mid) / span
		# Intrados: a rounded arch over the inlet, solid rock beyond it.
		var low := -8.0
		if absf(u) < 1.0:
			low = lerpf(deck - 9.0, -8.0, pow(absf(u), 2.6))
		var wl := h.half_l + 7.0
		var wr := h.half_r + 10.0
		var sec := PackedVector3Array()
		# Right edge, right shoulder, right foot, the soffit, then the same on the left.
		var prof := [Vector2(wr, deck + 0.2), Vector2(wr + 3.0, deck - 5.0), Vector2(wr + 2.0, lerpf(deck - 5.0, low, 0.6)), Vector2(wr * 0.4, low),
			Vector2(-wl * 0.4, low), Vector2(-wl - 2.0, lerpf(deck - 5.0, low, 0.6)), Vector2(-wl - 3.0, deck - 5.0), Vector2(-wl, deck + 0.2)]
		for q: Vector2 in prof:
			var p := Vector3(h.c.x, q.y, h.c.z) + right * q.x
			var dd := q.x
			p += (right * signf(dd) * 2.0 + Vector3.UP) * lumps.get_noise_3dv(p) * 2.5
			sec.append(p)
		if prev.size() > 0:
			mk.use("ground")
			var pair: Array[PackedVector3Array] = [prev, sec]
			mk.loft(pair, Color(0, 0, 0), false, false)
		prev = sec
		s += 6.0
	var mi := mk.instance("SeaArch", {"ground": _ground_mat()})
	root.add_child(mi)


# ------------------------------------------------------------------ lighthouse

static func _lighthouse_build(root: Node3D, hf: Glacier.HF) -> void:
	var c := _lighthouse
	c.y = hf.at(c.x, c.z) - 0.5
	var mk := MeshKit.new()
	# Keeper's house and yard wall.
	mk.use("facade")
	_walls(mk, c + Vector3(9.0, 0, 4.0), Vector3(12.0, 5.5, 8.0), 0.3, Color(0.96, 0.95, 0.92, 0.37))
	mk.use("tile")
	_hip_roof(mk, c + Vector3(9.0, 5.5, 4.0), Vector3(12.6, 2.4, 8.6), 0.3, Color(0.78, 0.36, 0.2))
	# Tower: white with red bands, gallery, lantern and dome.
	var base := c
	mk.use("plaster")
	mk.cyl(base, base + Vector3(0, 30.0, 0), 3.4, 2.6, 16, Color(0.97, 0.97, 0.95), false)
	mk.use("boat")
	for y: float in [9.0, 19.0]:
		mk.cyl(base + Vector3(0, y, 0), base + Vector3(0, y + 3.0, 0), lerpf(3.4, 2.6, y / 30.0) + 0.04, lerpf(3.4, 2.6, (y + 3.0) / 30.0) + 0.04, 16, Color(0.78, 0.12, 0.08), false)
	mk.use("metal_dark")
	mk.cyl(base + Vector3(0, 30.0, 0), base + Vector3(0, 30.6, 0), 3.6, 3.6, 16, Color.WHITE)
	mk.torus(base + Vector3(0, 31.6, 0), Vector3.UP, 3.5, 0.06, 16, 3, Color.WHITE)
	mk.use("glass")
	mk.cyl(base + Vector3(0, 30.6, 0), base + Vector3(0, 33.8, 0), 1.9, 1.9, 12, Color.WHITE, false)
	mk.use("lamp")
	mk.cyl(base + Vector3(0, 31.2, 0), base + Vector3(0, 32.8, 0), 0.9, 0.9, 8, Color.WHITE)
	mk.use("boat")
	mk.cyl(base + Vector3(0, 33.8, 0), base + Vector3(0, 35.6, 0), 2.1, 0.3, 12, Color(0.78, 0.12, 0.08))
	mk.use("metal_dark")
	mk.cyl(base + Vector3(0, 35.6, 0), base + Vector3(0, 37.0, 0), 0.12, 0.05, 4, Color.WHITE)
	var mi := mk.instance("Lighthouse", {"facade": _facade_mat(), "tile": _std(Color.WHITE, 0.8), "plaster": _std(Color.WHITE, 0.8), "boat": _std(Color.WHITE, 0.5)})
	root.add_child(mi)


# ------------------------------------------------------------------ buildings

## Four walls of a box house with facade UVs (u along the wall, v above the
## base). `col.a` is the facade seed (see facade_day.gdshader). Flat roof on top.
static func _walls(mk: MeshKit, base: Vector3, size: Vector3, rot: float, col: Color, roof: bool = true) -> void:
	var b := Basis(Vector3.UP, rot)
	var hx := b.x * size.x * 0.5
	var hz := b.z * size.z * 0.5
	var up := Vector3(0, size.y, 0)
	var corners := [base - hx - hz, base + hx - hz, base + hx + hz, base - hx + hz]
	var lens := [size.x, size.z, size.x, size.z]
	for k in 4:
		var a: Vector3 = corners[(k + 1) % 4]
		var c: Vector3 = corners[k]
		var n := (c - a).cross(Vector3.UP).normalized()
		var l: float = lens[k]
		var i0 := mk._vert(a + up, n, col, Vector2(0.0, size.y))
		var i1 := mk._vert(c + up, n, col, Vector2(l, size.y))
		var i2 := mk._vert(c, n, col, Vector2(l, 0.0))
		var i3 := mk._vert(a, n, col, Vector2(0.0, 0.0))
		mk._quad_i(i0, i1, i2, i3)
	if roof:
		var rc := Color(col.r * 0.9, col.g * 0.9, col.b * 0.88, 0.0)
		var i0 := mk._vert(corners[0] + up, Vector3.UP, rc)
		var i1 := mk._vert(corners[1] + up, Vector3.UP, rc)
		var i2 := mk._vert(corners[2] + up, Vector3.UP, rc)
		var i3 := mk._vert(corners[3] + up, Vector3.UP, rc)
		mk._quad_i(i0, i1, i2, i3)


## Four-sided hip roof (a low pyramid with a short ridge) on a box footprint.
static func _hip_roof(mk: MeshKit, base: Vector3, size: Vector3, rot: float, col: Color) -> void:
	var b := Basis(Vector3.UP, rot)
	var hx := b.x * size.x * 0.5
	var hz := b.z * size.z * 0.5
	var ridge := b.x * maxf(0.0, size.x - size.z) * 0.5
	var top := base + Vector3(0, size.y, 0)
	var c := [base - hx - hz, base + hx - hz, base + hx + hz, base - hx + hz]
	var ra: Vector3 = top - ridge
	var rb: Vector3 = top + ridge
	mk.quad(c[1], rb, ra, c[0], col)
	mk.quad(c[3], ra, rb, c[2], col)
	mk.tri(c[2], rb, c[1], col * 0.92)
	mk.tri(c[0], ra, c[3], col * 0.92)


const WALL_TINTS := [Color(0.97, 0.96, 0.93), Color(0.97, 0.96, 0.93), Color(0.97, 0.96, 0.93), Color(0.95, 0.95, 0.94),
	Color(0.97, 0.9, 0.74), Color(0.95, 0.78, 0.5), Color(0.86, 0.9, 0.95), Color(0.96, 0.86, 0.82)]


## One house: walls, a flat or tiled roof, sometimes an upper storey, a chimney
## or a bougainvillea. Returns false if the lot is taken.
static func _house(mk: MeshKit, hf: Glacier.HF, c: Vector2, size: Vector3, rot: float, seed_in: float = -1.0) -> bool:
	var b := Basis(Vector3.UP, rot)
	if not _lot_free(c, size, rot):
		return false
	_take(c, size, rot)
	var lo := INF
	var top := -INF
	for q: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2.ZERO]:
		var p := Vector3(c.x, 0, c.y) + b.x * size.x * q.x + b.z * size.z * q.y
		var g := hf.at(p.x, p.z)
		lo = minf(lo, g)
		top = maxf(top, g)
	var base := Vector3(c.x, lo - 1.5, c.y)
	var hgt := (top - lo) + 1.5 + size.y
	var tint: Color = WALL_TINTS[rng.randi() % WALL_TINTS.size()]
	var seed := seed_in if seed_in > 0.0 else rng.randf_range(0.05, 1.0)
	mk.use("facade")
	var kind := rng.randf()
	var flat := kind < 0.68
	_walls(mk, base, Vector3(size.x, hgt, size.z), rot, Color(tint.r, tint.g, tint.b, seed), flat)
	var roof_y := base.y + hgt
	if flat:
		# Parapet lip and, sometimes, an upper storey set back on the roof.
		if rng.randf() < 0.45 and size.x > 6.0 and size.z > 6.0:
			var up := Vector3(size.x * rng.randf_range(0.45, 0.65), 3.0, size.z * rng.randf_range(0.45, 0.65))
			var off := b.x * (size.x - up.x) * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
			_walls(mk, Vector3(base.x, roof_y, base.z) + off, up, rot, Color(tint.r, tint.g, tint.b, fposmod(seed * 3.7, 0.98) + 0.01))
		if rng.randf() < 0.3:
			var cp := Vector3(c.x, roof_y, c.y) + b.x * size.x * 0.32 + b.z * size.z * 0.3
			_walls(mk, cp, Vector3(0.9, 1.6, 0.9), rot, Color(tint.r, tint.g, tint.b, 0.0))
	else:
		mk.use("tile")
		var tc := Color(0.74, 0.34, 0.18) * rng.randf_range(0.85, 1.1)
		_hip_roof(mk, Vector3(c.x, roof_y, c.y), Vector3(size.x + 0.6, minf(size.x, size.z) * 0.28, size.z + 0.6), rot, tc)
	if rng.randf() < 0.14:
		mk.use("flora")
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var along := rng.randf_range(-0.3, 0.3)
		var fp := Vector3(c.x, base.y + 1.5 + (top - lo), c.y) + b.z * size.z * 0.5 * side + b.x * size.x * along
		for q in 2:
			var o := b.x * rng.randf_range(-1.4, 1.4) + Vector3(0, rng.randf_range(0.8, 3.0), 0)
			mk.sphere(fp + o, Vector3(1.3, 1.0, 0.6).rotated(Vector3.UP, rot), 2, 4, Color(1.0, 0.18, 0.55), Color(0.35, 0.5, 0.2))
	return true


static func _cell_key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))


static func _lot_free(c: Vector2, size: Vector3, rot: float) -> bool:
	var b := Basis(Vector3.UP, rot)
	var u := 0.0
	while u <= 1.0:
		var v := 0.0
		while v <= 1.0:
			var p := Vector3(c.x, 0, c.y) + b.x * size.x * (u - 0.5) * 0.9 + b.z * size.z * (v - 0.5) * 0.9
			if _occ.has(_cell_key(Vector2(p.x, p.z))):
				return false
			v += 0.25
		u += 0.25
	return true


static func _take(c: Vector2, size: Vector3, rot: float) -> void:
	var b := Basis(Vector3.UP, rot)
	var u := 0.0
	while u <= 1.0:
		var v := 0.0
		while v <= 1.0:
			var p := Vector3(c.x, 0, c.y) + b.x * size.x * (u - 0.5) + b.z * size.z * (v - 0.5)
			_occ[_cell_key(Vector2(p.x, p.z))] = true
			v += 0.2
		u += 0.2


## Marks the track corridor (plus `margin`) through the town as taken.
static func _block_corridor(td: TrackData, margin: float) -> void:
	var i := 0
	while i < td.count:
		var si := i * td.step
		if si > _town_s.y + 60.0 and si < td.length + _town_s.x - 60.0:
			i += 4
			continue
		var p := td.pos[i]
		var r := maxf(td.half_l[i], td.half_r[i]) + margin
		var n := int(ceil(r / 4.0))
		var cx := floori(p.x / 4.0)
		var cz := floori(p.z / 4.0)
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				if (dx * dx + dz * dz) * 16.0 <= r * r:
					_occ[Vector2i(cx + dx, cz + dz)] = true
		i += 4


## The domed church on its square inside the Church Square bend.
static func _church_build(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var c := _church
	var cs := _sec(td, "Church Square")
	var h := _hit(td, (cs.x + cs.y) * 0.5)
	var to_track := (_xz(h.c) - _xz(c)).normalized()
	var rot := atan2(to_track.x, to_track.y)     # facade faces the track
	var b := Basis(Vector3.UP, rot)
	var g := hf.at(c.x, c.z)
	var base := Vector3(c.x, g - 1.0, c.z)
	var mk := MeshKit.new()
	mk.use("plaster")
	# Nave (long axis away from the track), transept, apse.
	var nave := Vector3(15.0, 15.0, 34.0)
	mk.box_t(Transform3D(b, base + Vector3(0, nave.y * 0.5, 0) - b.z * 4.0), nave, Color(0.98, 0.97, 0.94))
	mk.box_t(Transform3D(b, base + Vector3(0, 6.5, 0) - b.z * 6.0), Vector3(30.0, 13.0, 12.0), Color(0.98, 0.97, 0.94))
	mk.push(Transform3D(b, base - b.z * 21.0))
	mk.cyl(Vector3.ZERO, Vector3(0, 11.0, 0), 6.5, 6.5, 12, Color(0.96, 0.95, 0.92))
	mk.pop()
	# Gabled front with a pediment, steps and a door.
	var front := base + b.z * 13.0
	mk.tri(front + Vector3(0, 15.0, 0) - b.x * 7.5, front + Vector3(0, 21.0, 0), front + Vector3(0, 15.0, 0) + b.x * 7.5, Color(0.98, 0.97, 0.94), true)
	mk.use("tile")
	var ridge0 := base + Vector3(0, 21.0, 0) + b.z * 13.0
	var ridge1 := base + Vector3(0, 21.0, 0) - b.z * 21.0
	for side: float in [-1.0, 1.0]:
		var e0 := base + Vector3(0, 15.0, 0) + b.z * 13.2 + b.x * side * 8.0
		var e1 := base + Vector3(0, 15.0, 0) - b.z * 21.0 + b.x * side * 8.0
		if side > 0.0:
			mk.quad(ridge0, ridge1, e1, e0, Color(0.76, 0.36, 0.2), Vector2.ONE, Vector2.ZERO, true)
		else:
			mk.quad(ridge1, ridge0, e0, e1, Color(0.76, 0.36, 0.2), Vector2.ONE, Vector2.ZERO, true)
	mk.use("trim")
	mk.box_t(Transform3D(b, front + Vector3(0, 3.0, 0.0) + b.z * 0.1), Vector3(3.2, 6.0, 0.3), Color(0.12, 0.25, 0.5))
	mk.box_t(Transform3D(b, front + Vector3(0, 11.0, 0.0) + b.z * 0.1), Vector3(2.4, 2.4, 0.3), Color(0.12, 0.25, 0.5))
	mk.use("plaster")
	mk.box_t(Transform3D(b, front + Vector3(0, 0.4, 0) + b.z * 3.0), Vector3(12.0, 1.6, 6.0), Color(0.9, 0.88, 0.84))
	# Drum and blue dome over the crossing.
	var cross := base - b.z * 6.0
	mk.cyl(cross + Vector3(0, 13.0, 0), cross + Vector3(0, 20.0, 0), 6.8, 6.8, 16, Color(0.98, 0.97, 0.94))
	mk.use("dome")
	var prof := PackedVector2Array()
	for q in 9:
		var a := PI * 0.5 * q / 8.0
		prof.append(Vector2(cos(a) * 7.4, sin(a) * 7.4))
	mk.push(Transform3D(Basis.IDENTITY, cross + Vector3(0, 20.0, 0)))
	mk.lathe(prof, 16, Color(0.12, 0.32, 0.72))
	mk.pop()
	mk.use("plaster")
	mk.cyl(cross + Vector3(0, 27.2, 0), cross + Vector3(0, 30.0, 0), 1.3, 1.0, 8, Color(0.98, 0.97, 0.94))
	mk.use("metal_dark")
	mk.beam(cross + Vector3(0, 30.0, 0), cross + Vector3(0, 33.5, 0), 0.25, 0.25, Color.WHITE)
	mk.beam(cross + Vector3(0, 32.4, 0) - b.x * 0.9, cross + Vector3(0, 32.4, 0) + b.x * 0.9, 0.22, 0.22, Color.WHITE)
	# Bell tower beside the front.
	var tw := base + b.z * 9.0 + b.x * 11.5
	mk.use("plaster")
	mk.box_t(Transform3D(b, tw + Vector3(0, 13.0, 0)), Vector3(5.0, 26.0, 5.0), Color(0.98, 0.97, 0.94))
	mk.use("trim")
	for q in 4:
		var dir: Vector3 = [b.x, -b.x, b.z, -b.z][q]
		mk.box(tw + Vector3(0, 23.0, 0) + dir * 2.52, Vector3(1.6, 2.8, 1.6) if q < 2 else Vector3(1.6, 2.8, 1.6), Color(0.05, 0.05, 0.06))
	mk.use("dome")
	mk.push(Transform3D(Basis.IDENTITY, tw + Vector3(0, 26.0, 0)))
	var p2 := PackedVector2Array()
	for q in 7:
		var a := PI * 0.5 * q / 6.0
		p2.append(Vector2(cos(a) * 2.9, sin(a) * 3.4))
	mk.lathe(p2, 12, Color(0.12, 0.32, 0.72))
	mk.pop()
	# Cypresses either side of the square.
	var mi := mk.instance("Church", {"plaster": _std(Color.WHITE, 0.85), "tile": _std(Color.WHITE, 0.8), "trim": _std(Color.WHITE, 0.5), "dome": _dome_mat()})
	root.add_child(mi)
	_take(Vector2(c.x, c.z), Vector3(40.0, 0, 52.0), rot)


static func _dome_mat() -> StandardMaterial3D:
	var m := _std(Color.WHITE, 0.35)
	m.metallic = 0.1
	return m


## The town: a frontage of houses lining the track through the town, then
## houses stacked up the hill on jittered lots, merged per 400 m cell.
static func _town(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	_block_corridor(td, 2.5)
	var density := float(Quality.p["city"])
	var cells: Dictionary = {}
	var quay_end := _sec(td, "Quay Bend").y
	var count := 0
	# Frontage: both sides of the town climb, and the landward side of the harbour front.
	var s := 12.0
	while s < _town_s.y - 30.0:
		var h := _hit(td, s)
		var t := Vector2(h.T.x, h.T.z).normalized()
		var right := Vector2(h.B.x, h.B.z).normalized()
		var rot := atan2(-t.y, t.x)
		var wid := rng.randf_range(7.0, 11.0)
		for side: float in [-1.0, 1.0]:
			if side > 0.0 and s < quay_end - 120.0:
				continue      # the quay is on the right of the harbour front
			var dep := rng.randf_range(8.0, 12.0)
			var off := (h.half_r if side > 0.0 else h.half_l) + 4.0 + dep * 0.5
			var c := _xz(h.c) + right * side * off
			if _coast_at(hf, c.x, c.y) < 10.0:
				continue
			var key := Vector2i(floori(c.x / CELL), floori(c.y / CELL))
			if not cells.has(key):
				cells[key] = MeshKit.new()
			if _house(cells[key], hf, c, Vector3(wid, rng.randf_range(5.5, 10.5), dep), rot):
				count += 1
		s += wid + rng.randf_range(0.3, 1.5)
	# Hillside lots.
	var spacing := 12.5 / sqrt(maxf(density, 0.3))
	var z := hf.z0
	while z < hf.z0 + (hf.nz - 1) * GRID:
		var x := hf.x0
		while x < hf.x0 + (hf.nx - 1) * GRID:
			var c := Vector2(x + rng.randf_range(-0.3, 0.3) * spacing, z + rng.randf_range(-0.3, 0.3) * spacing)
			x += spacing
			var k := _node(hf, c.x, c.y)
			var j := _fi[k]
			if j < 0:
				continue
			var sj := j * td.step
			if not (sj < _town_s.y or sj > td.length + _town_s.x):
				continue
			var d := Vector2(c.x - td.pos[j].x, c.y - td.pos[j].z).length()
			var reach := 150.0 + 70.0 * sin(c.x * 0.011 + c.y * 0.007)
			if d > reach or rng.randf() > 1.0 - smoothstep(reach * 0.6, reach, d) * 0.8:
				continue
			if _cd[k] < 16.0 or _slope(hf, c.x, c.y) > 0.75:
				continue
			var blocked := false
			for kc in _keep_clear:
				if c.distance_squared_to(Vector2(kc.x, kc.y)) < kc.z * kc.z:
					blocked = true
					break
			if blocked:
				continue
			# Align with the contour so houses step up the slope.
			var e := 6.0
			var grad := Vector2(hf.at(c.x + e, c.y) - hf.at(c.x - e, c.y), hf.at(c.x, c.y + e) - hf.at(c.x, c.y - e))
			var rot := atan2(grad.x, grad.y) if grad.length() > 0.2 else rng.randf() * PI
			var size := Vector3(rng.randf_range(6.0, 11.0), rng.randf_range(3.5, 8.5), rng.randf_range(6.0, 10.0))
			var key := Vector2i(floori(c.x / CELL), floori(c.y / CELL))
			if not cells.has(key):
				cells[key] = MeshKit.new()
			if _house(cells[key], hf, c, size, rot):
				count += 1
		z += spacing
	var mats := {"facade": _facade_mat(), "tile": _std(Color.WHITE, 0.8), "flora": _std(Color.WHITE, 0.9)}
	var view := float(Quality.p["view"])
	for key: Vector2i in cells:
		var mk: MeshKit = cells[key]
		if mk.is_empty():
			continue
		var mi := mk.instance("Town_%d_%d" % [key.x, key.y], mats)
		mi.visibility_range_end = 1900.0 * view
		mi.visibility_range_end_margin = 100.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(mi)
	if DevArgs.has("--load-times"):
		print("coastal town %d houses in %d cells" % [count, cells.size()])


# ------------------------------------------------------------------ beach

## Parasols, sun loungers, beached boats and a kiosk on the beach.
static func _beach(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var bs := _sec(td, "Beach Straight")
	var mk := MeshKit.new()
	var stripes := [Color(0.1, 0.35, 0.75), Color(0.85, 0.15, 0.12), Color(0.95, 0.7, 0.1), Color(0.1, 0.55, 0.5)]
	var s := bs.x - 120.0
	var row := 0
	while s < td.length - 70.0:
		var h := _hit(td, s)
		var right := Vector3(h.B.x, 0, h.B.z).normalized()
		var d := h.half_r + 16.0
		while true:
			var p := h.c + right * (d + rng.randf_range(-1.5, 1.5))
			var cd := _coast_at(hf, p.x, p.z)
			var g := hf.at(p.x, p.z)
			if cd < 14.0 or g < 0.6:
				break
			if g > 3.6 or rng.randf() < 0.3:
				d += 12.0
				continue
			p.y = g
			var col: Color = stripes[(row + int(d / 9.0)) % stripes.size()]
			mk.use("plaster")
			mk.cyl(p, p + Vector3(0, 2.6, 0), 0.05, 0.05, 4, Color(0.9, 0.9, 0.9), false)
			mk.use("cloth")
			for q in 8:
				var a0 := TAU * q / 8.0
				var a1 := TAU * (q + 1) / 8.0
				var tip := p + Vector3(0, 2.9, 0)
				var c0 := p + Vector3(cos(a0) * 1.7, 2.25, sin(a0) * 1.7)
				var c1 := p + Vector3(cos(a1) * 1.7, 2.25, sin(a1) * 1.7)
				mk.tri(tip, c1, c0, col if q % 2 == 0 else Color(0.97, 0.97, 0.95), true)
			mk.use("plaster")
			for lq: float in [-1.0, 1.0]:
				var lp := p + right * 1.2 + Vector3(h.T.x, 0, h.T.z).normalized() * lq * 0.9
				mk.box_t(Transform3D(Basis(right, Vector3.UP, -Vector3(h.T.x, 0, h.T.z).normalized()), lp + Vector3(0, 0.3, 0)), Vector3(1.9, 0.12, 0.65), Color(0.97, 0.97, 0.97))
			d += 12.0
		s += 15.0
		row += 1
	# Boats pulled up on the sand near the harbour end.
	for q in 5:
		var h := _hit(td, td.length - 150.0 + q * 18.0)
		var right := Vector3(h.B.x, 0, h.B.z).normalized()
		var p := h.c + right * (h.half_r + 50.0 + rng.randf_range(0.0, 10.0))
		p.y = hf.at(p.x, p.z) + 0.6
		var hulls := [Color(0.1, 0.3, 0.7), Color(0.85, 0.2, 0.15), Color(0.15, 0.55, 0.45)]
		_boat(mk, p, right.rotated(Vector3.UP, rng.randf_range(-0.3, 0.3)), 6.5, hulls[q % 3])
	# Kiosk with a striped awning behind the beach.
	var hk := _hit(td, bs.x + 120.0)
	var kr := Vector3(hk.B.x, 0, hk.B.z).normalized()
	var kp := hk.c + kr * (hk.half_r + 10.0)
	kp.y = hf.at(kp.x, kp.z)
	mk.use("facade")
	_walls(mk, kp, Vector3(6.0, 3.2, 4.0), atan2(hk.T.x, hk.T.z), Color(0.97, 0.96, 0.93, 0.61))
	mk.use("cloth")
	mk.box_t(Transform3D(Basis(kr, Vector3.UP, -Vector3(hk.T.x, 0, hk.T.z).normalized()), kp + Vector3(0, 3.0, 0) + kr * 3.0), Vector3(2.4, 0.1, 6.6), Color(0.1, 0.35, 0.75))
	var cloth := _std(Color.WHITE, 0.9)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := mk.instance("Beach", {"plaster": _std(Color.WHITE, 0.8), "cloth": cloth, "boat": _std(Color.WHITE, 0.5), "facade": _facade_mat()})
	root.add_child(mi)


# ------------------------------------------------------------------ vegetation

## Olive tree, cypress, umbrella pine and a scrub bush.
static func _tree_meshes() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var bark := _std(Color(0.36, 0.3, 0.25), 0.95)
	var leaf := _std(Color.WHITE, 0.85)
	var mats := {"bark": bark, "leaf": leaf}
	# Olive: short trunk, wide grey-green crown (about 44 triangles).
	var a := MeshKit.new()
	a.use("bark")
	a.cyl(Vector3.ZERO, Vector3(0.4, 2.4, 0.2), 0.45, 0.3, 4, Color.WHITE, false)
	a.use("leaf")
	a.sphere(Vector3(0.3, 3.5, 0.2), Vector3(3.0, 1.8, 2.6), 3, 5, Color(0.44, 0.49, 0.35), Color(0.24, 0.28, 0.18))
	out.append(a.commit(mats))
	# Cypress: a tall dark spindle (36 triangles).
	var b := MeshKit.new()
	b.use("leaf")
	var prof := PackedVector2Array([Vector2(0.5, 0.0), Vector2(1.3, 3.0), Vector2(0.9, 8.5), Vector2(0.02, 13.0)])
	b.lathe(prof, 6, Color(0.07, 0.13, 0.06))
	out.append(b.commit(mats))
	# Umbrella pine: tall bare trunk, flat spreading crown (36 triangles).
	var c := MeshKit.new()
	c.use("bark")
	c.cyl(Vector3.ZERO, Vector3(0.9, 7.5, 0.0), 0.5, 0.32, 4, Color.WHITE, false)
	c.use("leaf")
	c.sphere(Vector3(0.6, 8.9, 0.2), Vector3(5.6, 2.4, 4.8), 2, 7, Color(0.17, 0.27, 0.1), Color(0.07, 0.11, 0.04))
	out.append(c.commit(mats))
	# Scrub: a low rounded bush (20 triangles).
	var d := MeshKit.new()
	d.use("leaf")
	d.sphere(Vector3(0, 0.5, 0), Vector3(1.6, 1.0, 1.6), 2, 5, Color(0.17, 0.22, 0.11), Color(0.1, 0.13, 0.07))
	out.append(d.commit(mats))
	return out


static func _trees(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var meshes := _tree_meshes()
	var density := float(Quality.p["city"])
	var cells: Dictionary = {}     # Vector2i -> [[xf x4], [col x4]]
	var add := func(p: Vector3, kind: int, sc: float, tint: Color) -> void:
		var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not cells.has(key):
			cells[key] = [[[], [], [], []], [[], [], [], []]]
		var cell: Array = cells[key]
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
		(cell[0][kind] as Array).append(Transform3D(basis, p))
		(cell[1][kind] as Array).append(tint)
	var olive_s := _sec(td, "Olive Grove")
	var olive_end := _sec(td, "Headland Tunnel").x
	var head0 := _sec(td, "Cliff Road").x
	var head1 := _sec(td, "Cove Descent").y
	# Cypress avenue along the Olive Grove road.
	var s := olive_s.x + 20.0
	while s < olive_end - 30.0:
		var h := _hit(td, s)
		for side: float in [-1.0, 1.0]:
			var p := h.c + h.B * side * ((h.half_r if side > 0.0 else h.half_l) + 8.0)
			p.y = hf.at(p.x, p.z) - 0.3
			add.call(p, 1, rng.randf_range(0.85, 1.15), Color(1, 1, 1))
		s += 26.0
	# Cypresses beside the church.
	for q in 10:
		var a := TAU * q / 10.0
		var p := _church + Vector3(cos(a), 0, sin(a)) * rng.randf_range(32.0, 40.0)
		p.y = hf.at(p.x, p.z) - 0.3
		add.call(p, 1, rng.randf_range(0.9, 1.2), Color(1, 1, 1))
	var spacing := 14.0 / sqrt(maxf(density, 0.3))
	var z := hf.z0
	while z < hf.z0 + (hf.nz - 1) * GRID:
		var x := hf.x0
		while x < hf.x0 + (hf.nx - 1) * GRID:
			var px := x
			var pz := z
			x += spacing
			var k := _node(hf, px, pz)
			var j := _fi[k]
			if j < 0:
				continue
			var d := _fd[k]
			if d > 600.0 or d < maxf(td.half_l[j], td.half_r[j]) + 10.0:
				continue
			var cd := _cd[k]
			var y := hf.at(px, pz)
			if cd < 12.0 or y < 1.5:
				continue
			var p2 := Vector2(px, pz)
			var occupied := _occ.has(_cell_key(p2))
			if occupied:
				continue
			var blocked := false
			for kc in _keep_clear:
				if p2.distance_squared_to(Vector2(kc.x, kc.y)) < kc.z * kc.z:
					blocked = true
					break
			if blocked:
				continue
			var slope := _slope(hf, px, pz)
			var sj := j * td.step
			var in_town := sj < _town_s.y or sj > td.length + _town_s.x
			# Keep clear of the deck above (fills, the arch).
			if td.pos[j].y - TrackMesh.DECK - y < 4.0 and d < maxf(td.half_l[j], td.half_r[j]) + 16.0:
				continue
			var far := smoothstep(250.0, 600.0, d)
			# Olive groves: regular rows where the soil noise says so.
			var olive_zone := cd > 50.0 and y > 30.0 and slope < 0.45 and not in_town and _grove.get_noise_2d(px, pz) > 0.12
			if olive_zone and rng.randf() > far * 0.9:
				var jitter := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
				add.call(Vector3(px, y - 0.2, pz) + jitter, 0, rng.randf_range(0.8, 1.2), Color(rng.randf_range(0.9, 1.1), 1.0, rng.randf_range(0.9, 1.1)))
				continue
			if in_town:
				if rng.randf() < 0.04 and d > 30.0:
					add.call(Vector3(px, y - 0.3, pz), 1, rng.randf_range(0.8, 1.1), Color(1, 1, 1))
				continue
			if rng.randf() < far * 0.8:
				continue
			# Headland: umbrella pines in clumps, scrub on the rocky slopes.
			var on_head := sj > head0 - 200.0 and sj < head1
			var clump := _grove.get_noise_2d(px * 2.3, pz * 2.3 + 900.0)
			if slope < 0.6 and clump > (0.12 if on_head else 0.35) and rng.randf() < 0.45 and d > maxf(td.half_l[j], td.half_r[j]) + 18.0:
				add.call(Vector3(px, y - 0.3, pz), 2, rng.randf_range(0.75, 1.15), Color(rng.randf_range(0.85, 1.1), 1.0, 1.0))
			elif slope < 1.2 and rng.randf() < 0.2:
				add.call(Vector3(px + rng.randf_range(-3, 3), y - 0.2, pz + rng.randf_range(-3, 3)), 3, rng.randf_range(0.6, 1.4), Color(rng.randf_range(0.8, 1.2), 1.0, rng.randf_range(0.8, 1.1)))
		z += spacing
	var total := 0
	var per_kind := [0, 0, 0, 0]
	var view := float(Quality.p["view"])
	for key: Vector2i in cells:
		var cell: Array = cells[key]
		for kind in 4:
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
			mmi.visibility_range_end = (300.0 if kind == 3 else 700.0) * view
			mmi.visibility_range_end_margin = 50.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
			total += xf.size()
			per_kind[kind] += xf.size()
	if DevArgs.has("--load-times"):
		print("coastal trees %d in %d cells (olive/cypress/pine/scrub %s)" % [total, cells.size(), str(per_kind)])


# ------------------------------------------------------------------ trackside

static func _trackside(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	var ab := _sec(td, "Arch Bridge")
	var quay_end := _sec(td, "Quay Bend").y
	for i in td.count:
		var s := i * td.step
		var key := int(s / CELL)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 40, TrackData.F_TUNNEL) or td.flag_at_index(i - 110, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 8, TrackData.F_GAP) or td.flag_at_index(i - 8, TrackData.F_GAP)
		var on_arch := s > ab.x - 40.0 and s < ab.y + 40.0
		var in_town := s > quay_end - 60.0 and s < _town_s.y
		var p := td.pos[i]
		if i % 40 == 0 and not tunnel and not gap and not on_arch:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := hf.at(p.x, p.z)
			if under.y - foot > 1.5:
				mk.use("quay")
				var hgt := under.y - foot + 1.0
				mk.box(Vector3(under.x, foot - 1.0 + hgt * 0.5, under.z), Vector3(3.0, hgt, 3.0), Color(0.92, 0.9, 0.85), 0.7, 0.25)
		# Street lamps through the town.
		if in_town and i % 28 == 0:
			for side: float in [-1.0, 1.0]:
				var e := (td.half_r[i] + TrackMesh.WALL_T + 1.2) if side > 0.0 else -(td.half_l[i] + TrackMesh.WALL_T + 1.2)
				var lp := p + td.rgt[i] * e
				mk.use("metal_dark")
				mk.cyl(lp, lp + Vector3(0, 5.5, 0), 0.09, 0.07, 4, Color.WHITE, false)
				mk.beam(lp + Vector3(0, 5.5, 0), lp + Vector3(0, 5.5, 0) - td.rgt[i] * side * 1.2, 0.08, 0.08, Color.WHITE)
				mk.use("lamp")
				mk.box(lp + Vector3(0, 5.3, 0) - td.rgt[i] * side * 1.2, Vector3(0.35, 0.4, 0.35), Color.WHITE)
		if s - last_gate > 240.0 and s > 160.0 and not tunnel and not gap and not on_arch and not in_town:
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 240.0) * 2)
	var stone := _stone_mat()
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Trackside%02d" % key, {"quay": stone}))


# ------------------------------------------------------------------ far scenery

## Offshore islets and a ring of hazy mountains inland, beyond the height field.
static func _far(root: Node3D, hf: Glacier.HF) -> void:
	var mk := MeshKit.new()
	var c := Vector3(hf.x0 + hf.nx * GRID * 0.5, 0, hf.z0 + hf.nz * GRID * 0.5)
	var lumps := FastNoiseLite.new()
	lumps.seed = 5
	lumps.frequency = 0.01
	# Islets to the south and south-west.
	for k in 4:
		var a := lerpf(0.55, 2.2, k / 3.0) + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(3600.0, 5200.0)
		var p := c + Vector3(cos(a) * r, -6.0, sin(a) * r)
		var size := rng.randf_range(160.0, 420.0)
		mk.use("ground")
		mk.blob(p, Vector3(size, size * rng.randf_range(0.25, 0.4), size * rng.randf_range(0.5, 0.8)), 2, lumps, 0.35, Color.WHITE, Color.WHITE, false, Vector3(k * 50.0, 0, 0))
	# Mountains inland (north), two layers.
	mk.use("far_rock")
	for layer in 2:
		var rr := 5600.0 + layer * 1500.0
		var n := 40
		for k in n:
			var a0 := lerpf(-2.1, -0.5, float(k) / n)
			var a1 := lerpf(-2.1, -0.5, float(k + 1) / n)
			var h0 := 380.0 + 320.0 * absf(sin(k * 1.3 + layer * 2.0)) + 160.0 * sin(k * 0.5)
			var h1 := 380.0 + 320.0 * absf(sin((k + 1) * 1.3 + layer * 2.0)) + 160.0 * sin((k + 1) * 0.5)
			var p0 := c + Vector3(cos(a0) * rr, -30.0, sin(a0) * rr)
			var p1 := c + Vector3(cos(a1) * rr, -30.0, sin(a1) * rr)
			var t0 := p0 + Vector3(0, h0, 0) - (p0 - c).normalized() * 400.0
			var t1 := p1 + Vector3(0, h1, 0) - (p1 - c).normalized() * 400.0
			var col := Color(0.46, 0.5, 0.42) if layer == 0 else Color(0.5, 0.55, 0.56)
			mk.quad(t0, t1, p1, p0, col, Vector2.ONE, Vector2.ZERO, true)
	var far_m := _std(Color.WHITE, 1.0)
	far_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := mk.instance("Far", {"ground": _ground_mat(), "far_rock": far_m})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ debug

## Development aid (--load-times): triangles per kind of node (instances counted).
static func _triangle_report(root: Node3D) -> void:
	var sums := {}
	for c in root.get_children():
		var mesh: Mesh = null
		var mult := 1
		if c is MeshInstance3D:
			mesh = (c as MeshInstance3D).mesh
		elif c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			mult = mm.instance_count
		if mesh == null:
			continue
		var tris := 0
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var key := c.name.get_slice("_", 0).rstrip("0123456789")
		sums[key] = int(sums.get(key, 0)) + tris * mult
	print("coastal triangles ", sums)


## Development aid (--dump-terrain=out.png): heights (sea blue), track (white),
## coastline (red), ravine (yellow), landmarks (magenta), 3 px per node.
static func _debug_map(td: TrackData, hf: Glacier.HF, path: String) -> void:
	var img := Image.create(hf.nx, hf.nz, false, Image.FORMAT_RGB8)
	for iz in hf.nz:
		for ix in hf.nx:
			var h := hf.h[iz * hf.nx + ix]
			var c := Color(0.1, 0.3, 0.6).lerp(Color(0.0, 0.05, 0.2), clampf(-h / 40.0, 0.0, 1.0)) if h < 0.0 else Color.from_hsv(0.66 - clampf(h / 300.0, 0.0, 0.66), 0.55, 0.85)
			if h >= 0.0 and fmod(h, 20.0) < 2.5:
				c = c.darkened(0.45)
			img.set_pixel(ix, iz, c)
	var sc := 3
	img.resize(hf.nx * sc, hf.nz * sc, Image.INTERPOLATE_NEAREST)
	var to_px := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x - hf.x0) / GRID * sc), int((p.y - hf.z0) / GRID * sc))
	var put := func(q: Vector2i, c: Color, r: int) -> void:
		if q.x >= r and q.y >= r and q.x < img.get_width() - r and q.y < img.get_height() - r:
			img.fill_rect(Rect2i(q.x - r, q.y - r, 2 * r + 1, 2 * r + 1), c)
	for i in range(0, td.count, 3):
		put.call(to_px.call(_xz(td.pos[i])), Color.WHITE, 0)
	for p in _coast:
		put.call(to_px.call(p), Color(1, 0.2, 0.2), 0)
	for p in _densify(_ravine, 6.0):
		put.call(to_px.call(p), Color(1, 1, 0), 1)
	put.call(to_px.call(_xz(_lighthouse)), Color(1, 0, 1), 3)
	put.call(to_px.call(_xz(_church)), Color(1, 0, 1), 3)
	img.save_png(path)
	print("terrain map ", path, " ", hf.nx, "x", hf.nz)
