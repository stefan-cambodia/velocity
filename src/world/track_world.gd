## Builds everything around the racing surface for a track: environment
## (sky, fog, glow, light), the track mesh and the scenery for its theme.
class_name TrackWorld
extends RefCounted


static func build(track_id: String, td: TrackData, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "World"
	parent.add_child(root)
	var theme := "testbed"
	match track_id:
		"helix_bay":
			theme = "helix_bay"
		"glacier_ring":
			theme = "glacier"
		"atacama_spaceport":
			theme = "spaceport"
		"lagrange_station":
			theme = "orbital"
		"serra_verde":
			theme = "rainforest"
		"forge_caldera":
			theme = "forge"
		"costa_branca":
			theme = "coastal"
		"cirrus_heights":
			theme = "skyport"
		"tempest_shoals":
			theme = "offshore"
		"thalassa_deep":
			theme = "abyssal"
	_environment(theme, root)
	# The track material is shared between races; themes that want rain set it again.
	(Mats.get_mat("track") as ShaderMaterial).set_shader_parameter("wetness", 0.0)
	var tracknode := Node3D.new()
	tracknode.name = "Track"
	root.add_child(tracknode)
	TrackMesh.build(td, tracknode)
	match theme:
		"helix_bay":
			HelixBay.build(td, root)
		"glacier":
			Glacier.build(td, root)
		"spaceport":
			Spaceport.build(td, root)
		"orbital":
			Orbital.build(td, root)
		"rainforest":
			Rainforest.build(td, root)
		"forge":
			Forge.build(td, root)
		"coastal":
			Coastal.build(td, root)
		"skyport":
			Skyport.build(td, root)
		"offshore":
			Offshore.build(td, root)
		"abyssal":
			Abyssal.build(td, root)
		_:
			_testbed(td, root)
	return root


static func _environment(theme: String, root: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.05, 0.08, 0.2)
	sm.sky_horizon_color = Color(0.85, 0.45, 0.35)
	sm.ground_horizon_color = Color(0.3, 0.2, 0.25)
	sm.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sm.sun_angle_max = 8.0
	sm.sky_curve = 0.12
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = Quality.p["glow"]
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.55, 0.38, 0.4)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-22.0), deg_to_rad(-140.0), 0.0)
	sun.light_color = Color(1.0, 0.78, 0.6)
	sun.light_energy = 1.3
	sun.shadow_enabled = int(Quality.p["shadows"]) > 0
	sun.directional_shadow_max_distance = float(Quality.p["shadow_dist"])
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	root.add_child(sun)


static func _testbed(td: TrackData, root: Node3D) -> void:
	# Floor.
	var lo := INF
	for i in range(0, td.count, 10):
		lo = minf(lo, td.pos[i].y)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	floor_mi.mesh = pm
	var c := Vector3.ZERO
	for i in range(0, td.count, 10):
		c += td.pos[i]
	c /= float(td.count / 10 + (1 if td.count % 10 else 0))
	floor_mi.position = Vector3(c.x, lo - 14.0, c.z)
	floor_mi.material_override = Mats.shader_mat("ground_grid")
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_mi)
	# Support pylons every 60 m.
	var mk := MeshKit.new()
	mk.use("concrete")
	var i := 0
	while i < td.count:
		if not td.flag_at_index(i, TrackData.F_GAP):
			var top := td.pos[i] - td.nrm[i] * TrackMesh.DECK
			var bottom := Vector3(top.x, lo - 14.0, top.z)
			if top.y - bottom.y > 2.0:
				mk.box(Vector3(top.x, (top.y + bottom.y) * 0.5, top.z), Vector3(2.2, top.y - bottom.y, 2.2), Color(0.8, 0.8, 0.85), 0.5, 0.25)
		i += 60
	var pyl := mk.instance("Pylons")
	root.add_child(pyl)
