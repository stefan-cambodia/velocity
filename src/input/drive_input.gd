## Merges every input source into one ShipControls frame: keyboard, gamepad
## (analogue stick and triggers), touch controls and device tilt. The ship
## cannot tell them apart, and the AI writes the same structure.
##
## Keyboard: arrows/WASD steer + thrust, Down/S brake, Q/Z left airbrake,
## E/C right airbrake, Space fire, Shift boost... (see _ensure_actions).
## Gamepad: left stick steer, A thrust, B brake, LT/RT analogue airbrakes,
## X fire, Y camera, Start pause.
class_name DriveInput
extends RefCounted

const ACTIONS := {
	"steer_left": [KEY_LEFT, KEY_A],
	"steer_right": [KEY_RIGHT, KEY_D],
	"thrust": [KEY_UP, KEY_W],
	"brake": [KEY_DOWN, KEY_S],
	"ab_left": [KEY_Q, KEY_Z],
	"ab_right": [KEY_E, KEY_C],
	"fire": [KEY_SPACE],
	"camera": [KEY_V, KEY_TAB],
	"pause": [KEY_ESCAPE, KEY_P],
	"telemetry": [KEY_F3],
}
const PAD_BUTTONS := {
	"thrust": [JOY_BUTTON_A],
	"brake": [JOY_BUTTON_B],
	"fire": [JOY_BUTTON_X],
	"camera": [JOY_BUTTON_Y],
	"pause": [JOY_BUTTON_START],
	"ab_left": [JOY_BUTTON_LEFT_SHOULDER],
	"ab_right": [JOY_BUTTON_RIGHT_SHOULDER],
}

var out := ShipControls.new()
var touch: Node = null          ## TouchControls, when present.
var auto_thrust: bool = true

var _key_steer: float = 0.0     ## Ramped digital steering.
var _tilt_f: float = 0.0


static func ensure_actions() -> void:
	for a: String in ACTIONS:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.2)
		for k: int in ACTIONS[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
		for b: int in PAD_BUTTONS.get(a, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(a, jb)


static func gamepad_connected() -> bool:
	return Input.get_connected_joypads().size() > 0


## Raw device tilt (radians): the angle the screen's left-right axis makes with
## the horizon. Godot reports gravity in displayed-screen axes in landscape.
static func read_tilt_raw() -> float:
	var g := Input.get_gravity()
	if g.length_squared() < 1.0:
		g = Input.get_accelerometer()
	if g.length_squared() < 1.0:
		return 0.0
	return asin(clampf(g.x / g.length(), -1.0, 1.0))


func update(delta: float) -> ShipControls:
	auto_thrust = Settings.get_v("auto_thrust")
	var sens := Settings.f("steer_sens")
	var curve := Settings.f("steer_curve")
	# --- Keyboard (digital, ramped).
	var kdir := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if absf(kdir) > 0.01:
		var rate := 5.5 if signf(kdir) == signf(_key_steer) or absf(_key_steer) < 0.05 else 12.0
		_key_steer = move_toward(_key_steer, kdir, rate * delta)
	else:
		_key_steer = move_toward(_key_steer, 0.0, 9.0 * delta)
	var steer := _key_steer
	var thrust := Input.get_action_strength("thrust")
	var brake := Input.get_action_strength("brake")
	var ab_l := Input.get_action_strength("ab_left")
	var ab_r := Input.get_action_strength("ab_right")
	# --- Gamepad (analogue).
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var dev: int = pads[0]
		var sx := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
		if absf(sx) > 0.08:
			var a := (absf(sx) - 0.08) / 0.92
			steer += signf(sx) * _shape(a, curve) * Settings.f("pad_sens")
		ab_l = maxf(ab_l, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT))
		ab_r = maxf(ab_r, Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT))
	else:
		steer = signf(steer) * _shape(absf(steer), curve * 0.5)
	# --- Touch and tilt.
	if touch != null and touch.visible:
		var t: Dictionary = touch.call("state")
		steer += float(t.get("steer", 0.0))
		ab_l = maxf(ab_l, float(t.get("ab_l", 0.0)))
		ab_r = maxf(ab_r, float(t.get("ab_r", 0.0)))
		brake = maxf(brake, float(t.get("brake", 0.0)))
		if t.get("fire", false):
			out.fire = true
		if Settings.scheme() == Settings.S_TILT:
			steer += _tilt(delta)
	elif DevArgs.has("--fake-tilt"):
		steer += _tilt(delta)
	steer = clampf(steer * sens, -1.0, 1.0)
	if auto_thrust and brake < 0.5:
		thrust = 1.0
	if brake > 0.0:
		thrust = minf(thrust, 1.0 - brake)
		ab_l = maxf(ab_l, brake)
		ab_r = maxf(ab_r, brake)
	out.steer = steer
	out.thrust = thrust
	out.ab_l = ab_l
	out.ab_r = ab_r
	out.fire = out.fire or Input.is_action_just_pressed("fire")
	return out


func consume_fire() -> bool:
	var f := out.fire
	out.fire = false
	return f


func _tilt(delta: float) -> float:
	var raw := read_tilt_raw() - Settings.f("tilt_zero")
	_tilt_f = lerpf(_tilt_f, raw, 1.0 - exp(-delta * 25.0))
	var dead := Settings.f("tilt_dead")
	var mx := Settings.f("tilt_max") / maxf(Settings.f("tilt_sens"), 0.1)
	var a := clampf((absf(_tilt_f) - dead) / maxf(mx - dead, 0.05), 0.0, 1.0)
	return signf(_tilt_f) * _shape(a, Settings.f("steer_curve"))


## Progressive response: soft around the centre, full at the end of travel.
static func _shape(a: float, curve: float) -> float:
	return lerpf(a, a * a * a, clampf(curve, 0.0, 1.0) * 0.6) if a < 1.0 else 1.0
