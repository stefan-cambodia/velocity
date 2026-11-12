## On-screen racing controls. Every finger is tracked separately, so steering,
## both airbrakes and fire can be held in any combination.
##
## Schemes (Settings.scheme()):
##   Tilt     device tilt steers; left/right thumbs hold the two airbrakes
##            (both together = brake); fire above the right thumb.
##   Buttons  left thumb: steer left / right (ramped: a tap is a correction,
##            a hold winds on full lock in 0.22 s); right thumb: airbrakes.
##   Slider   left thumb: a floating horizontal pad, analogue steering from
##            how far the finger moves from where it landed; right thumb: airbrakes.
## Thrust is automatic unless turned off in the settings (then a thrust pad
## appears). Layout: per-control position and size in viewport fractions,
## overridable from Settings "layout".
extends CanvasLayer

const C_IDLE := Color(0.85, 0.92, 1.0)
const C_ACC := Color(0.3, 0.85, 1.0)

## id -> [centre x, centre y, radius] in viewport fractions (radius in height fractions).
const LAYOUTS := {
	0: {"ab_l": [0.075, 0.70, 0.13], "ab_r": [0.925, 0.70, 0.13], "fire": [0.9, 0.42, 0.085]},
	1: {"left": [0.075, 0.8, 0.12], "right": [0.215, 0.8, 0.12], "ab_l": [0.785, 0.8, 0.12], "ab_r": [0.925, 0.8, 0.12], "fire": [0.925, 0.52, 0.085]},
	2: {"slider": [0.15, 0.8, 0.14], "ab_l": [0.785, 0.8, 0.12], "ab_r": [0.925, 0.8, 0.12], "fire": [0.925, 0.52, 0.085]},
}
const THRUST_POS := [0.5, 0.86, 0.1]

var root: Control
var _fingers: Dictionary = {}      ## index -> {id, start: Vector2, pos: Vector2}
var _steer_btn: float = 0.0
var _slider: float = 0.0
var _fire_edge: bool = false
var _pressed: Dictionary = {}       ## id -> bool
var _font: Font
var paused_cb: Callable
var camera_cb: Callable


func _ready() -> void:
	layer = 20
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_controls)
	_font = load("res://assets/fonts/Rajdhani-Bold.ttf")


## Current control state for DriveInput.
func state() -> Dictionary:
	var scheme := Settings.scheme()
	var steer := 0.0
	if scheme == Settings.S_BUTTONS:
		steer = _steer_btn
	elif scheme == Settings.S_SLIDER:
		steer = _slider
	var f := _fire_edge
	_fire_edge = false
	var thrust_off: bool = not Settings.get_v("auto_thrust") and not _pressed.get("thrust", false)
	return {"steer": steer, "ab_l": 1.0 if _pressed.get("ab_l", false) else 0.0, "ab_r": 1.0 if _pressed.get("ab_r", false) else 0.0,
		"fire": f, "brake": 1.0 if thrust_off else 0.0}


func _layout() -> Dictionary:
	var lay: Dictionary = LAYOUTS[Settings.scheme()].duplicate(true)
	if not Settings.get_v("auto_thrust"):
		lay["thrust"] = THRUST_POS.duplicate()
	var custom: Dictionary = Settings.get_v("layout")
	var scale := Settings.f("ctrl_scale")
	for id: String in lay:
		var key := "%d/%s" % [Settings.scheme(), id]
		if custom.has(key):
			lay[id] = custom[key]
		var v: Array = lay[id]
		lay[id] = [float(v[0]), float(v[1]), float(v[2]) * scale]
	return lay


func _hit(pos: Vector2) -> String:
	var vs := root.size
	var lay := _layout()
	var best := ""
	var best_d := INF
	for id: String in lay:
		var v: Array = lay[id]
		var c := Vector2(v[0] * vs.x, v[1] * vs.y)
		var r: float = v[2] * vs.y * (1.35 if id != "slider" else 1.6)
		var d := pos.distance_to(c)
		if d < r and d < best_d:
			best = id
			best_d = d
	# Generous zones: anywhere in the lower-left / lower-right quarter counts for the nearest thumb control.
	if best == "":
		if pos.y > vs.y * 0.5:
			if pos.x < vs.x * 0.33:
				best = "slider" if lay.has("slider") else ("ab_l" if Settings.scheme() == Settings.S_TILT else "")
			elif pos.x > vs.x * 0.67:
				best = "ab_r"
	return best


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			var vs := root.size
			# Top strip: pause and camera.
			if t.position.y < vs.y * 0.12 and absf(t.position.x - vs.x * 0.5) < vs.x * 0.07:
				if paused_cb.is_valid():
					paused_cb.call()
				return
			if t.position.y < vs.y * 0.12 and absf(t.position.x - vs.x * 0.62) < vs.x * 0.05:
				if camera_cb.is_valid():
					camera_cb.call()
				return
			var id := _hit(t.position)
			if id == "":
				return
			_fingers[t.index] = {"id": id, "start": t.position, "pos": t.position}
			if id == "fire":
				_fire_edge = true
			if Settings.get_v("haptics"):
				Input.vibrate_handheld(12)
		else:
			_fingers.erase(t.index)
		_refresh()
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		if _fingers.has(d.index):
			var f: Dictionary = _fingers[d.index]
			f["pos"] = d.position
			# A finger that slides from one airbrake to the other changes brake.
			if f["id"] in ["ab_l", "ab_r", "left", "right"]:
				var id := _hit(d.position)
				if id in ["ab_l", "ab_r", "left", "right"] and id != f["id"]:
					f["id"] = id
			_refresh()


func _refresh() -> void:
	_pressed.clear()
	for idx: int in _fingers:
		var f: Dictionary = _fingers[idx]
		_pressed[f["id"]] = true
	# Slider: analogue steering from the finger's travel since touch-down.
	_slider = 0.0
	for idx: int in _fingers:
		var f: Dictionary = _fingers[idx]
		if f["id"] == "slider":
			var travel: float = (f["pos"] as Vector2).x - (f["start"] as Vector2).x
			var full := root.size.y * 0.11 / maxf(Settings.f("steer_sens"), 0.3)
			_slider = clampf(travel / full, -1.0, 1.0)


func _process(delta: float) -> void:
	if Settings.scheme() == Settings.S_BUTTONS:
		var dir := (1.0 if _pressed.get("right", false) else 0.0) - (1.0 if _pressed.get("left", false) else 0.0)
		if dir != 0.0:
			var rate := 1.0 / 0.22 if signf(dir) == signf(_steer_btn) or absf(_steer_btn) < 0.05 else 1.0 / 0.1
			_steer_btn = move_toward(_steer_btn, dir, rate * delta)
		else:
			_steer_btn = move_toward(_steer_btn, 0.0, delta / 0.08)
	root.queue_redraw()


func _draw_controls() -> void:
	var vs := root.size
	var op := Settings.f("ctrl_opacity")
	var lay := _layout()
	for id: String in lay:
		var v: Array = lay[id]
		var c := Vector2(v[0] * vs.x, v[1] * vs.y)
		var r: float = v[2] * vs.y
		var on: bool = _pressed.get(id, false)
		var col := C_ACC if on else C_IDLE
		col.a = op * (0.9 if on else 0.45)
		var fill := Color(col.r, col.g, col.b, op * (0.28 if on else 0.08))
		match id:
			"slider":
				var w := r * 2.6
				var rect := Rect2(c - Vector2(w, r * 0.55), Vector2(w * 2.0, r * 1.1))
				root.draw_rect(rect, fill)
				root.draw_rect(rect, col, false, 2.0)
				var knob := c + Vector2(_slider * w * 0.85, 0)
				root.draw_circle(knob, r * 0.42, Color(col.r, col.g, col.b, op * 0.7))
				_label(c + Vector2(0, r * 0.95), "STEER", col)
			_:
				root.draw_circle(c, r, fill)
				root.draw_arc(c, r, 0.0, TAU, 40, col, 3.0)
				var label: String = {"ab_l": "L BRAKE", "ab_r": "R BRAKE", "fire": "FIRE", "left": "◀", "right": "▶", "thrust": "THRUST"}.get(id, id)
				if id in ["left", "right"]:
					_arrow(c, r * 0.45, -1.0 if id == "left" else 1.0, col)
				else:
					_label(c + Vector2(0, 6), label, col)
				if id in ["ab_l", "ab_r"] and _pressed.get("ab_l", false) and _pressed.get("ab_r", false):
					_label(Vector2(vs.x * 0.5, vs.y * 0.78), "BRAKING", C_ACC)
	# Pause and camera buttons.
	var pc := Vector2(vs.x * 0.5, vs.y * 0.055)
	root.draw_rect(Rect2(pc - Vector2(22, 18), Vector2(44, 36)), Color(0, 0, 0, 0.3 * op))
	root.draw_rect(Rect2(pc + Vector2(-9, -11), Vector2(6, 22)), Color(1, 1, 1, op))
	root.draw_rect(Rect2(pc + Vector2(3, -11), Vector2(6, 22)), Color(1, 1, 1, op))
	var cc := Vector2(vs.x * 0.62, vs.y * 0.055)
	root.draw_rect(Rect2(cc - Vector2(26, 18), Vector2(52, 36)), Color(0, 0, 0, 0.3 * op))
	_label(cc + Vector2(0, 6), "CAM", Color(1, 1, 1, op))


func _label(pos: Vector2, text: String, col: Color) -> void:
	root.draw_string(_font, pos - Vector2(80, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 18, col)


func _arrow(c: Vector2, s: float, dir: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(dir * s, 0), c + Vector2(-dir * s * 0.6, -s * 0.8), c + Vector2(-dir * s * 0.6, s * 0.8)])
	root.draw_colored_polygon(pts, col)
