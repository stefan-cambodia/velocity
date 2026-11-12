## AI pilot. Reads its own ship's state and the racing line, writes the same
## ShipControls a human produces. It obeys the same physics as the player: no
## rubber-banding, no hidden speed. Difficulty and personality only change
## how close to the profile it drives, how it brakes, where it places itself
## and how consistent it is.
class_name AIDriver
extends RefCounted

## Personalities: pace = fraction of the profile speed, brake_margin = extra
## m/s of braking safety, line_bias = metres towards the outside, aggression =
## willingness to block and squeeze, ab_skill = use of the inside airbrake,
## wobble = steering noise, risk = chance of overcooking a corner.
const STYLES := {
	"technical": {"pace": 0.985, "brake_margin": 1.0, "line_bias": 0.0, "aggression": 0.3, "ab_skill": 1.0, "wobble": 0.01, "risk": 0.02},
	"aggressive": {"pace": 0.99, "brake_margin": 0.0, "line_bias": 0.5, "aggression": 1.0, "ab_skill": 0.8, "wobble": 0.025, "risk": 0.08},
	"defensive": {"pace": 0.975, "brake_margin": 2.0, "line_bias": -0.5, "aggression": 0.7, "ab_skill": 0.7, "wobble": 0.015, "risk": 0.03},
	"speed": {"pace": 1.0, "brake_margin": 0.5, "line_bias": 0.8, "aggression": 0.4, "ab_skill": 0.6, "wobble": 0.02, "risk": 0.05},
	"risk": {"pace": 1.0, "brake_margin": -1.5, "line_bias": 0.3, "aggression": 0.6, "ab_skill": 0.9, "wobble": 0.03, "risk": 0.12},
}
## Difficulty: [pace scale, wobble scale, risk scale].
const DIFFICULTY := [[0.88, 1.8, 1.5], [0.95, 1.0, 1.0], [0.995, 0.5, 0.6]]

var ship: Ship
var line: RacingLine
var style: Dictionary
var pace: float = 1.0
var others: Array = []           ## Other ships (for overtaking / avoidance).
var weapons: WeaponSystem        ## For seeking weapon pads when the item slot is empty.
var name: String = ""

var _rng := RandomNumberGenerator.new()
var _offset: float = 0.0         ## Current lateral offset from the line (overtaking/blocking).
var _offset_target: float = 0.0
var _mistake_t: float = 0.0      ## Seconds left of an overcooked corner.
var _noise_t: float = 0.0
var _stuck_t: float = 0.0
var _hit := TrackData.Hit.new()


func _init(p_ship: Ship, p_line: RacingLine, style_id: String, difficulty: int, seed: int) -> void:
	ship = p_ship
	line = p_line
	style = STYLES.get(style_id, STYLES["technical"])
	var dif: Array = DIFFICULTY[clampi(difficulty, 0, 2)]
	pace = float(style["pace"]) * float(dif[0])
	style = style.duplicate()
	style["wobble"] = float(style["wobble"]) * float(dif[1])
	style["risk"] = float(style["risk"]) * float(dif[2])
	_rng.seed = seed
	_noise_t = _rng.randf() * 100.0


func drive(dt: float) -> void:
	var ph := ship.phys
	var c := ship.controls
	var td := ph.track
	var s := ph.hit.s
	var spd := maxf(ph.v_fwd, 0.0)
	_noise_t += dt
	# --- Where to be across the track.
	_traffic(dt)
	var look := clampf(spd * 0.42, 14.0, 55.0)
	var s_aim := s + look
	var bias := float(style["line_bias"]) * signf(line.k_at(s_aim)) * -1.0
	var d_aim := line.d_at(s_aim) + _offset + bias + _pad_offset(s, spd)
	td.frame_at(s_aim, _hit)
	d_aim = clampf(d_aim, -_hit.half_l + 2.4, _hit.half_r - 2.4)
	var aim := _hit.c + _hit.B * d_aim
	var to := aim - ph.pos
	var r := ph.right()
	var ang := atan2(to.dot(r), to.dot(ph.fwd))
	# --- Steering: feedforward from the line curvature plus pursuit feedback.
	var w_lim := minf(ph.spec.yaw_low, ph.spec.steer_k * ph.spec.a_lat / maxf(spd, 4.0))
	var k_ahead := line.k_at(s + spd * 0.18)
	var ff := spd * k_ahead / w_lim
	var wobble := (sin(_noise_t * 1.7) * 0.6 + sin(_noise_t * 4.3) * 0.4) * float(style["wobble"])
	var steer := ff + ang * 2.3 - (ph.yaw_rate - ff * w_lim) * 0.22 + wobble
	# --- Edge guard: where will the hull be in 0.45 s? Pure pursuit cuts toward a
	# line that runs along the barrier and can overshoot it by a metre at a steep
	# crossing angle. Steer off before contact; silent when running parallel.
	var hw := absf(ph.fwd.dot(ph.hit.B)) * ph.spec.half_len + ph.spec.half_wid + 0.5
	var d_pred := ph.hit.d + ph.vel.dot(ph.hit.B) * 0.45
	var over_r := d_pred - (ph.hit.half_r - hw)
	var over_l := (-ph.hit.half_l + hw) - d_pred
	if over_r > 0.0:
		steer -= over_r * 0.3
	elif over_l > 0.0:
		steer += over_l * 0.3
	# --- Speed.
	var v_t := line.v_min_ahead(s, maxf(spd * 0.6, 20.0)) * pace - float(style["brake_margin"])
	if _mistake_t > 0.0:
		_mistake_t -= dt
		v_t += 6.0
	elif _rng.randf() < float(style["risk"]) * dt * 0.15:
		_mistake_t = 1.2
	var thrust := 1.0
	var brake := 0.0
	if spd > v_t + 1.5:
		thrust = 0.0
		brake = clampf((spd - v_t - 1.5) / 6.0, 0.0, 1.0)
	elif spd > v_t:
		thrust = 0.4
	# --- Airbrakes: the inside brake when steering saturates.
	var ab_l := brake
	var ab_r := brake
	var sat := absf(steer) - 0.92
	if sat > 0.0 and spd > 30.0:
		var amount := clampf(sat * 4.0, 0.0, 1.0) * float(style["ab_skill"])
		if steer > 0.0:
			ab_r = maxf(ab_r, amount)
		else:
			ab_l = maxf(ab_l, amount)
	# --- Recovery: facing the wrong way or wedged.
	var facing := ph.fwd.dot(ph.hit.T)
	if facing < 0.3 or (spd < 6.0 and ph.touching_wall):
		_stuck_t += dt
	else:
		_stuck_t = maxf(0.0, _stuck_t - dt)
	if facing < 0.3:
		var cross := ph.fwd.cross(ph.hit.T).dot(ph.up)
		steer = -1.0 if cross > 0.0 else 1.0
		thrust = 0.6
		ab_l = 0.0
		ab_r = 0.0
	if _stuck_t > 3.0:
		ph.respawn()
		_stuck_t = 0.0
	c.steer = clampf(steer, -1.0, 1.0)
	c.thrust = thrust
	c.ab_l = ab_l
	c.ab_r = ab_r


## Lateral offset towards a reachable pad ahead: boost pads always, weapon
## pads when the item slot is empty. Blends in over the approach and never
## asks for more than 9 m off the racing line.
func _pad_offset(s: float, spd: float) -> float:
	var td := ship.phys.track
	var best := 0.0
	var best_ds := INF
	for pad: Dictionary in td.pads:
		var kind: String = pad["kind"]
		if kind == "weapon" and (weapons == null or not weapons.enabled or weapons.item_of(ship) != ""):
			continue
		var ds := td.delta_s(s, float(pad["s"]) + float(pad["length"]) * 0.5)
		if ds < 6.0 or ds > maxf(150.0, spd * 2.2) or ds > best_ds:
			continue
		var off := float(pad["d"]) - line.d_at(float(pad["s"]))
		if absf(off) > 9.0:
			continue
		best_ds = ds
		# Full offset in the last 60 m, fading in before.
		best = off * clampf((maxf(150.0, spd * 2.2) - ds) / 90.0, 0.0, 1.0)
	return best


## Overtaking and blocking: adjust the lateral offset from the line.
func _traffic(dt: float) -> void:
	var ph := ship.phys
	var td := ph.track
	var my_s := ph.hit.s
	var my_d := ph.hit.d
	var target := 0.0
	var aggression := float(style["aggression"])
	for o: Ship in others:
		if o == ship:
			continue
		var op := o.phys
		var ds := td.delta_s(my_s, op.hit.s)
		var dd := op.hit.d - my_d
		# Ship ahead and we are closing: pick a side.
		if ds > 2.0 and ds < 38.0 and absf(dd) < 4.2:
			var closing := ph.v_fwd - op.v_fwd
			if closing > -1.0:
				var room_l := op.hit.d - (-op.hit.half_l)
				var room_r := op.hit.half_r - op.hit.d
				var side := 1.0 if room_r > room_l else -1.0
				target = op.hit.d + side * 4.6 - line.d_at(my_s + 20.0)
		# Ship close behind: defend by drifting towards its line.
		elif ds < -2.0 and ds > -22.0 and aggression > 0.5 and op.v_fwd > ph.v_fwd:
			target = clampf(dd, -3.0, 3.0) * (aggression - 0.5)
	_offset_target = target
	_offset = move_toward(_offset, _offset_target, 6.0 * dt)
