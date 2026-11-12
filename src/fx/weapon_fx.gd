## Draws the weapon system: plasma bolts, missiles, shockwave walls, mines,
## shield bubbles, EMP rings and explosion flashes. Reads WeaponSystem state
## every frame; pooled meshes, no per-frame allocation of nodes in steady state.
class_name WeaponFx
extends Node3D

var race: Node
var weapons: WeaponSystem
var _pool: Dictionary = {}       ## kind -> Array[MeshInstance3D]
var _bubbles: Dictionary = {}    ## Ship -> MeshInstance3D
var _rings: Array = []           ## [{node, t}]
var _flash: OmniLight3D
var _flash_t: float = 0.0
var _mats: Dictionary = {}


func setup(p_race: Node, p_weapons: WeaponSystem) -> void:
	race = p_race
	weapons = p_weapons
	_mats["plasma"] = Mats.glow(Color(0.35, 0.9, 1.0), 6.0)
	_mats["missile"] = Mats.glow(Color(1.0, 0.45, 0.1), 5.0)
	_mats["mine"] = Mats.glow(Color(1.0, 0.1, 0.25), 5.0)
	_mats["shock"] = Mats.shader_mat("shield_bubble", {"color": Color(1.0, 0.55, 0.2)})
	_mats["emp"] = Mats.glow(Color(0.55, 0.6, 1.0), 4.0)
	_flash = OmniLight3D.new()
	_flash.omni_range = 30.0
	_flash.light_color = Color(1.0, 0.6, 0.3)
	_flash.light_energy = 0.0
	add_child(_flash)


func _mesh(kind: String) -> Mesh:
	match kind:
		"plasma":
			var m := CapsuleMesh.new()
			m.radius = 0.28
			m.height = 2.4
			m.radial_segments = 8
			m.rings = 2
			return m
		"missile":
			var c := CapsuleMesh.new()
			c.radius = 0.22
			c.height = 1.4
			c.radial_segments = 8
			c.rings = 2
			return c
		"mine":
			var sm := SphereMesh.new()
			sm.radius = 0.7
			sm.height = 1.4
			sm.radial_segments = 10
			sm.rings = 5
			return sm
		"shock":
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			return q
	return BoxMesh.new()


func _take(kind: String, i: int) -> MeshInstance3D:
	if not _pool.has(kind):
		_pool[kind] = []
	var arr: Array = _pool[kind]
	while arr.size() <= i:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(kind)
		mi.material_override = _mats[kind]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		arr.append(mi)
	var node: MeshInstance3D = arr[i]
	node.visible = true
	return node


func _hide_from(kind: String, i: int) -> void:
	if not _pool.has(kind):
		return
	var arr: Array = _pool[kind]
	for k in range(i, arr.size()):
		(arr[k] as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	if weapons == null:
		return
	var td := weapons.track
	var counts := {"plasma": 0, "missile": 0, "shock": 0, "mine": 0}
	var hit := TrackData.Hit.new()
	for p in weapons.projectiles:
		td.frame_at(p.s, hit)
		var pos := hit.c + hit.B * p.d + hit.N * p.h
		var basis := Basis(hit.B, hit.N, -hit.T)
		if p.kind == "shockwave":
			var mi := _take("shock", counts["shock"])
			counts["shock"] += 1
			var w := hit.half_l + hit.half_r
			mi.transform = Transform3D(basis.scaled(Vector3(w, 5.0, 1.0)), hit.c + hit.B * (hit.half_r - hit.half_l) * 0.5 + hit.N * 2.5)
			mi.set_instance_shader_parameter("strength", clampf(1.0 - p.travelled / 230.0, 0.0, 1.0) * 1.5)
		else:
			var kind := p.kind
			var mi := _take(kind, counts[kind])
			counts[kind] += 1
			# Capsules are Y-aligned: rotate so the long axis runs along the track.
			mi.transform = Transform3D(Basis(hit.B, -hit.T, hit.N), pos)
	for m in weapons.mines:
		td.frame_at(m.s, hit)
		var mi := _take("mine", counts["mine"])
		counts["mine"] += 1
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.012)
		mi.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * pulse), hit.c + hit.B * m.d + hit.N * 0.8)
	for k: String in counts:
		_hide_from(k, counts[k])
	# Shield bubbles.
	for sh: Ship in race.ships:
		var on := sh.phys.shield_t > 0.0
		if on and not _bubbles.has(sh):
			var b := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 20
			sm.rings = 10
			b.mesh = sm
			b.material_override = Mats.shader_mat("shield_bubble")
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(b)
			_bubbles[sh] = b
		if _bubbles.has(sh):
			var b: MeshInstance3D = _bubbles[sh]
			b.visible = on
			if on:
				b.global_transform = sh.visual_transform() * Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, 1.1, 3.6)), Vector3.ZERO)
				b.set_instance_shader_parameter("strength", clampf(sh.phys.shield_t, 0.0, 1.0))
	# EMP rings and the explosion flash.
	var keep := []
	for r: Dictionary in _rings:
		r["t"] = float(r["t"]) + delta
		var node: MeshInstance3D = r["node"]
		var k := float(r["t"]) / 0.5
		if k >= 1.0:
			node.queue_free()
			continue
		node.scale = Vector3.ONE * lerpf(2.0, float(WeaponSystem.EMP["radius"]), k)
		node.set_instance_shader_parameter("strength", (1.0 - k) * 1.4)
		keep.append(r)
	_rings = keep
	_flash_t = maxf(0.0, _flash_t - delta * 4.0)
	_flash.light_energy = _flash_t * 6.0


## Event from the race (pickups, fire, hits).
func on_event(e: Dictionary) -> void:
	match e["type"]:
		"fire":
			if e["kind"] == "emp":
				var sm := SphereMesh.new()
				sm.radius = 1.0
				sm.height = 2.0
				sm.radial_segments = 24
				sm.rings = 12
				var node := MeshInstance3D.new()
				node.mesh = sm
				node.material_override = Mats.shader_mat("shield_bubble", {"color": Color(0.55, 0.55, 1.0)})
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(node)
				node.global_position = e["pos"]
				_rings.append({"node": node, "t": 0.0})
		"hit":
			_flash.global_position = e["pos"]
			_flash_t = 1.0
			if race.fx:
				race.fx.burst(e["pos"], 25.0)
