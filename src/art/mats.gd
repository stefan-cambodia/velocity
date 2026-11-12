## Shared material library. Procedural meshes name their materials by key and
## every user gets the same instance, so draw calls batch and shaders compile once.
class_name Mats
extends RefCounted

const TEX := "res://assets/textures/"
const SHD := "res://assets/shaders/"
static var _mats: Dictionary = {}
static var _tex: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(TEX + name + ".png")
	return _tex[name]


static func get_mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := _make(key)
	_mats[key] = m
	return m


static func shader_mat(shader: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHD + shader + ".gdshader")
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _std(col: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## Livery material for a team (see Catalog for the colours).
static func hull(primary: Color, secondary: Color, accent: Color) -> ShaderMaterial:
	return shader_mat("ship_hull", {"primary": primary, "secondary": secondary, "accent": accent})


static func glow(color: Color, energy: float = 3.0) -> ShaderMaterial:
	return shader_mat("ship_glow", {"color": color, "energy": energy})


static func _make(key: String) -> Material:
	if key.begins_with("logo_"):
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		lm.alpha_scissor_threshold = 0.4
		lm.albedo_texture = tex(key)
		lm.albedo_color = Color(1.4, 1.4, 1.4)
		lm.cull_mode = BaseMaterial3D.CULL_BACK
		return lm
	match key:
		"default": return _std(Color.WHITE, 0.7)
		"carbon": return _std(Color(0.05, 0.052, 0.06), 0.42, 0.3)
		"metal": return _std(Color(0.42, 0.44, 0.48), 0.32, 0.9)
		"metal_dark": return _std(Color(0.12, 0.125, 0.14), 0.4, 0.85)
		"chrome": return _std(Color(0.8, 0.82, 0.85), 0.1, 1.0)
		"glass":
			var g := _std(Color(0.03, 0.05, 0.08), 0.04, 0.2)
			g.metallic_specular = 1.0
			g.rim_enabled = true
			g.rim = 0.4
			g.rim_tint = 0.2
			return g
		"cockpit": return _std(Color(0.07, 0.075, 0.085), 0.55, 0.2)
		"seat": return _std(Color(0.1, 0.1, 0.11), 0.8)
		"engine_glow": return glow(Color(1.0, 0.5, 0.18), 4.0)
		"flux_glow": return glow(Color(0.3, 0.85, 1.0), 3.0)
		"nav_red": return glow(Color(1.0, 0.08, 0.05), 5.0)
		"nav_white": return glow(Color(1.0, 1.0, 1.0), 5.0)
		"plume": return shader_mat("engine_plume")
		"track":
			return shader_mat("track_surface", {"albedo_tex": tex("track_albedo"), "normal_tex": tex("track_normal")})
		"barrier":
			return shader_mat("barrier", {"albedo_tex": tex("panel_albedo"), "normal_tex": tex("panel_normal")})
		"deck":
			var d := _std(Color(0.3, 0.31, 0.34), 0.6, 0.5)
			d.albedo_texture = tex("panel_albedo")
			d.uv1_scale = Vector3(0.25, 0.25, 0.25)
			d.normal_enabled = true
			d.normal_texture = tex("panel_normal")
			return d
		"concrete":
			var c := _std(Color(0.42, 0.42, 0.44), 0.85, 0.0)
			c.albedo_texture = tex("panel_albedo")
			c.uv1_scale = Vector3(0.12, 0.12, 0.12)
			return c
		"bld": return shader_mat("building", {"windows_tex": tex("windows")})
		"bld_dense": return shader_mat("building", {"lit_fraction": 0.5, "window_energy": 1.9, "windows_tex": tex("windows")})
		"neon_cyan": return glow(Color(0.25, 0.85, 1.0), 3.5)
		"neon_magenta": return glow(Color(1.0, 0.2, 0.75), 3.5)
		"neon_amber": return glow(Color(1.0, 0.6, 0.15), 3.5)
		"neon_white": return glow(Color(0.9, 0.95, 1.0), 4.0)
		"warn_red": return glow(Color(1.0, 0.05, 0.03), 6.0)
		"lamp": return glow(Color(1.0, 0.85, 0.65), 5.0)
		"paint_yellow": return _std(Color(0.95, 0.68, 0.08), 0.45, 0.3)
		"container": return _std(Color(1, 1, 1), 0.6, 0.4)
		"rock": return _std(Color(0.09, 0.1, 0.14), 0.95, 0.0)
		"pad_boost":
			return shader_mat("pad", {"color": Color(0.2, 0.75, 1.0)})
		"pad_weapon":
			return shader_mat("pad", {"color": Color(1.0, 0.3, 0.75)})
	push_warning("Mats: unknown key " + key)
	return _std(Color.MAGENTA, 0.5)
