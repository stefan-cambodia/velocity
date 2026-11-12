## Minimal test base: subclasses in tests/unit/test_*.gd define test_* methods.
class_name TestCase
extends RefCounted

var failures: PackedStringArray = []
var assertions: int = 0
var notes: PackedStringArray = []
var _current: String = ""
var host: Node


func set_current(name: String) -> void:
	_current = name


func note(text: String) -> void:
	notes.append("%s: %s" % [_current, text])


func fail(message: String) -> void:
	failures.append("%s: %s" % [_current, message])


func ok(condition: bool, message: String = "") -> void:
	assertions += 1
	if not condition:
		fail("expected true. " + message)


func eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if actual != expected:
		fail("expected %s, got %s. %s" % [str(expected), str(actual), message])


func near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		fail("expected %.3f +- %.3f, got %.3f. %s" % [expected, tolerance, actual, message])


func between(actual: float, lo: float, hi: float, message: String = "") -> void:
	assertions += 1
	if actual < lo or actual > hi:
		fail("expected %.3f..%.3f, got %.3f. %s" % [lo, hi, actual, message])
