class_name AtomicFile
extends RefCounted
## Crash-safe JSON file writing (§36 "atomic save strategy").
##
## THE FAILURE THIS PREVENTS: the obvious implementation opens the save file and
## writes over it. If the process dies partway — power loss, a crash, the user
## killing the app — the player's file is now truncated JSON and their entire
## garden is gone. That is unrecoverable, and it is the single worst bug this
## application could ship.
##
## THE SEQUENCE (never reorder without re-reading this):
##   1. Write the new content to `<path>.tmp`.
##   2. Read `.tmp` back and parse it. If it does not parse, the write was bad
##      and we abort with the real file still untouched.
##   3. Copy the existing real file to a timestamped backup.
##   4. Remove the real file, then rename `.tmp` into place.
##
## At every instant, at least one of {real file, .tmp, newest backup} is complete
## and parseable, which is what `read_json_with_recovery` relies on. Step 4's
## remove-then-rename is used instead of an overwriting rename because rename
## semantics over an existing file differ across platforms, and the backup from
## step 3 already covers the brief window where the real path is absent.

const TMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"
const MAX_BACKUPS: int = 3


enum ReadSource { PRIMARY, TEMP, BACKUP, MISSING }


class ReadResult extends RefCounted:
	var data: Dictionary = {}
	var source: ReadSource = ReadSource.MISSING
	var recovered: bool = false
	var source_name: String = ""

	func exists() -> bool:
		return source != ReadSource.MISSING


## Writes `data` as pretty-printed JSON, atomically. Returns OK or an Error.
static func write_json(path: String, data: Dictionary, backup_dir: String = "") -> Error:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var make_error := DirAccess.make_dir_recursive_absolute(dir_path)
		if make_error != OK:
			return make_error

	var tmp_path := path + TMP_SUFFIX
	var text := JSON.stringify(data, "\t")

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	# Explicit close (rather than waiting for refcount) so the bytes are on disk
	# before we verify them.
	file.close()

	# Verify before touching the real file. A disk-full or permissions failure
	# shows up here, while the previous save is still intact.
	var verify := FileAccess.open(tmp_path, FileAccess.READ)
	if verify == null:
		return FileAccess.get_open_error()
	var written := verify.get_as_text()
	verify.close()
	if _parse_object(written) == null:
		DirAccess.remove_absolute(tmp_path)
		return ERR_FILE_CORRUPT

	if FileAccess.file_exists(path):
		_rotate_backup(path, backup_dir)
		DirAccess.remove_absolute(path)

	return DirAccess.rename_absolute(tmp_path, path)


## Reads JSON, falling back through the temp file and then backups when the
## primary is missing or corrupt (§36 "graceful recovery from corrupted data").
static func read_json_with_recovery(path: String, backup_dir: String = "") -> ReadResult:
	var result := ReadResult.new()

	# Explicitly Variant: _try_read returns null on failure, so `:=` would infer
	# Variant anyway and Godot treats that inference as an error.
	var primary: Variant = _try_read(path)
	if primary != null:
		result.data = primary
		result.source = ReadSource.PRIMARY
		result.source_name = path.get_file()
		return result

	# A leftover .tmp means we crashed between removing the real file and
	# renaming the new one. It was verified before the swap started, so it is
	# the freshest complete data available.
	var tmp: Variant = _try_read(path + TMP_SUFFIX)
	if tmp != null:
		result.data = tmp
		result.source = ReadSource.TEMP
		result.recovered = true
		result.source_name = (path + TMP_SUFFIX).get_file()
		return result

	for backup_path: String in list_backups(path, backup_dir):
		var backup: Variant = _try_read(backup_path)
		if backup != null:
			result.data = backup
			result.source = ReadSource.BACKUP
			result.recovered = true
			result.source_name = backup_path.get_file()
			return result

	return result


## Backup paths for `path`, newest first.
static func list_backups(path: String, backup_dir: String = "") -> PackedStringArray:
	var dir_path := backup_dir if not backup_dir.is_empty() else path.get_base_dir()
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out

	var prefix := path.get_file()
	var names := DirAccess.get_files_at(dir_path)
	var matching: Array[String] = []
	for name: String in names:
		if name.begins_with(prefix) and name.ends_with(BACKUP_SUFFIX):
			matching.append(name)
	# Names embed a zero-padded unix timestamp, so a reverse lexical sort is a
	# reverse chronological sort.
	matching.sort()
	matching.reverse()
	for name: String in matching:
		out.append(dir_path.path_join(name))
	return out


static func _rotate_backup(path: String, backup_dir: String) -> void:
	var dir_path := backup_dir if not backup_dir.is_empty() else path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
			return

	var stamp := "%012d" % int(Time.get_unix_time_from_system())
	var backup_path := dir_path.path_join("%s.%s%s" % [path.get_file(), stamp, BACKUP_SUFFIX])
	DirAccess.copy_absolute(path, backup_path)

	# Keep only the newest MAX_BACKUPS so a long-running install does not
	# accumulate thousands of files.
	var backups := list_backups(path, dir_path)
	for i in range(MAX_BACKUPS, backups.size()):
		DirAccess.remove_absolute(backups[i])


## Returns the parsed Dictionary, or null when the file is absent, unreadable,
## not valid JSON, or valid JSON that is not an object.
static func _try_read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return _parse_object(text)


## Parses JSON that is EXPECTED to be an object, returning null on any failure.
##
## Uses JSON.new().parse() rather than JSON.parse_string(): the latter pushes a
## raw engine error for malformed input. Corrupt saves are a case this class
## handles deliberately, and §51 requires a friendly message rather than an
## engine stack trace leaking into the player's log every time recovery runs.
## The caller logs the recovery through GameLog instead.
static func _parse_object(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var parsed: Variant = json.data
	return parsed if parsed is Dictionary else null
