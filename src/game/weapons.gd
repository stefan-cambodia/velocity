## Combat: items from weapon pads, projectiles, mines and area effects.
##
## Projectiles live in *track space* (lap distance s, lateral offset d, height
## h): they follow banks, crests and corners exactly, cannot pass through
## barriers or tunnel into the ground, and cost almost nothing to simulate.
## Hits are tested in the same coordinates as the ships. Pure logic: the
## visuals (WeaponFx) and sounds read `events` and the live lists.
class_name WeaponSystem
extends RefCounted

const ITEMS := {
	"plasma": {"name": "PLASMA BOLTS", "ammo": 3},
	"missile": {"name": "SEEKER MISSILE", "ammo": 1},
	"emp": {"name": "EMP PULSE", "ammo": 1},
	"shockwave": {"name": "SHOCKWAVE", "ammo": 1},
	"shield": {"name": "ENERGY SHIELD", "ammo": 1},
	"mines": {"name": "MINE BARRIER", "ammo": 1},
	"turbo": {"name": "TURBO", "ammo": 1},
	"repair": {"name": "REPAIR", "ammo": 1},
}
## Pad odds by race position: leaders get defensive tools, the back of the
## field more ways to fight back. Speed is never handed out beyond the turbo
## item itself (no hidden catch-up).
const TABLES := [
	{"plasma": 3, "shield": 3, "mines": 3, "turbo": 1, "repair": 2, "emp": 1},
	{"plasma": 3, "missile": 2, "mines": 2, "turbo": 2, "shield": 2, "emp": 2, "shockwave": 1, "repair": 1},
	{"plasma": 2, "missile": 3, "turbo": 3, "shockwave": 2, "emp": 2, "repair": 2},
]
## Tuning: damage (shield energy), speed loss (fraction), yaw kick (rad/s), stun (s).
const PLASMA := {"speed": 160.0, "life": 2.2, "damage": 12.0, "loss": 0.12, "kick": 0.35, "stun": 0.0, "r_s": 3.5, "r_d": 2.2}
const MISSILE := {"speed": 110.0, "accel": 60.0, "life": 4.5, "damage": 26.0, "loss": 0.3, "kick": 1.3, "stun": 0.6, "r_s": 4.0, "r_d": 2.6, "steer": 14.0, "range": 320.0}
const SHOCK := {"speed": 120.0, "range": 230.0, "damage": 14.0, "loss": 0.35, "stun": 0.3}
const EMP := {"radius": 36.0, "damage": 9.0, "stun": 1.1}
const MINE := {"damage": 18.0, "loss": 0.25, "kick": 0.9, "life": 30.0, "r_s": 2.6, "r_d": 2.1}

class Proj:
	var kind: String = ""
	var owner: Ship
	var target: Ship
	var s: float = 0.0
	var d: float = 0.0
	var h: float = 1.0
	var speed: float = 0.0
	var life: float = 0.0
	var travelled: float = 0.0
	var hit_set: Array = []        ## Ships already hit (shockwave hits each once).

class Mine:
	var owner: Ship
	var s: float = 0.0
	var d: float = 0.0
	var life: float = 0.0

var track: TrackData
var ships: Array = []
var enabled: bool = true
var combat: bool = false           ## Combat mode: everyone draws from the aggressive table.
var slot: Dictionary = {}          ## Ship -> {"item": String, "ammo": int}
var projectiles: Array[Proj] = []
var mines: Array[Mine] = []
## Events since the last drain: {type, pos, ship, kind, by}.
var events: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var stats: Dictionary = {}         ## "fire:<kind>" / "hit:<kind>" / "pickup" -> count


func _init(p_track: TrackData, p_ships: Array, seed: int = 99) -> void:
	track = p_track
	ships = p_ships
	rng.seed = seed


func item_of(sh: Ship) -> String:
	return String(slot.get(sh, {}).get("item", ""))


func ammo_of(sh: Ship) -> int:
	return int(slot.get(sh, {}).get("ammo", 0))


## A weapon pad was crossed. `place` 1 = leader, of `count` ships.
func give_random(sh: Ship, place: int, count: int) -> String:
	if not enabled or item_of(sh) != "":
		return ""
	var bucket := 0 if place <= maxi(1, count / 4) else (2 if place > count * 2 / 3 else 1)
	if combat:
		bucket = 2
	var table: Dictionary = TABLES[bucket]
	var total := 0
	for k: String in table:
		total += int(table[k])
	var roll := rng.randi_range(1, total)
	for k: String in table:
		roll -= int(table[k])
		if roll <= 0:
			give(sh, k)
			return k
	return ""


func give(sh: Ship, item: String) -> void:
	slot[sh] = {"item": item, "ammo": int(ITEMS[item]["ammo"])}
	events.append({"type": "pickup", "ship": sh, "kind": item, "pos": sh.phys.pos})


## Uses the ship's item. Returns true if something was fired.
func fire(sh: Ship) -> bool:
	var item := item_of(sh)
	if item == "" or not sh.phys.enabled:
		return false
	var ph := sh.phys
	match item:
		"plasma":
			_spawn("plasma", sh, ph.v_fwd + float(PLASMA["speed"]), float(PLASMA["life"]), null)
		"missile":
			_spawn("missile", sh, ph.v_fwd + float(MISSILE["speed"]), float(MISSILE["life"]), _lock_target(sh))
		"shockwave":
			var p := _spawn("shockwave", sh, ph.v_fwd + float(SHOCK["speed"]), 999.0, null)
			p.d = 0.0
		"emp":
			for o: Ship in ships:
				if o != sh and o.phys.enabled and o.phys.pos.distance_to(ph.pos) < float(EMP["radius"]):
					if o.phys.hit_by_weapon(float(EMP["damage"]), 0.0, 0.0, float(EMP["stun"])):
						events.append({"type": "hit", "ship": o, "kind": "emp", "by": sh, "pos": o.phys.pos})
		"shield":
			ph.shield_t = 4.0
		"mines":
			for k in 3:
				var m := Mine.new()
				m.owner = sh
				m.s = track.wrap_s(ph.hit.s - 7.0 - k * 2.0)
				var hit := TrackData.Hit.new()
				track.frame_at(m.s, hit)
				m.d = clampf(ph.hit.d + (k - 1) * 4.5, -hit.half_l + 2.0, hit.half_r - 2.0)
				m.life = float(MINE["life"])
				mines.append(m)
		"turbo":
			ph.boost_t = maxf(ph.boost_t, 2.0)
		"repair":
			ph.energy = minf(ph.spec.shield, ph.energy + 35.0)
	events.append({"type": "fire", "ship": sh, "kind": item, "pos": ph.pos})
	var sl: Dictionary = slot[sh]
	sl["ammo"] = int(sl["ammo"]) - 1
	if int(sl["ammo"]) <= 0:
		slot.erase(sh)
	return true


func _spawn(kind: String, sh: Ship, speed: float, life: float, target: Ship) -> Proj:
	var p := Proj.new()
	p.kind = kind
	p.owner = sh
	p.target = target
	p.s = track.wrap_s(sh.phys.hit.s + 4.0)
	p.d = sh.phys.hit.d
	p.h = 1.2
	p.speed = speed
	p.life = life
	projectiles.append(p)
	return p


## The nearest ship ahead within the missile's range (and roughly in front).
func _lock_target(sh: Ship) -> Ship:
	var best: Ship = null
	var best_ds := float(MISSILE["range"])
	for o: Ship in ships:
		if o == sh or not o.phys.enabled:
			continue
		var ds := track.delta_s(sh.phys.hit.s, o.phys.hit.s)
		if ds > 5.0 and ds < best_ds:
			best_ds = ds
			best = o
	return best


## Ship the missile from `sh` would lock on to (for HUD/AI), or null.
func would_lock(sh: Ship) -> Ship:
	return _lock_target(sh)


func tick(dt: float) -> void:
	if not enabled:
		projectiles.clear()
		mines.clear()
		return
	var keep: Array[Proj] = []
	for p in projectiles:
		if _advance(p, dt):
			keep.append(p)
	projectiles = keep
	var keep_m: Array[Mine] = []
	for m in mines:
		m.life -= dt
		var alive := m.life > 0.0
		if alive:
			for o: Ship in ships:
				if not o.phys.enabled:
					continue
				if absf(track.delta_s(m.s, o.phys.hit.s)) < float(MINE["r_s"]) and absf(m.d - o.phys.hit.d) < float(MINE["r_d"]) and o.phys.hit.h < 4.0:
					var kick := float(MINE["kick"]) * (1.0 if rng.randf() < 0.5 else -1.0)
					if o.phys.hit_by_weapon(float(MINE["damage"]), float(MINE["loss"]), kick):
						events.append({"type": "hit", "ship": o, "kind": "mine", "by": m.owner, "pos": o.phys.pos})
					else:
						events.append({"type": "blocked", "ship": o, "kind": "mine", "pos": o.phys.pos})
					alive = false
					break
		if alive:
			keep_m.append(m)
	mines = keep_m


## Moves one projectile; returns false when it is spent.
func _advance(p: Proj, dt: float) -> bool:
	p.life -= dt
	if p.life <= 0.0:
		return false
	if p.kind == "missile":
		p.speed += float(MISSILE["accel"]) * dt
		if p.target != null and p.target.phys.enabled:
			p.d = move_toward(p.d, p.target.phys.hit.d, float(MISSILE["steer"]) * dt)
	var step := p.speed * dt
	var s0 := p.s
	p.s = track.wrap_s(p.s + step)
	p.travelled += step
	var hit := TrackData.Hit.new()
	track.frame_at(p.s, hit)
	p.d = clampf(p.d, -hit.half_l + 0.8, hit.half_r - 0.8)
	if p.kind == "shockwave":
		if p.travelled > float(SHOCK["range"]):
			return false
		for o: Ship in ships:
			if o == p.owner or p.hit_set.has(o) or not o.phys.enabled:
				continue
			# The wave front swept past the ship this step (anywhere across the track).
			var a := track.delta_s(s0, o.phys.hit.s)
			if a >= -1.0 and a <= step + 1.0:
				p.hit_set.append(o)
				if o.phys.hit_by_weapon(float(SHOCK["damage"]), float(SHOCK["loss"]), 0.0, float(SHOCK["stun"])):
					events.append({"type": "hit", "ship": o, "kind": "shockwave", "by": p.owner, "pos": o.phys.pos})
		return true
	var cfg: Dictionary = PLASMA if p.kind == "plasma" else MISSILE
	for o: Ship in ships:
		if o == p.owner or not o.phys.enabled:
			continue
		# Swept test along s so a fast bolt cannot skip over a ship in one step.
		var a := track.delta_s(s0, o.phys.hit.s)
		if a >= -float(cfg["r_s"]) and a <= step + float(cfg["r_s"]) and absf(p.d - o.phys.hit.d) < float(cfg["r_d"]):
			var kick := float(cfg["kick"]) * (1.0 if p.d < o.phys.hit.d else -1.0)
			if o.phys.hit_by_weapon(float(cfg["damage"]), float(cfg["loss"]), kick, float(cfg["stun"])):
				events.append({"type": "hit", "ship": o, "kind": p.kind, "by": p.owner, "pos": o.phys.pos})
			else:
				events.append({"type": "blocked", "ship": o, "kind": p.kind, "pos": o.phys.pos})
			return false
	return true


## World position of a projectile or mine for drawing.
func world_pos(s: float, d: float, h: float) -> Vector3:
	return track.point_at(s, d, h)


func drain_events() -> Array[Dictionary]:
	for ev in events:
		var key: String = ev["type"] + (":" + String(ev.get("kind", "")) if ev["type"] != "pickup" else "")
		stats[key] = int(stats.get(key, 0)) + 1
	var e := events
	events = []
	return e


## Simple, readable AI rules. `aggression` 0..1 from the pilot's personality.
func ai_wants_fire(sh: Ship, aggression: float) -> bool:
	var item := item_of(sh)
	if item == "":
		return false
	var ph := sh.phys
	match item:
		"plasma":
			for o: Ship in ships:
				if o == sh:
					continue
				var ds := track.delta_s(ph.hit.s, o.phys.hit.s)
				if ds > 6.0 and ds < 90.0 + 60.0 * aggression and absf(o.phys.hit.d - ph.hit.d) < 2.5:
					return true
		"missile", "shockwave":
			var t := _lock_target(sh)
			return t != null and track.delta_s(ph.hit.s, t.phys.hit.s) < 160.0 + 120.0 * aggression
		"emp":
			for o: Ship in ships:
				if o != sh and o.phys.pos.distance_to(ph.pos) < float(EMP["radius"]) * 0.8:
					return true
		"mines":
			for o: Ship in ships:
				var ds := track.delta_s(ph.hit.s, o.phys.hit.s)
				if o != sh and ds < -8.0 and ds > -70.0:
					return true
		"shield":
			if ph.energy < 45.0:
				return true
			for p in projectiles:
				if p.kind == "missile" and p.target == sh:
					return true
		"repair":
			return ph.energy < ph.spec.shield * 0.62
		"turbo":
			return absf(track.curvature_h_at(ph.hit.s + 80.0)) < 0.002 and absf(track.curvature_h_at(ph.hit.s + 160.0)) < 0.002
	return false


## True when a missile is homing on `sh` (HUD warning).
func missile_on(sh: Ship) -> bool:
	for p in projectiles:
		if p.kind == "missile" and p.target == sh:
			return true
	return false
