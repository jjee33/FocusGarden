extends SceneTree
## Headless test runner (§53).
##
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tests/cli_test_runner.gd
##
## Discovers every tests/unit/test_*.gd, runs each `test_` method, prints a
## summary, and EXITS NON-ZERO on failure so this can gate a commit or a build
## rather than being something a human has to read carefully.

const TEST_DIR: String = "res://tests/unit"
const TEST_PREFIX: String = "test_"

var _total_tests: int = 0
var _total_assertions: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	print("\n=== Focus Garden test suite ===\n")

	var files := _discover_test_files()
	if files.is_empty():
		printerr("No test files found in %s" % TEST_DIR)
		quit(1)
		return

	for path: String in files:
		_run_file(path)

	_print_summary()
	quit(1 if not _failures.is_empty() else 0)


func _discover_test_files() -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(TEST_DIR):
		return found
	var names := DirAccess.get_files_at(TEST_DIR)
	# Sorted so a failure is reproducible in the same order every run.
	var sorted: Array[String] = []
	for name: String in names:
		# Exported builds may present .gd as .remap; tests only run from source,
		# but stripping it costs nothing and avoids a confusing empty run.
		var clean := name.trim_suffix(".remap")
		if clean.begins_with(TEST_PREFIX) and clean.ends_with(".gd"):
			sorted.append(clean)
	sorted.sort()
	for name: String in sorted:
		found.append(TEST_DIR.path_join(name))
	return found


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failures.append("%s — could not be loaded" % path)
		printerr("  LOAD FAILED  %s" % path)
		return

	var instance: Variant = script.new()
	if not (instance is TestCase):
		_failures.append("%s — does not extend TestCase" % path)
		printerr("  INVALID      %s" % path)
		return

	var suite := instance as TestCase
	var file_name := path.get_file()
	print("• %s" % file_name)

	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with(TEST_PREFIX):
			continue

		_total_tests += 1
		var before := suite.failures.size()
		var assertions_before := suite.assertion_count

		suite.before_each()
		suite.call(method_name)
		suite.after_each()

		# A test that asserted NOTHING did not pass — it either crashed part-way
		# (GDScript reports a runtime error and returns, which this harness cannot
		# catch) or it never checked anything. Both were previously printed as a
		# pass, which is the worst failure mode a test harness has: eight broken
		# tests once reported green this way.
		if suite.assertion_count == assertions_before:
			suite.failures.append("made no assertions — did it crash?")

		var new_failures := suite.failures.size() - before
		if new_failures > 0:
			for i in range(before, suite.failures.size()):
				var detail := "%s::%s — %s" % [file_name, method_name, suite.failures[i]]
				_failures.append(detail)
				printerr("    FAIL  %s" % detail)
		else:
			print("    pass  %s" % method_name)

	_total_assertions += suite.assertion_count


func _print_summary() -> void:
	print("\n--------------------------------------------")
	print("%d tests, %d assertions, %d failures" % [
		_total_tests, _total_assertions, _failures.size()
	])
	if _failures.is_empty():
		print("RESULT: PASS")
	else:
		print("RESULT: FAIL")
		for failure: String in _failures:
			print("  - %s" % failure)
	print("--------------------------------------------\n")
