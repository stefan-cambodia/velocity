## Procedural ship model. Builds the hull (one mesh, livery by vertex mask),
## the animated parts (airbrake flaps, exhaust plumes) and the cockpit interior.
##
## Model space: forward = -Z, up = +Y, right = +X, origin at the hover centre.
## Length 5.9 m, span 3.0 m. The design (Halden HX-7 "Skadi") is original:
## faceted central fuselage with chine creases, bubble canopy, twin flux-keel
## pods on swept wings, canted fins joined by a rear aerofoil, three engines.
class_name ShipModel
extends RefCounted

## Paint masks (vertex colour: R primary, G secondary, B accent, A occlusion).
const P := Color(1, 0, 0, 1)
const S := Color(0, 1, 0, 1)
const A := Color(0, 0, 1, 1)
const T := Color(0, 0, 0, 1)

## Reference geometry (Halden HX-7). Other teams' designs derive their own
## values in _derive(); consumers read them from Parts.
const FLAP_HINGE_A := Vector3(0.62, 0.02, 1.52)
const FLAP_HINGE_B := Vector3(0.98, 0.0, 1.74)
const NOZZLES := [Vector3(0.0, 0.02, 2.62), Vector3(1.18, -0.08, 2.56), Vector3(-1.18, -0.08, 2.56)]
const NOZZLE_R := [0.27, 0.17, 0.17]
const EYE := Vector3(0.0, 0.47, -0.32)

## Design parameters (see Catalog TEAMS "design"):
##   fuse_w, fuse_len (nose length), nose ("sharp"/"std"/"blunt"), canopy_z,
##   pod_x, pod_y, pod_scale, pod_len, pod_z, fins ("twin"/"center"/"quad"),
##   aerofoil, aero_h, canards, engine_r, wing_chord
const DEFAULT_DESIGN := {"fuse_w": 1.0, "fuse_len": 1.0, "nose": "std", "canopy_z": 0.0, "pod_x": 1.18, "pod_y": -0.08,
	"pod_scale": 1.0, "pod_len": 1.0, "pod_z": 0.0, "fins": "twin", "aerofoil": true, "aero_h": 0.66, "canards": true,
	"engine_r": 1.0, "wing_chord": 1.0}

## The design being built (set by build(); read by the builders below).
static var g: Dictionary = {}

## The parts created by build().
class Parts:
	var nozzles: Array = []          ## Nozzle positions in model space (main, right pod, left pod).
	var nozzle_r: Array = []
	var eye := Vector3.ZERO          ## Pilot's eye in model space.
	var body: MeshInstance3D
	var flap_l: Node3D       ## Pivot nodes; rotate about local X to deploy.
	var flap_r: Node3D
	var plumes: Array[MeshInstance3D] = []
	var glows: Array[MeshInstance3D] = []
	var cockpit: Node3D
	var speed_label: Label3D
	var info_label: Label3D
	var root: Node3D


static func _derive(design: Dictionary) -> Dictionary:
	var d := DEFAULT_DESIGN.duplicate()
	for k: String in design:
		d[k] = design[k]
	var px: float = d["pod_x"]
	var py: float = d["pod_y"]
	var ps: float = d["pod_scale"]
	var pz: float = d["pod_z"]
	var pl: float = d["pod_len"]
	var er: float = d["engine_r"]
	d["pod_tail"] = 2.45 * pl + pz
	d["nozzles"] = [Vector3(0.0, 0.02, 2.62), Vector3(px, py, d["pod_tail"] + 0.11), Vector3(-px, py, d["pod_tail"] + 0.11)]
	d["nozzle_r"] = [0.27 * er, 0.17 * ps * er, 0.17 * ps * er]
	d["root_x"] = 0.62 * float(d["fuse_w"])
	d["tip_x"] = px - 0.2 * ps
	var wing_back := 1.52 + pz * 0.6
	d["hinge_a"] = Vector3(d["root_x"], 0.02, wing_back)
	d["hinge_b"] = Vector3(d["tip_x"], 0.0, wing_back + 0.22)
	d["eye"] = Vector3(0.0, 0.47, -0.32 + float(d["canopy_z"]))
	return d


static func _sec_fuselage(z: float, w: float, top: float, bot: float, ch: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(0.0, top, z),
		Vector3(0.45 * w, top * 0.96, z),
		Vector3(0.84 * w, lerpf(ch, top, 0.55), z),
		Vector3(w, ch, z),
		Vector3(0.83 * w, lerpf(ch, bot, 0.55), z),
		Vector3(0.45 * w, bot * 0.95, z),
		Vector3(0.0, bot, z),
	])


## Fuselage table: z, half width, top, bottom, chine height.
const FUSE := [
	[-2.95, 0.03, 0.035, -0.03, 0.0],
	[-2.75, 0.13, 0.06, -0.07, -0.01],
	[-2.45, 0.24, 0.1, -0.12, -0.02],
	[-2.05, 0.36, 0.15, -0.17, -0.03],
	[-1.6, 0.48, 0.2, -0.21, -0.03],
	[-1.1, 0.6, 0.26, -0.24, -0.02],
	[-0.5, 0.69, 0.31, -0.26, 0.0],
	[0.2, 0.73, 0.33, -0.26, 0.0],
	[0.9, 0.72, 0.31, -0.25, 0.0],
	[1.6, 0.67, 0.28, -0.23, 0.0],
	[2.15, 0.6, 0.25, -0.21, 0.0],
	[2.35, 0.56, 0.235, -0.2, 0.0],
]
## Livery boundaries along z per facet strip (0 = deck centre .. 5 = keel).
## Paired rows straddle each boundary so the paint edges are crisp.
const FUSE_CUTS := [-2.25, -2.0, -1.55, 0.35, 0.95, 1.25, 1.95]


static func _table_at(table: Array, z: float) -> Array:
	for i in table.size() - 1:
		var a: Array = table[i]
		var b: Array = table[i + 1]
		if z <= float(b[0]) or i == table.size() - 2:
			var t := clampf((z - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
			var out := [z]
			for k in range(1, a.size()):
				out.append(lerpf(float(a[k]), float(b[k]), t))
			return out
	return table[0]


static func _rows_with_cuts(table: Array, cuts: Array) -> PackedFloat32Array:
	var zs := PackedFloat32Array()
	for r: Array in table:
		zs.append(float(r[0]))
	for c: float in cuts:
		zs.append(c - 0.004)
		zs.append(c + 0.004)
	zs.sort()
	return zs


static func _fuse_paint(k: int, z: float) -> Color:
	var c: Color
	match k:
		0: c = S if z < -2.25 else P
		1: c = S if z < -2.0 else (A if z > 1.95 else P)
		2: c = S if z < 0.35 else P
		3: c = S if z < 0.95 else (A if z < 1.25 else T)
		4: c = S if z < -1.55 else T
		_: c = T * 0.7
	if k >= 4:
		c.a = 0.62
	return c


static func _fuselage(mk: MeshKit) -> void:
	var zs := _rows_with_cuts(FUSE, FUSE_CUTS)
	var secs: Array[PackedVector3Array] = []
	var fw: float = g["fuse_w"]
	var fl: float = g["fuse_len"]
	for z in zs:
		var r := _table_at(FUSE, z)
		var w: float = r[1] * fw
		var top: float = r[2]
		var bot: float = r[3]
		var zz: float = z * fl if z < 0.0 else z
		# Nose character: blunt noses carry their width further forward.
		if g["nose"] == "blunt" and z < -1.0:
			var k := clampf((-1.0 - z) / 1.95, 0.0, 1.0)
			w = lerpf(w, maxf(w, 0.42 * fw), k * 0.85)
			top = lerpf(top, maxf(top, 0.16), k * 0.7)
			bot = lerpf(bot, minf(bot, -0.16), k * 0.7)
		elif g["nose"] == "sharp" and z < -1.0:
			var k2 := clampf((-1.0 - z) / 1.95, 0.0, 1.0)
			w *= lerpf(1.0, 0.72, k2)
			top *= lerpf(1.0, 0.8, k2)
		secs.append(_sec_fuselage(zz, w, top, bot, r[4]))
	var start := mk.use("hull").group_vertex_count()
	# One loft per facet strip (sharp creases between strips).
	for k in 6:
		var strip: Array[PackedVector3Array] = []
		var cols: Array[PackedColorArray] = []
		for si in secs.size():
			var sec := secs[si]
			strip.append(PackedVector3Array([sec[k], sec[k + 1]]))
			var c := _fuse_paint(k, sec[0].z)
			cols.append(PackedColorArray([c, c]))
		mk.loft_colored(strip, cols, false, true)
	mk.mirror_x_since(start)
	# Tail cap behind the engine ring.
	var tail := secs[secs.size() - 1]
	var start2 := mk.group_vertex_count()
	for k in 6:
		mk.tri(tail[k], tail[k + 1], Vector3(0.0, 0.02, 2.36), T)
	mk.mirror_x_since(start2)


static func _canopy(mk: MeshKit) -> void:
	# Half-ellipse sections sitting on the deck.
	var cz: float = g["canopy_z"]
	var zs := [-1.32 + cz, -1.15 + cz, -0.9 + cz, -0.6 + cz, -0.3 + cz, -0.05 + cz, 0.12 + cz, 0.22 + cz]
	var ws := [0.03, 0.17, 0.27, 0.32, 0.32, 0.28, 0.2, 0.06]
	var hs := [0.0, 0.11, 0.2, 0.26, 0.27, 0.23, 0.15, 0.03]
	var secs: Array[PackedVector3Array] = []
	for i in zs.size():
		var z: float = zs[i]
		var deck := lerpf(0.235, 0.33, clampf((z - cz + 1.4) / 1.5, 0.0, 1.0)) - 0.01
		var sec := PackedVector3Array()
		for k in 9:
			var a := PI * k / 8.0
			sec.append(Vector3(cos(a) * ws[i], deck + sin(a) * hs[i], z))
		secs.append(sec)
	mk.use("glass").loft(secs, Color.WHITE, false, false)
	# Frame: a spine bar and a rim along the base.
	mk.use("hull")
	for i in zs.size() - 1:
		var a: PackedVector3Array = secs[i]
		var b: PackedVector3Array = secs[i + 1]
		mk.beam(a[0] + Vector3(0.015, 0.0, 0), b[0] + Vector3(0.015, 0.0, 0), 0.04, 0.035, T)
		mk.beam(a[8] + Vector3(-0.015, 0.0, 0), b[8] + Vector3(-0.015, 0.0, 0), 0.04, 0.035, T)
	# Windscreen arch.
	var arch := PackedVector3Array()
	var sec2: PackedVector3Array = secs[2]
	for p in sec2:
		arch.append(p + Vector3(0, 0.008, 0))
	mk.tube(arch, PackedFloat32Array([0.012]), 5, T)


static func _sec_pod(z: float, hw: float, h: float, cx: float, cy: float) -> PackedVector3Array:
	var sec := PackedVector3Array()
	for k in 12:
		var a := TAU * k / 12.0
		var ca := cos(a)
		var sa := sin(a)
		# Superellipse (exponent 3): squarish industrial section.
		var x := signf(ca) * pow(absf(ca), 0.66) * hw
		var y := signf(sa) * pow(absf(sa), 0.66) * h
		sec.append(Vector3(cx + x, cy + y, z))
	return sec


static func _pod(mk: MeshKit) -> void:
	var cx: float = g["pod_x"]
	var cy: float = g["pod_y"]
	var ps: float = g["pod_scale"]
	var pl: float = g["pod_len"]
	var pz: float = g["pod_z"]
	var table := []
	for r: Array in [[-1.95, 0.02, 0.02], [-1.75, 0.1, 0.07], [-1.45, 0.17, 0.12], [-1.0, 0.23, 0.17], [-0.4, 0.26, 0.2],
			[0.4, 0.27, 0.21], [1.2, 0.27, 0.21], [1.9, 0.26, 0.2], [2.3, 0.23, 0.18], [2.45, 0.2, 0.16]]:
		table.append([float(r[0]) * pl + pz, float(r[1]) * ps, float(r[2]) * ps])
	var secs: Array[PackedVector3Array] = []
	var cols: Array[PackedColorArray] = []
	for z in _rows_with_cuts(table, [-1.5 * pl + pz, 1.6 * pl + pz]):
		var r := _table_at(table, z)
		var sec := _sec_pod(r[0], r[1], r[2], cx, cy)
		secs.append(sec)
		var cc := PackedColorArray()
		for k in 12:
			var p := sec[k]
			var c: Color
			var up := p.y - cy
			if up < -0.06:
				c = T
				c.a = 0.6
			elif p.x > cx + 0.12 and up < 0.1:
				c = S                       # outer flank stripe
			elif float(r[0]) < -1.5 * pl + pz or float(r[0]) > 1.6 * pl + pz:
				c = A if float(r[0]) < -1.5 * pl + pz else S   # accent tips, team-colour tails
			else:
				c = P
			cc.append(c)
		cols.append(cc)
	var start := mk.use("hull").group_vertex_count()
	mk.loft_colored(secs, cols, true, false)
	# Rear cap.
	var last := secs[secs.size() - 1]
	for k in 12:
		mk.tri(last[(k + 1) % 12], last[k], Vector3(cx, cy, float(g["pod_tail"]) + 0.01), T)
	# Vents: three dark slots on the outer flank.
	for v in 3:
		var z := (0.2 + v * 0.28) * pl + pz
		mk.box(Vector3(cx + 0.272 * ps, cy + 0.05, z), Vector3(0.02, 0.06, 0.18), T * 0.5)
	# Flux emitter housing under the pod.
	mk.box(Vector3(cx, cy - 0.215 * ps, 0.35 * pl + pz), Vector3(0.3 * ps, 0.05, 3.0 * pl), T * 0.8)
	mk.mirror_x_since(start)
	# Glowing flux emitters (separate material).
	var g0 := mk.use("flux_glow").group_vertex_count()
	mk.box(Vector3(cx, cy - 0.245 * ps, 0.35 * pl + pz), Vector3(0.18 * ps, 0.02, 2.7 * pl), Color.WHITE)
	mk.box(Vector3(0.0, -0.275, 0.6), Vector3(0.22, 0.02, 2.2), Color.WHITE)
	mk.mirror_x_since(g0)


static func _wings(mk: MeshKit) -> void:
	var start := mk.use("hull").group_vertex_count()
	var rx: float = g["root_x"]
	var tx: float = g["tip_x"]
	var pz: float = g["pod_z"]
	var ch: float = g["wing_chord"]
	var cx: float = g["pod_x"]
	var ps: float = g["pod_scale"]
	var hb: Vector3 = g["hinge_a"]
	# Swept wing from the fuselage chine to the pod; trailing edge on the airbrake hinge line.
	var r1 := Vector3(rx, 0.03, hb.z)
	var r0 := Vector3(rx, 0.03, hb.z - 2.07 * ch)
	var t1 := Vector3(tx, 0.0, hb.z + 0.22)
	var t0 := Vector3(tx, 0.0, t1.z - 1.69 * ch)
	var th := Vector3(0, 0.035, 0)
	if tx > rx + 0.05:
		mk.quad(r0 + th, t0 + th, t1 + th, r1 + th, P)            # top
		mk.quad(r1 - th, t1 - th, t0 - th, r0 - th, T * 0.7)      # bottom
		mk.quad(r0 - th, t0 - th, t0 + th, r0 + th, A)            # leading edge (accent)
		mk.quad(t1 - th, r1 - th, r1 + th, t1 + th, T)            # trailing edge
		mk.quad(r0 + th * 1.05, t0 + th * 1.05, t0.lerp(t1, 0.12) + th * 1.05, r0.lerp(r1, 0.1) + th * 1.05, A)
	if g["canards"]:
		var nz: float = g["fuse_len"]
		var c0 := Vector3(0.38, -0.02, -1.75 * nz)
		var c1 := Vector3(0.38, -0.02, -1.25 * nz)
		var c2 := Vector3(0.82, -0.08, -1.35 * nz)
		var c3 := Vector3(0.82, -0.08, -1.18 * nz)
		var ct := Vector3(0, 0.02, 0)
		mk.quad(c0 + ct, c2 + ct, c3 + ct, c1 + ct, S, Vector2.ONE, Vector2.ZERO, true)
		mk.quad(c0 - ct, c2 - ct, c2 + ct, c0 + ct, A, Vector2.ONE, Vector2.ZERO, true)
	var tail: float = g["pod_tail"]
	var fins: String = g["fins"]
	var fin_tops: Array = []
	if fins == "twin" or fins == "quad":
		# Fin on each pod, canted outwards.
		var cant := Basis(Vector3(0, 0, 1), -deg_to_rad(12.0 if fins == "twin" else 30.0))
		var hgt := 0.55 if fins == "twin" else 0.4
		var f0 := Vector3(cx, 0.1 * ps, tail - 1.3)
		var f1 := Vector3(cx, 0.1 * ps, tail - 0.03)
		var f2 := f0 + cant * Vector3(0, hgt, 0.62)
		var f3 := f1 + cant * Vector3(0, hgt, 0.12)
		_fin(mk, f0, f1, f2, f3)
		fin_tops.append([f2, f3])
		if fins == "quad":
			# Second, smaller fin pair under the pods, canted down.
			var dcant := Basis(Vector3(0, 0, 1), deg_to_rad(35.0))
			var u0 := Vector3(cx, -0.12 * ps, tail - 0.9)
			var u1 := Vector3(cx, -0.12 * ps, tail - 0.05)
			_fin(mk, u1, u0, u1 + dcant * Vector3(0, -0.3, 0.05), u0 + dcant * Vector3(0, -0.3, 0.35))
	elif fins == "center":
		# A single tall fin on the fuselage spine (built on the right, mirrored = thickness).
		var f0 := Vector3(0.025, 0.24, 1.0)
		var f1 := Vector3(0.025, 0.24, 2.35)
		var f2 := Vector3(0.025, 0.95, 1.85)
		var f3 := Vector3(0.025, 0.95, 2.45)
		mk.quad(f1, f3, f2, f0, S)
		mk.quad(f2, f3, f3 - Vector3(0.025, 0, 0), f2 - Vector3(0.025, 0, 0), A)
		fin_tops.append([Vector3(0.0, 0.95, 1.85), Vector3(0.0, 0.95, 2.45)])
	if g["aerofoil"]:
		var ah: float = g["aero_h"]
		var w0 := Vector3(0.0, ah, 2.0 + pz * 0.3)
		var w1 := Vector3(0.0, ah - 0.04, 2.42 + pz * 0.3)
		var w2: Vector3
		var w3: Vector3
		if fins == "twin" and not fin_tops.is_empty():
			var ft: Array = fin_tops[0]
			w2 = (ft[0] as Vector3).lerp(ft[1], 0.5) + Vector3(0.0, -0.02, -0.06)
			w3 = (ft[1] as Vector3) + Vector3(0.0, -0.03, 0.0)
		else:
			# Free-standing wing on struts.
			w2 = Vector3(cx + 0.1, ah + 0.02, 2.05 + pz * 0.3)
			w3 = Vector3(cx + 0.1, ah - 0.02, 2.45 + pz * 0.3)
			mk.beam(Vector3(cx * 0.55, 0.15, 2.2 + pz * 0.3), Vector3(cx * 0.55, ah, 2.2 + pz * 0.3), 0.06, 0.18, T)
		var wt := Vector3(0, 0.03, 0)
		mk.quad(w0 + wt, w2 + wt, w3 + wt, w1 + wt, P)
		mk.quad(w1 - wt, w3 - wt, w2 - wt, w0 - wt, T)
		mk.quad(w0 - wt, w2 - wt, w2 + wt, w0 + wt, A)
		mk.quad(w3 - wt, w1 - wt, w1 + wt, w3 + wt, T)
	# Side intake behind the cockpit.
	var fw: float = g["fuse_w"]
	mk.box(Vector3(0.7 * fw, 0.08, 0.25), Vector3(0.1, 0.16, 0.7), T * 0.6)
	mk.box(Vector3(0.74 * fw, 0.08, -0.08), Vector3(0.04, 0.12, 0.05), Color(0, 0, 0, 1))
	# Sensor blade on the spine (not with a centre fin).
	if fins != "center":
		mk.quad(Vector3(0.0, 0.33, 0.55), Vector3(0.0, 0.47, 0.85), Vector3(0.0, 0.47, 1.05), Vector3(0.0, 0.31, 1.15), S, Vector2.ONE, Vector2.ZERO, true)
	mk.mirror_x_since(start)
	# Engine rings.
	mk.use("metal_dark")
	var nozzles: Array = g["nozzles"]
	var radii: Array = g["nozzle_r"]
	for i in nozzles.size():
		var p: Vector3 = nozzles[i]
		var r: float = radii[i]
		mk.cyl(p - Vector3(0, 0, 0.32), p, r * 1.08, r, 14, Color.WHITE, false)
		mk.cyl(p - Vector3(0, 0, 0.02), p + Vector3(0, 0, 0.03), r * 0.98, r * 0.86, 14, Color(0.6, 0.6, 0.6), false)
	# Nav lights on the outermost tips.
	var nav := Vector3(cx + 0.11, 0.66, 2.36) if fins == "twin" else Vector3(cx + 0.15 * ps, 0.1, tail - 0.2)
	mk.use("nav_red").sphere(Vector3(-nav.x, nav.y, nav.z), Vector3(0.035, 0.035, 0.035), 4, 6, Color.WHITE)
	mk.use("nav_white").sphere(nav, Vector3(0.035, 0.035, 0.035), 4, 6, Color.WHITE)


static func _fin(mk: MeshKit, f0: Vector3, f1: Vector3, f2: Vector3, f3: Vector3) -> void:
	var ft := Vector3(0.025, 0, 0)
	mk.quad(f1 + ft, f3 + ft, f2 + ft, f0 + ft, S)
	mk.quad(f0 - ft, f2 - ft, f3 - ft, f1 - ft, S)
	mk.quad(f2 + ft, f3 + ft, f3 - ft, f2 - ft, A)
	mk.quad(f0 + ft, f2 + ft, f2 - ft, f0 - ft, S)


## The right airbrake flap in hinge space: hinge along +X at the origin, flap trailing towards +Z.
static func _flap_mesh(right: bool, hull_mat: Material) -> ArrayMesh:
	var mk := MeshKit.new()
	var a: Vector3 = g["hinge_a"]
	var b: Vector3 = g["hinge_b"]
	var span := b - a
	var len := span.length()
	var chord := 0.34
	var t := 0.025
	# Local: x along the hinge, z aft.
	var p0 := Vector3(0, 0, 0)
	var p1 := Vector3(len, 0, 0)
	var p2 := Vector3(len, 0, chord * 0.9)
	var p3 := Vector3(0, 0, chord)
	var th := Vector3(0, t, 0)
	mk.use("hull")
	mk.quad(p0 + th, p1 + th, p2 + th, p3 + th, S)
	mk.quad(p3 - th, p2 - th, p1 - th, p0 - th, T)
	mk.quad(p2 - th, p3 - th, p3 + th, p2 + th, A)
	mk.quad(p3 - th, p0 - th, p0 + th, p3 + th, T)
	mk.quad(p1 - th, p2 - th, p2 + th, p1 + th, T)
	# Inner face actuator glow strip (visible when deployed).
	mk.use("flux_glow").box(Vector3(len * 0.5, -t - 0.006, chord * 0.5), Vector3(len * 0.7, 0.008, 0.04), Color.WHITE)
	return mk.commit({"hull": hull_mat})


static func _plume_mesh(radius: float, length: float) -> ArrayMesh:
	var mk := MeshKit.new()
	mk.use("plume")
	# Cone along +Z: UV.y = 0 at the nozzle .. 1 at the tip.
	var sides := 12
	var rings := 6
	var base := mk.group_vertex_count()
	var secs: Array[PackedVector3Array] = []
	for j in rings + 1:
		var v := float(j) / rings
		var r := radius * lerpf(0.95, 0.15, pow(v, 0.8))
		var sec := PackedVector3Array()
		for k in sides + 1:
			var a := TAU * k / sides
			sec.append(Vector3(cos(a) * r, sin(a) * r, v * length))
		secs.append(sec)
	mk.loft(secs, Color.WHITE, false, false)
	# loft() writes UV (k/(cols-1), r/(rows-1)), which is exactly (around, along).
	return mk.commit()


static func _cockpit(parts: Parts, hull_mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Cockpit"
	var mk := MeshKit.new()
	var e: Vector3 = g["eye"]
	mk.use("cockpit")
	# Dashboard: a curved console in front of and below the eye.
	var dash_secs: Array[PackedVector3Array] = []
	for j in 3:
		var z := e.z - 0.62 + j * 0.16
		var y := e.y - 0.2 - j * 0.035
		var sec := PackedVector3Array()
		for k in 7:
			var a := lerpf(-0.95, 0.95, k / 6.0)
			sec.append(Vector3(sin(a) * 0.3, y + cos(a) * 0.05, z - cos(a) * 0.04))
		dash_secs.append(sec)
	mk.loft(dash_secs, Color(0.9, 0.9, 0.9), false, true)
	# Side consoles.
	for sx: float in [-1.0, 1.0]:
		mk.box(Vector3(sx * 0.29, e.y - 0.26, e.z - 0.1), Vector3(0.08, 0.1, 0.7), Color(0.8, 0.8, 0.8))
	# Seat headrest behind the eye (seen when looking around).
	mk.use("seat").box(Vector3(0, e.y - 0.05, e.z + 0.35), Vector3(0.36, 0.5, 0.12), Color.WHITE)
	# Inner canopy frame: arch bars and side rails, seen from inside.
	mk.use("carbon")
	for z: float in [e.z + 0.05]:
		var pts := PackedVector3Array()
		for k in 9:
			var a := PI * k / 8.0
			pts.append(Vector3(cos(a) * 0.3, e.y - 0.16 + sin(a) * 0.24, z))
		mk.tube(pts, PackedFloat32Array([0.014]), 5, Color.WHITE)
	for sx: float in [-1.0, 1.0]:
		mk.beam(Vector3(sx * 0.3, e.y - 0.16, e.z - 0.95), Vector3(sx * 0.31, e.y - 0.16, e.z + 0.3), 0.05, 0.05, Color.WHITE)
	var body := mk.instance("CockpitMesh")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	# Screens.
	var screen_mat := Mats.glow(Color(0.02, 0.06, 0.09), 1.0)
	for i in 3:
		var scr := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.17, 0.085) if i != 1 else Vector2(0.2, 0.1)
		scr.mesh = qm
		scr.material_override = screen_mat
		var x := (i - 1) * 0.19
		scr.position = Vector3(x, e.y - 0.155, e.z - 0.51 + absf(x) * 0.25)
		scr.rotation = Vector3(-deg_to_rad(28.0), -x * 1.2, 0.0)
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(scr)
	var lbl := Label3D.new()
	lbl.name = "Speed"
	lbl.font = load("res://assets/fonts/Orbitron.ttf")
	lbl.font_size = 64
	lbl.pixel_size = 0.0009
	lbl.modulate = Color(0.75, 0.95, 1.0)
	lbl.outline_size = 0
	lbl.shaded = false
	lbl.double_sided = false
	lbl.text = "000"
	lbl.position = Vector3(0, e.y - 0.152, e.z - 0.505)
	lbl.rotation = Vector3(-deg_to_rad(28.0), 0, 0)
	lbl.render_priority = 1
	root.add_child(lbl)
	parts.speed_label = lbl
	var info := lbl.duplicate() as Label3D
	info.name = "Info"
	info.font_size = 36
	info.text = "E 100"
	info.modulate = Color(1.0, 0.75, 0.4)
	info.position = Vector3(0.19, e.y - 0.152, e.z - 0.46)
	info.rotation = Vector3(-deg_to_rad(28.0), -0.23, 0)
	root.add_child(info)
	parts.info_label = info
	return root


## Builds a complete ship. `livery` = {primary, secondary, accent} colours.
static func build(livery: Dictionary, with_cockpit: bool = true, design: Dictionary = {}) -> Parts:
	g = _derive(design)
	var parts := Parts.new()
	parts.nozzles = g["nozzles"]
	parts.nozzle_r = g["nozzle_r"]
	parts.eye = g["eye"]
	var root := Node3D.new()
	root.name = "Model"
	parts.root = root
	var hull_mat := Mats.hull(livery.get("primary", Color(0.9, 0.92, 0.95)), livery.get("secondary", Color(0.06, 0.22, 0.72)), livery.get("accent", Color(1.0, 0.42, 0.08)))
	var mk := MeshKit.new()
	_fuselage(mk)
	_canopy(mk)
	_pod(mk)
	_wings(mk)
	var body := mk.instance("Body", {"hull": hull_mat})
	root.add_child(body)
	parts.body = body
	# Airbrake flaps on pivots at the hinge lines.
	for right: bool in [false, true]:
		var piv := Node3D.new()
		piv.name = "FlapR" if right else "FlapL"
		var a: Vector3 = g["hinge_a"]
		var b: Vector3 = g["hinge_b"]
		if not right:
			a.x = -a.x
			b.x = -b.x
		var x := (b - a).normalized()
		if not right:
			x = -x
		var z := Vector3(0, 0, 1).slide(x).normalized()
		var y := z.cross(x).normalized()
		piv.transform = Transform3D(Basis(x, y, z), a if right else b)
		var flap := MeshInstance3D.new()
		flap.mesh = _flap_mesh(right, hull_mat)
		piv.add_child(flap)
		root.add_child(piv)
		if right:
			parts.flap_r = piv
		else:
			parts.flap_l = piv
	# Plumes.
	var nozzles: Array = g["nozzles"]
	var nr: Array = g["nozzle_r"]
	for i in nozzles.size():
		var pl := MeshInstance3D.new()
		pl.name = "Plume%d" % i
		pl.mesh = _plume_mesh(float(nr[i]) * 0.9, 2.4 if i == 0 else 1.6)
		pl.position = nozzles[i]
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pl)
		parts.plumes.append(pl)
		var core := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(nr[i]) * 0.84
		disc.bottom_radius = float(nr[i]) * 0.84
		disc.height = 0.02
		disc.radial_segments = 14
		disc.rings = 1
		core.mesh = disc
		core.material_override = Mats.get_mat("engine_glow")
		core.rotation = Vector3(PI * 0.5, 0, 0)
		core.position = (nozzles[i] as Vector3) - Vector3(0, 0, 0.04)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(core)
		parts.glows.append(core)
	if with_cockpit:
		parts.cockpit = _cockpit(parts, hull_mat)
		parts.cockpit.visible = false
		root.add_child(parts.cockpit)
	return parts
