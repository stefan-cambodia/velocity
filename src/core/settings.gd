## Player preferences, saved to user://settings.cfg. Read with Settings.get_v()
## or Settings.f(), write with Settings.set_v(); listeners get `changed(key)`.
extends Node

signal changed(key: String)

const PATH := "user://settings.cfg"
## Steering schemes. All feed the same ShipControls (see DriveInput).
const SCHEMES: PackedStringArray = ["Tilt", "Touch buttons", "Touch slider"]
const S_TILT := 0
const S_BUTTONS := 1
const S_SLIDER := 2

const DEFAULTS := {
	# Controls
	"scheme": 1,
	"scheme_chosen": false,       # until the player picks: tilt on phones with a sensor, buttons otherwise
	"steer_sens": 1.0,            # 0.5 .. 1.6
	"steer_curve": 0.45,          # 0 linear .. 1 very soft around the centre
	"tilt_sens": 1.0,
	"tilt_zero": 0.0,             # calibration offset (radians)
	"tilt_dead": 0.03,            # dead zone (radians)
	"tilt_max": 0.42,             # tilt for full lock (radians, ~24 degrees)
	"auto_thrust": true,          # thrust held automatically (release with the brake button)
	"steer_assist": 1,            # 0 off, 1 low, 2 high
	"haptics": true,
	"ctrl_opacity": 0.6,
	"ctrl_scale": 1.0,
	"layout": {},                 # control id -> [x, y, scale] in viewport fractions
	"pad_sens": 1.0,              # gamepad stick sensitivity
	# Camera
	"camera": 0,                  # 0 standard chase, 1 wide, 2 close, 3 cockpit
	"camera_motion": 1.0,         # 0 .. 1.5: shake, roll and FOV kick
	"show_telemetry": false,
	# Audio
	"vol_master": 0.9,
	"vol_music": 0.75,
	"vol_sfx": 0.9,
	"vol_engine": 0.7,
	# Graphics
	"preset": -1,                 # -1 auto, 0 low .. 3 ultra
	"adaptive_res": true,
	"fps_cap": 60,
	"show_fps": false,
	"motion_blur": true,
	"speed_lines": true,
	# Game
	"speed_class": 1,
	"laps": 3,
	"difficulty": 1,              # 0 rookie, 1 pro, 2 elite
	"team": "halden",
	"track": "helix_bay",
}

var _v: Dictionary = {}
var _path: String = PATH


func _ready() -> void:
	if DevArgs.has("--autopilot") or DevArgs.has("--test-save"):
		_path = "user://test_settings.cfg"
	_v = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(_path) == OK:
		for key: String in DEFAULTS:
			if cfg.has_section_key("s", key):
				var val: Variant = cfg.get_value("s", key)
				if typeof(val) == typeof(DEFAULTS[key]) or (val is int and DEFAULTS[key] is float) or (val is float and DEFAULTS[key] is int):
					_v[key] = val


func scheme() -> int:
	if _v["scheme_chosen"]:
		return clampi(int(_v["scheme"]), 0, SCHEMES.size() - 1)
	return S_TILT if has_motion_sensor() else S_BUTTONS


func set_scheme(i: int) -> void:
	_v["scheme_chosen"] = true
	set_v("scheme", i)


static func has_motion_sensor() -> bool:
	if DevArgs.has("--fake-tilt"):
		return true
	return Input.get_gravity().length_squared() > 1.0 or Input.get_accelerometer().length_squared() > 1.0


func get_v(key: String) -> Variant:
	return _v[key]


func f(key: String) -> float:
	return float(_v[key])


func set_v(key: String, value: Variant) -> void:
	if _v.get(key) == value and not (value is Dictionary):
		return
	_v[key] = value
	changed.emit(key)
	_save()


func reset(keys: PackedStringArray) -> void:
	for k in keys:
		_v[k] = DEFAULTS[k].duplicate(true) if DEFAULTS[k] is Dictionary else DEFAULTS[k]
		changed.emit(k)
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _v:
		cfg.set_value("s", key, _v[key])
	cfg.save(_path)
