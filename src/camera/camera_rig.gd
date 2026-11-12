## Chase cameras (standard, wide, close), cockpit camera and a trackside replay
## camera, all computed every frame from the ship's interpolated pose.
##
## The chase cameras smooth the *frame* they follow (heading and up vector),
## not the world position: at 100 m/s a position spring would trail the ship
## by metres. Speed widens the field of view and pulls the camera down and in;
## acceleration and braking move it along the ship; slides and banking show
## through the lagging heading and roll. The camera never leaves the space
## between the barriers.
class_name CameraRig
extends Node3D

enum Mode { CHASE, WIDE, CLOSE, COCKPIT, TRACKSIDE }
const MODE_COUNT := 4   ## Modes the player cycles through (trackside is for replays).
const NAMES: PackedStringArray = ["STANDARD", "WIDE", "CLOSE", "COCKPIT", "TRACKSIDE"]
## dist, height, look_ahead, look_up, fov_base, fov_top
const CHASE_P := {
	Mode.CHASE: [7.4, 1.85, 9.0, 0.7, 68.0, 86.0],
	Mode.WIDE: [10.0, 3.1, 9.0, 0.9, 66.0, 82.0],
	Mode.CLOSE: [5.0, 1.55, 6.0, 0.62, 70.0, 90.0],
}

var cam: Camera3D
var ship: Ship
var mode: int = Mode.CHASE
var motion: float = 1.0          ## Player setting: scales shake, roll and FOV kick.

var _fwd_s := Vector3.FORWARD
var _up_s := Vector3.UP
var _dist_dyn: float = 0.0
var _h_dyn: float = 0.0
var _fov: float = 70.0
var _shake: float = 0.0
var _t: float = 0.0
var _blend: float = 1.0
var _from := Transform3D.IDENTITY
var _from_fov: float = 70.0
var _eye_basis := Basis.IDENTITY
var _hit := TrackData.Hit.new()
var _hint: int = -1
var _ts_pos := Vector3.ZERO      ## Trackside camera position.
var _ts_s: float = -1.0


func _init() -> void:
	cam = Camera3D.new()
	cam.near = 0.08
	cam.far = 9000.0
	cam.fov = 70.0
	add_child(cam)


func attach(p_ship: Ship) -> void:
	ship = p_ship
	var b := ship.global_transform.basis
	_fwd_s = -b.z
	_up_s = b.y
	_eye_basis = b
	_hint = -1
	_apply_cockpit()
	_update_now(0.0)


func set_mode(m: int) -> void:
	if m == mode:
		return
	_from = cam.global_transform
	_from_fov = cam.fov
	_blend = 0.0
	mode = m
	_apply_cockpit()


func cycle() -> void:
	set_mode((mode + 1) % MODE_COUNT)


func _apply_cockpit() -> void:
	if ship:
		ship.set_cockpit(mode == Mode.COCKPIT)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	if ship == null:
		return
	_update_now(delta)


func _update_now(delta: float) -> void:
	_t += delta
	var ph := ship.phys
	var spd := maxf(ph.v_fwd, 0.0)
	var vt := clampf(spd / maxf(ph.spec.v_top, 1.0), 0.0, 1.3)
	var target: Transform3D
	var fov: float
	match mode:
		Mode.COCKPIT:
			var eye := ship.eye_transform()
			# Head inertia: the view lags the hull's rotation very slightly.
			_eye_basis = _eye_basis.slerp(eye.basis.orthonormalized(), 1.0 - exp(-delta * 22.0)) if delta > 0.0 else eye.basis
			var vib := Vector3(sin(_t * 71.0), sin(_t * 53.0 + 1.3), 0.0) * 0.004 * vt * motion
			target = Transform3D(_eye_basis.orthonormalized(), eye.origin + _eye_basis * vib)
			fov = lerpf(76.0, 90.0, vt * vt) * lerpf(1.0, 1.0 + 0.06 * motion, 1.0 if ph.boost_t > 0.0 else 0.0)
		Mode.TRACKSIDE:
			target = _trackside()
			fov = 50.0
		_:
			var res := _chase(delta, CHASE_P[mode], vt)
			target = res[0]
			fov = res[1]
	# Shake (impacts, landings) and a faint high-speed buzz.
	_shake = maxf(0.0, _shake - delta * 2.5)
	var sh := (_shake * _shake * 0.35 + vt * vt * 0.012) * motion
	if sh > 0.0001:
		var o := Vector3(sin(_t * 47.0) + sin(_t * 31.0) * 0.5, sin(_t * 59.0 + 2.0) + sin(_t * 23.0) * 0.5, 0.0) * sh * 0.3
		target.origin += target.basis * o
	# Mode switch blend.
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / 0.35)
		var e := _blend * _blend * (3.0 - 2.0 * _blend)
		target = _from.interpolate_with(target, e)
		fov = lerpf(_from_fov, fov, e)
	cam.global_transform = target
	cam.fov = fov


func _chase(delta: float, p: Array, vt: float) -> Array:
	var ph := ship.phys
	var xf := ship.global_transform
	var b := xf.basis
	var s_up := b.y
	var s_fwd := -b.z
	# Follow a blend of the nose and the direction of travel, so slides read.
	var vdir := ph.vel - s_up * ph.vel.dot(s_up)
	var dir := s_fwd
	if vdir.length() > 8.0:
		dir = (s_fwd * 0.55 + vdir.normalized() * 0.45).normalized()
	var k_yaw := 1.0 - exp(-delta * 9.0) if delta > 0.0 else 1.0
	var k_up := 1.0 - exp(-delta * (6.5 if ph.locked else 2.0)) if delta > 0.0 else 1.0
	_up_s = _up_s.lerp(s_up, k_up).normalized()
	_fwd_s = _fwd_s.lerp(dir, k_yaw)
	_fwd_s = (_fwd_s - _up_s * _fwd_s.dot(_up_s)).normalized()
	# Longitudinal acceleration moves the camera along the ship (squat on launch, close in on braking).
	var dd := clampf(ph.accel_long * 0.018, -0.9, 0.7)
	_dist_dyn = lerpf(_dist_dyn, dd, 1.0 - exp(-delta * 4.0)) if delta > 0.0 else dd
	# Vertical: lag the hover/landing motion a little.
	var dist: float = p[0] * lerpf(1.0, 0.86, vt) + _dist_dyn
	var height: float = p[1] * lerpf(1.0, 0.85, vt)
	var pos := xf.origin - _fwd_s * dist + _up_s * height
	var look := xf.origin + _fwd_s * float(p[2]) + _up_s * float(p[3])
	# Keep the camera between the barriers and under tunnel roofs.
	pos = _contain(pos)
	# Roll with the ship's lean (a fraction) for a sense of carving.
	var lean := ship.visual_transform().basis.y
	var up := _up_s.lerp(lean, 0.25 * motion).normalized()
	var t := Transform3D(Basis.IDENTITY, pos).looking_at(look, up)
	var fov: float = lerpf(float(p[4]), float(p[5]), vt * vt)
	if ph.boost_t > 0.0:
		fov += 6.0 * motion
	_fov = lerpf(_fov, fov, 1.0 - exp(-delta * 3.0)) if delta > 0.0 else fov
	return [t, _fov]


func _contain(pos: Vector3) -> Vector3:
	var td := ship.phys.track
	td.project(pos, _hint if _hint >= 0 else ship.phys.hint, _hit)
	_hint = _hit.i
	if (_hit.flags & TrackData.F_GAP) != 0:
		return pos
	var lim_r := _hit.half_r - 0.6
	var lim_l := -_hit.half_l + 0.6
	if _hit.h < 4.0:
		if _hit.d > lim_r:
			pos -= _hit.B * (_hit.d - lim_r)
		elif _hit.d < lim_l:
			pos += _hit.B * (lim_l - _hit.d)
	if _hit.h < 0.6:
		pos += _hit.N * (0.6 - _hit.h)
	var ceil_h := td.ceiling[_hit.i]
	if ceil_h > 0.0 and _hit.h > ceil_h - 0.8:
		pos -= _hit.N * (_hit.h - (ceil_h - 0.8))
	return pos


## A camera beside the track that the ship flies past, then jumps ahead.
func _trackside() -> Transform3D:
	var ph := ship.phys
	var td := ph.track
	if _ts_s < 0.0 or td.delta_s(_ts_s, ph.hit.s) > 40.0:
		_ts_s = td.wrap_s(ph.hit.s + 120.0)
		var hit := TrackData.Hit.new()
		td.frame_at(_ts_s, hit)
		var side := 1.0 if int(_ts_s) % 2 == 0 else -1.0
		_ts_pos = hit.c + hit.B * side * (hit.half_r + 4.0) + hit.N * 5.0
	return Transform3D(Basis.IDENTITY, _ts_pos).looking_at(ship.global_transform.origin, Vector3.UP)
