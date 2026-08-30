extends TestCase
## AtomicFile (§53, §36).
##
## These tests write real files under user://, because the whole point of the
## class is what happens on disk. Each test starts from a clean directory so one
## run cannot influence the next.

const TEST_DIR: String = "user://test_atomic"
const BACKUP_DIR: String = "user://test_atomic/backups"

var _path: String = TEST_DIR.path_join("save.json")


func before_each() -> void:
	_purge()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func after_each() -> void:
	_purge()


func test_write_then_read_round_trip() -> void:
	var data := {"save_version": 1, "player": {"name": "Fern"}, "count": 7}
	assert_eq(AtomicFile.write_json(_path, data, BACKUP_DIR), OK, "write succeeded")

	var result := AtomicFile.read_json_with_recovery(_path, BACKUP_DIR)
	assert_true(result.exists(), "file was found")
	assert_false(result.recovered, "no recovery was needed")
	assert_eq(result.data["count"], 7, "value survived the round trip")
	assert_eq(result.data["player"]["name"], "Fern", "nested value survived")


func test_missing_file_reports_absent() -> void:
	var result := AtomicFile.read_json_with_recovery(_path, BACKUP_DIR)
	assert_false(result.exists(), "a missing save is reported, not invented")


func test_creates_missing_directories() -> void:
	var nested := TEST_DIR.path_join("a/b/c/save.json")
	assert_eq(AtomicFile.write_json(nested, {"ok": true}, BACKUP_DIR), OK, "nested write succeeded")
	assert_true(FileAccess.file_exists(nested), "the directory tree was created")


func test_overwrite_creates_a_backup() -> void:
	AtomicFile.write_json(_path, {"generation": 1}, BACKUP_DIR)
	AtomicFile.write_json(_path, {"generation": 2}, BACKUP_DIR)

	var backups := AtomicFile.list_backups(_path, BACKUP_DIR)
	assert_gt(float(backups.size()), 0.0, "the previous save was backed up before being replaced")


func test_corrupt_primary_recovers_from_backup() -> void:
	# THE SCENARIO THIS EXISTS FOR: the player's save is truncated by a crash or
	# a bad disk. Their garden must come back, not vanish.
	AtomicFile.write_json(_path, {"generation": 1, "plants": 12}, BACKUP_DIR)
	AtomicFile.write_json(_path, {"generation": 2, "plants": 13}, BACKUP_DIR)

	var corrupt := FileAccess.open(_path, FileAccess.WRITE)
	corrupt.store_string('{"generation": 2, "plants":')  # truncated mid-write
	corrupt.close()

	var result := AtomicFile.read_json_with_recovery(_path, BACKUP_DIR)
	assert_true(result.exists(), "something was recovered")
	assert_true(result.recovered, "the result is flagged as recovered so the user can be told")
	assert_eq(result.data["generation"], 1, "the last good backup was used")


func test_recovers_from_a_leftover_temp_file() -> void:
	# A crash between removing the old file and renaming the new one leaves only
	# the .tmp, which was already verified before the swap began.
	var tmp_path := _path + AtomicFile.TMP_SUFFIX
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	file.store_string('{"generation": 9}')
	file.close()

	var result := AtomicFile.read_json_with_recovery(_path, BACKUP_DIR)
	assert_true(result.exists(), "the temp file was found")
	assert_true(result.recovered, "flagged as recovered")
	assert_eq(result.data["generation"], 9, "the in-flight write was salvaged")


func test_non_object_json_is_rejected() -> void:
	# A file containing a bare array or string is valid JSON but not a save.
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string('["not", "a", "save"]')
	file.close()

	var result := AtomicFile.read_json_with_recovery(_path, BACKUP_DIR)
	assert_false(result.exists(), "valid JSON of the wrong shape is not accepted")


func test_backups_are_capped() -> void:
	# An install running for years must not accumulate thousands of backups.
	for generation in range(AtomicFile.MAX_BACKUPS + 4):
		AtomicFile.write_json(_path, {"generation": generation}, BACKUP_DIR)

	var backups := AtomicFile.list_backups(_path, BACKUP_DIR)
	assert_true(
		backups.size() <= AtomicFile.MAX_BACKUPS,
		"kept %d backups, cap is %d" % [backups.size(), AtomicFile.MAX_BACKUPS]
	)


func test_no_temp_file_is_left_behind() -> void:
	AtomicFile.write_json(_path, {"ok": true}, BACKUP_DIR)
	assert_false(
		FileAccess.file_exists(_path + AtomicFile.TMP_SUFFIX),
		"a successful write leaves no .tmp behind"
	)


func test_an_export_leaves_no_backup_beside_it() -> void:
	# An export writes into a folder the PLAYER chose. Rotating there drops a .bak
	# next to their file every time they re-export over it — litter in someone
	# else's folder rather than insurance in ours.
	AtomicFile.write_json(_path, {"generation": 1}, "", false)
	AtomicFile.write_json(_path, {"generation": 2}, "", false)

	assert_eq(AtomicFile.list_backups(_path, TEST_DIR).size(), 0, "no .bak was written")
	assert_eq(
		AtomicFile.read_json(_path).data["generation"], 2, "and the newest write is what is there"
	)


func test_saves_still_rotate_by_default() -> void:
	# The opt-out must never be reachable by accident: every path that writes a
	# SAVE depends on rotation, and this asserts the default beside the opt-out so
	# the two cannot be confused.
	AtomicFile.write_json(_path, {"generation": 1}, BACKUP_DIR)
	AtomicFile.write_json(_path, {"generation": 2}, BACKUP_DIR)
	assert_eq(AtomicFile.list_backups(_path, BACKUP_DIR).size(), 1, "the previous save was kept")


func test_a_strict_read_never_substitutes_a_neighbouring_file() -> void:
	# Import reads the exact file the player picked. Quietly handing them a
	# DIFFERENT, older export from the same folder because theirs would not parse
	# is not recovery — it is a substitution, and the import would then report
	# success while replacing their garden with the wrong one.
	AtomicFile.write_json(_path, {"generation": 1}, TEST_DIR)
	AtomicFile.write_json(_path, {"generation": 2}, TEST_DIR)
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{ truncated")
	file.close()

	assert_false(AtomicFile.read_json(_path).exists(), "the strict read reports failure")

	# Side by side, because the difference between them IS the point.
	var recovered := AtomicFile.read_json_with_recovery(_path, TEST_DIR)
	assert_true(recovered.exists(), "while recovery still rescues a real save")
	assert_true(recovered.recovered, "and says that it did")


func _purge() -> void:
	_purge_dir(BACKUP_DIR)
	_purge_dir(TEST_DIR.path_join("a/b/c"))
	_purge_dir(TEST_DIR.path_join("a/b"))
	_purge_dir(TEST_DIR.path_join("a"))
	_purge_dir(TEST_DIR)


func _purge_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
