## Race effects driven by simulation events: barrier sparks, landing dust,
## ship contact sparks, camera shake. Pooled one-shot particle emitters.
class_name RaceFx
extends Node3D

const POOL := 6

var race: Node
var _sparks: Array[GPUParticles3D] = []
var _next: int = 0


func setup(p_race: Node) -> void:
	race = p_race
	for k in POOL:
		var p := _make_sparks()
		add_child(p)
		_sparks.append(p)


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int(48 * float(Quality.p["particles"]))
	p.lifetime = 0.55
	p.explosiveness = 0.9
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -18, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = Color(1.0, 0.75, 0.35)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	grad.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.08, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Mats.tex("spark")
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(2.0, 1.6, 1.0)
	qm.material = mat
	p.draw_pass_1 = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func burst(at: Vector3, strength: float) -> void:
	if _sparks.is_empty():
		return
	var p := _sparks[_next]
	_next = (_next + 1) % _sparks.size()
	p.global_position = at
	p.amount_ratio = clampf(strength / 20.0, 0.25, 1.0)
	p.restart()


func contact(at: Vector3, strength: float) -> void:
	if strength > 2.0:
		burst(at, strength)


func tick(_dt: float) -> void:
	for sh: Ship in race.ships:
		var ph := sh.phys
		if ph.ev_wall > 3.0:
			burst(ph.ev_wall_point, ph.ev_wall)
			if sh.is_player:
				race.rig.shake(clampf(ph.ev_wall / 25.0, 0.2, 1.0))
		if sh.is_player and ph.ev_land > 4.0:
			race.rig.shake(clampf(ph.ev_land / 20.0, 0.1, 0.7))
