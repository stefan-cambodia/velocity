## Pause overlay: resume, restart, camera, a few quick settings, quit.
extends CanvasLayer

var _root: Control
var _open: bool = false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	get_tree().paused = true
	Audio.ui("ui_select")
	_build()


func close() -> void:
	_open = false
	visible = false
	get_tree().paused = false
	if _root:
		_root.queue_free()
		_root = null


func _build() -> void:
	if _root:
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UIKit.theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 10)
	box.position = Vector2(-260, -250)
	box.custom_minimum_size = Vector2(520, 0)
	_root.add_child(box)
	box.add_child(UIKit.title("PAUSED", 46))
	var race := get_parent() as Race
	var resume := UIKit.button("RESUME", close, 520)
	box.add_child(resume)
	box.add_child(UIKit.button("RESTART RACE", func() -> void:
		close()
		Game.restart_race(), 520))
	box.add_child(UIKit.option_row("Camera", CameraRig.NAMES.slice(0, CameraRig.MODE_COUNT), race.rig.mode, func(i: int) -> void:
		race.rig.set_mode(i)
		Settings.set_v("camera", i)))
	box.add_child(UIKit.option_row("Steering", Settings.SCHEMES, Settings.scheme(), func(i: int) -> void: Settings.set_scheme(i)))
	box.add_child(UIKit.option_row("Steering assist", PackedStringArray(["OFF", "LOW", "HIGH"]), int(Settings.get_v("steer_assist")), func(i: int) -> void: Settings.set_v("steer_assist", i)))
	box.add_child(UIKit.slider_row("Music", Settings.f("vol_music"), 0.0, 1.0, func(v: float) -> void: Settings.set_v("vol_music", v)))
	box.add_child(UIKit.slider_row("Effects", Settings.f("vol_sfx"), 0.0, 1.0, func(v: float) -> void: Settings.set_v("vol_sfx", v)))
	box.add_child(UIKit.button("QUIT TO MENU", func() -> void:
		close()
		Audio.stop_music(0.5)
		Game.goto_menu("home"), 520))
	resume.grab_focus.call_deferred()


func _unhandled_input(ev: InputEvent) -> void:
	if _open and (ev.is_action_pressed("pause") or ev.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
