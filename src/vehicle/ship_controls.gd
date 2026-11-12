## One frame of driver input, shared by every input source (touch, tilt, keys,
## gamepad) and by the AI, so all ships obey exactly the same controls.
class_name ShipControls
extends RefCounted

var steer: float = 0.0       ## -1 (left) .. 1 (right), after sensitivity curves.
var thrust: float = 0.0      ## 0 .. 1
var ab_l: float = 0.0        ## Left airbrake 0 .. 1
var ab_r: float = 0.0        ## Right airbrake 0 .. 1
var boost: bool = false      ## Fire a stored boost / use item (edge-triggered by the user of the struct).
var fire: bool = false


func clear() -> void:
	steer = 0.0
	thrust = 0.0
	ab_l = 0.0
	ab_r = 0.0
	boost = false
	fire = false


func copy_from(o: ShipControls) -> void:
	steer = o.steer
	thrust = o.thrust
	ab_l = o.ab_l
	ab_r = o.ab_r
	boost = o.boost
	fire = o.fire
