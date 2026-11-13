## FORGE CALDERA world: a volcanic island at night with a foundry built into a
## live caldera.
##
## Layout analysis (_layout) derives everything from the track: the caldera
## centre sits inside the U that the Lava Lake Loop, Lava Bridge and Ledge
## Turn make around it; the rim follows the U about 100 m outside it and
## closes across the U's mouth, with saddles where the track crosses it; the
## lake's outflow leaves under the Lava Bridge through a breach in the east
## rim; the lava channel under the Channel Jump runs from a vent inside the
## circuit down to the sea; the coastline is star-shaped around the circuit's
## middle, close off the coastal sections and far beyond the volcano.
##
## Terrain: the shared height field (Glacier.HF + Glacier.distance_field)
## with polyline fields for the lava rivers, built in ~1 km tiles. Its vertex
## colour carries heat, which the volcanic shader turns into glowing cracks,
## so the lava lights the ground without real lights; the few omni lights
## skip the terrain's layer. Structures: the causeway and ore harbour, basalt
## column walls in the cuttings, crags on the rim and flanks, the arch over
## the Lava Bridge, Foundry Hall (crucibles pouring into ladles, furnaces,
## chimneys), cooling towers, stacks, conveyor gantries and fumaroles.
## Development aids: --dump-terrain=out.png, --mesh-stats.
class_name Forge
extends RefCounted

const GRID := 32.0
const MARGIN := 1600.0
const SEA_Y := 0.0
const LAVA_Y := 44.0          ## Lava lake surface.
const FLOOR_Y := 51.0         ## Caldera floor around the lake.
const RIM_OFF := 100.0        ## Rim crest, metres outside the U.
const LAKE_R := 245.0         ## Lava lake radius.
const ARM_HW := 42.0          ## Half-width of the lake's outflow arm.
const CHAN_HW := 13.0         ## Half-width of the jump's lava channel.
const RIVER_HW := 16.0        ## Half-width of the outflow river below the breach.
const TERRAIN_LAYER := 2      ## Visual layer bit of the terrain (lava omnis skip it).
const HALL_HW := 46.0         ## Half-width of Foundry Hall.
const HALL_H := 27.0          ## Foundry Hall's inner roof above the deck.
const LAVA_LIGHT := Color(1.0, 0.45, 0.16)

static var rng := RandomNumberGenerator.new()
static var last_hf: Glacier.HF
static var _fd := PackedFloat32Array()     ## Track distance per height-field node.
static var _fi := PackedInt32Array()       ## Nearest track sample per node.
static var _heat := PackedFloat32Array()   ## Heat per node (0..1).
static var _of := PackedFloat32Array()     ## Distance to the outflow river per node.
static var _cf := PackedFloat32Array()     ## Distance to the jump channel per node.
static var _V := Vector2.ZERO              ## Caldera centre (x, z).
static var _ru := 380.0                    ## Radius of the U around the lake.
static var _rim := PackedFloat32Array()    ## Rim radius per degree of azimuth.
static var _crest := PackedFloat32Array()  ## Rim crest height per degree.
static var _breach := Vector2.ZERO         ## Where the outflow leaves the caldera.
static var _arm_end := Vector2.ZERO        ## End of the flat lava arm (inside the breach).
static var _outflow := PackedVector2Array()   ## Outflow river: breach -> down the east flank.
static var _channel := PackedVector2Array()   ## Jump channel: vent -> gap -> sea.
static var _cut := PackedFloat32Array()    ## Ground offset from the deck, per track sample.
static var _sea_off := PackedFloat32Array()   ## Shore distance off the track, per track sample.
static var _isle_c := Vector2.ZERO         ## Middle of the circuit (the coastline is star-shaped around it).
static var _coast := PackedFloat32Array()  ## Coast radius per degree of azimuth around _isle_c.
static var _keep_clear: Array[Vector3] = []   ## (x, z, radius) spots props must leave open.
static var _flat: Array[Dictionary] = []   ## Building footprints: {c, t, hl, hw, y} (ground kept below y).
static var _vents := PackedVector3Array()  ## Fumaroles (x, -, z) along the Steam Vents section.


static func build(td: TrackData, root: Node3D) -> void:
	rng.seed = 5150
	_keep_clear.clear()
	_flat.clear()
	var t0 := Time.get_ticks_msec()
	_layout(td)
	_environment(root)
	var hf := _terrain(td, root)
	last_hf = hf
	for a in DevArgs.all():
		if a.begins_with("--dump-terrain="):
			_debug_map(td, hf, a.substr(15))
	_sea(root, hf)
	_lava(td, root, hf)
	_lava_bridge(td, root, hf)
	_foundry(td, root)
	_caldera_fx(td, root, hf)
	_cuttings(td, root, hf)
	_causeway(td, root, hf)
	_harbour(td, root, hf)
	_industry(td, root, hf)
	_crags(td, root, hf)
	_trackside(td, root, hf)
	_track_range(root)
	HelixBay._start_gantry(td, root, "FORGE CALDERA  /  VELOCITY LEAGUE")
	if DevArgs.has("--load-times"):
		print("forge world %d ms" % (Time.get_ticks_msec() - t0))
	if DevArgs.has("--mesh-stats"):
		_mesh_stats(root)


# ------------------------------------------------------------------ helpers

static func _section(td: TrackData, name: String) -> Vector2:
	for sc: Dictionary in td.sections:
		if sc["name"] == name:
			return Vector2(sc["s0"], sc["s1"])
	return Vector2(-1, -1)


static func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


static func _az(v: Vector2) -> float:
	## Azimuth in degrees, 0 = north (-z), clockwise, 0..360.
	return fposmod(rad_to_deg(atan2(v.x, -v.y)), 360.0)


static func _table(tab: PackedFloat32Array, az: float) -> float:
	var a := fposmod(az, 360.0)
	var i := int(a)
	return lerpf(tab[i % 360], tab[(i + 1) % 360], a - i)


static func _smooth_ring(tab: PackedFloat32Array, radius: int, passes: int) -> PackedFloat32Array:
	var out := tab
	for _p in passes:
		var nxt := PackedFloat32Array()
		nxt.resize(360)
		for i in 360:
			var acc := 0.0
			for k in range(-radius, radius + 1):
				acc += out[(i + k + 360) % 360]
			nxt[i] = acc / (2 * radius + 1)
		out = nxt
	return out


## Signed distance outside the lava lake (disk plus the outflow arm).
static func _lake_sd(p: Vector2) -> float:
	var disk := p.distance_to(_V) - LAKE_R
	var ab := _arm_end - _V
	var t := clampf((p - _V).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var arm := p.distance_to(_V + ab * t) - ARM_HW
	return minf(disk, arm)


static func _smooth_track(td: TrackData, vals: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := td.count
	var pre := PackedFloat64Array()
	pre.resize(n * 3 + 1)
	pre[0] = 0.0
	for k in n * 3:
		pre[k + 1] = pre[k] + vals[k % n]
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := i + n - radius
		var b := i + n + radius + 1
		out[i] = (pre[b] - pre[a]) / float(b - a)
	return out


# ------------------------------------------------------------------ layout

static func _layout(td: TrackData) -> void:
	var hit := TrackData.Hit.new()
	var gate := _section(td, "Caldera Gate")
	var hall := _section(td, "Foundry Hall")
	var bridge := _section(td, "Lava Bridge")
	td.frame_at(gate.y, hit)
	var gate_end := _xz(hit.c)
	td.frame_at(hall.x, hit)
	var hall_start := _xz(hit.c)
	_ru = gate_end.distance_to(hall_start) * 0.5
	td.frame_at((bridge.x + bridge.y) * 0.5, hit)
	var bmid := _xz(hit.c)
	var inward := _xz(hit.B).normalized()      # the loop turns right: the lake is on the right
	_V = bmid + inward * _ru
	# Rim: RIM_OFF beyond the U where the U runs, a 500 m arc across its mouth.
	var loop := _section(td, "Lava Lake Loop")
	var ledge := _section(td, "Ledge Turn")
	var rim := PackedFloat32Array()
	rim.resize(360)
	rim.fill(-1.0)
	var i := int(loop.x / td.step)
	while i < int(ledge.y / td.step):
		var v := _xz(td.pos[i]) - _V
		var a := int(_az(v)) % 360
		rim[a] = maxf(rim[a], v.length() + RIM_OFF)
		i += 1
	for a in 360:
		if rim[a] < 0.0:
			rim[a] = _ru + 120.0
	_rim = _smooth_ring(rim, 6, 3)
	# Crest height: a ragged ridge, saddles where the track crosses the rim
	# (the gate cutting and the foundry), and the breach under the outflow.
	var ridge := FastNoiseLite.new()
	ridge.seed = 77
	ridge.frequency = 0.05
	var crest := PackedFloat32Array()
	crest.resize(360)
	var gate_az := -1.0
	var hall_az := -1.0
	for k in range(int(gate.x / td.step) - 400, int(gate.y / td.step)):
		var v := _xz(td.pos[td.wrap_i(k)]) - _V
		if v.length() < _table(_rim, _az(v)):
			gate_az = _az(v)
			break
	for k in range(int(hall.y / td.step) + 400, int(hall.x / td.step), -1):
		var v := _xz(td.pos[td.wrap_i(k)]) - _V
		if v.length() < _table(_rim, _az(v)):
			hall_az = _az(v)
			break
	var out_dir := -inward
	var breach_az := _az(out_dir)
	for a in 360:
		var ar := deg_to_rad(float(a))
		var c := 225.0 + 45.0 * ridge.get_noise_2d(cos(ar) * 30.0, sin(ar) * 30.0)
		for sad: Vector2 in [Vector2(gate_az, 112.0), Vector2(hall_az, 104.0)]:
			if sad.x >= 0.0:
				var da := absf(angle_difference(deg_to_rad(a), deg_to_rad(sad.x)))
				c = lerpf(sad.y, c, smoothstep(deg_to_rad(10.0), deg_to_rad(38.0), da))
		var db := absf(angle_difference(deg_to_rad(a), deg_to_rad(breach_az)))
		c = lerpf(LAVA_Y - 6.0, c, smoothstep(deg_to_rad(5.0), deg_to_rad(20.0), db))
		crest[a] = c
	_crest = crest
	# Outflow: the arm runs from the lake under the bridge to the breach; the
	# river then falls down the east flank with a gentle meander.
	var rim_e := _table(_rim, breach_az)
	_arm_end = _V + out_dir * (rim_e + 30.0)
	_breach = _V + out_dir * rim_e
	_outflow = PackedVector2Array()
	var side := Vector2(-out_dir.y, out_dir.x)
	for k in 64:
		var q := _arm_end - out_dir * 40.0 + out_dir * (k * 40.0) + side * sin(k * 0.21) * 60.0 * smoothstep(0.0, 5.0, float(k))
		_outflow.append(q)
	# Jump channel: from a vent inside the circuit, through the gap, to the sea.
	var g0 := -1
	var g1 := -1
	for k in td.count:
		if td.flag_at_index(k, TrackData.F_GAP):
			if g0 < 0:
				g0 = k
			g1 = k
	var gi := (g0 + g1) / 2
	var gc := _xz(td.pos[gi])
	var gr := _xz(td.rgt[gi]).normalized()
	_channel = PackedVector2Array()
	for k in 13:
		var f := -380.0 + k * 40.0
		var q := gc - gr * f + Vector2(-gr.y, gr.x) * sin(k * 0.6) * 18.0 * smoothstep(0.0, 120.0, absf(f))
		_channel.append(q)
	_channel.reverse()     # vent first
	for k in 30:
		_channel.append(gc - gr * (100.0 + k * 40.0) + Vector2(-gr.y, gr.x) * sin(k * 0.5) * 25.0)
	_channel = _dedupe(_channel)
	# Ground offsets and the shore, per track sample.
	var cut_by := {"Causeway": -6.0, "Breakwater Sweep": -5.0, "Lava Field Run": -3.0, "Basalt Cuttings": 12.0,
		"Ash Climb": 14.0, "Caldera Gate": 8.0, "Lava Lake Loop": -2.5, "Lava Bridge": -2.5, "Ledge Turn": -2.5,
		"Foundry Hall": -2.5, "Slag Bend": 6.0, "Flank Descent": -1.0, "Channel Jump": -5.0, "Steam Vents": -4.0,
		"Coast Run": -5.0, "Harbour Turn": -6.0, "Quay": -6.0}
	var sea_by := {"Slag Bend": 700.0, "Flank Descent": 420.0, "Channel Jump": 300.0, "Steam Vents": 170.0, "Coast Run": 110.0, "Harbour Turn": 85.0,
		"Quay": 60.0, "Causeway": 60.0, "Breakwater Sweep": 80.0, "Lava Field Run": 140.0}
	var cut := PackedFloat32Array()
	var sea := PackedFloat32Array()
	cut.resize(td.count)
	sea.resize(td.count)
	sea.fill(1300.0)
	var last_cut := -6.0
	for k in td.count:
		var s := k * td.step
		var nm := ""
		for sc: Dictionary in td.sections:
			if s >= float(sc["s0"]) and s < float(sc["s1"]):
				nm = sc["name"]
		if cut_by.has(nm):
			last_cut = cut_by[nm]
		cut[k] = last_cut
		if sea_by.has(nm):
			sea[k] = sea_by[nm]
	# The coast bends away inland of the sea-side stretch at its north end.
	var lf := _section(td, "Lava Field Run")
	for k in td.count:
		var s := k * td.step
		if s >= lf.x and s < lf.y:
			sea[k] = lerpf(140.0, 1300.0, smoothstep(lf.x + 120.0, lf.y, s))
	_cut = _smooth_track(td, cut, 45)
	_sea_off = _smooth_track(td, sea, 90)
	# Coastline: star-shaped around the circuit's middle, at the track's
	# distance plus the shore margin along each azimuth.
	var cc := Vector2.ZERO
	for k in td.count:
		cc += _xz(td.pos[k])
	_isle_c = cc / td.count
	var coast := PackedFloat32Array()
	coast.resize(360)
	coast.fill(-1.0)
	for k in td.count:
		var v := _xz(td.pos[k]) - _isle_c
		var a := int(_az(v)) % 360
		coast[a] = maxf(coast[a], v.length() + _sea_off[k])
	for a in 360:
		if coast[a] < 0.0:
			coast[a] = maxf(coast[(a + 359) % 360], coast[(a + 1) % 360])
	_coast = _smooth_ring(coast, 5, 3)
	# Steam vents: fumaroles both sides of the Steam Vents section.
	_vents = PackedVector3Array()
	var sv := _section(td, "Steam Vents")
	for q in 9:
		var sq := lerpf(sv.x - 60.0, sv.y + 40.0, (q + 0.5) / 9.0)
		td.frame_at(sq, hit)
		var side_v := 1.0 if q % 2 == 0 else -1.0
		var dd := side_v * (maxf(hit.half_l, hit.half_r) + 24.0 + rng.randf() * 40.0)
		var vp := hit.c + hit.B * dd
		_vents.append(Vector3(vp.x, 0.0, vp.z))
	# Foundry Hall's footprint: the ground stays under its floor.
	var hall_mid := (hall.x + hall.y) * 0.5
	td.frame_at(hall_mid, hit)
	var ylo := INF
	for k in range(int(hall.x / td.step), int(hall.y / td.step)):
		ylo = minf(ylo, td.pos[k].y)
	_flat.append({"c": _xz(hit.c), "t": _xz(hit.T).normalized(), "hl": (hall.y - hall.x) * 0.5 + 14.0,
		"hw": HALL_HW + 6.0, "y": ylo - TrackMesh.DECK - 3.0})


static func _dedupe(line: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in line:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 1.0:
			out.append(p)
	return out


# ------------------------------------------------------------------ environment

static func _environment(root: Node3D) -> void:
	# Direction from the circuit's middle toward the caldera, for the sky glow.
	for c in root.get_children():
		if c is WorldEnvironment:
			var env := (c as WorldEnvironment).environment
			var sm := ShaderMaterial.new()
			sm.shader = load("res://assets/shaders/sky_forge.gdshader")
			sm.set_shader_parameter("clouds", Mats.tex("forge_clouds"))
			sm.set_shader_parameter("glow_dir", Vector2(0.97, -0.25))
			env.sky.sky_material = sm
			env.sky.radiance_size = Sky.RADIANCE_SIZE_64
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.34, 0.26, 0.25)
			env.ambient_light_energy = 1.1
			env.fog_light_color = Color(0.26, 0.11, 0.06)
			env.fog_density = 0.0011
			env.fog_aerial_perspective = 0.15
			env.fog_sky_affect = 0.12
			env.tonemap_exposure = 1.1
			env.glow_hdr_threshold = 0.95
			env.glow_intensity = 0.8
			env.glow_bloom = 0.06
		elif c is DirectionalLight3D:
			# The "sun" becomes the lava glow: warm, low, from the caldera side
			# (it travels from the caldera toward the middle of the circuit).
			var key := c as DirectionalLight3D
			key.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(104.0), 0.0)
			key.light_color = Color(1.0, 0.52, 0.26)
			key.light_energy = 1.0
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-60.0), 0.0)
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.3
	moon.shadow_enabled = false
	root.add_child(moon)


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
	_heat.resize(hf.nx * hf.nz)
	var hills := FastNoiseLite.new()
	hills.seed = 41
	hills.frequency = 0.0022
	hills.fractal_octaves = 3
	var rough := FastNoiseLite.new()
	rough.seed = 13
	rough.frequency = 0.012
	rough.fractal_octaves = 2
	var cracks := FastNoiseLite.new()
	cracks.seed = 5
	cracks.frequency = 0.008
	var field := Glacier.distance_field(td, hf)
	_fd = field[0]
	_fi = field[1]
	_of = Rainforest._poly_field(_outflow, hf)[0]
	_cf = Rainforest._poly_field(_channel, hf)[0]
	# An older, extinct cone to the north-east for the skyline.
	var old_c := _V + Vector2(1100.0, -1500.0)
	for iz in hf.nz:
		for ix in hf.nx:
			var k := iz * hf.nx + ix
			var x := hf.x0 + ix * GRID
			var z := hf.z0 + iz * GRID
			var p := Vector2(x, z)
			var j := _fi[k]
			var d: float = _fd[k] if j >= 0 else 1e6
			var n := hills.get_noise_2d(x, z)
			var rn := rough.get_noise_2d(x, z)
			var rv := p - _V
			var r := rv.length()
			var az := _az(rv)
			var rim := _table(_rim, az)
			var crest := _table(_crest, az)
			var h: float
			if r >= rim:
				var fall := exp(-(r - rim) / 360.0)
				h = 9.0 + (crest - 9.0) * fall + (n * 7.0 + rn * 2.0) * (1.0 - fall)
				# Radial gullies down the cone.
				var gul := absf(sin(deg_to_rad(az) * 26.0 + n * 4.0 + r * 0.004))
				h -= (crest - 9.0) * fall * 0.16 * (1.0 - gul) * smoothstep(rim, rim + 60.0, r)
			else:
				h = lerpf(FLOOR_Y + n * 3.0, crest, pow(smoothstep(rim - 90.0, rim, r), 1.4)) + rn * 1.5
			h = maxf(h, 300.0 * exp(-pow(p.distance_to(old_c) / 950.0, 2.0)) + n * 20.0)
			# Safety: the field's edges are always under the sea.
			var border := float(mini(mini(ix, iz), mini(hf.nx - 1 - ix, hf.nz - 1 - iz))) * GRID
			h = lerpf(-30.0, h, smoothstep(60.0, 300.0, border))
			var inside := r < rim - 20.0
			# Near the track the ground follows the deck (cuttings, embankments).
			var heat := 0.0
			if j >= 0:
				var tp := td.pos[j]
				var w := maxf(td.half_l[j], td.half_r[j])
				var near := tp.y + _cut[j] + rn * (1.5 + 2.5 * smoothstep(30.0, 10.0, tp.y))
				var kn := 1.0 - smoothstep(w + 15.0, w + (45.0 if inside else 220.0), d)
				h = lerpf(h, near, kn)
			# The lava lake and its arm, inside the rim.
			var sl := _lake_sd(p)
			h = lerpf(LAVA_Y - 5.0, h, smoothstep(-6.0, 60.0, sl))
			heat = maxf(heat, 1.0 - smoothstep(-10.0, 75.0, sl))
			# Outflow river below the breach, and the jump's lava channel.
			var dr := _of[k]
			var dc := _cf[k]
			h -= 12.0 * (1.0 - smoothstep(RIVER_HW, RIVER_HW + 36.0, dr)) * (0.0 if inside else 1.0)
			h -= 15.0 * (1.0 - smoothstep(CHAN_HW, CHAN_HW + 34.0, dc))
			heat = maxf(heat, 1.0 - smoothstep(RIVER_HW - 4.0, RIVER_HW + 50.0, dr))
			heat = maxf(heat, 1.0 - smoothstep(CHAN_HW - 4.0, CHAN_HW + 46.0, dc))
			# Hot cracks scattered over the caldera floor and the upper flank.
			var cz := smoothstep(0.38, 0.7, cracks.get_noise_2d(x, z)) * (1.0 - smoothstep(rim - 60.0, rim + 120.0, r))
			heat = maxf(heat, cz * 0.6)
			for vp in _vents:
				heat = maxf(heat, 0.8 * (1.0 - smoothstep(4.0, 34.0, p.distance_to(Vector2(vp.x, vp.z)))))
			# The corridor: never above the deck underside.
			if j >= 0:
				var w2 := maxf(td.half_l[j], td.half_r[j]) + 12.0
				var limit := td.pos[j].y - TrackMesh.DECK - 2.0
				h = lerpf(h, minf(h, limit), 1.0 - smoothstep(w2, w2 + 33.0, d))
			# Building footprints.
			for fp: Dictionary in _flat:
				var q: Vector2 = p - fp["c"]
				var ft: Vector2 = fp["t"]
				var u := absf(q.dot(ft)) - float(fp["hl"])
				var v := absf(q.dot(Vector2(-ft.y, ft.x))) - float(fp["hw"])
				var out := maxf(u, v)
				h = lerpf(h, minf(h, float(fp["y"])), 1.0 - smoothstep(0.0, 26.0, out))
			# The sea beyond the coastline (never inside the corridor).
			var cv := p - _isle_c
			var coast := _table(_coast, _az(cv)) + n * 45.0
			var sea := smoothstep(coast - 25.0, coast + 90.0, cv.length()) * smoothstep(30.0, 45.0, d)
			h = lerpf(h, -14.0 + n * 4.0, sea)
			hf.h[k] = h
			_heat[k] = clampf(heat, 0.0, 1.0)
	# Tiles of 32 x 32 cells (about 1 km), so the view frustum culls them; tiles
	# wholly under the sea are left out (the sea plane covers them).
	var mat := Mats.shader_mat("volcanic", {"noise_tex": Mats.tex("forge_noise"), "sea_y": SEA_Y})
	const T := 32
	for tz in range(0, hf.nz - 1, T):
		for tx in range(0, hf.nx - 1, T):
			var x1 := mini(tx + T, hf.nx - 1)
			var z1 := mini(tz + T, hf.nz - 1)
			var top := -INF
			for iz in range(tz, z1 + 1):
				for ix in range(tx, x1 + 1):
					top = maxf(top, hf.h[iz * hf.nx + ix])
			if top < SEA_Y - 3.0:
				continue
			var mk := MeshKit.new()
			mk.use("volcanic")
			var cols := x1 - tx + 1
			for iz in range(tz, z1 + 1):
				for ix in range(tx, x1 + 1):
					var x := hf.x0 + ix * GRID
					var z := hf.z0 + iz * GRID
					var hl := hf.h[iz * hf.nx + maxi(ix - 1, 0)]
					var hr := hf.h[iz * hf.nx + mini(ix + 1, hf.nx - 1)]
					var hd := hf.h[maxi(iz - 1, 0) * hf.nx + ix]
					var hu := hf.h[mini(iz + 1, hf.nz - 1) * hf.nx + ix]
					var ht := _heat[iz * hf.nx + ix]
					mk._vert(Vector3(x, hf.h[iz * hf.nx + ix], z), Vector3(hl - hr, 2.0 * GRID, hd - hu).normalized(), Color(ht, 0, 0), Vector2(x, z))
			for iz in range(0, z1 - tz):
				for ix in range(0, x1 - tx):
					var a := iz * cols + ix
					mk._quad_i(a, a + 1, a + cols + 1, a + cols)
			var mi := mk.instance("Terrain_%d_%d" % [tx / T, tz / T], {"volcanic": mat})
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = TERRAIN_LAYER
			root.add_child(mi)
	return hf


# ------------------------------------------------------------------ sea

static func _sea(root: Node3D, hf: Glacier.HF) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	mi.mesh = pm
	mi.position = Vector3(hf.x0 + hf.nx * GRID * 0.5, SEA_Y, hf.z0 + hf.nz * GRID * 0.5)
	mi.material_override = Mats.shader_mat("water", {
		"deep": Color(0.004, 0.006, 0.01), "shallow": Color(0.012, 0.014, 0.02),
		"reflect_col": Color(0.07, 0.035, 0.03), "glints": Color(0.35, 0.14, 0.06), "ripple": 1.4, "chop": 0.6})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ lava

static func _lava_mat(flow: float, energy: float = 3.2, crust: float = 0.55, speed: float = 1.0) -> ShaderMaterial:
	return Mats.shader_mat("lava", {"noise_tex": Mats.tex("forge_noise"), "flow": flow, "energy": energy,
		"crust_amount": crust, "speed": speed})


static func _lava(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	# The lake and its arm: one plane at lava level, seen only where the
	# ground is carved below it.
	var mk := MeshKit.new()
	mk.use("lake")
	var c := Vector3(_V.x, LAVA_Y, _V.y)
	var rr := LAKE_R + 45.0
	var ci := mk._vert(c, Vector3.UP, Color.WHITE)
	var first := mk.group_vertex_count()
	for k in 48:
		var a := TAU * k / 48.0
		mk._vert(c + Vector3(cos(a), 0, sin(a)) * rr, Vector3.UP, Color.WHITE)
	for k in 48:
		var i0 := first + k
		var i1 := first + (k + 1) % 48
		# Clockwise seen from above.
		if (mk._cur.v[i1] - c).cross(mk._cur.v[i0] - c).y >= 0.0:
			mk._tri(ci, i0, i1)
		else:
			mk._tri(ci, i1, i0)
	# The arm out to the breach.
	var dir := (_arm_end - _V).normalized()
	var side := Vector3(-dir.y, 0, dir.x) * (ARM_HW + 30.0)
	var a0 := c + Vector3(dir.x, 0, dir.y) * (LAKE_R * 0.5)
	var a1 := Vector3(_arm_end.x, LAVA_Y, _arm_end.y) + Vector3(dir.x, 0, dir.y) * 20.0
	_face(mk, a0 - side, a1 - side, a1 + side, a0 + side, Color.WHITE, Vector3.UP)
	var mi := mk.instance("LavaLake", {"lake": _lava_mat(0.0, 3.0, 0.62)})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Rivers: ribbons draped on their carved beds.
	var rv := MeshKit.new()
	_ribbon(rv, hf, _outflow, RIVER_HW * 2.0 + 4.0, 1.0)
	_ribbon(rv, hf, _channel, CHAN_HW * 2.0 + 4.0, 1.0)
	var rmi := rv.instance("LavaRivers", {"river": _lava_mat(1.0, 3.0, 0.4, 1.0)})
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rmi)


## A lava ribbon along `line`, draped on the height field (stops at the sea).
## UV.x 0..1 across, UV.y = metres along / 10.
static func _ribbon(mk: MeshKit, hf: Glacier.HF, line: PackedVector2Array, width: float, lift: float) -> void:
	mk.use("river")
	var dense := PackedVector2Array()
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var steps := maxi(1, int(a.distance_to(b) / 4.0))
		for q in steps:
			dense.append(a.lerp(b, float(q) / steps))
	dense.append(line[line.size() - 1])
	var acc := 0.0
	var prev := -1
	for k in dense.size():
		if k > 0:
			acc += dense[k].distance_to(dense[k - 1])
		var dir := (dense[mini(k + 1, dense.size() - 1)] - dense[maxi(k - 1, 0)]).normalized()
		var across := Vector2(-dir.y, dir.x) * width * 0.5
		var pl := dense[k] - across
		var pr := dense[k] + across
		var yc := hf.at(dense[k].x, dense[k].y)
		if yc < SEA_Y - 1.0:
			break
		var y := minf(minf(hf.at(pl.x, pl.y), hf.at(pr.x, pr.y)), yc) + lift
		y = maxf(y, yc + lift)
		var l := mk._vert(Vector3(pl.x, y, pl.y), Vector3.UP, Color.WHITE, Vector2(0.0, acc / 10.0))
		mk._vert(Vector3(pr.x, y, pr.y), Vector3.UP, Color.WHITE, Vector2(1.0, acc / 10.0))
		if prev >= 0:
			mk._quad_i(prev, l, l + 1, prev + 1)
		prev = l


# ------------------------------------------------------------------ shared bits

## Quad a-b-c-d whose front faces `want` (MeshKit.quad's winding either way).
static func _face(mk: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, want: Vector3, uv: Vector2 = Vector2.ONE) -> void:
	if (c - a).cross(b - a).dot(want) >= 0.0:
		mk.quad(a, b, c, d, col, uv)
	else:
		mk.quad(a, d, c, b, col, uv)


## A warm lava light. It skips the terrain's layer (the terrain's glow is baked
## into its vertex colour), so it only shades the track, ships and structures.
static func _light(root: Node3D, at: Vector3, energy: float, reach: float, col: Color = LAVA_LIGHT) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = col
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 0.8
	l.shadow_enabled = false
	l.light_specular = 0.3
	l.light_cull_mask = 0xFFFFF & ~TERRAIN_LAYER
	root.add_child(l)
	return l


static func _steel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.2, 0.19, 0.19)
	m.albedo_texture = Mats.tex("panel_albedo")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	m.roughness = 0.55
	m.metallic = 0.7
	return m


static func _hot_glow(col: Color, energy: float) -> Material:
	return Mats.glow(col, energy)


## Billboard smoke or steam: colour ramps from c0 (young) to c1 (old).
static func _plume(root: Node3D, at: Vector3, box: Vector3, amount: int, life: float, vel: Vector2, size: Vector2,
		c0: Color, c1: Color, accel: Vector3 = Vector3(1.5, 0.6, 0.0), spread: float = 12.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Plume"
	# Static emitters: local coordinates, so the preprocessed particles start
	# at the emitter (in world space they were simulated before the emitter's
	# transform reached the renderer and appeared at the origin).
	p.local_coords = true
	p.amount = maxi(4, int(amount * float(Quality.p["particles"])))
	p.lifetime = life
	p.preprocess = life
	p.position = at
	var top := vel.y * life + 0.5 * accel.y * life * life + 20.0
	p.visibility_aabb = AABB(Vector3(-box.x - 60.0, -box.y - 10.0, -box.z - 60.0), Vector3(box.x * 2.0 + 120.0, top + box.y + 30.0, box.z * 2.0 + 120.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spread
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	pm.gravity = accel
	pm.scale_min = size.x / size.y
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(1.0, 1.0))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(c0.r, c0.g, c0.b, 0.0), c0, c0.lerp(c1, 0.6), Color(c1.r, c1.g, c1.b, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE * size.y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = Mats.tex("smoke")
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return p


## Sparks or embers: small additive streaks thrown up and pulled down.
static func _sparks(root: Node3D, at: Vector3, box: Vector3, amount: int, vel: Vector2, grav: float, life: float = 1.2,
		size: float = 0.35, col: Color = Color(3.0, 1.5, 0.45)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Sparks"
	p.local_coords = true
	p.amount = maxi(4, int(amount * float(Quality.p["particles"])))
	p.lifetime = life
	p.preprocess = life
	p.position = at
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	pm.gravity = Vector3(0, -grav, 0)
	pm.scale_min = 0.45
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.4, 0.2, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 1.6) * size * 2.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = Mats.tex("spark")
	mat.albedo_color = col
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	return p


# ------------------------------------------------------------------ the lava bridge

## Through-arch bridge over the lake's outflow arm: a box girder under the
## deck, two steel arch ribs springing below the deck at the banks, hangers,
## bracing over the track, warning lights on the crowns.
static func _lava_bridge(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var r := _section(td, "Lava Bridge")
	if r.x < 0.0:
		return
	var mk := MeshKit.new()
	var hit := TrackData.Hit.new()
	var s := r.x - 40.0
	while s < r.y + 40.0:
		td.frame_at(s + 5.0, hit)
		var b := Basis(hit.B, hit.N, -hit.T)
		var wdt := hit.half_l + hit.half_r + 2.0 * TrackMesh.WALL_T + 1.0
		mk.use("steel")
		mk.box_t(Transform3D(b, hit.c - hit.N * (TrackMesh.DECK + 1.8)), Vector3(wdt - 2.0, 3.6, 10.2), Color(0.8, 0.8, 0.8))
		s += 10.0
	var a := r.x + 6.0
	var e := r.y - 6.0
	var rise := 38.0
	var arches: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var deck_pts: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var nseg := 30
	for k in nseg + 1:
		var f := float(k) / nseg
		td.frame_at(lerpf(a, e, f), hit)
		for si in 2:
			var side := -1.0 if si == 0 else 1.0
			var off := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 2.6
			var base := hit.c + hit.B * side * off
			arches[si].append(base + Vector3(0, -9.0 + (rise + 9.0) * sin(PI * f), 0))
			deck_pts[si].append(base + Vector3(0, -TrackMesh.DECK, 0))
	mk.use("steel")
	for si in 2:
		var arc := arches[si]
		for k in nseg:
			mk.beam(arc[k], arc[k + 1], 2.2, 3.2, Color(0.75, 0.42, 0.3), Vector3.UP)
		for k in range(2, nseg - 1):
			if arc[k].y - deck_pts[si][k].y > 3.0:
				mk.beam(deck_pts[si][k], arc[k], 0.35, 0.35, Color(0.8, 0.8, 0.8), td.tan[0])
		# Lower chord along the deck edge.
		for k in nseg:
			mk.beam(deck_pts[si][k], deck_pts[si][k + 1], 1.0, 1.6, Color(0.6, 0.6, 0.6), Vector3.UP)
	# Bracing between the ribs where they are well above the track.
	for k in range(7, nseg - 6, 2):
		mk.beam(arches[0][k], arches[1][k], 1.4, 1.4, Color(0.7, 0.7, 0.7), Vector3.UP)
		if k + 2 < nseg - 6:
			mk.beam(arches[0][k], arches[1][k + 2], 0.8, 0.8, Color(0.7, 0.7, 0.7), Vector3.UP)
	# Abutments where the ribs spring, on the banks.
	for f: int in [0, nseg]:
		for si in 2:
			var p := arches[si][f]
			var g := hf.at(p.x, p.z)
			mk.use("basalt_blk")
			mk.box(Vector3(p.x, (p.y + g) * 0.5 - 2.0, p.z), Vector3(9.0, p.y - g + 6.0, 9.0), Color(0.9, 0.9, 0.9), 0.5, 0.2)
	mk.use("warn_red")
	for si in 2:
		mk.box(arches[si][nseg / 2] + Vector3(0, 2.4, 0), Vector3(0.8, 0.8, 0.8), Color.WHITE)
	mk.use("neon_amber")
	for si in 2:
		for k in range(0, nseg + 1, 3):
			mk.box(deck_pts[si][k] + Vector3(0, 0.2, 0), Vector3(0.5, 0.25, 0.5), Color.WHITE)
	var basalt := StandardMaterial3D.new()
	basalt.vertex_color_use_as_albedo = true
	basalt.albedo_color = Color(0.16, 0.15, 0.15)
	basalt.albedo_texture = Mats.tex("panel_normal")
	basalt.uv1_triplanar = true
	basalt.uv1_scale = Vector3(0.1, 0.1, 0.1)
	basalt.roughness = 0.85
	root.add_child(mk.instance("LavaBridge", {"steel": _steel(), "basalt_blk": basalt}))
	# The lava under the bridge lights its underside.
	td.frame_at((r.x + r.y) * 0.5, hit)
	_light(root, Vector3(hit.c.x, LAVA_Y + 4.0, hit.c.z) + Vector3(hit.B.x, 0, hit.B.z) * -20.0, 5.0, 70.0)
	_sparks(root, Vector3(hit.c.x, LAVA_Y + 1.0, hit.c.z) - Vector3(hit.B.x, 0, hit.B.z) * 40.0, Vector3(30, 1, 30), 60, Vector2(3, 9), 4.0, 2.5, 0.5)


# ------------------------------------------------------------------ foundry hall

## Foundry Hall: a smelter shed straddling the track where it leaves the
## caldera. Inside: side bays with crucibles hanging from bridge cranes and
## pouring molten metal into ladles, furnaces with glowing mouths along the
## walls, columns, crane rails, roof trusses and lamps. Outside: clad walls, a
## gable roof with a lit lantern strip, four chimneys with smoke.
static func _foundry(td: TrackData, root: Node3D) -> void:
	var r := _section(td, "Foundry Hall")
	if r.x < 0.0:
		return
	var mk := MeshKit.new()
	var hot := MeshKit.new()
	var hit := TrackData.Hit.new()
	var s0 := r.x - 6.0
	var s1 := r.y + 6.0
	var rows: Array[Dictionary] = []
	var s := s0
	while s <= s1 + 0.01:
		td.frame_at(minf(s, s1), hit)
		var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
		rows.append({"c": hit.c, "b": Vector3(-t.z, 0, t.x), "t": t, "hw": maxf(hit.half_l, hit.half_r) + TrackMesh.WALL_T + 0.12})
		s += 6.0
	for k in rows.size() - 1:
		var A: Dictionary = rows[k]
		var B: Dictionary = rows[k + 1]
		var ca: Vector3 = A["c"]
		var cb: Vector3 = B["c"]
		var ba: Vector3 = A["b"]
		var bb: Vector3 = B["b"]
		var up := Vector3.UP
		var soot := Color(0.55, 0.52, 0.5)
		mk.use("hall_in")
		for side: float in [-1.0, 1.0]:
			# Inner walls.
			var wa := ca + ba * side * HALL_HW
			var wb := cb + bb * side * HALL_HW
			_face(mk, wa + up * -1.0, wb + up * -1.0, wb + up * HALL_H, wa + up * HALL_H, soot, -ba * side)
			# Side floors from the barrier foot to the wall.
			var fa := ca + ba * side * float(A["hw"]) + up * -0.3
			var fb := cb + bb * side * float(B["hw"]) + up * -0.3
			_face(mk, fa, fb, wb + up * -0.3, wa + up * -0.3, Color(0.35, 0.33, 0.32), up)
		# Inner roof.
		_face(mk, ca - ba * HALL_HW + up * HALL_H, cb - bb * HALL_HW + up * HALL_H, cb + bb * HALL_HW + up * HALL_H, ca + ba * HALL_HW + up * HALL_H, Color(0.3, 0.28, 0.27), -up)
		# Outside: clad walls down to the ground, a gable roof.
		mk.use("hall_out")
		for side: float in [-1.0, 1.0]:
			var oa := ca + ba * side * (HALL_HW + 1.2)
			var ob := cb + bb * side * (HALL_HW + 1.2)
			_face(mk, oa + up * -16.0, ob + up * -16.0, ob + up * (HALL_H + 2.0), oa + up * (HALL_H + 2.0), Color(0.7, 0.62, 0.55), ba * side)
			var ridge_a := ca + up * (HALL_H + 13.0)
			var ridge_b := cb + up * (HALL_H + 13.0)
			_face(mk, oa + up * (HALL_H + 2.0), ob + up * (HALL_H + 2.0), ridge_b + bb * side * 4.0, ridge_a + ba * side * 4.0, Color(0.5, 0.45, 0.42), up + ba * side * 0.5)
			# A band of lit windows along the outer wall.
			hot.use("lantern")
			_face(hot, oa + ba * side * 0.15 + up * 9.0, ob + bb * side * 0.15 + up * 9.0, ob + bb * side * 0.15 + up * 12.0, oa + ba * side * 0.15 + up * 12.0, Color.WHITE, ba * side)
			# The lantern: a lit strip of windows under the ridge.
			hot.use("lantern")
			_face(hot, ridge_a + ba * side * 4.0, ridge_b + bb * side * 4.0, ridge_b + bb * side * 4.0 + up * 3.0, ridge_a + ba * side * 4.0 + up * 3.0, Color.WHITE, ba * side)
		mk.use("hall_out")
		_face(mk, ca - ba * 4.0 + up * (HALL_H + 16.0), cb - bb * 4.0 + up * (HALL_H + 16.0), cb + bb * 4.0 + up * (HALL_H + 16.0), ca + ba * 4.0 + up * (HALL_H + 16.0), Color(0.5, 0.45, 0.42), up)
	# End walls with portals (inside and outside faces).
	for end in 2:
		var R: Dictionary = rows[0] if end == 0 else rows[rows.size() - 1]
		var c: Vector3 = R["c"]
		var b: Vector3 = R["b"]
		var t: Vector3 = R["t"]
		var ow := float(R["hw"]) + 2.5
		var oh := 17.0
		var out_n := -t if end == 0 else t
		var panels := [[-HALL_HW - 1.2, -ow, -16.0, HALL_H + 2.0], [ow, HALL_HW + 1.2, -16.0, HALL_H + 2.0], [-ow, ow, oh, HALL_H + 2.0], [-ow, ow, -16.0, -1.7]]
		for pnl: Array in panels:
			var p00 := c + b * float(pnl[0]) + Vector3.UP * float(pnl[2])
			var p10 := c + b * float(pnl[1]) + Vector3.UP * float(pnl[2])
			var p11 := c + b * float(pnl[1]) + Vector3.UP * float(pnl[3])
			var p01 := c + b * float(pnl[0]) + Vector3.UP * float(pnl[3])
			mk.use("hall_out")
			_face(mk, p00, p10, p11, p01, Color(0.6, 0.55, 0.5), out_n)
			mk.use("hall_in")
			_face(mk, p00 - out_n * 0.3, p10 - out_n * 0.3, p11 - out_n * 0.3, p01 - out_n * 0.3, Color(0.45, 0.42, 0.4), -out_n)
		# Gable end triangle.
		mk.use("hall_out")
		var g0 := c - b * (HALL_HW + 1.2) + Vector3.UP * (HALL_H + 2.0)
		var g1 := c + b * (HALL_HW + 1.2) + Vector3.UP * (HALL_H + 2.0)
		var g2 := c + Vector3.UP * (HALL_H + 16.0)
		if (g2 - g0).cross(g1 - g0).dot(out_n) >= 0.0:
			mk.tri(g0, g1, g2, Color(0.6, 0.55, 0.5))
		else:
			mk.tri(g0, g2, g1, Color(0.6, 0.55, 0.5))
		# Hazard frame round the portal.
		mk.use("neon_amber")
		var pf := c + out_n * 0.4
		mk.beam(pf - b * ow + Vector3.UP * -0.5, pf - b * ow + Vector3.UP * oh, 0.5, 0.5, Color.WHITE, t)
		mk.beam(pf + b * ow + Vector3.UP * -0.5, pf + b * ow + Vector3.UP * oh, 0.5, 0.5, Color.WHITE, t)
		mk.beam(pf - b * ow + Vector3.UP * oh, pf + b * ow + Vector3.UP * oh, 0.5, 0.5, Color.WHITE, t)
	# Structure inside: columns, crane rails, trusses and lamps every 24 m.
	var steel := _steel()
	var n_bays := int((s1 - s0) / 24.0)
	for q in n_bays + 1:
		var sq := lerpf(s0 + 4.0, s1 - 4.0, float(q) / n_bays)
		td.frame_at(sq, hit)
		var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
		var b := Vector3(-t.z, 0, t.x)
		var c := hit.c
		mk.use("steel")
		for side: float in [-1.0, 1.0]:
			var col_p := c + b * side * 21.0
			mk.box_t(Transform3D(Basis(b, Vector3.UP, -t), col_p + Vector3.UP * (HALL_H * 0.5 - 0.5)), Vector3(1.3, HALL_H + 1.0, 1.3), Color(0.7, 0.66, 0.62))
			mk.box_t(Transform3D(Basis(b, Vector3.UP, -t), c + b * side * (HALL_HW - 0.8) + Vector3.UP * (HALL_H * 0.5 - 0.5)), Vector3(1.0, HALL_H + 1.0, 1.6), Color(0.6, 0.58, 0.55))
		# Truss: top and bottom chords across the hall, posts between.
		var l := c - b * HALL_HW + Vector3.UP * (HALL_H - 1.0)
		var rr := c + b * HALL_HW + Vector3.UP * (HALL_H - 1.0)
		mk.beam(l, rr, 0.8, 1.2, Color(0.55, 0.52, 0.5), t)
		mk.beam(l + Vector3.UP * -4.0, rr + Vector3.UP * -4.0, 0.6, 0.8, Color(0.55, 0.52, 0.5), t)
		for x in range(-4, 5):
			var px := c + b * (x * 10.0) + Vector3.UP * (HALL_H - 3.0)
			mk.beam(px + Vector3.UP * -2.0, px + Vector3.UP * 2.0, 0.4, 0.4, Color(0.55, 0.52, 0.5), t)
		mk.use("lamp")
		for x: float in [-34.0, -10.0, 10.0, 34.0]:
			mk.box(c + b * x + Vector3.UP * (HALL_H - 5.4), Vector3(2.2, 0.3, 2.2), Color.WHITE)
	# Crane rails along both bays.
	for side: float in [-1.0, 1.0]:
		for off: float in [21.0, HALL_HW - 1.5]:
			var prev := Vector3.INF
			for R: Dictionary in rows:
				var c: Vector3 = R["c"]
				var b: Vector3 = R["b"]
				var p := c + b * side * off + Vector3.UP * 18.0
				if prev != Vector3.INF:
					mk.use("steel")
					mk.beam(prev, p, 1.0, 1.4, Color(0.75, 0.6, 0.2), Vector3.UP)
				prev = p
	# Furnaces against the walls, glowing mouths facing the track.
	var nf := 0
	var sf := s0 + 30.0
	while sf < s1 - 20.0:
		td.frame_at(sf, hit)
		var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
		var b := Vector3(-t.z, 0, t.x)
		var side := 1.0 if nf % 2 == 0 else -1.0
		var bas := Basis(b, Vector3.UP, -t)
		var fc := hit.c + b * side * (HALL_HW - 6.0)
		mk.use("furnace")
		mk.box_t(Transform3D(bas, fc + Vector3.UP * 6.0), Vector3(10.0, 13.0, 16.0), Color(0.7, 0.65, 0.6))
		mk.box_t(Transform3D(bas, fc + Vector3.UP * 14.0 - b * side * 1.0), Vector3(8.0, 3.0, 12.0), Color(0.5, 0.48, 0.45))
		mk.cyl(fc + Vector3.UP * 15.0, fc + Vector3.UP * (HALL_H + 24.0), 1.6, 1.3, 8, Color(0.5, 0.45, 0.42))
		hot.use("molten")
		var mouth := fc - b * side * 5.05 + Vector3.UP * 3.2
		_face(hot, mouth - t * 3.5 + Vector3.UP * -2.0, mouth + t * 3.5 + Vector3.UP * -2.0, mouth + t * 3.5 + Vector3.UP * 2.0, mouth - t * 3.5 + Vector3.UP * 2.0, Color.WHITE, -b * side)
		nf += 1
		sf += 52.0
	# Crucible pours at three stations, alternating sides.
	var stations := [0.22, 0.52, 0.8]
	for q in stations.size():
		var sq := lerpf(r.x, r.y, float(stations[q]))
		td.frame_at(sq, hit)
		var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
		var b := Vector3(-t.z, 0, t.x)
		var side := -1.0 if q % 2 == 0 else 1.0
		var floor_y := hit.c.y - 0.3
		var bay := hit.c + b * side * 28.0
		# Bridge crane across the bay with a hoist.
		mk.use("crane")
		var g0 := hit.c + b * side * 21.0 + Vector3.UP * 19.0
		var g1 := hit.c + b * side * (HALL_HW - 1.5) + Vector3.UP * 19.0
		for dz: float in [-2.0, 2.0]:
			mk.beam(g0 + t * dz, g1 + t * dz, 1.0, 1.8, Color(0.95, 0.7, 0.15), t)
		mk.box(bay + Vector3.UP * 20.5 - b * side * 2.0 + Vector3(0, floor_y - hit.c.y, 0), Vector3(5.0, 2.4, 5.0), Color(0.95, 0.7, 0.15))
		mk.use("steel")
		var hang := bay - b * side * 2.0 + Vector3(0, floor_y - hit.c.y, 0)
		for dz: float in [-1.4, 1.4]:
			mk.beam(hang + Vector3.UP * 19.3 + t * dz, hang + Vector3.UP * 13.6 + t * dz, 0.12, 0.12, Color.WHITE, b)
		# The crucible, tilted toward the track, pouring into a ladle.
		var tilt := Basis(t, side * deg_to_rad(38.0))
		var cpos := hang + Vector3.UP * 9.0
		var cr_prof := PackedVector2Array([Vector2(0.01, -3.6), Vector2(3.6, -3.6), Vector2(4.7, -1.4), Vector2(5.0, 3.3), Vector2(5.4, 3.9)])
		mk.use("crucible")
		mk.lathe_at(Transform3D(tilt, cpos), cr_prof, 14, Color(0.5, 0.42, 0.38))
		hot.use("molten")
		var rim_c := cpos + tilt * Vector3(0, 3.2, 0)
		var rim_n := tilt * Vector3.UP
		var rx := rim_n.cross(t).normalized()
		hot.cyl(rim_c - rim_n * 0.1, rim_c, 4.9, 4.9, 14, Color.WHITE, true)
		# Pour: from the low side of the lip down into the ladle.
		var lip := rim_c - rx * 4.8 * side * -1.0
		if (lip - hit.c).length() > (rim_c + rx * 4.8 * side * -1.0 - hit.c).length():
			lip = rim_c + rx * 4.8 * side * -1.0
		var ladle := Vector3(lip.x, floor_y, lip.z)
		var pts := PackedVector3Array()
		for k in 9:
			var f := k / 8.0
			pts.append(lip.lerp(ladle + Vector3.UP * 4.8, f) + (lip - Vector3(cpos.x, lip.y, cpos.z)).normalized() * sin(f * PI * 0.5) * 0.8)
		hot.tube(pts, PackedFloat32Array([1.1, 0.85, 0.75, 0.7, 0.7, 0.7, 0.7, 0.75, 0.9]), 8, Color.WHITE, false)
		mk.use("crucible")
		var ld_prof := PackedVector2Array([Vector2(0.01, 0.0), Vector2(4.6, 0.0), Vector2(5.6, 3.6), Vector2(5.9, 5.0)])
		mk.lathe_at(Transform3D(Basis.IDENTITY, ladle), ld_prof, 16, Color(0.45, 0.4, 0.36))
		hot.use("molten")
		hot.cyl(ladle + Vector3.UP * 4.4, ladle + Vector3.UP * 4.6, 5.5, 5.5, 16, Color.WHITE, true)
		_sparks(root, ladle + Vector3.UP * 4.0, Vector3(1.5, 0.3, 1.5), 70, Vector2(5.0, 12.0), 9.8, 1.1, 0.3)
		_light(root, ladle + Vector3.UP * 7.0 - b * side * 6.0, 6.0, 48.0, Color(1.0, 0.55, 0.22))
		# Ingot moulds on a line beside the ladle, still glowing.
		for m in 7:
			var mp := ladle + t * (8.0 + m * 3.2) + b * side * 4.0
			mk.use("steel")
			mk.box(mp + Vector3.UP * 0.5, Vector3(2.4, 1.0, 1.8), Color(0.5, 0.48, 0.45))
			hot.use("ingot")
			hot.box(mp + Vector3.UP * 1.02, Vector3(1.9, 0.06, 1.3), Color.WHITE)
	# Working light down the middle of the hall.
	for f: float in [0.33, 0.67]:
		td.frame_at(lerpf(r.x, r.y, f), hit)
		_light(root, hit.c + Vector3.UP * 16.0, 2.5, 70.0, Color(1.0, 0.78, 0.55))
	# Chimneys on the roof with smoke, red lights on top.
	for q in 4:
		td.frame_at(lerpf(r.x + 40.0, r.y - 40.0, q / 3.0), hit)
		var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
		var b := Vector3(-t.z, 0, t.x)
		var side := 1.0 if q % 2 == 0 else -1.0
		var base := hit.c + b * side * (HALL_HW - 10.0) + Vector3.UP * (HALL_H + 2.0)
		var top := base + Vector3.UP * 62.0
		mk.use("chimney")
		mk.cyl(base, top, 4.2, 3.0, 12, Color(0.75, 0.7, 0.66), false)
		for band: float in [0.86, 0.94]:
			mk.use("paint_band")
			mk.cyl(base.lerp(top, band), base.lerp(top, band + 0.035), 3.25, 3.2, 12, Color.WHITE, false)
		mk.use("warn_red")
		mk.box(top + Vector3.UP * 0.6, Vector3(0.9, 0.9, 0.9), Color.WHITE)
		_plume(root, top + Vector3.UP * 2.0, Vector3(1.5, 0.5, 1.5), 22, 9.0, Vector2(4.0, 6.0), Vector2(8.0, 26.0),
			Color(0.5, 0.36, 0.3, 0.55), Color(0.1, 0.09, 0.09, 0.35), Vector3(2.2, 0.4, 0.6), 8.0)
	# Sign on the lake side.
	td.frame_at((r.x + r.y) * 0.5, hit)
	var tt := Vector3(hit.T.x, 0, hit.T.z).normalized()
	var bb2 := Vector3(-tt.z, 0, tt.x)
	var lbl := Label3D.new()
	lbl.text = "CALDERA  FOUNDRY  No.3"
	lbl.font = load("res://assets/fonts/Orbitron.ttf")
	lbl.font_size = 128
	lbl.pixel_size = 0.07
	lbl.modulate = Color(1.0, 0.62, 0.25)
	lbl.shaded = false
	var face_n := bb2   # the lake is on the right of the track
	lbl.transform = Transform3D(Basis(face_n.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, face_n), hit.c + bb2 * (HALL_HW + 1.6) + Vector3.UP * (HALL_H - 6.0))
	root.add_child(lbl)
	var inn := StandardMaterial3D.new()
	inn.vertex_color_use_as_albedo = true
	inn.albedo_color = Color(0.5, 0.44, 0.4)
	inn.albedo_texture = Mats.tex("panel_albedo")
	inn.uv1_triplanar = true
	inn.uv1_scale = Vector3(0.08, 0.08, 0.08)
	inn.roughness = 0.6
	inn.metallic = 0.3
	inn.emission_enabled = true
	inn.emission = Color(0.16, 0.08, 0.04)
	var outm := StandardMaterial3D.new()
	outm.vertex_color_use_as_albedo = true
	outm.albedo_color = Color(0.24, 0.2, 0.18)
	outm.albedo_texture = Mats.tex("panel_albedo")
	outm.uv1_triplanar = true
	outm.uv1_scale = Vector3(0.06, 0.06, 0.06)
	outm.roughness = 0.7
	outm.metallic = 0.4
	var furnace := StandardMaterial3D.new()
	furnace.vertex_color_use_as_albedo = true
	furnace.albedo_color = Color(0.3, 0.22, 0.18)
	furnace.roughness = 0.8
	var crane := StandardMaterial3D.new()
	crane.vertex_color_use_as_albedo = true
	crane.roughness = 0.5
	crane.metallic = 0.5
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.75, 0.12, 0.08)
	band.roughness = 0.6
	var chim := StandardMaterial3D.new()
	chim.vertex_color_use_as_albedo = true
	chim.albedo_color = Color(0.3, 0.28, 0.27)
	chim.roughness = 0.85
	var mi := mk.instance("FoundryHall", {"hall_in": inn, "hall_out": outm, "steel": steel, "furnace": furnace,
		"crucible": furnace, "crane": crane, "paint_band": band, "chimney": chim})
	root.add_child(mi)
	var hmi := hot.instance("FoundryMolten", {"molten": _lava_mat(1.0, 4.0, 0.12, 1.6), "lantern": _hot_glow(Color(1.0, 0.5, 0.2), 1.6),
		"ingot": _hot_glow(Color(1.0, 0.35, 0.08), 2.4)})
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hmi)


# ------------------------------------------------------------------ caldera effects

## Smoke and embers over the lake, lights that throw its glow onto the
## track around it, steam where the lava rivers meet the sea.
static func _caldera_fx(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var c := Vector3(_V.x, LAVA_Y, _V.y)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var at := c + Vector3(cos(a), 0, sin(a)) * LAKE_R * 0.45
		_plume(root, at + Vector3.UP * 3.0, Vector3(40, 2, 40), 26, 14.0, Vector2(3.0, 6.0), Vector2(30.0, 80.0),
			Color(1.0, 0.42, 0.18, 0.32), Color(0.12, 0.1, 0.1, 0.0), Vector3(2.5, 0.8, 1.0), 20.0)
	_sparks(root, c + Vector3.UP * 1.0, Vector3(LAKE_R * 0.7, 1.0, LAKE_R * 0.7), 220, Vector2(4.0, 14.0), 2.5, 4.0, 0.9, Color(3.2, 1.3, 0.35))
	# Lights at the lava's edge throw its glow onto the U around it (not onto
	# the terrain: its glow is baked).
	var inward := (_V - _breach).normalized()
	for k in 3:
		var dir := inward.rotated(PI * 0.5 * (k - 1)) * -1.0
		var at := _V + dir * (LAKE_R - 25.0)
		_light(root, Vector3(at.x, LAVA_Y + 16.0, at.y), 5.0, 240.0)
	# Lava meets the sea: steam plumes, lit from below.
	for line: PackedVector2Array in [_outflow, _channel]:
		for k in line.size():
			var q := line[k]
			if hf.at(q.x, q.y) < SEA_Y - 0.5:
				_plume(root, Vector3(q.x, SEA_Y + 1.0, q.y), Vector3(18, 1, 18), 30, 10.0, Vector2(4.0, 8.0), Vector2(20.0, 70.0),
					Color(1.0, 0.7, 0.5, 0.45), Color(0.35, 0.33, 0.33, 0.0), Vector3(3.0, 1.0, 0.5), 15.0)
				_light(root, Vector3(q.x, SEA_Y + 6.0, q.y), 3.0, 60.0)
				break


# ------------------------------------------------------------------ basalt cuttings

## A unit hexagonal column (radius 1, height 1, standing on y = 0).
static func _hex_mesh(mat: Material) -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("col")
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		_face(mk, p0, p1, p1 + Vector3.UP, p0 + Vector3.UP, Color(0.75, 0.75, 0.75), (p0 + p1) * 0.5)
		var top := Vector3.UP
		var t0 := p0 + Vector3.UP * 0.97
		var t1 := p1 + Vector3.UP * 0.97
		if (t1 - top).cross(t0 - top).y >= 0.0:
			mk.tri(top, t0, t1, Color.WHITE)
		else:
			mk.tri(top, t1, t0, Color.WHITE)
	return mk.commit({"col": mat})


## Walls of hexagonal basalt columns lining the cuttings and the rim gate,
## stepped up away from the barrier; instanced in 400 m cells.
static func _cuttings(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var a := _section(td, "Basalt Cuttings")
	var b := _section(td, "Caldera Gate")
	if a.x < 0.0 or b.x < 0.0:
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.13, 0.125, 0.13)
	mat.albedo_texture = Mats.tex("panel_normal")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	mat.roughness = 0.75
	mat.metallic = 0.15
	var mesh := _hex_mesh(mat)
	var cells: Dictionary = {}
	var hit := TrackData.Hit.new()
	var s := a.x
	var end := b.y - 40.0
	while s < end:
		td.frame_at(s, hit)
		for side: float in [-1.0, 1.0]:
			var edge := (hit.half_r if side > 0.0 else hit.half_l) + TrackMesh.WALL_T + 3.0
			var probe := hit.c + hit.B * side * (edge + 32.0)
			var bank := hf.at(probe.x, probe.z) - hit.c.y
			if bank < 5.0:
				continue
			for row in 2:
				var d := edge + 1.6 + row * 2.8 + rng.randf() * 0.8
				var p := hit.c + hit.B * side * d + hit.T * rng.randf_range(-0.8, 0.8)
				var foot := minf(hf.at(p.x, p.z), hit.c.y - 1.0) - 2.0
				var top := hit.c.y + minf(bank * (0.5 + 0.3 * row), 34.0) * rng.randf_range(0.75, 1.15)
				if top - foot < 3.0:
					continue
				var rad := rng.randf_range(1.15, 1.55)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rad, top - foot, rad)), Vector3(p.x, foot, p.z))
				var key := Vector2i(floori(p.x / 400.0), floori(p.z / 400.0))
				if not cells.has(key):
					cells[key] = [[], []]
				(cells[key][0] as Array).append(xf)
				var g := rng.randf_range(0.7, 1.15)
				(cells[key][1] as Array).append(Color(g, g * 0.97, g * 0.95))
		s += 2.3
	for key: Vector2i in cells:
		var xs: Array = cells[key][0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = xs.size()
		for q in xs.size():
			mm.set_instance_transform(q, xs[q])
			mm.set_instance_color(q, cells[key][1][q])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Columns_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.visibility_range_end = 600.0 * float(Quality.p["view"])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


# ------------------------------------------------------------------ causeway and harbour

## The start causeway: a basalt-block embankment under the deck from the
## Harbour Turn round to the Breakwater Sweep, boulders on the sea side,
## lamp posts along both edges.
static func _causeway(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var ht := _section(td, "Harbour Turn")
	var bw := _section(td, "Breakwater Sweep")
	if ht.x < 0.0 or bw.x < 0.0:
		return
	var s0 := (ht.x + ht.y) * 0.5
	var s1 := bw.y + td.length
	var mk := MeshKit.new()
	var rocks: Array = []
	var hit := TrackData.Hit.new()
	var prev := PackedVector3Array()
	var s := s0
	var n := 0
	while s <= s1:
		td.frame_at(fmod(s, td.length), hit)
		var b := Vector3(hit.B.x, 0, hit.B.z).normalized()
		var top := hit.c.y - TrackMesh.DECK - 0.2
		var hl := hit.half_l + TrackMesh.WALL_T + 2.0
		var hr := hit.half_r + TrackMesh.WALL_T + 2.0
		var gl := hf.at(hit.c.x - b.x * (hl + 12.0), hit.c.z - b.z * (hl + 12.0))
		var gr := hf.at(hit.c.x + b.x * (hr + 12.0), hit.c.z + b.z * (hr + 12.0))
		var foot_l := minf(gl, top) - 3.0
		var foot_r := minf(gr, top) - 3.0
		var sec := PackedVector3Array([
			hit.c - b * (hl + 0.8 * (top - foot_l) + 2.0) + Vector3(0, foot_l - hit.c.y, 0),
			hit.c - b * hl + Vector3(0, top - hit.c.y, 0),
			hit.c + b * hr + Vector3(0, top - hit.c.y, 0),
			hit.c + b * (hr + 0.8 * (top - foot_r) + 2.0) + Vector3(0, foot_r - hit.c.y, 0)])
		if prev.size() > 0:
			mk.use("embank")
			var pair: Array[PackedVector3Array] = [prev, sec]
			mk.loft(pair, Color.WHITE, false, false)
		prev = sec
		# Lamp posts on both edges every 36 m.
		if n % 12 == 0:
			for side: float in [-1.0, 1.0]:
				var e := hit.c + b * side * ((hr if side > 0.0 else hl) + 0.6)
				mk.use("metal_dark")
				mk.beam(e + Vector3(0, -1.5, 0), e + Vector3(0, 9.0, 0), 0.3, 0.3, Color.WHITE)
				mk.beam(e + Vector3(0, 9.0, 0), e + Vector3(0, 9.0, 0) - b * side * 2.2, 0.25, 0.25, Color.WHITE)
				mk.use("lamp_sodium")
				mk.box(e + Vector3(0, 8.7, 0) - b * side * 2.2, Vector3(0.9, 0.3, 0.6), Color.WHITE)
		# Boulders on the sea side.
		if n % 3 == 0:
			var d := hl + 0.8 * (top - foot_l) + rng.randf_range(0.0, 10.0)
			var p := hit.c - b * d
			var g := hf.at(p.x, p.z)
			if g < 3.0:
				var sc := rng.randf_range(2.0, 4.2)
				rocks.append(Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU).scaled(Vector3(sc, sc * 0.75, sc)), Vector3(p.x, maxf(g, SEA_Y - 2.0) + sc * 0.3, p.z)))
		s += 3.0
		n += 1
	var emb := StandardMaterial3D.new()
	emb.albedo_color = Color(0.1, 0.095, 0.095)
	emb.albedo_texture = Mats.tex("forge_noise")
	emb.uv1_triplanar = true
	emb.uv1_scale = Vector3(0.09, 0.09, 0.09)
	emb.roughness = 0.95
	root.add_child(mk.instance("Causeway", {"embank": emb, "lamp_sodium": _hot_glow(Color(1.0, 0.62, 0.25), 4.0)}))
	if rocks.is_empty():
		return
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.9
	var rk := MeshKit.new()
	rk.use("rock")
	rk.blob(Vector3.ZERO, Vector3.ONE, 1, noise, 0.35, Color(0.5, 0.48, 0.46), Color(0.25, 0.24, 0.24), true)
	var rmat := StandardMaterial3D.new()
	rmat.vertex_color_use_as_albedo = true
	rmat.albedo_color = Color(0.22, 0.21, 0.21)
	rmat.roughness = 0.85
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rk.commit({"rock": rmat})
	mm.instance_count = rocks.size()
	for q in rocks.size():
		mm.set_instance_transform(q, rocks[q])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Breakwater"
	mmi.multimesh = mm
	mmi.visibility_range_end = 1000.0 * float(Quality.p["view"])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


## The ore harbour off the Harbour Turn: a quay, two gantry cranes, an ore
## carrier with lit superstructure, and ore heaps.
static func _harbour(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var ht := _section(td, "Harbour Turn")
	if ht.x < 0.0:
		return
	var hit := TrackData.Hit.new()
	td.frame_at(lerpf(ht.x, ht.y, 0.45), hit)
	var out := -Vector3(hit.B.x, 0, hit.B.z).normalized()     # seaward
	var along := Vector3(hit.T.x, 0, hit.T.z).normalized()
	# Find the shore along the seaward ray.
	var d := 40.0
	while d < 400.0:
		var q := hit.c + out * d
		if hf.at(q.x, q.z) < SEA_Y + 0.5:
			break
		d += 4.0
	var quay := hit.c + out * (d - 6.0)
	quay.y = SEA_Y
	var bas := Basis(along, Vector3.UP, -out)    # x along the quay, -z out to sea
	var mk := MeshKit.new()
	mk.use("concrete")
	mk.box_t(Transform3D(bas, quay + Vector3.UP * 0.5 + out * 8.0), Vector3(260.0, 9.0, 34.0), Color(0.42, 0.4, 0.4), 0.6, 0.12)
	mk.use("lamp_sodium")
	for k in range(-6, 7):
		mk.box(quay + Vector3.UP * 5.4 + out * 24.5 + along * (k * 20.0), Vector3(0.6, 0.6, 0.6), Color.WHITE)
	# Ore carrier moored along the quay.
	var ship := quay + out * 48.0 + Vector3.UP * SEA_Y
	var sb := Transform3D(bas, ship)
	mk.push(sb)
	mk.use("hull")
	var hull := PackedVector2Array([Vector2(-95, -2), Vector2(85, -2), Vector2(100, 4), Vector2(100, 14), Vector2(-98, 14), Vector2(-100, 4)])
	mk.extrude(hull, -13.0, 13.0, Color(0.35, 0.12, 0.08))
	mk.use("metal_dark")
	for k in 6:
		mk.box(Vector3(-60.0 + k * 24.0, 15.0, 0), Vector3(18.0, 2.0, 20.0), Color(0.5, 0.5, 0.5))
	mk.use("bld")
	mk.box(Vector3(-82.0, 24.0, 0), Vector3(14.0, 20.0, 22.0), Color(0.85, 0.85, 0.8, 0.6))
	mk.use("warn_red")
	mk.box(Vector3(-82.0, 36.0, 0), Vector3(0.8, 0.8, 0.8), Color.WHITE)
	mk.use("nav_white")
	mk.box(Vector3(98.0, 16.0, 0), Vector3(0.6, 0.6, 0.6), Color.WHITE)
	mk.pop()
	# Gantry cranes on the quay, booms out over the ship.
	for k in 2:
		var cp := quay + along * (-45.0 + k * 90.0) + out * 6.0
		var cb := Transform3D(bas, cp)
		mk.push(cb)
		mk.use("crane_paint")
		for lx: float in [-7.0, 7.0]:
			for lz: float in [-6.0, 6.0]:
				mk.beam(Vector3(lx, 4.0, lz), Vector3(lx * 0.6, 40.0, lz * 0.8), 1.2, 1.2, Color.WHITE)
		mk.box(Vector3(0, 41.0, -30.0), Vector3(7.0, 3.0, 100.0), Color.WHITE)
		mk.box(Vector3(0, 46.0, 10.0), Vector3(9.0, 8.0, 12.0), Color(0.8, 0.8, 0.8))
		mk.use("warn_red")
		mk.box(Vector3(0, 43.0, -79.0), Vector3(0.8, 0.8, 0.8), Color.WHITE)
		mk.box(Vector3(0, 51.0, 10.0), Vector3(0.8, 0.8, 0.8), Color.WHITE)
		mk.pop()
	# Ore heaps inland of the quay.
	for k in 4:
		var hp := quay - out * rng.randf_range(30.0, 50.0) + along * (-90.0 + k * 55.0)
		var g := hf.at(hp.x, hp.z)
		var dist := Vector2(hp.x, hp.z).distance_to(_xz(hit.c))
		if dist < maxf(hit.half_l, hit.half_r) + 30.0:
			continue
		mk.use("ore")
		mk.lathe_at(Transform3D(Basis.IDENTITY, Vector3(hp.x, g - 1.0, hp.z)), PackedVector2Array([Vector2(22, 0), Vector2(12, 7), Vector2(0.5, 12)]), 10, Color(0.9, 0.9, 0.9), 1.0, false)
	var hullm := StandardMaterial3D.new()
	hullm.vertex_color_use_as_albedo = true
	hullm.roughness = 0.6
	hullm.metallic = 0.4
	var cranem := StandardMaterial3D.new()
	cranem.albedo_color = Color(0.85, 0.55, 0.1)
	cranem.roughness = 0.5
	cranem.metallic = 0.5
	cranem.vertex_color_use_as_albedo = true
	var ore := StandardMaterial3D.new()
	ore.albedo_color = Color(0.3, 0.12, 0.08)
	ore.vertex_color_use_as_albedo = true
	ore.roughness = 0.95
	root.add_child(mk.instance("Harbour", {"hull": hullm, "crane_paint": cranem, "ore": ore, "lamp_sodium": _hot_glow(Color(1.0, 0.62, 0.25), 4.0)}))


# ------------------------------------------------------------------ industry

## Cooling towers and stacks inside the circuit by the coast, conveyor
## gantries over the descent, and the fumaroles of the Steam Vents.
static func _industry(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var mk := MeshKit.new()
	var hit := TrackData.Hit.new()
	# Cooling towers, on the inside of the Steam Vents / Coast Run.
	var sv := _section(td, "Steam Vents")
	var cr := _section(td, "Coast Run")
	var towers := [[lerpf(sv.x, sv.y, 0.35), 190.0], [lerpf(sv.y, cr.y, 0.5), 260.0], [lerpf(sv.x, sv.y, 0.85), 330.0]]
	for tw: Array in towers:
		td.frame_at(float(tw[0]), hit)
		var base := hit.c + Vector3(hit.B.x, 0, hit.B.z).normalized() * float(tw[1])
		base.y = hf.at(base.x, base.z) - 2.0
		var prof := PackedVector2Array()
		for k in 11:
			var y := k * 8.0
			prof.append(Vector2(16.0 * sqrt(1.0 + pow((y - 58.0) / 30.0, 2.0)), y))
		mk.use("tower")
		mk.lathe_at(Transform3D(Basis.IDENTITY, base), prof, 24, Color(0.75, 0.72, 0.7), 4.0)
		mk.use("metal_dark")
		mk.cyl(base + Vector3.UP * 79.0, base + Vector3.UP * 81.0, prof[10].x + 0.6, prof[10].x + 0.6, 24, Color.WHITE, false)
		mk.use("warn_red")
		mk.box(base + Vector3(prof[10].x, 81.5, 0), Vector3(0.9, 0.9, 0.9), Color.WHITE)
		_keep_clear.append(Vector3(base.x, base.z, 45.0))
		_plume(root, base + Vector3.UP * 82.0, Vector3(10, 1, 10), 26, 12.0, Vector2(3.0, 5.0), Vector2(25.0, 60.0),
			Color(0.62, 0.55, 0.52, 0.45), Color(0.2, 0.19, 0.2, 0.0), Vector3(2.2, 0.4, 0.8), 10.0)
	# Stacks beside the towers.
	for k in 3:
		td.frame_at(lerpf(sv.x, cr.y, 0.15 + k * 0.3), hit)
		var base := hit.c + Vector3(hit.B.x, 0, hit.B.z).normalized() * (120.0 + k * 35.0) + Vector3(hit.T.x, 0, hit.T.z).normalized() * 30.0
		base.y = hf.at(base.x, base.z) - 1.0
		var top := base + Vector3.UP * (95.0 + k * 12.0)
		mk.use("stack")
		mk.cyl(base, top, 5.0, 3.2, 12, Color(0.7, 0.68, 0.66), false)
		mk.use("paint_band")
		for band: float in [0.82, 0.9]:
			mk.cyl(base.lerp(top, band), base.lerp(top, band + 0.04), 3.6, 3.5, 12, Color.WHITE, false)
		mk.use("warn_red")
		mk.box(top + Vector3.UP * 0.6, Vector3(1.0, 1.0, 1.0), Color.WHITE)
		mk.box(base.lerp(top, 0.5) + Vector3(4.3, 0, 0), Vector3(0.8, 0.8, 0.8), Color.WHITE)
		_plume(root, top + Vector3.UP * 2.0, Vector3(1.5, 0.5, 1.5), 20, 10.0, Vector2(4.0, 7.0), Vector2(10.0, 34.0),
			Color(0.42, 0.33, 0.3, 0.5), Color(0.08, 0.07, 0.07, 0.0), Vector3(2.5, 0.3, 0.6), 8.0)
	# Conveyor gantries over the descent: box trusses carrying ore up to the
	# foundry, crossing the track at an angle.
	var fd := _section(td, "Flank Descent")
	var sb := _section(td, "Slag Bend")
	for sc: float in [lerpf(sb.x, sb.y, 0.55), lerpf(fd.x, fd.y, 0.55)]:
		td.frame_at(sc, hit)
		var t := Vector3(hit.T.x, 0, hit.T.z).normalized()
		var b := Vector3(-t.z, 0, t.x)
		var dir := (b * cos(deg_to_rad(28.0)) + t * sin(deg_to_rad(28.0))).normalized()
		var span := 150.0
		var a := hit.c - dir * span * 0.5
		var e := hit.c + dir * span * 0.5
		a.y = hit.c.y + 13.0
		e.y = hit.c.y + 24.0
		_conveyor(mk, a, e, hf)
		_keep_clear.append(Vector3(hit.c.x, hit.c.z, 20.0))
	# Fumaroles: rings of hot rock with steam rising.
	for vp in _vents:
		var g := hf.at(vp.x, vp.z)
		var at := Vector3(vp.x, g, vp.z)
		mk.use("vent_rock")
		var noise := FastNoiseLite.new()
		noise.seed = int(vp.x) & 255
		noise.frequency = 0.8
		for q in 5:
			var a := TAU * q / 5.0 + rng.randf()
			mk.blob(at + Vector3(cos(a) * 5.0, 0.6, sin(a) * 5.0), Vector3(2.6, 1.8, 2.6), 0, noise, 0.4, Color(0.6, 0.55, 0.5), Color(0.3, 0.27, 0.25), true)
		_plume(root, at + Vector3.UP * 1.5, Vector3(2.5, 0.5, 2.5), 22, 7.0, Vector2(5.0, 9.0), Vector2(5.0, 24.0),
			Color(0.62, 0.53, 0.47, 0.34), Color(0.3, 0.28, 0.28, 0.0), Vector3(1.0, 0.6, 0.4), 10.0)
	var tower := StandardMaterial3D.new()
	tower.vertex_color_use_as_albedo = true
	tower.albedo_color = Color(0.4, 0.38, 0.37)
	tower.albedo_texture = Mats.tex("panel_albedo")
	tower.uv1_scale = Vector3(1.0, 0.1, 1.0)
	tower.roughness = 0.9
	tower.cull_mode = BaseMaterial3D.CULL_DISABLED
	var stack := StandardMaterial3D.new()
	stack.vertex_color_use_as_albedo = true
	stack.albedo_color = Color(0.32, 0.3, 0.3)
	stack.roughness = 0.85
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.75, 0.12, 0.08)
	band.roughness = 0.6
	var vrock := StandardMaterial3D.new()
	vrock.vertex_color_use_as_albedo = true
	vrock.albedo_color = Color(0.3, 0.22, 0.14)
	vrock.roughness = 0.8
	vrock.emission_enabled = true
	vrock.emission = Color(0.5, 0.12, 0.02)
	var ore := StandardMaterial3D.new()
	ore.albedo_color = Color(0.3, 0.12, 0.08)
	ore.roughness = 0.95
	root.add_child(mk.instance("Industry", {"tower": tower, "stack": stack, "paint_band": band, "steel": _steel(), "vent_rock": vrock, "ore_belt": ore}))


## A conveyor gantry from a to b: a box truss on trestles with a belt of ore
## and a lit walkway.
static func _conveyor(mk: MeshKit, a: Vector3, b: Vector3, hf: Glacier.HF) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	var length := a.distance_to(b)
	var n := int(length / 6.0)
	var w := 2.4
	var h := 3.2
	var prev: Array = []
	mk.use("steel")
	for k in n + 1:
		var p := a + dir * (length * k / n)
		var c := [p - side * w + up * 0.0, p + side * w, p + side * w + up * h, p - side * w + up * h]
		for q in 4:
			mk.beam(c[q], c[(q + 1) % 4], 0.3, 0.3, Color(0.7, 0.66, 0.6), dir)
		if not prev.is_empty():
			for q in 4:
				mk.beam(prev[q], c[q], 0.4, 0.4, Color(0.7, 0.66, 0.6), up)
			mk.beam(prev[0], c[3], 0.2, 0.2, Color(0.7, 0.66, 0.6), side)
			mk.beam(prev[1], c[2], 0.2, 0.2, Color(0.7, 0.66, 0.6), side)
		prev = c
	# Belt with ore, a lit walkway strip.
	mk.use("metal_dark")
	mk.beam(a + up * 0.5, b + up * 0.5, w * 1.4, 0.3, Color.WHITE, up)
	mk.use("ore_belt")
	mk.beam(a + up * 0.8, b + up * 0.8, w * 1.0, 0.4, Color.WHITE, up)
	mk.use("neon_amber")
	mk.beam(a - side * (w + 0.2) + up * 0.1, b - side * (w + 0.2) + up * 0.1, 0.15, 0.15, Color.WHITE, up)
	# Trestles at both ends and a quarter in from each end.
	for f: float in [0.02, 0.2, 0.8, 0.98]:
		var p := a.lerp(b, f)
		var g := hf.at(p.x, p.z) - 2.0
		mk.use("steel")
		for sgn: float in [-1.0, 1.0]:
			mk.beam(Vector3(p.x, g, p.z) + side * sgn * (w + 1.6), p + side * sgn * w, 0.7, 0.7, Color(0.7, 0.66, 0.6), dir)


# ------------------------------------------------------------------ crags

## Jagged rock: spires along the rim crest, outcrops on the caldera's inner
## wall, boulders and old lava blocks over the flanks. Three faceted shapes,
## instanced in 500 m cells.
static func _crags(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var shapes: Array[ArrayMesh] = []
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.17, 0.155, 0.15)
	mat.albedo_texture = Mats.tex("panel_normal")
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	mat.roughness = 0.85
	for k in 3:
		var noise := FastNoiseLite.new()
		noise.seed = 31 + k * 7
		noise.frequency = 0.7 + k * 0.25
		var mk := MeshKit.new()
		mk.use("crag")
		mk.blob(Vector3(0, 0.45, 0), Vector3(1.0, 1.0, 1.0), 1, noise, 0.45, Color(0.85, 0.8, 0.78), Color(0.35, 0.32, 0.3), true)
		shapes.append(mk.commit({"crag": mat}))
	var cells: Dictionary = {}     # Vector3i(cx, cz, shape) -> Array[Transform3D]
	var far: Dictionary = {}       # cells holding rim spires (longer range)
	var add := func(p: Vector3, sc: Vector3, big: bool) -> void:
		var key := Vector3i(floori(p.x / 500.0), floori(p.z / 500.0), rng.randi() % 3 + (3 if big else 0))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(sc), p))
	var track_d := func(p: Vector3) -> float:
		var ix := clampi(int(round((p.x - hf.x0) / GRID)), 0, hf.nx - 1)
		var iz := clampi(int(round((p.z - hf.z0) / GRID)), 0, hf.nz - 1)
		return _fd[iz * hf.nx + ix]
	# Rim spires (skip the saddles where the track crosses and the breach).
	var a := 0.0
	while a < 360.0:
		var dir := Vector2(sin(deg_to_rad(a)), -cos(deg_to_rad(a)))
		var rr := _table(_rim, a) + rng.randf_range(-18.0, 12.0)
		var q := _V + dir * rr
		var p := Vector3(q.x, 0.0, q.y)
		p.y = hf.at(p.x, p.z) - 3.0
		if float(track_d.call(p)) > 75.0 and p.y > LAVA_Y + 10.0 and p.y > SEA_Y + 2.0:
			var w := rng.randf_range(9.0, 18.0)
			add.call(p, Vector3(w, rng.randf_range(16.0, 38.0), w * rng.randf_range(0.7, 1.2)), true)
		a += rng.randf_range(2.0, 3.5)
	# Inner wall outcrops and flank boulders.
	var tries := 0
	var placed := 0
	var want := int(520.0 * float(Quality.p["city"]))
	while placed < want and tries < 6000:
		tries += 1
		var inner := placed < want * 160 / 520
		var p := Vector3.ZERO
		if inner:
			var az := rng.randf() * 360.0
			var dir := Vector2(sin(deg_to_rad(az)), -cos(deg_to_rad(az)))
			var q := _V + dir * (_table(_rim, az) - rng.randf_range(15.0, 70.0))
			p = Vector3(q.x, 0, q.y)
		else:
			var q := _V + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 1900.0
			p = Vector3(q.x, 0, q.y)
			if Vector2(p.x, p.z).distance_to(_V) < _table(_rim, _az(Vector2(p.x, p.z) - _V)) + 20.0:
				continue
		p.y = hf.at(p.x, p.z) - 1.0
		if p.y < SEA_Y + 1.5 or float(track_d.call(p)) < 55.0:
			continue
		var bad := false
		for kc in _keep_clear:
			if Vector2(p.x, p.z).distance_squared_to(Vector2(kc.x, kc.y)) < kc.z * kc.z:
				bad = true
				break
		if bad:
			continue
		var s := rng.randf_range(5.0, 12.0) if inner else rng.randf_range(2.5, 9.0)
		add.call(p, Vector3(s, s * rng.randf_range(0.6, 1.3), s * rng.randf_range(0.7, 1.2)), false)
		placed += 1
	for key: Vector3i in cells:
		var xs: Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shapes[key.z % 3]
		mm.instance_count = xs.size()
		for q in xs.size():
			mm.set_instance_transform(q, xs[q])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Crags_%d_%d_%d" % [key.x, key.y, key.z]
		mmi.multimesh = mm
		mmi.visibility_range_end = (2200.0 if key.z >= 3 else 900.0) * float(Quality.p["view"])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


## The open island shows most of the circuit at once; chunks of the track far
## beyond the fog are dropped (TrackMesh builds them without a range).
static func _track_range(root: Node3D) -> void:
	if not root.has_node("Track"):
		return
	for c in root.get_node("Track").get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.visibility_range_end = 1450.0 * float(Quality.p["view"])
			mi.visibility_range_end_margin = 80.0


# ------------------------------------------------------------------ trackside

static func _trackside(td: TrackData, root: Node3D, hf: Glacier.HF) -> void:
	var cells: Dictionary = {}
	var last_gate := -1000.0
	var bridge := _section(td, "Lava Bridge")
	for i in td.count:
		var s := i * td.step
		var key := int(s / 400.0)
		if not cells.has(key):
			cells[key] = MeshKit.new()
		var mk: MeshKit = cells[key]
		var tunnel := td.flag_at_index(i, TrackData.F_TUNNEL) or td.flag_at_index(i + 40, TrackData.F_TUNNEL) or td.flag_at_index(i - 40, TrackData.F_TUNNEL)
		var gap := td.flag_at_index(i, TrackData.F_GAP) or td.flag_at_index(i + 8, TrackData.F_GAP) or td.flag_at_index(i - 8, TrackData.F_GAP)
		var on_bridge := s > bridge.x - 30.0 and s < bridge.y + 30.0
		var p := td.pos[i]
		if i % 46 == 0 and not tunnel and not gap and not on_bridge:
			var under := p - td.nrm[i] * TrackMesh.DECK
			var foot := hf.at(p.x, p.z)
			if under.y - foot > 1.5:
				mk.use("concrete")
				var hgt := under.y - foot
				mk.box(Vector3(under.x, foot + hgt * 0.5, under.z), Vector3(2.8, hgt, 2.8), Color(0.45, 0.42, 0.4), 0.6, 0.25)
		var near_hall := td.flag_at_index(i + 90, TrackData.F_TUNNEL) or td.flag_at_index(i - 90, TrackData.F_TUNNEL)
		if s - last_gate > 230.0 and s > 160.0 and not tunnel and not near_hall and not gap and not on_bridge:
			last_gate = s
			HelixBay._gate(mk, td, i, int(s / 230.0) * 2)
	for key: int in cells:
		var mk: MeshKit = cells[key]
		if not mk.is_empty():
			root.add_child(mk.instance("Trackside%02d" % key))


# ------------------------------------------------------------------ debug

## Development aid (--mesh-stats): triangles per world node, heaviest first.
static func _mesh_stats(root: Node3D) -> void:
	var rows: Array = []
	var groups := {}
	var nodes: Array[Node] = root.get_children()
	if root.has_node("Track"):
		nodes.append_array(root.get_node("Track").get_children())
	for c in nodes:
		var tris := 0
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var m := (c as MeshInstance3D).mesh
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		elif c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			var arr := mm.mesh.surface_get_arrays(0)
			tris = mm.instance_count * (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif c is GPUParticles3D:
			tris = (c as GPUParticles3D).amount * 2
		var g := String(c.name).rstrip("0123456789_-")
		groups[g] = int(groups.get(g, 0)) + tris
	for g: String in groups:
		rows.append([groups[g], g])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	for r: Array in rows:
		print("  mesh %-24s %7d tris" % [r[1], r[0]])

## Development aid (--dump-terrain=out.png): shaded heights, sea (blue), lava
## (orange), heat (red tint), track (white), 4 px per height-field node.
static func _debug_map(td: TrackData, hf: Glacier.HF, path: String) -> void:
	var img := Image.create(hf.nx, hf.nz, false, Image.FORMAT_RGB8)
	for iz in hf.nz:
		for ix in hf.nx:
			var k := iz * hf.nx + ix
			var h := hf.h[k]
			var hl := hf.h[iz * hf.nx + maxi(ix - 1, 0)]
			var hu := hf.h[maxi(iz - 1, 0) * hf.nx + ix]
			var shade := clampf(0.6 + (hl - h) * 0.03 + (hu - h) * 0.03, 0.2, 1.0)
			var c := Color.from_hsv(0.08, 0.25, clampf(0.12 + h / 180.0, 0.0, 1.0) * shade)
			if h < SEA_Y:
				c = Color(0.05, 0.12, 0.3)
			var p := Vector2(hf.x0 + ix * GRID, hf.z0 + iz * GRID)
			if h < LAVA_Y - 0.5 and _lake_sd(p) < 40.0 and p.distance_to(_V) < 700.0:
				c = Color(1.0, 0.45, 0.1)
			c = c.lerp(Color(0.9, 0.15, 0.05), _heat[k] * 0.5)
			img.set_pixel(ix, iz, c)
	img.resize(hf.nx * 4, hf.nz * 4, Image.INTERPOLATE_NEAREST)
	var to_px := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x - hf.x0) / GRID * 4.0), int((p.y - hf.z0) / GRID * 4.0))
	var put := func(q: Vector2i, c: Color, r: int) -> void:
		if q.x >= r and q.y >= r and q.x < img.get_width() - r and q.y < img.get_height() - r:
			img.fill_rect(Rect2i(q.x - r, q.y - r, 2 * r + 1, 2 * r + 1), c)
	for i in range(0, td.count, 3):
		put.call(to_px.call(_xz(td.pos[i])), Color.WHITE, 0)
	for p in _outflow:
		put.call(to_px.call(p), Color(1, 0.8, 0.2), 2)
	for p in _channel:
		put.call(to_px.call(p), Color(1, 1, 0.3), 2)
	put.call(to_px.call(_V), Color(0, 1, 0), 4)
	img.save_png(path)
	print("terrain map ", path, " ", hf.nx, "x", hf.nz, " V=", _V, " ru=", _ru)
	# Cross-sections through the circuit for checking cut and fill.
	var hit := TrackData.Hit.new()
	for sec: Dictionary in td.sections:
		var sx := (float(sec["s0"]) + float(sec["s1"])) * 0.5
		td.frame_at(sx, hit)
		var row := "%-17s s=%5.0f deck %5.1f |" % [sec["name"], sx, hit.c.y]
		for dd: float in [-300.0, -150.0, -80.0, -40.0, -25.0, 25.0, 40.0, 80.0, 150.0, 300.0]:
			var q := hit.c + hit.B * dd
			row += " %+.0f:%.0f" % [dd, hf.at(q.x, q.z)]
		print(row)
