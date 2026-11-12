## Command-line options for development runs. On Android, where launch intents
## cannot carry them, a debug build also reads a one-shot `user://dev_args.txt`
## (pushed with adb run-as) and deletes it, so a normal launch is never affected.
class_name DevArgs
extends RefCounted

static var _args: PackedStringArray
static var _ready: bool = false


static func all() -> PackedStringArray:
	if _ready:
		return _args
	_ready = true
	_args = OS.get_cmdline_user_args()
	var path := "user://dev_args.txt"
	if OS.is_debug_build() and FileAccess.file_exists(path):
		for a in FileAccess.get_file_as_string(path).split(" ", false):
			_args.append(a.strip_edges())
		DirAccess.remove_absolute(path)
	return _args


static func has(flag: String) -> bool:
	return all().has(flag)
