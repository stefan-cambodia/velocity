## Compiles every script under res://src and res://tests and reports parse errors.
##   godot --headless --path . --import && godot --headless --path . -s tools/check.gd
extends SceneTree

class Counter extends Logger:
	var count: int = 0
	var _lock := Mutex.new()
	func _log_error(_f: String, _file: String, _l: int, _c: String, _r: String, _e: bool, error_type: int, _b: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		count += 1
		_lock.unlock()
	func _log_message(_m: String, _e: bool) -> void:
		pass


func _initialize() -> void:
	var counter := Counter.new()
	OS.add_logger(counter)
	var bad := 0
	var n := 0
	for dir in ["res://src", "res://tests", "res://tools"]:
		for f in _scan(dir):
			n += 1
			var before := counter.count
			var s: Script = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_IGNORE)
			if s == null or counter.count > before:
				print("FAIL ", f)
				bad += 1
	print("%d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)


func _scan(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") and not dir.contains("scratch") and f != "check.gd":
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scan(dir + "/" + sub))
	return out
