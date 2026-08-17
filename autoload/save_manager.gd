extends Node
## Persistence: serialization, atomic writes, backups, migrations, recovery (§40).
##
## Owns: getting player data onto and off of disk safely.
## Must never: know gameplay rules. It cannot compute XP, decide growth, or
## evaluate an achievement. It moves SaveData between memory and files, nothing
## more — that boundary is what keeps save logic testable and gameplay logic
## free of file concerns.

## Status of the most recent load, so the UI can tell the player what happened
## instead of failing silently (§51).
enum LoadStatus {
	NEW_GAME,         ## No save present. First launch.
	LOADED,           ## Clean load.
	RECOVERED,        ## Primary was unreadable; a backup or .tmp was used.
	MIGRATED,         ## Older save upgraded successfully.
	FUTURE_VERSION,   ## Save is newer than this build. Nothing was modified.
	MIGRATION_FAILED, ## Gap in the migration chain. Nothing was modified.
}

const DEFAULT_SAVE_DIR: String = "user://saves"
const PROFILE_FILE: String = "profile.json"
const BACKUP_SUBDIR: String = "backups"
## Records where a relocated save lives. Stored outside the save itself because
## we must know the path before we can read anything (§35 "save location").
const LOCATION_CONFIG: String = "user://save_location.cfg"

var last_load_status: LoadStatus = LoadStatus.NEW_GAME
var last_error_detail: String = ""

var _save_dir: String = DEFAULT_SAVE_DIR


func _ready() -> void:
	_save_dir = _read_configured_dir()
	GameLog.info(GameLog.Category.SAVE, "Save directory: %s" % get_save_dir())


func get_save_dir() -> String:
	return _save_dir


func get_profile_path() -> String:
	return _save_dir.path_join(PROFILE_FILE)


func get_backup_dir() -> String:
	return _save_dir.path_join(BACKUP_SUBDIR)


## Loads the profile, applying migrations and falling back to backups as needed.
## Always returns usable SaveData — a brand-new save when nothing loadable exists
## — so callers never have to handle a null.
##
## On FUTURE_VERSION or MIGRATION_FAILED the returned data is a fresh save, but
## the file on disk is left completely untouched (§36: never silently erase an
## incompatible save). The caller is responsible for warning the player BEFORE
## anything overwrites it.
func load_game() -> SaveData:
	last_error_detail = ""
	var read := AtomicFile.read_json_with_recovery(get_profile_path(), get_backup_dir())

	if not read.exists():
		last_load_status = LoadStatus.NEW_GAME
		GameLog.info(GameLog.Category.SAVE, "No save found; starting a new garden.")
		return SaveData.create_new()

	var migration := SaveMigrations.migrate(read.data)
	match migration.status:
		SaveMigrations.Status.FUTURE_VERSION:
			last_load_status = LoadStatus.FUTURE_VERSION
			last_error_detail = (
				"This save was made by a newer version of Focus Garden (save format %d; this build understands %d)."
				% [migration.from_version, SaveData.CURRENT_VERSION]
			)
			GameLog.error(GameLog.Category.SAVE, last_error_detail)
			return SaveData.create_new()

		SaveMigrations.Status.NO_PATH:
			last_load_status = LoadStatus.MIGRATION_FAILED
			last_error_detail = (
				"No upgrade path from save format %d to %d."
				% [migration.from_version, SaveData.CURRENT_VERSION]
			)
			GameLog.error(GameLog.Category.SAVE, last_error_detail)
			return SaveData.create_new()

		_:
			pass

	var save := SaveData.from_dict(migration.data)

	if read.recovered:
		last_load_status = LoadStatus.RECOVERED
		last_error_detail = "Recovered your garden from %s." % read.source_name
		GameLog.warn(GameLog.Category.SAVE, last_error_detail)
		EventBus.save_recovered_from_backup.emit(read.source_name)
	elif not migration.applied_steps.is_empty():
		last_load_status = LoadStatus.MIGRATED
		GameLog.info(
			GameLog.Category.SAVE,
			"Migrated save: %s" % ", ".join(migration.applied_steps)
		)
	else:
		last_load_status = LoadStatus.LOADED

	EventBus.save_loaded.emit()
	return save


## Writes the profile atomically. Sessions are written separately by
## `append_session` so a routine save never rewrites the whole history.
func save_game(save: SaveData) -> bool:
	if save == null:
		_report_failure("Nothing to save.")
		return false

	save.save_version = SaveData.CURRENT_VERSION
	var error := AtomicFile.write_json(get_profile_path(), save.to_dict(), get_backup_dir())
	if error != OK:
		_report_failure("Could not write the save file (error %d)." % error)
		return false

	GameLog.debug(GameLog.Category.SAVE, "Profile saved.")
	EventBus.save_completed.emit()
	return true


func append_session(session: FocusSession) -> bool:
	var error := SessionStore.append(_save_dir, session)
	if error != OK:
		_report_failure("Could not record the session (error %d)." % error)
		return false
	return true


func load_sessions() -> Array[FocusSession]:
	return SessionStore.load_all(_save_dir)


## True when a real save file exists on disk, regardless of whether it loads.
## Used to decide whether overwriting would destroy something.
func has_existing_save() -> bool:
	return FileAccess.file_exists(get_profile_path())


## Whether the last load left data on disk that must not be overwritten.
## The settings screen and any autosave path must check this before writing.
func is_save_write_blocked() -> bool:
	return (
		last_load_status == LoadStatus.FUTURE_VERSION
		or last_load_status == LoadStatus.MIGRATION_FAILED
	)


## Exports the current save to an arbitrary path (§35).
func export_save(destination_path: String, save: SaveData) -> bool:
	var error := AtomicFile.write_json(destination_path, save.to_dict(), "")
	if error != OK:
		_report_failure("Export failed (error %d)." % error)
		return false
	return true


## Imports a save file without touching the live one. Returns null on failure and
## sets `last_error_detail`; the caller decides whether to adopt the result.
func import_save(source_path: String) -> SaveData:
	var read := AtomicFile.read_json_with_recovery(source_path, "")
	if not read.exists():
		_report_failure("That file could not be read as a Focus Garden save.")
		return null

	var migration := SaveMigrations.migrate(read.data)
	if not migration.is_ok():
		_report_failure(
			"That save uses format %d, which this build cannot open."
			% migration.from_version
		)
		return null
	return SaveData.from_dict(migration.data)


func _report_failure(detail: String) -> void:
	last_error_detail = detail
	GameLog.error(GameLog.Category.SAVE, detail)
	EventBus.save_failed.emit(detail)


func _read_configured_dir() -> String:
	if not FileAccess.file_exists(LOCATION_CONFIG):
		return DEFAULT_SAVE_DIR
	var config := ConfigFile.new()
	if config.load(LOCATION_CONFIG) != OK:
		GameLog.warn(GameLog.Category.SAVE, "Save location config unreadable; using the default.")
		return DEFAULT_SAVE_DIR
	var configured: String = config.get_value("save", "directory", DEFAULT_SAVE_DIR)
	return configured if not configured.is_empty() else DEFAULT_SAVE_DIR
