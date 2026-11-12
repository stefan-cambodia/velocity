## Graphics presets and adaptive resolution. Picks a preset for the device on
## first run, applies it to the viewport, and exposes the numbers the world
## builder and effects read (view distance, densities, which effects are on).
extends Node

signal applied

const NAMES: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
const PRESETS := [
	{"scale": 0.62, "msaa": 0, "shadows": 0, "shadow_dist": 0.0, "view": 0.6, "particles": 0.4, "glow": false, "post": false, "city": 0.5, "aniso": 0, "reflections": false},
	{"scale": 0.78, "msaa": 0, "shadows": 1, "shadow_dist": 40.0, "view": 0.8, "particles": 0.7, "glow": true, "post": false, "city": 0.75, "aniso": 2, "reflections": false},
	{"scale": 0.9, "msaa": 1, "shadows": 2, "shadow_dist": 60.0, "view": 1.0, "particles": 1.0, "glow": true, "post": true, "city": 1.0, "aniso": 4, "reflections": true},
	{"scale": 1.0, "msaa": 2, "shadows": 3, "shadow_dist": 90.0, "view": 1.3, "particles": 1.3, "glow": true, "post": true, "city": 1.25, "aniso": 8, "reflections": true},
]

var level: int = 2
var p: Dictionary = PRESETS[2]
var dynamic_scale: float = 1.0
var fps: float = 60.0

var _frame_avg: float = 1.0 / 60.0
var _cooldown: float = 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(_on_setting)
	apply()


func _on_setting(key: String) -> void:
	if key in ["preset", "fps_cap", "adaptive_res"]:
		apply()


## A guess at what the hardware can do, from the GPU name and core count.
func auto_level() -> int:
	if not OS.has_feature("mobile"):
		return 3
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return 0
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var cores := OS.get_processor_count()
	var score := 1
	for strong: String in ["adreno (tm) 7", "adreno (tm) 8", "mali-g7", "mali-g6", "mali-g9", "xclipse", "immortalis", "apple"]:
		if gpu.contains(strong):
			score = 2
	for top: String in ["adreno (tm) 74", "adreno (tm) 75", "adreno (tm) 8", "immortalis", "xclipse 9"]:
		if gpu.contains(top):
			score = 3
	if cores <= 4:
		score = mini(score, 0)
	elif cores <= 6:
		score = mini(score, 1)
	return score


func apply() -> void:
	var chosen: int = Settings.get_v("preset")
	level = auto_level() if chosen < 0 else clampi(chosen, 0, 3)
	p = PRESETS[level]
	dynamic_scale = 1.0
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][p["msaa"]]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = p["scale"]
	var an := {0: Viewport.ANISOTROPY_DISABLED, 2: Viewport.ANISOTROPY_2X, 4: Viewport.ANISOTROPY_4X, 8: Viewport.ANISOTROPY_8X}
	vp.anisotropic_filtering_level = an.get(int(p["aniso"]), Viewport.ANISOTROPY_2X)
	Engine.max_fps = int(Settings.get_v("fps_cap"))
	RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 2048, 4096][p["shadows"]], true)
	applied.emit()


func _process(delta: float) -> void:
	if delta <= 0.0 or delta > 0.5:
		return
	_frame_avg = lerpf(_frame_avg, delta, 0.05)
	fps = 1.0 / _frame_avg
	if not Settings.get_v("adaptive_res") or get_tree().paused:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var cap: int = Settings.get_v("fps_cap")
	var target := 1.0 / (float(cap) if cap > 0 else 60.0)
	var changed := false
	if _frame_avg > target * 1.12 and dynamic_scale > 0.62:
		dynamic_scale = maxf(dynamic_scale - 0.07, 0.62)
		changed = true
		_cooldown = 1.2
	elif _frame_avg < target * 1.03 and dynamic_scale < 1.0:
		dynamic_scale = minf(dynamic_scale + 0.03, 1.0)
		changed = true
		_cooldown = 2.5
	if changed:
		get_viewport().scaling_3d_scale = float(p["scale"]) * dynamic_scale
