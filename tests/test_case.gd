class_name TestCase
extends RefCounted
## Base class for unit tests (§53).
##
## A ~100-line in-repo test harness instead of GUT or GdUnit4. §53 requires
## automated tests for the high-risk logic, and the whole application is required
## to work offline with no external services — pulling in a third-party addon for
## assert_eq would add a dependency, a version to track, and a network fetch, for
## something this small.
##
## Tests subclass this and define methods starting with `test_`. The runner finds
## them by reflection, so adding a test is adding a method.
##
## Assertions RECORD failures rather than halting, so one broken expectation does
## not hide the other twenty results in the same file.

var failures: PackedStringArray = PackedStringArray()
var assertion_count: int = 0


## Optional per-test setup, called before each `test_` method.
func before_each() -> void:
	pass


## Optional per-test teardown, called after each `test_` method even if it failed.
func after_each() -> void:
	pass


func assert_true(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		failures.append("%s — expected true, got false" % message)


func assert_false(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		failures.append("%s — expected false, got true" % message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assertion_count += 1
	if actual != expected:
		failures.append("%s — expected %s, got %s" % [message, expected, actual])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	assertion_count += 1
	if actual == unexpected:
		failures.append("%s — expected anything but %s" % [message, unexpected])


## Float comparison with a tolerance. Exact float equality would make tests fail
## for reasons that have nothing to do with the logic under test.
func assert_almost_eq(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	assertion_count += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s — expected %f (±%f), got %f" % [message, expected, tolerance, actual])


func assert_null(value: Variant, message: String) -> void:
	assertion_count += 1
	if value != null:
		failures.append("%s — expected null, got %s" % [message, value])


func assert_not_null(value: Variant, message: String) -> void:
	assertion_count += 1
	if value == null:
		failures.append("%s — expected a value, got null" % message)


func assert_gt(actual: float, threshold: float, message: String) -> void:
	assertion_count += 1
	if actual <= threshold:
		failures.append("%s — expected greater than %f, got %f" % [message, threshold, actual])


func fail(message: String) -> void:
	assertion_count += 1
	failures.append(message)
