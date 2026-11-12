## Race HUD: position, lap, timers, speed, shield, boost, messages, and the
## telemetry overlay (F3 / setting). Drawn on a 1280x720 canvas that stretches.
class_name Hud
extends CanvasLayer

const C_TEXT := Color(0.94, 0.96, 1.0)
const C_DIM := Color(0.62, 0.68, 0.78)
const C_ACC := Color(0.3, 0.85, 1.0)
const C_WARN := Color(1.0, 0.45, 0.12)
const C_BAD := Color(1.0, 0.18, 0.2)
const C_PANEL := Color(0.02, 0.03, 0.05, 0.55)

var race: Node
var root: Control
var f_num: Font
var f_txt: Font
var _msg: String = ""
var _msg_t: float = 0.0
var _msg_col := C_TEXT
var _lap_flash: float = 0.0
var _speed_shown: float = 0.0
var _tel: Label
var _go_t: float = 0.0


func setup(p_race: Node) -> void:
	race = p_race
	f_num = load("res://assets/fonts/Orbitron.ttf")
	f_txt = load("res://assets/fonts/Rajdhani-Bold.ttf")
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.draw.connect(_draw_hud)
	_tel = Label.new()
	_tel.position = Vector2(14, 150)
	_tel.add_theme_font_size_override("font_size", 15)
	_tel.add_theme_color_override("font_color", Color(0.75, 1.0, 0.85))
	_tel.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_tel.add_theme_constant_override("outline_size", 4)
	root.add_child(_tel)


func on_lap(r: RefCounted) -> void:
	var s: RaceSession = race.session
	var rr := r as RaceSession.Racer
	if rr.lap == s.laps - 1:
		message("FINAL LAP", C_WARN, 2.2)
	elif rr.lap < s.laps:
		message("LAP %d" % (rr.lap + 1), C_TEXT, 1.6)
	_lap_flash = 2.5


func on_finish(r: RefCounted) -> void:
	var rr := r as RaceSession.Racer
	message("FINISH  %s" % _ordinal(rr.place), C_ACC, 6.0)


func on_eliminated(r: RefCounted) -> void:
	var rr := r as RaceSession.Racer
	if rr.is_player:
		message("KNOCKED OUT" if rr.knocked_out else "SHIELD DEPLETED", C_BAD, 4.0)
	else:
		message("%s  OUT" % rr.name, C_WARN, 1.6)


func on_weapon_event(e: Dictionary) -> void:
	var me: Ship = race.player
	match e["type"]:
		"hit":
			if e["ship"] == me:
				message("HIT  " + String(WeaponSystem.ITEMS.get(e["kind"], {"name": "MINE"})["name"]) if e["kind"] != "mine" else "MINE HIT", C_BAD, 1.2)
			elif e.get("by") == me:
				message("TARGET HIT", C_ACC, 1.0)
		"blocked":
			if e["ship"] == me:
				message("SHIELD BLOCKED", C_ACC, 1.0)
		"pickup":
			if e["ship"] == me:
				message(String(WeaponSystem.ITEMS[e["kind"]]["name"]), Color(1.0, 0.45, 0.85), 1.2)


func message(text: String, col: Color, t: float) -> void:
	_msg = text
	_msg_col = col
	_msg_t = t


func _process(delta: float) -> void:
	if race == null or race.session == null:
		return
	_msg_t -= delta
	_lap_flash -= delta
	var ph: ShipPhysics = race.player.phys
	_speed_shown = lerpf(_speed_shown, ph.displayed_kmh(), 1.0 - exp(-delta * 14.0))
	var s: RaceSession = race.session
	if s.state == RaceSession.State.RACING and s.time < 1.2:
		_go_t = s.time
	_tel.visible = Settings.get_v("show_telemetry")
	if _tel.visible:
		_tel.text = _telemetry()
	# Cockpit display text.
	var parts: ShipModel.Parts = race.player.parts
	if parts.speed_label and parts.cockpit.visible:
		parts.speed_label.text = "%03d" % int(_speed_shown)
		parts.info_label.text = "P%d  L%d/%d\nE %d" % [s.player.place, s.lap_shown(s.player), s.laps, int(maxf(ph.energy, 0.0))]
	root.queue_redraw()


func _telemetry() -> String:
	var ph: ShipPhysics = race.player.phys
	var c: ShipControls = race.player.controls
	var up_err := rad_to_deg(ph.align_err)
	var pitch := rad_to_deg(asin(clampf(ph.fwd.y, -1, 1)))
	var roll := rad_to_deg(asin(clampf(ph.right().y, -1, 1)))
	return "\n".join([
		"TELEMETRY",
		"speed      %6.1f m/s  %5.0f km/h" % [ph.speed, ph.displayed_kmh()],
		"accel lon  %6.1f m/s²  lat %6.1f (%.2f g)" % [ph.accel_long, ph.accel_lat, ph.accel_lat / 9.81],
		"v lat      %6.2f m/s  slip %5.1f°" % [ph.v_lat, rad_to_deg(ph.slip)],
		"yaw rate   %6.3f rad/s" % ph.yaw_rate,
		"steer      %+5.2f  thrust %.2f" % [c.steer, c.thrust],
		"airbrake   L %.2f  R %.2f" % [ph.ab_l, ph.ab_r],
		"hover      %5.2f m  %s  air %.2f s" % [ph.h_c, "LOCK" if ph.locked else "AIR ", ph.air_time],
		"orient     pitch %5.1f°  roll %5.1f°" % [pitch, roll],
		"surf align %5.2f°" % up_err,
		"track      s %6.0f  d %+5.1f  bank %4.1f°" % [ph.hit.s, ph.hit.d, rad_to_deg(ph.track.bank[ph.hit.i])],
		"wall       %5.1f m/s  energy %5.1f" % [ph.ev_wall, ph.energy],
		"fps %3.0f" % Quality.fps,
	])


func _ordinal(n: int) -> String:
	var suf := "TH"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "ST"
			2: suf = "ND"
			3: suf = "RD"
	return "%d%s" % [n, suf]


static func fmt_time(t: float) -> String:
	if t <= 0.0:
		return "-:--.---"
	var m := int(t / 60.0)
	var sec := t - m * 60.0
	return "%d:%06.3f" % [m, sec]


func _text(font: Font, pos: Vector2, text: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	# Soft shadow for legibility over bright scenery.
	root.draw_string(font, pos + Vector2(2, 2), text, align, width, size, Color(0, 0, 0, 0.55 * col.a))
	root.draw_string(font, pos, text, align, width, size, col)


func _draw_hud() -> void:
	var vs := root.size
	var s: RaceSession = race.session
	var p := s.player
	var ph: ShipPhysics = race.player.phys
	var cockpit: bool = race.rig.mode == CameraRig.Mode.COCKPIT
	# --- Position (top left).
	_panel(Rect2(18, 16, 172, 92))
	_text(f_txt, Vector2(30, 40), "POSITION", 16, C_DIM)
	_text(f_num, Vector2(28, 96), str(p.place), 54, C_TEXT)
	_text(f_num, Vector2(28 + 40 * str(p.place).length(), 96), "/%d" % s.racers.size(), 24, C_DIM)
	# --- Lap (under position).
	_panel(Rect2(18, 114, 172, 40))
	_text(f_txt, Vector2(30, 141), "LAP", 18, C_DIM)
	var lap_col := C_WARN if p.lap == s.laps - 1 and not p.finished else C_TEXT
	_text(f_num, Vector2(78, 143), "%d/%d" % [s.lap_shown(p), s.laps], 24, lap_col)
	# --- Times (top right).
	var x := vs.x - 250.0
	_panel(Rect2(x - 12, 16, 244, 110))
	_text(f_txt, Vector2(x, 40), "TIME", 16, C_DIM)
	_text(f_num, Vector2(x + 60, 42), fmt_time(s.time), 22, C_TEXT)
	_text(f_txt, Vector2(x, 72), "LAP", 16, C_DIM)
	var cur := s.current_lap_time(p)
	var flash := _lap_flash > 0.0 and p.last_lap > 0.0
	_text(f_num, Vector2(x + 60, 74), fmt_time(p.last_lap if flash else cur), 22, C_ACC if flash else C_TEXT)
	_text(f_txt, Vector2(x, 104), "BEST", 16, C_DIM)
	_text(f_num, Vector2(x + 60, 106), fmt_time(p.best_lap), 22, C_DIM)
	# --- Speed (bottom right): arc of segments and the digital readout.
	var touch_on: bool = race.touch != null
	if not cockpit:
		var c := Vector2(vs.x - 150.0, vs.y - 90.0) if not touch_on else Vector2(vs.x * 0.5, vs.y - 62.0)
		var vt := clampf(ph.v_fwd / ph.spec.v_top, 0.0, 1.25)
		var segs := 28
		for k in segs:
			var f := float(k) / segs
			var a0 := lerpf(PI * 0.82, PI * 2.18, f)
			var a1 := lerpf(PI * 0.82, PI * 2.18, f + 0.8 / segs)
			var on := f < vt / 1.2
			var col := C_ACC if f < 0.75 else (C_WARN if f < 0.9 else C_BAD)
			if not on:
				col = Color(0.25, 0.3, 0.38, 0.5)
			root.draw_arc(c, 108.0, a0, a1, 4, col, 9.0)
		_text(f_num, c + Vector2(-110, 18), "%d" % int(_speed_shown), 52, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 220)
		_text(f_txt, c + Vector2(-110, 46), "KM/H", 18, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 220)
		if ph.boost_t > 0.0:
			_text(f_txt, c + Vector2(-110, -40), "BOOST", 22, C_ACC, HORIZONTAL_ALIGNMENT_CENTER, 220)
	# --- Shield (bottom left).
	var e := clampf(ph.energy / ph.spec.shield, 0.0, 1.0)
	var bx := 24.0 if not touch_on else vs.x * 0.5 - 124.0
	var by := vs.y - 54.0 if not touch_on else 96.0
	_panel(Rect2(bx - 10, by - 34, 268, 64))
	_text(f_txt, Vector2(bx, by - 12), "SHIELD", 16, C_DIM)
	_text(f_num, Vector2(bx + 180, by - 10), "%d" % int(e * 100.0), 18, C_TEXT if e > 0.3 else C_BAD)
	var nseg := 20
	for k in nseg:
		var on := float(k) / nseg < e
		var col := (C_ACC if e > 0.5 else (C_WARN if e > 0.25 else C_BAD)) if on else Color(0.25, 0.3, 0.38, 0.5)
		root.draw_rect(Rect2(bx + k * 12.0, by, 9.0, 16.0), col)
	# --- Centre messages: countdown, wrong way, lap messages.
	var cx := vs.x * 0.5
	if s.state == RaceSession.State.COUNTDOWN:
		var n := int(ceil(s.countdown))
		if n <= 3:
			var frac := s.countdown - floorf(s.countdown)
			var sz := int(lerpf(96.0, 140.0, frac))
			_text(f_num, Vector2(cx - 200, vs.y * 0.42), str(n), sz, Color(1, 1, 1, clampf(frac * 2.0, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, 400)
		else:
			_text(f_txt, Vector2(cx - 300, vs.y * 0.4), "GET READY", 42, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 600)
	elif s.time < 1.0:
		_text(f_num, Vector2(cx - 200, vs.y * 0.42), "GO", 120, Color(C_ACC.r, C_ACC.g, C_ACC.b, 1.0 - s.time), HORIZONTAL_ALIGNMENT_CENTER, 400)
	if s.wrong_way and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_text(f_txt, Vector2(cx - 300, vs.y * 0.3), "WRONG WAY", 52, C_BAD, HORIZONTAL_ALIGNMENT_CENTER, 600)
	if _msg_t > 0.0:
		var a := clampf(_msg_t * 2.0, 0.0, 1.0)
		_text(f_txt, Vector2(cx - 300, vs.y * 0.25), _msg, 48, Color(_msg_col.r, _msg_col.g, _msg_col.b, a), HORIZONTAL_ALIGNMENT_CENTER, 600)
	# --- Mode panels.
	var mpy := 160.0
	match s.mode:
		"elimination":
			_panel(Rect2(18, mpy, 172, 62))
			_text(f_txt, Vector2(30, mpy + 22), "KNOCKOUT", 16, C_DIM)
			var danger := s.is_racing() and p.place >= s.active_count() and not p.eliminated
			_text(f_num, Vector2(30, mpy + 52), "%4.1f" % maxf(s.knockout_t, 0.0), 24, C_BAD if danger else C_TEXT)
			if danger and int(Time.get_ticks_msec() / 300) % 2 == 0:
				_text(f_txt, Vector2(cx - 300, vs.y * 0.18), "IN THE DROP ZONE", 32, C_BAD, HORIZONTAL_ALIGNMENT_CENTER, 600)
		"combat":
			_panel(Rect2(18, mpy, 172, 62))
			_text(f_txt, Vector2(30, mpy + 22), "POINTS", 16, C_DIM)
			_text(f_num, Vector2(30, mpy + 52), str(p.points), 24, C_ACC)
		"speed":
			_panel(Rect2(18, mpy, 172, 96))
			var names := ["GOLD", "SILVER", "BRONZE"]
			var cols := [Color(1.0, 0.82, 0.3), Color(0.8, 0.85, 0.92), Color(0.85, 0.55, 0.3)]
			for k in 3:
				_text(f_txt, Vector2(30, mpy + 26 + k * 28), "%-6s %s" % [names[k], fmt_time(s.targets[k])], 18, cols[k])
	# --- Item slot (right side) and warnings.
	var w: WeaponSystem = race.weapons
	if w != null and w.enabled:
		var item := w.item_of(race.player)
		var ix := vs.x - 250.0
		var iy := 140.0
		_panel(Rect2(ix - 12, iy, 244, 50))
		if item != "":
			var nm: String = WeaponSystem.ITEMS[item]["name"]
			var ammo := w.ammo_of(race.player)
			_text(f_txt, Vector2(ix, iy + 33), nm + ("  x%d" % ammo if ammo > 1 else ""), 22, Color(1.0, 0.5, 0.88))
		else:
			_text(f_txt, Vector2(ix, iy + 33), "NO ITEM", 20, C_DIM)
		if w.missile_on(race.player) and int(Time.get_ticks_msec() / 250) % 2 == 0:
			_text(f_txt, Vector2(cx - 300, vs.y * 0.18), "MISSILE LOCK", 40, C_BAD, HORIZONTAL_ALIGNMENT_CENTER, 600)
		if ph.shield_t > 0.0:
			_text(f_txt, Vector2(cx - 300, vs.y * 0.66), "SHIELD UP  %.1f" % ph.shield_t, 26, C_ACC, HORIZONTAL_ALIGNMENT_CENTER, 600)
		if ph.stun_t > 0.0:
			_text(f_txt, Vector2(cx - 300, vs.y * 0.7), "SYSTEMS DOWN", 26, C_WARN, HORIZONTAL_ALIGNMENT_CENTER, 600)
	if Settings.get_v("show_fps"):
		_text(f_txt, Vector2(vs.x * 0.5 - 40, 24), "%d FPS" % int(Quality.fps), 16, C_DIM)


func _panel(r: Rect2) -> void:
	root.draw_rect(r, C_PANEL)
	root.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), Color(C_ACC.r, C_ACC.g, C_ACC.b, 0.8))
