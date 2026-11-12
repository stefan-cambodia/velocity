## Runs every tests/unit/test_*.gd. Usage:
##   godot --headless --path . -s tests/run_tests.gd [-- --filter=name] [--verbose]
extends SceneTree

## Counts engine and script errors, so a test that dies on a script error (and
## so never reaches its assertions) fails instead of passing silently.
class ErrorCounter extends Logger:
	var count: int = 0
	var last: String = ""
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		count += 1
		last = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var filter := ""
	var verbose := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
		elif a == "--verbose":
			verbose = true
	var dir := DirAccess.open("res://tests/unit")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var asserts := 0
	var t0 := Time.get_ticks_msec()
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null:
			print("FAIL  %s could not be loaded" % f)
			failed += 1
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + "." + name).contains(filter):
				continue
			var tc: TestCase = script.new()
			tc.host = root
			tc.set_current(name)
			var errors_before := errors.count
			tc.call(name)
			if errors.count > errors_before:
				tc.fail("%d engine/script error(s), last: %s" % [errors.count - errors_before, errors.last])
			total += 1
			asserts += tc.assertions
			if tc.failures.size() > 0:
				failed += 1
				for msg in tc.failures:
					print("FAIL  %s  %s" % [f, msg])
			if verbose or tc.failures.size() > 0:
				for n in tc.notes:
					print("      %s  %s" % [f, n])
	print("%d tests, %d assertions, %d failed (%.1f s)" % [total, asserts, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)
