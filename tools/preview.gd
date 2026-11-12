## Renders a ship model from several angles into one PNG (needs a display; not headless).
##   godot --path . -s tools/preview.gd -- out.png [team_id] [--cockpit]
extends SceneTree

var _out := "/tmp/ship.png"
var _team := "halden"
var _cockpit := false
var _lineup := false
var _shots: Array[Image] = []
var _cam: Camera3D
var _views := [
	[Vector3(5.5, 2.2, -6.5), Vector3(0, 0, 0)],      # front three-quarter
	[Vector3(-6.0, 1.6, 5.5), Vector3(0, 0, 0.3)],    # rear three-quarter
	[Vector3(0.0, 9.0, 0.01), Vector3(0, 0, 0)],      # top
	[Vector3(7.5, 0.25, 0.0), Vector3(0, 0, 0)],      # side
	[Vector3(0.0, 0.9, 7.5), Vector3(0, 0.1, 0)],     # rear
	[Vector3(3.5, -2.2, -4.0), Vector3(0, 0, 0)],     # underside
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--cockpit":
			_cockpit = true
		elif a == "--lineup":
			_lineup = true
		elif a.ends_with(".png"):
			_out = a
		else:
			_team = a
	root.size = Vector2i(800, 450)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-140), 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.6, 0.75, 1.0)
	root.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.position = Vector3(0, -1.05, 0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.21, 0.24)
	fm.roughness = 0.3
	fm.metallic = 0.2
	floor_mi.material_override = fm
	root.add_child(floor_mi)
	if _lineup:
		root.size = Vector2i(1600, 900)
		floor_mi.scale = Vector3(4, 1, 4)
		var ids := Catalog.team_ids()
		for k in ids.size():
			var t := Catalog.team(ids[k])
			var pp := ShipModel.build(t.get("livery", {}), false, t.get("design", {}))
			pp.root.position = Vector3((k % 4) * 4.2 - 6.3, 0, (k / 4) * 7.5 - 3.0)
			pp.root.rotation.y = deg_to_rad(-25.0)
			root.add_child(pp.root)
			for pl in pp.plumes:
				pl.set_instance_shader_parameter("thrust", 0.7)
			var lbl := Label3D.new()
			lbl.text = t["short"]
			lbl.font = load("res://assets/fonts/Orbitron.ttf")
			lbl.font_size = 48
			lbl.pixel_size = 0.006
			lbl.position = pp.root.position + Vector3(0, 1.4, -1.0)
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			root.add_child(lbl)
		_cam = Camera3D.new()
		_cam.fov = 45.0
		root.add_child(_cam)
		_views = [[Vector3(6.0, 9.5, -14.0), Vector3(0.0, 0, 0.5)]]
		_run()
		return
	var team := Catalog.team(_team)
	var parts := ShipModel.build(team.get("livery", {}), true, team.get("design", {}))
	root.add_child(parts.root)
	for pl in parts.plumes:
		pl.set_instance_shader_parameter("thrust", 1.0)
	if _cockpit:
		parts.cockpit.visible = true
		_views = [[parts.eye, parts.eye + Vector3(0, -0.12, -1.0)], [parts.eye + Vector3(0, 0.05, 0.1), parts.eye + Vector3(0.4, -0.3, -1.0)]]
	# Deploy the right airbrake halfway so the flap can be checked.
	parts.flap_r.transform.basis = parts.flap_r.transform.basis * Basis(Vector3.RIGHT, -deg_to_rad(50))
	_cam = Camera3D.new()
	_cam.fov = 40.0 if not _cockpit else 75.0
	_cam.near = 0.05
	root.add_child(_cam)
	print("triangles: ", _count(parts.root))
	_run()


func _count(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			if arr[Mesh.ARRAY_INDEX] != null:
				t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for c in n.get_children():
		t += _count(c)
	return t


func _run() -> void:
	for v: Array in _views:
		_cam.look_at_from_position(v[0], v[1], Vector3.UP if absf((v[1] - v[0]).normalized().y) < 0.99 else Vector3.FORWARD)
		for k in 6:
			await process_frame
		_shots.append(root.get_texture().get_image())
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var cols := 2 if _shots.size() > 1 else 1
	var rows := int(ceil(_shots.size() / float(cols)))
	var sheet := Image.create(w * cols, h * rows, false, _shots[0].get_format())
	for i in _shots.size():
		sheet.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(_out)
	print("saved ", _out)
	quit()
