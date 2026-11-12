## Race rules: grid, countdown, laps, positions, finishing, results.
##
## Progress is a continuous signed distance (lap × length + s) advanced by the
## local change of s every tick, so laps cannot be skipped by cutting across a
## looping layout and a respawn cannot gain ground. The grid sits behind the
## line (negative progress); lap 1 starts at the line.
class_name RaceSession
extends RefCounted

enum State { COUNTDOWN, RACING, FINISHED }

const COUNTDOWN_TIME := 3.6
const GRID_ROW := 15.0
const GRID_COL := 5.0

class Racer:
	var ship: Ship
	var name: String = ""
	var team: String = ""
	var is_player: bool = false
	var progress: float = 0.0
	var last_s: float = 0.0
	var lap: int = 0                 ## Laps completed.
	var lap_start: float = 0.0
	var last_lap: float = 0.0
	var best_lap: float = 0.0
	var finished: bool = false
	var finish_time: float = 0.0
	var eliminated: bool = false
	var place: int = 0
	var lap_times: PackedFloat32Array = []
	var wall_hits: int = 0
	var top_speed: float = 0.0
	var points: int = 0             ## Combat mode.
	var knocked_out: bool = false   ## Elimination mode (timer), as opposed to shield loss.

signal lap_completed(r: Racer)
signal racer_finished(r: Racer)
signal racer_eliminated(r: Racer)

var track: TrackData
var laps: int = 3
var state: int = State.COUNTDOWN
var countdown: float = COUNTDOWN_TIME
var time: float = 0.0               ## Race clock (starts at GO).
var racers: Array[Racer] = []
var player: Racer
var wrong_way: bool = false
var finish_wait: float = 0.0        ## Seconds since the player finished.
## "race", "time_trial", "practice", "elimination", "combat", "speed".
var mode: String = "race"
const KNOCKOUT_EVERY := 35.0
var knockout_t: float = KNOCKOUT_EVERY
## Speed challenge targets (lap times, seconds): [gold, silver, bronze].
var targets: PackedFloat32Array = []
const COMBAT_HIT := 100
const COMBAT_KO := 500


func _init(p_track: TrackData, p_laps: int, p_mode: String = "race") -> void:
	track = p_track
	laps = p_laps
	mode = p_mode
	if mode == "elimination":
		laps = 999


## Speed challenge: targets from the racing line's ideal lap estimate.
func set_targets(ideal_lap: float) -> void:
	targets = PackedFloat32Array([ideal_lap * 1.0, ideal_lap * 1.06, ideal_lap * 1.14])


func medal(lap_time: float) -> int:
	if lap_time <= 0.0 or targets.is_empty():
		return 0
	for k in 3:
		if lap_time <= targets[k]:
			return 3 - k        # 3 gold, 2 silver, 1 bronze
	return 0


func add_points(sh: Ship, n: int) -> void:
	for r in racers:
		if r.ship == sh:
			r.points += n


func active_count() -> int:
	var n := 0
	for r in racers:
		if not r.eliminated and not r.finished:
			n += 1
	return n


func add(ship: Ship, name: String, team: String, is_player: bool) -> Racer:
	var r := Racer.new()
	r.ship = ship
	r.name = name
	r.team = team
	r.is_player = is_player
	racers.append(r)
	if is_player:
		player = r
	return r


## Grid slot k (0 = pole): staggered two-wide rows behind the line.
func grid_slot(k: int) -> Vector2:
	var row := k / 2
	var col := -1.0 if k % 2 == 0 else 1.0
	var s := -12.0 - row * GRID_ROW - (GRID_ROW * 0.5 if k % 2 == 1 else 0.0)
	return Vector2(s, col * GRID_COL)


func place_on_grid() -> void:
	for k in racers.size():
		var r := racers[k]
		var g := grid_slot(k)
		r.ship.place(track.wrap_s(g.x), g.y)
		r.progress = g.x
		r.last_s = track.wrap_s(g.x)
		r.ship.phys.enabled = false


func is_racing() -> bool:
	return state == State.RACING


## Advances the rules by dt (after the ships moved this tick).
func update(dt: float) -> void:
	if state == State.COUNTDOWN:
		_rank()
		countdown -= dt
		if countdown <= 0.0:
			state = State.RACING
			for r in racers:
				r.ship.phys.enabled = true
				r.lap_start = 0.0
		return
	time += dt
	for r in racers:
		if r.eliminated:
			continue
		var ph := r.ship.phys
		var s := ph.hit.s
		var ds := track.delta_s(r.last_s, s)
		r.last_s = s
		r.progress += ds
		r.top_speed = maxf(r.top_speed, ph.v_fwd)
		if ph.ev_wall > 6.0:
			r.wall_hits += 1
		if not r.finished:
			while r.progress >= (r.lap + 1) * track.length:
				_complete_lap(r)
				if r.finished:
					break
			if ph.energy <= 0.0:
				r.eliminated = true
				ph.enabled = false
				racer_eliminated.emit(r)
	_rank()
	if mode == "elimination" and state != State.COUNTDOWN:
		knockout_t -= dt
		if knockout_t <= 0.0 and active_count() > 1:
			knockout_t = KNOCKOUT_EVERY
			_knock_out_last()
		if active_count() == 1:
			for r in racers:
				if not r.eliminated and not r.finished:
					r.finished = true
					r.finish_time = time
					racer_finished.emit(r)
	# Wrong way: the player is moving backwards along the track.
	if player != null and not player.finished:
		var ph := player.ship.phys
		wrong_way = ph.fwd.dot(ph.hit.T) < -0.2 and ph.vel.dot(ph.hit.T) < -2.0
	if state == State.RACING and player != null and (player.finished or player.eliminated):
		state = State.FINISHED
	if state == State.FINISHED:
		finish_wait += dt


func _complete_lap(r: Racer) -> void:
	var t := time - r.lap_start
	r.lap += 1
	r.last_lap = t
	r.lap_times.append(t)
	if r.best_lap <= 0.0 or t < r.best_lap:
		r.best_lap = t
	r.lap_start = time
	lap_completed.emit(r)
	if r.lap >= laps:
		r.finished = true
		r.finish_time = time
		racer_finished.emit(r)


func _knock_out_last() -> void:
	var last: Racer = null
	for r in racers:
		if r.eliminated or r.finished:
			continue
		if last == null or r.progress < last.progress:
			last = r
	if last != null:
		last.eliminated = true
		last.knocked_out = true
		last.ship.phys.enabled = false
		last.finish_time = time
		racer_eliminated.emit(last)


func _rank() -> void:
	var order := racers.duplicate()
	if mode == "combat":
		order.sort_custom(func(a: Racer, b: Racer) -> bool:
			if a.points != b.points:
				return a.points > b.points
			return a.progress > b.progress)
		for k in order.size():
			(order[k] as Racer).place = k + 1
		return
	if mode == "elimination":
		# Survivors by progress, then the knocked-out in reverse order of exit.
		order.sort_custom(func(a: Racer, b: Racer) -> bool:
			if a.eliminated != b.eliminated:
				return b.eliminated
			if a.eliminated:
				return a.finish_time > b.finish_time
			if a.finished != b.finished:
				return a.finished
			return a.progress > b.progress)
		for k in order.size():
			(order[k] as Racer).place = k + 1
		return
	order.sort_custom(func(a: Racer, b: Racer) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		if a.eliminated != b.eliminated:
			return b.eliminated
		return a.progress > b.progress)
	for k in order.size():
		(order[k] as Racer).place = k + 1


func all_done() -> bool:
	for r in racers:
		if not r.finished and not r.eliminated:
			return false
	return true


## Current lap number shown to a racer (1-based, capped at laps).
func lap_shown(r: Racer) -> int:
	return clampi(r.lap + 1, 1, laps)


func current_lap_time(r: Racer) -> float:
	if state == State.COUNTDOWN or r.progress < 0.0:
		return 0.0
	return time - r.lap_start


func results() -> Array:
	var out := []
	var order := racers.duplicate()
	order.sort_custom(func(a: Racer, b: Racer) -> bool: return a.place < b.place)
	for r: Racer in order:
		var t := r.finish_time
		var est := false
		if not r.finished and not r.eliminated and r.progress > 0.0 and time > 1.0 and mode not in ["elimination", "combat"]:
			# Still racing when the results were taken: project the finish at its race pace.
			var remaining := laps * track.length - r.progress
			t = time + remaining / maxf(r.progress / time, 1.0)
			est = true
		out.append({"name": r.name, "team": r.team, "player": r.is_player, "place": r.place, "finished": r.finished or est,
			"estimated": est, "time": t, "best_lap": r.best_lap, "laps": r.lap_times, "eliminated": r.eliminated, "top_speed": r.top_speed,
			"points": r.points, "knocked_out": r.knocked_out})
	return out


func player_result() -> Dictionary:
	if player == null:
		return {}
	return {"place": player.place, "finished": player.finished or (mode == "elimination" and player.knocked_out), "time": player.finish_time,
		"best_lap": player.best_lap, "distance": maxf(player.progress, 0.0), "laps": player.lap_times, "wall_hits": player.wall_hits,
		"top_speed": player.top_speed, "mode": mode, "points": player.points, "medal": medal(player.best_lap), "targets": Array(targets),
		"knocked_out": player.knocked_out}
