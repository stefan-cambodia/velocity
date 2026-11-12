## Audio autoload: buses (Music, SFX, Engine, UI), volumes from Settings,
## cached streams, one-shot sounds and a two-deck music player that can
## crossfade between bar-synchronised variations of a song.
extends Node

const BUSES := ["Music", "SFX", "Engine", "UI"]
const ROOT := "res://assets/audio/"

var _cache: Dictionary = {}
var _decks: Array[AudioStreamPlayer] = []
var _active: int = 0
var _ui_pool: Array[AudioStreamPlayer] = []
var _ui_next: int = 0
var music_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# Gentle limiter on the master so stacked one-shots never clip.
	var mi := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(mi) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(mi, lim)
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_decks.append(p)
	for k in 6:
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		_ui_pool.append(u)
	Settings.changed.connect(_on_setting)
	apply_volumes()


func _on_setting(key: String) -> void:
	if key.begins_with("vol_"):
		apply_volumes()


func apply_volumes() -> void:
	_set_bus("Master", Settings.f("vol_master"))
	_set_bus("Music", Settings.f("vol_music"))
	_set_bus("SFX", Settings.f("vol_sfx"))
	_set_bus("UI", Settings.f("vol_sfx"))
	_set_bus("Engine", Settings.f("vol_engine"))


func _set_bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


## Loads "engine/engine_low" etc. Returns null if the file does not exist.
## Loops are set up at runtime (WAV loop points, OGG loop flag).
func stream(path: String, loop: bool = false) -> AudioStream:
	var key := path + ("#L" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var full := ""
	for ext in [".wav", ".ogg"]:
		if ResourceLoader.exists(ROOT + path + ext):
			full = ROOT + path + ext
			break
	if full == "":
		_cache[key] = null
		return null
	var st: AudioStream = load(full)
	if loop:
		st = st.duplicate()
		if st is AudioStreamWAV:
			var w := st as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
	_cache[key] = st
	return st


func ui(name: String, volume_db: float = 0.0) -> void:
	var st := stream("sfx/" + name)
	if st == null:
		return
	var p := _ui_pool[_ui_next]
	_ui_next = (_ui_next + 1) % _ui_pool.size()
	p.stream = st
	p.volume_db = volume_db
	p.play()


## Plays a music file (looping unless `once`), crossfading from what plays now.
## With `sync`, the new song starts at the current playback position (for
## bar-aligned variations of the same song).
func music(id: String, fade: float = 1.0, sync: bool = false, once: bool = false) -> void:
	if id == music_id:
		return
	var st := stream("music/" + id, not once)
	if st == null:
		music_id = id
		return
	var old := _decks[_active]
	var pos := old.get_playback_position() if (sync and old.playing) else 0.0
	_active = 1 - _active
	var nw := _decks[_active]
	nw.stream = st
	nw.volume_db = -40.0
	nw.play(pos)
	music_id = id
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nw, "volume_db", 0.0, fade)
	if old.playing:
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.chain().tween_callback(old.stop)


func stop_music(fade: float = 1.0) -> void:
	music_id = ""
	for d in _decks:
		if d.playing:
			var tw := create_tween()
			tw.tween_property(d, "volume_db", -40.0, fade)
			tw.tween_callback(d.stop)
