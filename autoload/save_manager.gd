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
## Records a relocated SNAPSHOT folder, for the same reason: the path has to be
## known before anything can be written to it.
const BACKUP_LOCATION_CONFIG: String = "user://backup_location.cfg"

## Shortest gap between automatic snapshots while the game is running. A snapshot
## is a file copy, not a save — doing one on every autosave would mean twenty
## folders inside a single pomodoro and no history worth the name.
const SNAPSHOT_INTERVAL_SECONDS: float = 3600.0
## Floor under every automatic snapshot, including the one on quit. Opening and
## closing the app twice in a minute should leave one folder, not three.
const SNAPSHOT_MIN_GAP_SECONDS: float = 120.0

## Where incoming session shards are staged before they replace the real ones.
## A sibling of `sessions/` inside the save directory, so committing an import is
## a rename on the same volume rather than a copy that could half-finish.
const IMPORT_STAGING_SUBDIR: String = ".incoming"

var last_load_status: LoadStatus = LoadStatus.NEW_GAME
var last_error_detail: String = ""

var _save_dir: String = DEFAULT_SAVE_DIR
var _snapshot_dir: String = ""
var _last_snapshot_unix: float = 0.0


func _ready() -> void:
	_save_dir = _read_configured_dir()
	_snapshot_dir = _read_configured_snapshot_dir()
	GameLog.info(GameLog.Category.SAVE, "Save directory: %s" % get_save_dir())
	GameLog.info(GameLog.Category.SAVE, "Backup folder: %s" % get_snapshot_dir())
	# A snapshot on the way out covers the ordinary case — the player closes the
	# app and everything they did this session is already in a dated folder.
	get_tree().set_auto_accept_quit(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		snapshot_now()


func get_save_dir() -> String:
	return _save_dir


func get_profile_path() -> String:
	return _save_dir.path_join(PROFILE_FILE)


func get_backup_dir() -> String:
	return _save_dir.path_join(BACKUP_SUBDIR)


## Where dated snapshots go. Documents\Focus Garden\Backups unless the player
## moved it, falling back to the rotating-backup folder if the OS cannot say
## where Documents is.
func get_snapshot_dir() -> String:
	if not _snapshot_dir.is_empty():
		return _snapshot_dir
	var default_dir := SaveBackup.default_directory()
	return default_dir if not default_dir.is_empty() else get_backup_dir()


## Points snapshots at a new folder and remembers it. Passing "" restores the
## default. The existing snapshots are left where they are rather than moved —
## silently relocating a player's backups is exactly the kind of surprise a
## backup feature must not spring.
func set_snapshot_dir(directory: String) -> void:
	_snapshot_dir = directory
	var config := ConfigFile.new()
	config.set_value("backup", "directory", directory)
	config.save(BACKUP_LOCATION_CONFIG)
	GameLog.info(GameLog.Category.SAVE, "Backup folder: %s" % get_snapshot_dir())


## Points the save at a new folder and remembers it. Passing "" restores the
## default. Callers must reload afterwards — this only changes where the next
## read and write go.
##
## The existing files are NOT moved, for the same reason `set_snapshot_dir` does
## not move snapshots: quietly relocating someone's garden is the kind of
## surprise a data feature must not spring. The caller knows whether it wants the
## old save carried over or a fresh one at the new path.
##
## `save_location.cfg` has always been READ on startup (§35 "save location");
## until now nothing wrote it, so the relocation the format documented could not
## actually be reached.
func set_save_dir(directory: String) -> void:
	_save_dir = directory if not directory.is_empty() else DEFAULT_SAVE_DIR
	var config := ConfigFile.new()
	config.set_value("save", "directory", directory)
	config.save(LOCATION_CONFIG)
	GameLog.info(GameLog.Category.SAVE, "Save directory: %s" % get_save_dir())


## Writes a dated snapshot. `force` is for the player pressing the button, and
## for the moment before an import destroys a garden — either way an explicit
## snapshot must always produce a folder, even seconds after the last one and
## even when the save on disk is one this build has refused. Automatic calls
## respect SNAPSHOT_MIN_GAP_SECONDS and the write block.
func snapshot_now(force: bool = false) -> bool:
	var now := Time.get_unix_time_from_system()
	if not force and now - _last_snapshot_unix < SNAPSHOT_MIN_GAP_SECONDS:
		return false
	if not force and is_save_write_blocked():
		# The save on disk is from a newer build and this one has not understood
		# it. Copying it AUTOMATICALLY would fill the folder with duplicates of a
		# file the player already cannot open here.
		#
		# A FORCED snapshot is the opposite case and must go through. Importing is
		# a player's way out of a blocked save, and it overwrites that file — so
		# refusing here would mean the one moment we are certain the file is about
		# to be destroyed is also the one moment we decline to copy it.
		return false
	var written := SaveBackup.create(get_save_dir(), get_snapshot_dir())
	if written:
		_last_snapshot_unix = now
		GameLog.info(GameLog.Category.SAVE, "Backed up to %s" % SaveBackup.last_snapshot_path)
	return written


## Writes a snapshot only if the last one is old enough. Called after routine
## saves, so a long play session leaves a trail without flooding the folder.
func snapshot_if_due() -> bool:
	var now := Time.get_unix_time_from_system()
	if now - _last_snapshot_unix < SNAPSHOT_INTERVAL_SECONDS:
		return false
	return snapshot_now()


func list_snapshots() -> Array[SaveBackup.Snapshot]:
	return SaveBackup.list(get_snapshot_dir())


## Copies a snapshot back over the live save and reloads from it. The caller is
## responsible for adopting the returned data — nothing in memory is touched here.
func restore_snapshot(snapshot_path: String) -> SaveData:
	if not SaveBackup.restore(snapshot_path, get_save_dir(), get_snapshot_dir()):
		_report_failure("That backup could not be restored from %s." % snapshot_path)
		return null
	GameLog.info(GameLog.Category.SAVE, "Restored from %s" % snapshot_path)
	var restored := load_game()
	_last_snapshot_unix = Time.get_unix_time_from_system()
	return restored


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

	# A snapshot of what was on disk BEFORE this run touches it. If something goes
	# wrong during the session, the state the player last closed the app in is
	# already safely copied somewhere they can find it.
	snapshot_if_due()

	# `save_loaded` is deliberately NOT emitted here. This function returns into
	# `AppState.data = SaveManager.load_game()`, so at this instant AppState still
	# holds the PREVIOUS save and the previous session list — every screen that
	# refreshes on that signal would redraw the state being replaced. AppState
	# emits it once everything is in place.
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


## Exports the whole garden — profile AND session history — to one file (§35).
##
## The sessions are the point. They used to be left behind, and because every
## statistic and every plant's growth ratio is derived from them rather than
## stored, the file that came out the other end looked like a garden with its
## history erased: zeroed totals and mature-looking plants back at seed stage.
## See `SaveBundle` for why the envelope is a superset of `profile.json`.
func export_save(
	destination_path: String, save: SaveData, sessions: Array[FocusSession]
) -> bool:
	if save == null:
		_report_failure("There is nothing to export yet.")
		return false

	var bundle := SaveBundle.build(save, sessions, VersionUtil.current())
	# No backup rotation: this writes into a folder the player picked, and
	# re-exporting over an old copy must not leave a .bak beside it.
	var error := AtomicFile.write_json(destination_path, bundle, "", false)
	if error != OK:
		_report_failure("Export failed (error %d)." % error)
		return false

	GameLog.info(
		GameLog.Category.SAVE,
		"Exported %d plants and %d sessions to %s"
		% [save.plants.size(), sessions.size(), destination_path]
	)
	return true


## Reads an import file WITHOUT touching anything on disk. Returns null on
## failure and sets `last_error_detail`.
##
## Reading and applying are deliberately two calls. The player is shown what the
## file actually contains and asked to confirm before a single byte of their own
## garden is at risk (§36) — which means the whole file has to be parsed,
## migrated and validated while the live save is still completely intact.
func read_bundle(source_path: String) -> SaveBundle.Imported:
	last_error_detail = ""
	# Strict: the player picked one file, and a neighbouring .bak from an earlier
	# export must never be substituted for it.
	var read := AtomicFile.read_json(source_path)
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
	return SaveBundle.read(migration.data)


## Writes an imported bundle over the live save. Destroys the current garden.
##
## THE ORDER MATTERS, and the failure it rules out is "the garden was deleted and
## the replacement could not be written":
##
##   1. Force a snapshot, so the garden being replaced is recoverable from a
##      dated folder even if the player picked the wrong file.
##   2. Stage every incoming shard into `.incoming/sessions/`. If any of them
##      cannot be written — disk full, permissions, a bad row — throw the staging
##      folder away and abort with NOTHING of the player's touched. This is the
##      same rule `AtomicFile` follows: verify before going near the real file.
##   3. Only now remove `sessions/` and rename the staged folder into place.
##   4. Write `profile.json`, through the ordinary atomic save path.
##
## Steps 3 and 4 cannot be made one transaction, so a crash between them leaves a
## real garden beside a real history that did not grow together. That is an
## honest, visible state rather than a corrupt one, and step 1 took a copy of
## both seconds earlier. Do not reorder 3 before 2.
func apply_bundle(imported: SaveBundle.Imported) -> bool:
	if imported == null or imported.save == null:
		_report_failure("There was nothing in that file to import.")
		return false

	snapshot_now(true)

	var staging_root := _save_dir.path_join(IMPORT_STAGING_SUBDIR)
	var staged_dir := SessionStore.sessions_dir(staging_root)
	SessionStore.clear(staging_root)

	# The folder is created up front so the commit below is always a rename of a
	# directory that exists. A bundle with NO sessions is a legitimate file — one
	# exported by a build from before sessions travelled, or by a player who has
	# never finished a session — and `save_all` writes nothing whatsoever for one.
	# Without this there would be nothing to rename, and the import that failed
	# would be exactly the kind that most needs to work.
	var staging_error := DirAccess.make_dir_recursive_absolute(staged_dir)
	if staging_error == OK:
		staging_error = SessionStore.save_all(staging_root, imported.sessions)
	if staging_error != OK:
		SessionStore.clear(staging_root)
		DirAccess.remove_absolute(staging_root)
		_report_failure("Could not write the imported history (error %d)." % staging_error)
		return false

	SessionStore.clear(_save_dir)
	var live_dir := SessionStore.sessions_dir(_save_dir)
	var rename_error := DirAccess.rename_absolute(staged_dir, live_dir)
	if rename_error != OK:
		# The history is gone and the replacement is still sitting in .incoming.
		# Say so loudly and leave the folder alone — it is the data, and step 1's
		# snapshot is the way back.
		_report_failure(
			"The imported history could not be moved into place (error %d). It is still in %s."
			% [rename_error, staged_dir]
		)
		return false
	DirAccess.remove_absolute(staging_root)

	# Deliberately not `AppState.save_now()`: that refuses to write when the save
	# on disk is blocked, and importing is precisely how a player gets out of that.
	if not save_game(imported.save):
		return false

	GameLog.info(
		GameLog.Category.SAVE,
		"Imported %d plants and %d sessions."
		% [imported.save.plants.size(), imported.sessions.size()]
	)
	return true


func _report_failure(detail: String) -> void:
	last_error_detail = detail
	GameLog.error(GameLog.Category.SAVE, detail)
	EventBus.save_failed.emit(detail)


func _read_configured_snapshot_dir() -> String:
	if not FileAccess.file_exists(BACKUP_LOCATION_CONFIG):
		return ""
	var config := ConfigFile.new()
	if config.load(BACKUP_LOCATION_CONFIG) != OK:
		GameLog.warn(GameLog.Category.SAVE, "Backup location config unreadable; using the default.")
		return ""
	return config.get_value("backup", "directory", "")


func _read_configured_dir() -> String:
	if not FileAccess.file_exists(LOCATION_CONFIG):
		return DEFAULT_SAVE_DIR
	var config := ConfigFile.new()
	if config.load(LOCATION_CONFIG) != OK:
		GameLog.warn(GameLog.Category.SAVE, "Save location config unreadable; using the default.")
		return DEFAULT_SAVE_DIR
	var configured: String = config.get_value("save", "directory", DEFAULT_SAVE_DIR)
	return configured if not configured.is_empty() else DEFAULT_SAVE_DIR
