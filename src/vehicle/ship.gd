## A ship in the world: owns the simulation (ShipPhysics), the procedural model,
## and the purely visual motion layered on top (lean into corners, pitch under
## acceleration, hover bob, flap and plume animation). The simulation runs on
## the physics tick; the model is drawn at an interpolated pose every frame so
## 90/120 Hz displays stay smooth. Visual motion never feeds back into physics.
class_name Ship
extends Node3D

const SUBSTEPS := 2

var phys: ShipPhysics
var controls := ShipControls.new()
var parts: ShipModel.Parts
var team: Dictionary = {}
var is_player: bool = false
var pilot_name: String = ""

var _prev := Transform3D.IDENTITY
var _cur := Transform3D.IDENTITY
var _visual: Node3D           ## Carries lean/pitch/bob on top of the physics pose.
var _lean: float = 0.0
var _pitch: float = 0.0
var _bob_t: float = 0.0
var _thrust_vis: float = 0.0
var _flap_l_base: Basis
var _flap_r_base: Basis
var _hit_flash: float = 0.0
var _last_energy: float = 0.0


func setup(spec: ShipSpec, track: TrackData, p_team: Dictionary, with_cockpit: bool) -> void:
	team = p_team
	phys = ShipPhysics.new(spec, track)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	parts = ShipModel.build(p_team.get("livery", {}), with_cockpit, p_team.get("design", {}))
	_visual.add_child(parts.root)
	_flap_l_base = parts.flap_l.transform.basis
	_flap_r_base = parts.flap_r.transform.basis
	_last_energy = phys.energy


func place(s: float, d: float) -> void:
	phys.place(s, d)
	_prev = phys.xform()
	_cur = _prev
	global_transform = _cur


## One physics tick (called by the race at 60 Hz, simulated in substeps).
func tick(dt: float) -> void:
	_prev = _cur
	var h := dt / SUBSTEPS
	for k in SUBSTEPS:
		phys.step(h, controls)
		# Keep the strongest event of the tick for FX.
	_cur = phys.xform()


## Called from _process with the physics interpolation fraction.
func draw(frac: float, delta: float) -> void:
	var t := _prev.interpolate_with(_cur, frac)
	global_transform = t
	_animate(delta)


func _animate(delta: float) -> void:
	var ph := phys
	# Lean into corners: proportional to the lateral acceleration the ship is pulling.
	var lean_target := clampf(-ph.yaw_rate * maxf(ph.v_fwd, 0.0) / 9.81 * 0.09, -0.42, 0.42)
	lean_target += (ph.ab_r - ph.ab_l) * -0.06
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-delta * 7.0))
	# Nose dips under braking and lifts under acceleration.
	var pitch_target := clampf(-ph.accel_long * 0.0035, -0.07, 0.07) if ph.locked else 0.0
	_pitch = lerpf(_pitch, pitch_target, 1.0 - exp(-delta * 5.0))
	_bob_t += delta
	var bob := sin(_bob_t * 5.3) * 0.025 + sin(_bob_t * 8.9) * 0.012 if ph.locked else 0.0
	var roll_bob := sin(_bob_t * 3.7) * 0.006
	_visual.transform = Transform3D(Basis.from_euler(Vector3(_pitch, 0.0, _lean + roll_bob)), Vector3(0, bob, 0))
	# Airbrake flaps.
	var a_l := ph.ab_l * deg_to_rad(68.0)
	var a_r := ph.ab_r * deg_to_rad(68.0)
	parts.flap_l.transform.basis = _flap_l_base * Basis(Vector3.RIGHT, -a_l)
	parts.flap_r.transform.basis = _flap_r_base * Basis(Vector3.RIGHT, -a_r)
	# Engines.
	var th := controls.thrust
	if ph.boost_t > 0.0:
		th = 1.5
	_thrust_vis = lerpf(_thrust_vis, th, 1.0 - exp(-delta * 9.0))
	var flicker := 0.92 + 0.08 * sin(_bob_t * 61.0)
	for i in parts.plumes.size():
		var pl := parts.plumes[i]
		pl.set_instance_shader_parameter("thrust", (0.25 + _thrust_vis) * flicker)
		pl.scale = Vector3(1.0, 1.0, 0.35 + _thrust_vis * 0.75)
	for g in parts.glows:
		g.set_instance_shader_parameter("intensity", 0.35 + _thrust_vis * 0.65)
	# Damage flash.
	if ph.energy < _last_energy - 0.5:
		_hit_flash = 1.0
	_last_energy = ph.energy
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)


func set_cockpit(on: bool) -> void:
	if parts.cockpit:
		parts.cockpit.visible = on
	# The canopy is single-sided, so from the pilot's eye it is invisible and
	# the nose and pods stay in view as a speed reference.


## World-space eye point for the cockpit camera (includes visual lean/pitch).
func eye_transform() -> Transform3D:
	return global_transform * _visual.transform * Transform3D(Basis.IDENTITY, parts.eye)


func visual_transform() -> Transform3D:
	return global_transform * _visual.transform
