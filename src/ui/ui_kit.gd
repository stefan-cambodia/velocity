## Shared look for menus: industrial panels, cyan accent bars, uppercase
## Rajdhani labels, Orbitron numerals. Builders return plain Controls.
class_name UIKit
extends RefCounted

const BG := Color(0.02, 0.025, 0.04)
const PANEL := Color(0.05, 0.065, 0.09, 0.92)
const PANEL_HI := Color(0.08, 0.11, 0.15, 0.95)
const ACC := Color(0.3, 0.85, 1.0)
const ACC2 := Color(1.0, 0.45, 0.12)
const TEXT := Color(0.93, 0.95, 1.0)
const DIM := Color(0.58, 0.64, 0.74)

static var _theme: Theme


static func font(bold: bool = true) -> Font:
	return load("res://assets/fonts/Rajdhani-Bold.ttf" if bold else "res://assets/fonts/Rajdhani-SemiBold.ttf")


static func num_font() -> Font:
	return load("res://assets/fonts/Orbitron.ttf")


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 22
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_left = 4
	sb.border_color = Color(ACC.r, ACC.g, ACC.b, 0.5)
	sb.content_margin_left = 22
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = PANEL_HI
	hov.border_color = ACC
	hov.border_width_left = 8
	var prs := hov.duplicate() as StyleBoxFlat
	prs.bg_color = Color(ACC.r * 0.35, ACC.g * 0.35, ACC.b * 0.35, 0.95)
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = Color(0.04, 0.045, 0.06, 0.7)
	dis.border_color = Color(0.3, 0.32, 0.36, 0.5)
	t.set_stylebox("normal", "Button", sb)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("focus", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.48, 0.55))
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 26)
	t.set_color("font_color", "Label", TEXT)
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.15, 0.18, 0.24)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	var grab := StyleBoxFlat.new()
	grab.bg_color = ACC
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	_theme = t
	return t


static func label(text: String, size: int = 22, col: Color = TEXT, bold: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func title(text: String, size: int = 54) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", num_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	return l


static func button(text: String, cb: Callable, min_w: float = 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(min_w, 56)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void:
		Audio.ui("ui_select")
		cb.call())
	b.focus_entered.connect(func() -> void: Audio.ui("ui_move", -8.0))
	return b


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 2
	sb.border_color = Color(ACC.r, ACC.g, ACC.b, 0.6)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = min_size
	return p


## A left-label / right-value row with arrows to cycle through options.
static func option_row(name: String, options: PackedStringArray, current: int, cb: Callable, min_w: float = 520.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(min_w, 50)
	var l := label(name.to_upper(), 22, DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var idx := [current]
	var val := label(options[current], 24, TEXT)
	val.custom_minimum_size = Vector2(220, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var left := Button.new()
	left.text = "◀"
	left.custom_minimum_size = Vector2(52, 46)
	var right := Button.new()
	right.text = "▶"
	right.custom_minimum_size = Vector2(52, 46)
	var step := func(d: int) -> void:
		idx[0] = posmod(idx[0] + d, options.size())
		val.text = options[idx[0]]
		Audio.ui("ui_move", -6.0)
		cb.call(idx[0])
	left.pressed.connect(step.bind(-1))
	right.pressed.connect(step.bind(1))
	row.add_child(left)
	row.add_child(val)
	row.add_child(right)
	return row


static func slider_row(name: String, value: float, lo: float, hi: float, cb: Callable, min_w: float = 520.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(min_w, 46)
	var l := label(name.to_upper(), 22, DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(260, 40)
	s.value_changed.connect(func(v: float) -> void: cb.call(v))
	row.add_child(s)
	return row


static func bar(value: float, w: float = 220.0, col: Color = ACC) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 14)
	c.draw.connect(func() -> void:
		var n := 10
		for k in n:
			var on := float(k) / n < value - 0.001
			c.draw_rect(Rect2(k * (w / n), 2, w / n - 4, 10), col if on else Color(0.2, 0.24, 0.3)))
	return c
