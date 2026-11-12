## Optional steering assist for touch and tilt players. While the player's own
## steering is small, it adds the steering the track's curvature asks for at
## the ship's speed (so the ship holds its line across the track rather than
## being pulled to the centre) and nudges away from a barrier the ship is
## about to touch. It fades out as soon as the player steers, never brakes,
## and does nothing in the air: it is a help, not an autopilot.
class_name SteerAssist
extends RefCounted

const LEVELS := [0.0, 0.4, 0.7]

var _hit := TrackData.Hit.new()


func apply(c: ShipControls, ph: ShipPhysics, level: int) -> void:
	var k: float = LEVELS[clampi(level, 0, 2)]
	if k <= 0.0 or not ph.locked or ph.fwd.dot(ph.hit.T) < 0.7:
		return
	var own := absf(c.steer)
	var fade := clampf(1.0 - (own - 0.03) / 0.12, 0.0, 1.0)
	if fade <= 0.0:
		return
	var spd := maxf(ph.v_fwd, 4.0)
	var w_lim := minf(ph.spec.yaw_low, ph.spec.steer_k * ph.spec.a_lat / spd)
	var kappa := ph.track.curvature_h_at(ph.hit.s + spd * 0.35)
	var ff := spd * kappa / w_lim
	# Heading error relative to the track: hold the current line.
	var head := atan2(ph.fwd.dot(ph.hit.B), ph.fwd.dot(ph.hit.T))
	var assist := ff - head * 1.2
	# Barrier nudge: within 2.5 m of a barrier and closing.
	var room_r := ph.hit.half_r - ph.hit.d
	var room_l := ph.hit.d + ph.hit.half_l
	var vlat := ph.vel.dot(ph.hit.B)
	if room_r < 4.0 and vlat > 0.0:
		assist -= (4.0 - room_r) * 0.12
	elif room_l < 4.0 and vlat < 0.0:
		assist += (4.0 - room_l) * 0.12
	c.steer = clampf(c.steer + clampf(assist, -1.0, 1.0) * k * fade, -1.0, 1.0)
