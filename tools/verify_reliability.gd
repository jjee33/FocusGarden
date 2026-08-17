extends SceneTree
## Reliability checks against real files on disk (§67).
##
##     ... --headless --path . --script res://tools/verify_reliability.gd
##
## Unit tests cover the save logic with fabricated dictionaries. These exercise
## the same code against the actual filesystem, because the failures §67 asks
## about — a truncated file, a half-finished swap, a save from a newer build —
## are properties of the IO path, not of the parsing.
##
## Runs in a scratch directory and cleans up, so it never touches a real save.

const SCRATCH: String = "user://reliability_probe"

var _problems: PackedStringArray = PackedStringArray()
var _checks: int = 0


func _init() -> void:
	await process_frame
	_reset_scratch()

	print("\n=== Reliability checks ===\n")
	_check_atomic_write_and_read()
	_check_truncated_file_recovers_from_backup()
	_check_orphaned_temp_file_is_used()
	_check_garbage_file_is_survivable()
	_check_future_version_is_refused()
	_check_migration_chain()
	_check_large_session_dataset()

	_cleanup()
	print("\n--------------------------------------------")
	if _problems.is_empty():
		print("%d checks passed" % _checks)
		print("RESULT: PASS")
		print("--------------------------------------------\n")
		quit(0)
		return
	print("RESULT: FAIL")
	for problem: String in _problems:
		print("  - %s" % problem)
	print("--------------------------------------------\n")
	quit(1)


func _check(description: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % description)
		return
	print("  FAIL %s" % description)
	_problems.append("%s%s" % [description, "" if detail.is_empty() else " — %s" % detail])


func _check_atomic_write_and_read() -> void:
	print("• atomic write and read back")
	var path := SCRATCH.path_join("profile.json")
	var payload := {"save_version": 1, "player": {"display_name": "Probe"}}

	var error := AtomicFile.write_json(path, payload, SCRATCH.path_join("backups"))
	_check("write returns OK", error == OK, "error %d" % error)
	_check("the file exists", FileAccess.file_exists(path))

	var read := AtomicFile.read_json_with_recovery(path, SCRATCH.path_join("backups"))
	_check("it reads back", read.exists())
	_check("without needing recovery", not read.recovered)
	_check(
		"and the contents survive",
		DictUtil.get_string(DictUtil.get_dict(read.data, "player"), "display_name") == "Probe"
	)


func _check_truncated_file_recovers_from_backup() -> void:
	print("• a truncated save falls back to its backup")
	var path := SCRATCH.path_join("profile.json")
	var backups := SCRATCH.path_join("backups")

	# Two writes, so a backup of the first exists.
	AtomicFile.write_json(path, {"save_version": 1, "marker": "first"}, backups)
	AtomicFile.write_json(path, {"save_version": 1, "marker": "second"}, backups)

	# Truncate mid-object, exactly as a crash during a naive write would.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{\"save_version\": 1, \"marker\": \"tru")
	file.close()

	var read := AtomicFile.read_json_with_recovery(path, backups)
	_check("the truncated file still yields data", read.exists())
	_check("flagged as recovered", read.recovered)
	_check(
		"from the previous good copy",
		DictUtil.get_string(read.data, "marker") == "first",
		"got '%s'" % DictUtil.get_string(read.data, "marker")
	)


func _check_orphaned_temp_file_is_used() -> void:
	print("• a leftover .tmp from an interrupted swap is used")
	_reset_scratch()
	var path := SCRATCH.path_join("profile.json")

	# The state after a crash between removing the real file and renaming the
	# verified temp into place. The temp is the freshest complete data.
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var tmp := FileAccess.open(path + AtomicFile.TMP_SUFFIX, FileAccess.WRITE)
	tmp.store_string(JSON.stringify({"save_version": 1, "marker": "from_tmp"}))
	tmp.close()

	var read := AtomicFile.read_json_with_recovery(path, SCRATCH.path_join("backups"))
	_check("the temp file is found", read.exists())
	_check("and recognised as a recovery", read.recovered)
	_check("with its contents intact", DictUtil.get_string(read.data, "marker") == "from_tmp")


func _check_garbage_file_is_survivable() -> void:
	print("• a file that is not JSON at all")
	_reset_scratch()
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var path := SCRATCH.path_join("profile.json")

	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("this is not a save file, it is a photograph of a cat")
	file.close()

	var read := AtomicFile.read_json_with_recovery(path, SCRATCH.path_join("backups"))
	_check("it reports nothing loadable rather than crashing", not read.exists())

	# And the game must still be playable afterwards.
	var save := SaveData.from_dict({})
	_check("a save can still be built from nothing", save != null)
	_check("with a usable default profile", save.profile.display_name == "Gardener")


func _check_future_version_is_refused() -> void:
	print("• a save from a newer build is refused, not erased")
	var future := {"save_version": SaveData.CURRENT_VERSION + 5, "player": {"total_xp": 999}}
	var result := SaveMigrations.migrate(future)

	_check(
		"the status is FUTURE_VERSION",
		result.status == SaveMigrations.Status.FUTURE_VERSION
	)
	_check("and the original data is untouched", DictUtil.get_int(future, "save_version") == SaveData.CURRENT_VERSION + 5)


func _check_migration_chain() -> void:
	print("• a multi-step migration chain")
	var chain: Array[Dictionary] = [
		{"from": 1, "to": 2, "apply": func(data: Dictionary) -> Dictionary:
			data["step_one"] = true
			return data},
		{"from": 2, "to": 3, "apply": func(data: Dictionary) -> Dictionary:
			data["step_two"] = true
			return data},
	]

	var result := SaveMigrations.migrate({"save_version": 1}, 3, chain)
	_check("it completes", result.is_ok())
	_check("running both steps in order", result.applied_steps.size() == 2)
	_check("the first applied", DictUtil.get_bool(result.data, "step_one"))
	_check("the second applied", DictUtil.get_bool(result.data, "step_two"))
	_check("and the version updated", DictUtil.get_int(result.data, "save_version") == 3)

	# A gap must be reported rather than silently half-migrating.
	var gapped: Array[Dictionary] = [
		{"from": 1, "to": 2, "apply": func(data: Dictionary) -> Dictionary: return data},
	]
	var broken := SaveMigrations.migrate({"save_version": 1}, 3, gapped)
	_check("a gap in the chain is reported", broken.status == SaveMigrations.Status.NO_PATH)


## §64: large session datasets must stay responsive.
func _check_large_session_dataset() -> void:
	print("• five years of sessions")
	_reset_scratch()

	var sessions: Array[FocusSession] = []
	var now := Time.get_unix_time_from_system()
	for i in 5000:
		var session := FocusSession.new()
		session.id = Uid.generate("s")
		session.started_at_utc = now - float(i) * 3600.0
		session.date_key = TimeUtil.local_date_key(session.started_at_utc)
		session.start_hour = TimeUtil.local_hour(session.started_at_utc)
		session.actual_focus_minutes = 25.0
		session.intended_duration_minutes = 25.0
		session.awards_applied = true
		sessions.append(session)

	var write_start := Time.get_ticks_msec()
	var error := SessionStore.save_all(SCRATCH, sessions)
	var write_ms := Time.get_ticks_msec() - write_start
	_check("5000 sessions write", error == OK, "error %d" % error)
	print("       write: %d ms" % write_ms)

	var read_start := Time.get_ticks_msec()
	var loaded := SessionStore.load_all(SCRATCH)
	var read_ms := Time.get_ticks_msec() - read_start
	_check("and load back", loaded.size() == 5000, "got %d" % loaded.size())
	print("       read:  %d ms" % read_ms)

	var aggregate_start := Time.get_ticks_msec()
	var context := RequirementContext.new()
	context.ingest_sessions(loaded)
	var streak := StreakCalculator.calculate(loaded, 25.0)
	var aggregate_ms := Time.get_ticks_msec() - aggregate_start
	print("       aggregate: %d ms (%d days, streak %d)" % [
		aggregate_ms, context.unique_focus_days.size(), streak.longest
	])

	# A screen open must not stall. Anything approaching a second here would be
	# felt as a hang on the statistics screen.
	_check("aggregation stays under 500 ms", aggregate_ms < 500, "took %d ms" % aggregate_ms)
	_check("loading stays under 2000 ms", read_ms < 2000, "took %d ms" % read_ms)


func _reset_scratch() -> void:
	_purge(SCRATCH.path_join("backups"))
	_purge(SessionStore.sessions_dir(SCRATCH))
	_purge(SCRATCH)
	DirAccess.make_dir_recursive_absolute(SCRATCH)


func _cleanup() -> void:
	_purge(SCRATCH.path_join("backups"))
	_purge(SessionStore.sessions_dir(SCRATCH))
	_purge(SCRATCH)


func _purge(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
