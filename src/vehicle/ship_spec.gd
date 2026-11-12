## Every handling parameter of one ship in one speed class. Pure data: the
## simulation (ShipPhysics) reads it, the handling bench and telemetry overlay
## tune it. Team ratings (1..10) map onto it in from_ratings().
class_name ShipSpec
extends RefCounted

## Speed classes: [name, top speed m/s, base acceleration m/s²].
const CLASSES := [
	{"id": "spark", "name": "SPARK", "v_top": 72.0, "accel": 21.0},
	{"id": "arc", "name": "ARC", "v_top": 90.0, "accel": 25.0},
	{"id": "nova", "name": "NOVA", "v_top": 110.0, "accel": 30.0},
	{"id": "quasar", "name": "QUASAR", "v_top": 130.0, "accel": 35.0},
]
## Displayed speed = m/s * 3.6 * SPEED_SCALE (the league's fictional scale, see docs/ARCHITECTURE.md).
const SPEED_SCALE := 2.0

# --- Engine -----------------------------------------------------------------
var v_top: float = 90.0          ## Top speed at full thrust (m/s).
var accel: float = 25.0          ## Thrust acceleration at rest (m/s²); equals drag at v_top.
var coast: float = 0.35          ## Fraction of drag that remains with the throttle closed.
var reverse_damp: float = 3.0    ## Resists travelling backwards (1/s).

# --- Handling ---------------------------------------------------------------
var a_lat: float = 36.0          ## Lateral force capacity of the flux keels (m/s²).
var yaw_low: float = 1.9         ## Yaw rate limit at low speed (rad/s).
var steer_k: float = 1.08        ## Full steer asks for steer_k × a_lat / v of yaw rate.
var yaw_response: float = 7.5    ## How quickly the yaw rate follows its target (1/s).
var align: float = 9.0           ## How quickly the velocity turns towards the nose (1/s), within a_lat.
var scrub: float = 0.5           ## Speed lost per second per unit sin(slip angle).
var air_control: float = 0.35    ## Steering authority in the air.

# --- Airbrakes ----------------------------------------------------------------
var ab_drag: float = 0.11        ## Per brake: deceleration = ab_drag × v (1/s).
var ab_yaw: float = 0.62         ## Per brake: yaw added, as a fraction of the steering limit.
var ab_grip: float = 0.16        ## Per brake: extra lateral capacity (fraction of a_lat).

# --- Hover (flux lock) -------------------------------------------------------
var hover_h: float = 1.05        ## Rest height of the hull centre above the surface (m).
var hover_k: float = 420.0       ## Spring stiffness (1/s²).
var hover_c: float = 34.0        ## Damping (1/s).
var pull_max: float = 24.0       ## Maximum pull towards the surface on crests (m/s²).
var g_track: float = 16.0        ## Track gravity along -N while locked (m/s²).
var lock_h: float = 6.0          ## Above this height the lock breaks (airborne).
var g_air: float = 15.0          ## Gravity in the air (m/s²); stronger than 1 g so jumps stay snappy.
var planar_g: float = 1.0        ## Share of world gravity acting along the surface (slopes, banks).
var min_clear: float = 0.38      ## The hull centre never goes closer to the surface than this.
var up_rate: float = 11.0        ## Surface alignment rate (1/s).
var probe_len: float = 2.3       ## Probe offsets from the centre (m).
var probe_wid: float = 1.1

# --- Body ---------------------------------------------------------------------
var half_len: float = 2.8
var half_wid: float = 1.3
var mass: float = 1.0

# --- Contact -------------------------------------------------------------------
var wall_e: float = 0.22         ## Restitution against barriers.
var wall_mu: float = 0.5         ## Speed lost per unit of impact speed.
var wall_drag: float = 3.0       ## Extra deceleration while scraping (m/s²).
var wall_kick: float = 0.03      ## Yaw rate (rad/s) per m/s of impact.
var wall_dmg: float = 0.25       ## Energy lost = wall_dmg × (impact speed − 4)^1.3.

# --- Energy and boost -----------------------------------------------------------
var shield: float = 100.0
var boost_accel: float = 32.0
var boost_top: float = 1.2       ## Top-speed multiplier while boosting.
var boost_time: float = 1.2      ## Seconds per speed pad.
var recharge_rate: float = 4.5   ## Shield energy per second on a recharge strip.


func duplicate_spec() -> ShipSpec:
	var o := ShipSpec.new()
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			o.set(p["name"], get(p["name"]))
	return o


## Builds a spec from team ratings (1..10 each: speed, thrust, handling,
## stability, shield, airbrake) for a speed class index. Rating 5 is the
## reference ship; every point is a few percent.
static func from_ratings(r: Dictionary, class_idx: int = 1) -> ShipSpec:
	var s := ShipSpec.new()
	var c: Dictionary = CLASSES[clampi(class_idx, 0, CLASSES.size() - 1)]
	var k := func(key: String) -> float: return (float(r.get(key, 5)) - 5.0) / 5.0   # -0.8 .. 1.0
	var cls_scale := float(c["v_top"]) / 90.0
	s.v_top = float(c["v_top"]) * (1.0 + 0.045 * k.call("speed"))
	s.accel = float(c["accel"]) * (1.0 + 0.12 * k.call("thrust"))
	# Lateral capacity grows with the class (faster ships corner harder) but
	# less than speed does, so faster classes are genuinely harder.
	s.a_lat = 36.0 * pow(cls_scale, 0.85) * (1.0 + 0.08 * k.call("handling"))
	s.yaw_response = 7.5 * (1.0 + 0.15 * k.call("handling"))
	s.yaw_low = 1.9 * (1.0 + 0.08 * k.call("handling"))
	s.align = 9.0 * (1.0 + 0.2 * k.call("stability"))
	s.scrub = 0.5 * (1.0 - 0.2 * k.call("stability"))
	s.shield = 100.0 * (1.0 + 0.25 * k.call("shield"))
	s.ab_drag = 0.11 * (1.0 + 0.15 * k.call("airbrake"))
	s.ab_yaw = 0.62 * (1.0 + 0.18 * k.call("airbrake"))
	s.ab_grip = 0.16 * (1.0 + 0.25 * k.call("airbrake"))
	s.wall_dmg = 0.25 * (1.0 - 0.2 * k.call("shield"))
	s.g_track = 16.0 * pow(cls_scale, 0.5)
	s.pull_max = 24.0 * pow(cls_scale, 0.8)
	return s
