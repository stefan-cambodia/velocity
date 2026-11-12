## Anti-gravity ship simulation. Pure data, deterministic, no engine physics.
## See docs/ARCHITECTURE.md §7 and docs/HANDLING.md for the model.
##
## Orientation: `fwd` (nose direction) and `up` (hull up) are kept orthonormal;
## right = fwd × up. Positive yaw rate turns right.
class_name ShipPhysics
extends RefCounted

const G := Vector3(0.0, -9.81, 0.0)


## Share of world gravity that acts along a locked surface whose normal has
## world-up component `ny`. Full on ordinary banks and slopes; fades out once
## the deck rolls past ~55 degrees, where the flux lock alone holds the ship
## (corkscrews), so the pull never swings sideways as the deck turns over.
static func planar_fade(ny: float) -> float:
	return smoothstep(0.2, 0.6, ny)

var spec: ShipSpec
var track: TrackData

# --- State --------------------------------------------------------------------
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var fwd := Vector3.FORWARD
var up := Vector3.UP
var yaw_rate: float = 0.0
var locked: bool = true
var _roll_w: float = 0.0               ## Roll rate of the deck under a locked ship (rad/s).
var _roll_carry := Vector3.ZERO        ## Sideways sweep of the hover gap on a rolling deck (m/s).
var energy: float = 100.0
var boost_t: float = 0.0
var hint: int = -1
var hit := TrackData.Hit.new()       ## Projection of the hull centre (after the step).
var surf_n := Vector3.UP             ## Fitted surface normal under the hull.
var last_safe_s: float = 0.0         ## Last lap distance where the ship was locked, on the surface, upright.
var last_safe_d: float = 0.0
var enabled: bool = true             ## False = frozen (countdown, eliminated).
var stun_t: float = 0.0              ## Seconds of disabled thrust left (EMP, hits).
var shield_t: float = 0.0            ## Seconds of weapon invulnerability left (energy shield item).

# --- Telemetry (read-only outside) --------------------------------------------
var speed: float = 0.0               ## |vel| (m/s)
var v_fwd: float = 0.0               ## Velocity along the nose.
var v_lat: float = 0.0               ## Velocity to the right of the nose.
var slip: float = 0.0                ## Angle between velocity and nose (rad, + = sliding right).
var h_c: float = 1.0                 ## Hull height above the fitted surface.
var accel_long: float = 0.0          ## Longitudinal acceleration (m/s²).
var accel_lat: float = 0.0           ## Lateral acceleration (m/s²).
var align_err: float = 0.0           ## Angle between hull up and surface normal (rad).
var air_time: float = 0.0
var ab_l: float = 0.0                ## Airbrake deflection actually applied (smoothed), for visuals.
var ab_r: float = 0.0

# --- Events of the last step (consumed by FX / audio / race) -------------------
var ev_wall: float = 0.0             ## Impact speed against a barrier (m/s).
var ev_wall_point := Vector3.ZERO
var ev_wall_side: int = 0            ## -1 left, +1 right
var ev_land: float = 0.0             ## Landing normal speed (m/s).
var ev_scrape: bool = false          ## Hull touching the floor or sliding along a barrier.
var ev_floor: float = 0.0            ## Floor contact speed.
var ev_pad: String = ""              ## "boost" / "weapon" when a pad was triggered.
var ev_pad_index: int = -1
var touching_wall: bool = false

var _probe := TrackData.Hit.new()
var _pad_lock: int = -1              ## Last pad triggered (one trigger per pass).
var _prev_vel := Vector3.ZERO


func _init(p_spec: ShipSpec, p_track: TrackData) -> void:
	spec = p_spec
	track = p_track
	energy = spec.shield


## Puts the ship at rest on the surface at (s, d), facing along the track.
func place(s: float, d: float) -> void:
	track.frame_at(s, hit)
	pos = hit.c + hit.B * d + hit.N * spec.hover_h
	fwd = hit.T
	up = hit.N
	surf_n = hit.N
	vel = Vector3.ZERO
	_prev_vel = Vector3.ZERO
	yaw_rate = 0.0
	locked = true
	boost_t = 0.0
	hint = hit.i
	last_safe_s = hit.s
	last_safe_d = d
	h_c = spec.hover_h
	air_time = 0.0
	track.project(pos, hint, hit)


func right() -> Vector3:
	return fwd.cross(up)


func basis() -> Basis:
	return Basis(fwd.cross(up), up, -fwd)


func xform() -> Transform3D:
	return Transform3D(basis(), pos)


func displayed_kmh() -> float:
	return maxf(v_fwd, 0.0) * 3.6 * ShipSpec.SPEED_SCALE


## Advances the simulation by dt (use 1/120 s).
func step(dt: float, c: ShipControls) -> void:
	ev_wall = 0.0
	ev_land = 0.0
	ev_scrape = false
	ev_floor = 0.0
	ev_pad = ""
	ev_pad_index = -1
	touching_wall = false
	if not enabled:
		return
	_prev_vel = vel
	# Smoothed airbrake deflection (flaps take ~80 ms to deploy).
	var k_ab := 1.0 - exp(-dt / 0.08)
	ab_l += (clampf(c.ab_l, 0.0, 1.0) - ab_l) * k_ab
	ab_r += (clampf(c.ab_r, 0.0, 1.0) - ab_r) * k_ab
	var ab := ab_l + ab_r

	# 1. Where are we, and what is the surface doing under the hull?
	track.project(pos, hint, hit)
	hint = hit.i
	var on_span := (hit.flags & TrackData.F_GAP) == 0 and hit.d > -hit.half_l - 2.0 and hit.d < hit.half_r + 2.0
	var fit := _fit_surface()
	var n: Vector3 = fit[0]
	h_c = fit[1]
	var probes_ok: bool = fit[2]
	if locked:
		if not on_span or not probes_ok or h_c > spec.lock_h:
			locked = false
	elif on_span and probes_ok and h_c < spec.lock_h * 0.7 and vel.dot(n) < 2.0:
		locked = true
		ev_land = maxf(0.0, -vel.dot(n))
	if locked:
		surf_n = n
		air_time = 0.0
	else:
		air_time += dt

	# 2. Forces.
	var acc := Vector3.ZERO
	if locked:
		var v_n := vel.dot(n)
		var a_spring := spec.hover_k * (spec.hover_h - h_c) - spec.hover_c * v_n
		a_spring = maxf(a_spring, -spec.pull_max)
		acc += n * (a_spring - spec.g_track)
		acc += (G - n * G.dot(n)) * (spec.planar_g * planar_fade(n.y))
		# Co-rotating lock. Where the deck rolls about its centre line at w rad/m
		# (corkscrews), the deck point at offset d rides a helix round that line.
		# In plain world space nothing supplies its centripetal pull (w²·v²·d,
		# about 18 m/s² at the barrier of a 420 m roll), so the ship would be
		# flung outward, and the hull would trail the deck by ~10 degrees. So
		# the lock turns the velocity, nose and hull with the deck each step
		# (_roll_w, applied below). That supplies the centripetal terms exactly
		# and keeps the heading relative to the deck. What a pure rotation
		# cannot supply is the normal pull as the roll rate changes, -w'·v²·d,
		# and the swing of the hover gap h. The gap's sideways sweep (w·h·v) is
		# geometry, not motion the keels should resist, so it moves the position
		# (_roll_carry), not the velocity where grip would read it as slip. On
		# ordinary bank changes all of this is negligible. A twist drives like a
		# straight.
		var w0 := _roll_rate(hit.i)
		var w1 := _roll_rate(hit.i + 1)
		var w := lerpf(w0, w1, hit.t)
		var dw := (w1 - w0) / track.step
		var vs := vel.dot(hit.T)
		acc += hit.N * (vs * vs * (-dw * hit.d - w * w * hit.h))
		_roll_w = w * vs
		_roll_carry = hit.B * (w * hit.h * vs)
	else:
		_roll_w = 0.0
		_roll_carry = Vector3.ZERO
		acc += G * (spec.g_air / 9.81)
	var vf := vel.dot(fwd)
	var top := spec.v_top * (spec.boost_top if boost_t > 0.0 else 1.0)
	var ratio := vf / top
	var th := clampf(c.thrust, 0.0, 1.0)
	if stun_t > 0.0:
		stun_t -= dt
		th = 0.0
	if shield_t > 0.0:
		shield_t -= dt
	var a_f := th * spec.accel - spec.accel * ratio * absf(ratio) * (spec.coast + (1.0 - spec.coast) * th)
	if boost_t > 0.0:
		a_f += spec.boost_accel
		boost_t -= dt
	a_f -= spec.ab_drag * vf * ab
	if vf < 0.0:
		a_f -= vf * spec.reverse_damp
	acc += fwd * a_f
	vel += acc * dt
	if _roll_w != 0.0:
		# Rigid turn with the deck, before the yaw and grip stages read the
		# planar velocity. The surface normal of this step turns too, so grip
		# measures slip in the frame the velocity and nose now sit in.
		var ax := hit.T.normalized()
		var phi := _roll_w * dt
		vel = vel.rotated(ax, phi)
		fwd = fwd.rotated(ax, phi)
		up = up.rotated(ax, phi)
		n = n.rotated(ax, phi)
		surf_n = n

	# 3. Yaw: the nose turns at a rate that follows the steering, with inertia.
	var n_ref := n if locked else up
	var v_pl := vel - n_ref * vel.dot(n_ref)
	var spd := v_pl.length()
	var cap := spec.a_lat * (1.0 + spec.ab_grip * ab)
	var w_lim := minf(spec.yaw_low, spec.steer_k * spec.a_lat / maxf(spd, 4.0))
	var w_tgt := clampf(c.steer, -1.0, 1.0) * w_lim + (ab_r - ab_l) * spec.ab_yaw * w_lim
	var resp := spec.yaw_response * (1.0 if locked else spec.air_control)
	yaw_rate += (w_tgt - yaw_rate) * (1.0 - exp(-resp * dt))
	fwd = fwd.rotated(up, -yaw_rate * dt)

	# 4. Grip: the velocity turns towards the nose, limited by the keels' capacity.
	if locked and spd > 0.5:
		var f_pl := (fwd - n * fwd.dot(n)).normalized()
		var vdir := v_pl / spd
		var beta := atan2(vdir.cross(f_pl).dot(n), vdir.dot(f_pl))
		var want := beta * (1.0 - exp(-spec.align * dt))
		var max_rot := cap / spd * dt
		var rot := clampf(want, -max_rot, max_rot)
		var v_new := vdir.rotated(n, rot) * spd
		v_new *= maxf(0.0, 1.0 - spec.scrub * absf(sin(beta)) * dt)
		vel = v_new + n * vel.dot(n)

	# 5. Orientation: hull up follows the surface (or levels out in the air).
	if locked:
		up = up.lerp(n, 1.0 - exp(-spec.up_rate * dt)).normalized()
	else:
		var r := fwd.cross(up)
		var vd := vel.normalized()
		vd = (vd - r * vd.dot(r))
		if vd.length() > 0.1:
			fwd = fwd.lerp(vd.normalized(), 1.0 - exp(-1.6 * dt)).normalized()
		var lvl := (Vector3.UP * 0.6 + surf_n * 0.4).normalized()
		up = up.lerp(lvl, 1.0 - exp(-1.2 * dt)).normalized()
	fwd = (fwd - up * fwd.dot(up)).normalized()

	# 6. Move, then resolve contact with the floor, barriers and islands.
	pos += (vel + _roll_carry) * dt
	_constrain(dt)

	# 7. Pads, energy, telemetry.
	_pads()
	if (hit.flags & TrackData.F_RECHARGE) != 0 and locked:
		energy = minf(spec.shield, energy + spec.recharge_rate * dt)
	var r2 := fwd.cross(up)
	speed = vel.length()
	v_fwd = vel.dot(fwd)
	v_lat = vel.dot(r2)
	slip = atan2(v_lat, maxf(absf(v_fwd), 0.1))
	var a := (vel - _prev_vel) / dt
	accel_long = a.dot(fwd)
	accel_lat = a.dot(r2)
	align_err = up.angle_to(surf_n)
	if locked and on_span and absf(hit.d) < minf(hit.half_l, hit.half_r) - 2.0 and fwd.dot(hit.T) > 0.5:
		last_safe_s = hit.s
		last_safe_d = hit.d


## Roll rate of the deck frame about the centre line at sample i (rad/m,
## positive turns N toward B).
func _roll_rate(i: int) -> float:
	var a := track.wrap_i(i)
	var b := track.wrap_i(i + 1)
	return -(track.rgt[b] - track.rgt[a]).dot(track.nrm[a]) / track.step


## Fits a plane through the surface points under four probes at the hull
## corners. Returns [normal, height of the hull centre above it, all probes valid].
func _fit_surface() -> Array:
	var r := fwd.cross(up)
	var q := PackedVector3Array()
	q.resize(4)
	var ok := true
	var k := 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [1.0, -1.0]:
			var p := pos + fwd * (spec.probe_len * sz) + r * (spec.probe_wid * sx)
			track.project(p, hit.i, _probe)
			if (_probe.flags & TrackData.F_GAP) != 0:
				ok = false
			q[k] = p - _probe.N * _probe.h
			k += 1
	# q: 0 = left-front, 1 = left-rear, 2 = right-front, 3 = right-rear.
	var front := (q[0] + q[2]) * 0.5
	var rear := (q[1] + q[3]) * 0.5
	var left := (q[0] + q[1]) * 0.5
	var rgt := (q[2] + q[3]) * 0.5
	var nn := (rgt - left).cross(front - rear)
	if nn.length_squared() < 1e-6:
		return [hit.N, hit.h, false]
	nn = nn.normalized()
	if nn.dot(hit.N) < 0.0:
		nn = -nn
	var centroid := (q[0] + q[1] + q[2] + q[3]) * 0.25
	return [nn, (pos - centroid).dot(nn), ok]


func _constrain(dt: float) -> void:
	track.project(pos, hint, hit)
	hint = hit.i
	var gap := (hit.flags & TrackData.F_GAP) != 0
	# Floor: the hull never enters the surface.
	if not gap and hit.d > -hit.half_l - 1.0 and hit.d < hit.half_r + 1.0 and hit.h < spec.min_clear and hit.h > -6.0:
		pos += hit.N * (spec.min_clear - hit.h)
		var vn := vel.dot(hit.N)
		if vn < 0.0:
			ev_floor = -vn
			vel -= hit.N * vn
			# Hard contact scrubs speed.
			vel *= maxf(0.0, 1.0 - minf(0.25, 0.004 * -vn))
		ev_scrape = true
		hit.h = spec.min_clear
	# Barriers: the hull's extent across the track depends on its yaw.
	var r := fwd.cross(up)
	var hw := absf(fwd.dot(hit.B)) * spec.half_len + absf(r.dot(hit.B)) * spec.half_wid
	hw = minf(hw, minf(hit.half_l, hit.half_r) - 0.5)
	var d_max := hit.half_r - hw
	var d_min := -hit.half_l + hw
	if hit.d > d_max:
		_wall(hit.d - d_max, 1.0, dt)
	elif hit.d < d_min:
		_wall(d_min - hit.d, -1.0, dt)
	# Split-lane islands.
	if not track.islands.is_empty():
		var isl := track.island_at(hit.s)
		if not isl.is_empty():
			var d0: float = isl["d0"]
			var d1: float = isl["d1"]
			if hit.d + hw > d0 and hit.d - hw < d1:
				if hit.d < (d0 + d1) * 0.5:
					_wall(hit.d + hw - d0, 1.0, dt)
				else:
					_wall(d1 - (hit.d - hw), -1.0, dt)


## Resolves penetration `pen` into a barrier on `side` (+1 right, -1 left).
func _wall(pen: float, side: float, dt: float) -> void:
	var nw := hit.B * side   # Points into the barrier.
	pos -= nw * pen
	hit.d -= side * pen
	touching_wall = true
	ev_scrape = true
	var vin := vel.dot(nw)
	if vin > 0.0:
		vel -= nw * vin * (1.0 + spec.wall_e)
		var vt := vel - nw * vel.dot(nw) - hit.N * vel.dot(hit.N)
		var vt_len := vt.length()
		if vt_len > 0.01:
			var loss := minf(spec.wall_mu * vin, vt_len * 0.6)
			vel -= vt / vt_len * loss
		# Kick the nose away from the barrier and straighten it along the wall.
		# Hard hits stun the yaw; a scrape barely touches it, so a ship sliding
		# along the outside wall can still steer away.
		yaw_rate = yaw_rate * (1.0 - clampf(vin / 24.0, 0.0, 0.75)) - side * spec.wall_kick * vin
		var into := fwd.dot(nw)
		if into > 0.0:
			fwd = fwd.rotated(up, side * asin(clampf(into, 0.0, 1.0)) * 0.6).normalized()
		if vin > 4.0:
			energy -= spec.wall_dmg * pow(vin - 4.0, 1.3)
		if vin > ev_wall:
			ev_wall = vin
			ev_wall_side = int(side)
			ev_wall_point = pos + nw * spec.half_wid
	# Sliding along a barrier costs a little speed.
	var vt2 := vel - hit.N * vel.dot(hit.N)
	var l2 := vt2.length()
	if l2 > 0.1:
		vel -= vt2 / l2 * minf(spec.wall_drag * dt, l2)


func _pads() -> void:
	var pad := track.pad_under(hit.i, hit.d)
	if pad.is_empty() or not locked:
		if pad.is_empty():
			_pad_lock = -1
		return
	var idx: int = pad["index"]
	if idx == _pad_lock:
		return
	_pad_lock = idx
	ev_pad = pad["kind"]
	ev_pad_index = idx
	if ev_pad == "boost":
		boost_t = spec.boost_time


## Weapon damage: energy loss and speed loss unless the shield item is up.
## Returns false when the shield absorbed the hit.
func hit_by_weapon(damage: float, speed_loss: float, yaw_kick: float = 0.0, stun: float = 0.0) -> bool:
	if shield_t > 0.0:
		return false
	energy -= damage
	var vn := surf_n * vel.dot(surf_n)
	vel = vn + (vel - vn) * (1.0 - clampf(speed_loss, 0.0, 0.9))
	yaw_rate += yaw_kick
	stun_t = maxf(stun_t, stun)
	return true


## Applies an external impulse (ship-ship contact, weapon hit).
func impulse(dv: Vector3, yaw_kick: float = 0.0) -> void:
	vel += dv
	yaw_rate += yaw_kick


## Puts the ship back on the track after a fall or a wreck.
func respawn() -> void:
	var d := clampf(last_safe_d, -4.0, 4.0)
	place(last_safe_s, d)
