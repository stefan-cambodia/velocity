## The coordinated speed effects around the player's camera:
## - streaks: short glowing dashes hanging in the air ahead of the camera; they
##   stand still in the world, so at speed they stream past with real parallax;
## - post pass: radial blur, chromatic aberration and vignette at the screen
##   edges, scaled by speed and boost (quality and setting gated);
## - energy trails from every ship's pods;
## - a light that sweeps over the hull when passing under gates and tunnel bars.
class_name SpeedFx
extends Node3D

const TRAIL_POINTS := 22

var race: Node
var streaks: GPUParticles3D
var post: MeshInstance3D
var post_mat: ShaderMaterial
var sweep: OmniLight3D
var _trails: Array = []          ## [{ship, mesh, hist: PackedVector3Array, side}]
var _trail_mat: Material
var _sweep_s: PackedFloat32Array = []   ## Lap distances of overhead lights.
var _amount: float = 0.0


func setup(p_race: Node) -> void:
	race = p_race
	_streaks()
	_post()
	_trail_setup()
	_sweep_setup()


func _streaks() -> void:
	streaks = GPUParticles3D.new()
	streaks.name = "Streaks"
	streaks.amount = int(90 * float(Quality.p["particles"]))
	streaks.lifetime = 0.9
	streaks.local_coords = false
	streaks.fixed_fps = 0
	streaks.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13.0, 40.0, 4.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	streaks.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 3.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Mats.tex("streak")
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.45)
	# Long axis along the direction of travel: the quad's Y axis is rotated to Z by the emitter basis.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = mat
	streaks.draw_pass_1 = qm
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pm.particle_flag_align_y = false
	add_child(streaks)


func _post() -> void:
	post = MeshInstance3D.new()
	post.name = "SpeedPost"
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	qm.flip_faces = false
	post.mesh = qm
	post_mat = Mats.shader_mat("speed_post")
	post.material_override = post_mat
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.sorting_offset = 1000.0
	add_child(post)


func _trail_setup() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_trail_mat = m
	for sh: Ship in race.ships:
		for side: float in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = ImmediateMesh.new()
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 200.0
			add_child(mi)
			var glow: Color = sh.team.get("glow", Color(0.3, 0.8, 1.0))
			_trails.append({"ship": sh, "mesh": mi, "hist": PackedVector3Array(), "side": side, "col": glow})


func _sweep_setup() -> void:
	sweep = OmniLight3D.new()
	sweep.name = "SweepLight"
	sweep.omni_range = 16.0
	sweep.light_energy = 0.0
	sweep.light_color = Color(0.5, 0.85, 1.0)
	sweep.shadow_enabled = false
	add_child(sweep)
	# Overhead light positions: gates (trackside) and tunnel bars, approximated from the track data.
	var td: TrackData = race.track
	var last := -1000.0
	for i in td.count:
		var s := i * td.step
		if td.flag_at_index(i, TrackData.F_TUNNEL):
			if s - last >= 8.0:
				_sweep_s.append(s)
				last = s
	for c in race.world.get_children():
		if c.name.begins_with("Trackside"):
			pass


func _process(delta: float) -> void:
	if race == null or race.player == null:
		return
	var cam: Camera3D = race.rig.cam
	var ph: ShipPhysics = race.player.phys
	var vt := clampf(ph.v_fwd / ph.spec.v_top, 0.0, 1.3)
	_amount = lerpf(_amount, vt, 1.0 - exp(-delta * 4.0))
	var cockpit: bool = race.rig.mode == CameraRig.Mode.COCKPIT
	# Streaks: an emission box ahead of the camera, oriented along the travel direction.
	var on: bool = Settings.get_v("speed_lines") and _amount > 0.45
	streaks.emitting = on
	if on:
		var fwd := ph.vel.normalized() if ph.speed > 5.0 else -cam.global_transform.basis.z
		var up := ph.up
		var right := fwd.cross(up).normalized()
		up = right.cross(fwd).normalized()
		# Quad Y axis along travel (fwd), its face towards the camera.
		var b := Basis(right, fwd, -up)
		streaks.global_transform = Transform3D(b, cam.global_position + fwd * 50.0 + up * 1.5)
		streaks.amount_ratio = clampf((_amount - 0.45) / 0.55, 0.15, 1.0)
	# Post pass.
	var post_on: bool = Quality.p["post"] and Settings.get_v("motion_blur")
	post.visible = post_on and _amount > 0.3
	if post.visible:
		post_mat.set_shader_parameter("amount", clampf((_amount - 0.3) / 0.8, 0.0, 1.0) * (0.6 if cockpit else 1.0))
		post_mat.set_shader_parameter("boost", 1.0 if ph.boost_t > 0.0 else 0.0)
		post_mat.set_shader_parameter("aberration", Settings.f("camera_motion"))
	_update_trails()
	_update_sweep(delta)


func _update_trails() -> void:
	var cam_pos: Vector3 = race.rig.cam.global_position
	for t: Dictionary in _trails:
		var sh: Ship = t["ship"]
		var mi: MeshInstance3D = t["mesh"]
		var hist: PackedVector3Array = t["hist"]
		var vx := sh.visual_transform()
		var nz: Vector3 = sh.parts.nozzles[1 if t["side"] > 0.0 else 2]
		var p := vx * (nz + Vector3(0, 0, 0.1))
		var spd := sh.phys.v_fwd
		hist.insert(0, p)
		# Keep about 11 m of trail whatever the frame rate.
		var length := 0.0
		var keep := hist.size()
		for k in range(1, hist.size()):
			length += hist[k].distance_to(hist[k - 1])
			if length > 11.0:
				keep = k + 1
				break
		if hist.size() > keep:
			hist.resize(keep)
		if hist.size() > TRAIL_POINTS:
			hist.resize(TRAIL_POINTS)
		t["hist"] = hist
		var im: ImmediateMesh = mi.mesh
		im.clear_surfaces()
		if hist.size() < 3 or spd < 25.0 or (sh.is_player and race.rig.mode == CameraRig.Mode.COCKPIT):
			continue
		var col: Color = t["col"]
		var strength := clampf((spd - 25.0) / 60.0, 0.0, 1.0) * (1.5 if sh.phys.boost_t > 0.0 else 1.0)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for k in hist.size():
			var a := hist[k]
			var dir := (hist[maxi(k - 1, 0)] - hist[mini(k + 1, hist.size() - 1)]).normalized()
			var to_cam := cam_pos - a
			var near_fade := clampf((to_cam.length() - 4.0) / 6.0, 0.0, 1.0)
			var side := dir.cross(to_cam.normalized()).normalized()
			var f := 1.0 - float(k) / (hist.size() - 1)
			var w := 0.09 * f + 0.015
			var c := Color(col.r, col.g, col.b, f * f * 0.5 * strength * near_fade)
			im.surface_set_color(c)
			im.surface_add_vertex(a + side * w)
			im.surface_set_color(c)
			im.surface_add_vertex(a - side * w)
		im.surface_end()


func _update_sweep(delta: float) -> void:
	var ph: ShipPhysics = race.player.phys
	var td: TrackData = race.track
	var s := ph.hit.s
	var best := INF
	var best_s := 0.0
	# Tunnel bars (dense) and gate-like overhead lights.
	if td.flag_at_index(ph.hit.i, TrackData.F_TUNNEL) and int(Quality.level) >= 2:
		var q := fmod(s, 8.0)
		best = minf(q, 8.0 - q)
		best_s = s - q if q < 4.0 else s + 8.0 - q
		var hit := TrackData.Hit.new()
		td.frame_at(best_s, hit)
		sweep.global_position = hit.c + hit.N * (td.ceiling[hit.i] - 1.0)
		sweep.light_color = Color(0.85, 0.92, 1.0)
		sweep.light_energy = 2.2 * clampf(1.0 - best / 4.0, 0.0, 1.0)
		sweep.omni_range = 12.0
	else:
		sweep.light_energy = move_toward(sweep.light_energy, 0.0, delta * 8.0)
