extends SceneTree
## Proves a garden actually survives being exported and imported somewhere else.
##
##     ... --headless --path . --script res://tools/verify_save_transfer.gd
##
## Runs ONCE, unlike `verify_save_roundtrip.gd`. That tool needs two passes
## because it is proving a cold start; this one is proving a transfer, which
## happens entirely inside a single run. Do not add a second invocation by
## analogy — the second pass would find the probe save already cleaned up.
##
## WHAT IT GUARDS. Export used to write `profile.json` and nothing else, so the
## session history — from which every statistic and every plant's growth ratio is
## derived — never travelled. Worse, import left the RECEIVING machine's shards
## in place, so the imported garden silently inherited someone else's history.
## Both faults are invisible to a unit test of `SaveBundle`, because both live in
## the wiring between the bundle, the session store and the save directory.
##
## The assertion that would have caught the original bug is the plant-progress
## one: a still-growing plant read 0.0 after an import while its stored stage
## still said otherwise.
##
## It runs entirely inside `user://verify_transfer`, on its own save directory —
## it resets a garden and deletes a session history, and doing that to the real
## `user://saves` would destroy whatever the person running it had been playing.
## The relocation is asserted before the first destructive call, not merely set,
## because a silently-ignored redirect would be indistinguishable from safety.
##
## Exits non-zero on any mismatch.

const PROBE_ROOT: String = "user://verify_transfer"
const PROBE_SAVE_DIR: String = "user://verify_transfer/saves"
const EXPORT_DIR: String = "user://verify_transfer/export"
const SNAPSHOT_DIR: String = "user://verify_transfer/backups"
const BUNDLE_NAME: String = "bundle.json"

## A year the imported bundle will never mention, recorded on the "receiving"
## machine so its survival would prove contamination.
const FOREIGN_DATE_KEY: String = "2019-06-01"
const FOREIGN_MINUTES: float = 90.0

## Enough focus on a common species to clear the first stage band without
## maturing the plant, so there is real, partial progress to lose.
const GROWING_MINUTES: float = 60.0

# Autoloads are fetched from the tree rather than referenced by name. A script
# run via --script is COMPILED BEFORE autoloads are registered, so writing
# `AppState` directly here is a compile error ("Identifier not found"). Inside
# the game itself the names resolve normally — this applies only to tool scripts.
var _app_state: Node
var _save_manager: Node
var _statistics: Node
var _content: Node

var _problems: PackedStringArray = PackedStringArray()


func _init() -> void:
	# Autoloads also initialise after this script is constructed, so their data is
	# not loaded until at least one frame has passed.
	await process_frame

	_app_state = root.get_node_or_null("/root/AppState")
	_save_manager = root.get_node_or_null("/root/SaveManager")
	_statistics = root.get_node_or_null("/root/StatisticsManager")
	_content = root.get_node_or_null("/root/ContentDB")
	if _app_state == null or _save_manager == null or _statistics == null or _content == null:
		printerr("Autoloads are not available; cannot verify.")
		quit(1)
		return

	# Everything this tool does is destructive, so it gets its own save directory
	# and its own snapshot folder before it touches anything. Snapshots otherwise
	# default to the real Documents folder, and the save to the real user://saves.
	_save_manager.set_save_dir(PROBE_SAVE_DIR)
	_save_manager.set_snapshot_dir(SNAPSHOT_DIR)
	_app_state.load_game()

	if _save_manager.get_save_dir() != PROBE_SAVE_DIR:
		# Refuse rather than proceed. Everything below resets a garden and wipes a
		# session history; doing that to a real save would be unforgivable, and a
		# redirect that quietly failed would look exactly like one that worked.
		printerr("The probe save directory is not in effect; refusing to run.")
		quit(1)
		return

	_run()

	_cleanup()
	_save_manager.set_save_dir("")
	_save_manager.set_snapshot_dir("")

	if _problems.is_empty():
		print("PASS: the garden survived an export and an import.")
		quit(0)
		return

	printerr("FAILED:")
	for problem: String in _problems:
		printerr("  - %s" % problem)
	quit(1)


func _run() -> void:
	var species_id := _pick_species()
	if species_id == &"":
		_problems.append("no species are authored, so growth cannot be verified")
		return

	# --- The garden, on the first machine ------------------------------------
	var growing := _grow(species_id, GROWING_MINUTES, "2026-03-01")
	var matured := _grow(species_id, 0.0, "2025-11-02")
	matured.maturity = PlantInstance.Maturity.MATURE
	matured.growth_stage = 2
	# A session in an earlier year, so the export has to carry more than one shard.
	_record(matured.uid, 45.0, "2025-11-02")
	_app_state.get_settings().theme_mode = "dark"
	_app_state.save_now()

	var expected_sessions: int = _app_state.sessions.size()
	var expected_lifetime: float = _statistics.get_summary().focus_lifetime
	var expected_progress: float = _app_state.get_plant_progress(growing)
	var growing_uid: String = growing.uid
	var matured_uid: String = matured.uid

	if expected_progress <= 0.0:
		_problems.append("the probe plant had no progress before exporting; the test proves nothing")
		return
	if expected_progress >= 1.0:
		_problems.append("the probe plant matured before exporting; it must be partially grown")
		return

	# --- Export ---------------------------------------------------------------
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var bundle_path := EXPORT_DIR.path_join(BUNDLE_NAME)
	if not _save_manager.export_save(bundle_path, _app_state.data, _app_state.sessions):
		_problems.append("the export failed: %s" % _save_manager.last_error_detail)
		return

	# Read the BYTES back, not the object. `SaveBundle.read(build(x))` being
	# symmetric is a unit test's job; what matters here is that the file on disk
	# is self-contained.
	_check_file_is_self_contained(bundle_path, expected_sessions)

	# Re-exporting over the same path must not leave a rotating backup in the
	# player's own folder.
	_save_manager.export_save(bundle_path, _app_state.data, _app_state.sessions)
	for file_name: String in DirAccess.get_files_at(EXPORT_DIR):
		if file_name.ends_with(".bak"):
			_problems.append("re-exporting left %s beside the player's file" % file_name)

	# --- The second machine: a different garden, with its own history ---------
	_app_state.reset_to_new_game()
	_record("", FOREIGN_MINUTES, FOREIGN_DATE_KEY)
	if _app_state.sessions.size() != 1:
		_problems.append("could not set up the receiving machine's own history")
		return

	# --- Import ---------------------------------------------------------------
	var imported: SaveBundle.Imported = _save_manager.read_bundle(bundle_path)
	if imported == null:
		_problems.append("the bundle could not be read: %s" % _save_manager.last_error_detail)
		return
	if imported.summary.session_count <= 0:
		_problems.append("the bundle summary reported no sessions")
	if not _save_manager.apply_bundle(imported):
		_problems.append("applying the bundle failed: %s" % _save_manager.last_error_detail)
		return
	_app_state.load_game()

	# --- What must be true afterwards ----------------------------------------
	_check_history_replaced_not_merged(expected_sessions)
	_check_statistics(expected_lifetime)
	_check_growth(growing_uid, matured_uid, expected_progress)
	_check_the_rest()

	# --- And the file the broken build produced -------------------------------
	_check_a_legacy_bundle_still_imports(bundle_path, growing_uid)


## A bundle with no session history at all — what every export written before
## this fix looks like. It must still import: refusing would strand anyone who
## already made one, and those are the files most likely to be all somebody has.
##
## It also pins the graceful-degradation promise. A plant whose history did not
## come with it shows the stage it had reached rather than dropping to zero, so a
## garden imported from a legacy file looks like a garden rather than a seed tray.
func _check_a_legacy_bundle_still_imports(bundle_path: String, growing_uid: String) -> void:
	var file := FileAccess.open(bundle_path, FileAccess.READ)
	if file == null:
		_problems.append("could not reopen the bundle to build a legacy copy")
		return
	var json := JSON.new()
	var parsed_ok := json.parse(file.get_as_text()) == OK
	file.close()
	if not parsed_ok or not (json.data is Dictionary):
		_problems.append("could not parse the bundle to build a legacy copy")
		return

	var legacy: Dictionary = json.data
	legacy.erase(SaveBundle.SESSIONS_KEY)
	legacy.erase(SaveBundle.META_KEY)
	var legacy_path := EXPORT_DIR.path_join("legacy.json")
	if AtomicFile.write_json(legacy_path, legacy, "", false) != OK:
		_problems.append("could not write the legacy bundle")
		return

	var imported: SaveBundle.Imported = _save_manager.read_bundle(legacy_path)
	if imported == null:
		_problems.append("a legacy export could not be read: %s" % _save_manager.last_error_detail)
		return
	if imported.summary.has_sessions:
		_problems.append("a history-less file was not reported as history-less")
	if not _save_manager.apply_bundle(imported):
		_problems.append(
			"a legacy export could not be imported: %s" % _save_manager.last_error_detail
		)
		return
	_app_state.load_game()

	if not _app_state.sessions.is_empty():
		_problems.append("a history-less import left sessions behind")
	var growing: PlantInstance = _app_state.get_plant(growing_uid)
	if growing == null:
		_problems.append("the garden did not survive a legacy import")
	elif _app_state.get_plant_progress(growing) <= 0.0:
		_problems.append(
			"a plant with no history rendered at zero instead of the stage it had reached"
		)


## The exported file must carry the history in its own bytes.
func _check_file_is_self_contained(bundle_path: String, expected_sessions: int) -> void:
	var file := FileAccess.open(bundle_path, FileAccess.READ)
	if file == null:
		_problems.append("the exported file could not be reopened")
		return
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		_problems.append("the exported file is not valid JSON")
		return
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		_problems.append("the exported file is not a JSON object")
		return

	var bundle: Dictionary = parsed
	var rows: Variant = bundle.get(SaveBundle.SESSIONS_KEY)
	if not (rows is Array):
		_problems.append("the exported file carries no session history at all")
		return
	if (rows as Array).size() != expected_sessions:
		_problems.append(
			"exported sessions: expected %d, the file holds %d"
			% [expected_sessions, (rows as Array).size()]
		)
	if not bundle.has("plants"):
		_problems.append("the exported file carries no plants")


## The imported history replaces the local one wholesale. A merge would
## double-count, and inheriting the receiving machine's rows is the original bug.
func _check_history_replaced_not_merged(expected_sessions: int) -> void:
	var actual: int = _app_state.sessions.size()
	if actual != expected_sessions:
		_problems.append("sessions after import: expected %d, got %d" % [expected_sessions, actual])

	for session: FocusSession in _app_state.sessions:
		if session.date_key == FOREIGN_DATE_KEY:
			_problems.append("the receiving machine's own history survived the import")
			break

	var save_dir: String = _save_manager.get_save_dir()
	if FileAccess.file_exists(SessionStore.shard_path(save_dir, "2019")):
		_problems.append("a shard for a year the import never mentioned was left on disk")
	if not FileAccess.file_exists(SessionStore.shard_path(save_dir, "2025")):
		_problems.append("the imported 2025 shard is missing; sharding did not survive")
	if DirAccess.dir_exists_absolute(
		save_dir.path_join(_save_manager.IMPORT_STAGING_SUBDIR)
	):
		_problems.append("the import staging folder was left behind")


## Every figure on the statistics screen is derived from the rows just imported.
func _check_statistics(expected_lifetime: float) -> void:
	var summary: RefCounted = _statistics.get_summary()
	if not is_equal_approx(summary.focus_lifetime, expected_lifetime):
		_problems.append(
			"lifetime focus: expected %f, got %f" % [expected_lifetime, summary.focus_lifetime]
		)
	if summary.session_count <= 0:
		_problems.append("session count came across as zero")
	if summary.days_focused <= 0:
		_problems.append("days focused came across as zero")
	if summary.longest_session_minutes <= 0.0:
		_problems.append("longest session came across as zero")


## THE ASSERTION THIS TOOL EXISTS FOR. A still-growing plant used to read 0.0
## after an import, because its progress is evaluated from its own session rows.
func _check_growth(
	growing_uid: String, matured_uid: String, expected_progress: float
) -> void:
	var growing: PlantInstance = _app_state.get_plant(growing_uid)
	if growing == null:
		_problems.append("the growing plant did not survive the import")
	else:
		var progress: float = _app_state.get_plant_progress(growing)
		if not is_equal_approx(progress, expected_progress):
			_problems.append(
				"plant progress: expected %f, got %f" % [expected_progress, progress]
			)
		if growing.growth_stage < PlantGrowthService.DISPLAY_STAGE:
			_problems.append("the growing plant came back below the stage it had reached")

	var matured: PlantInstance = _app_state.get_plant(matured_uid)
	if matured == null:
		_problems.append("the mature plant did not survive the import")
	elif not is_equal_approx(_app_state.get_plant_progress(matured), 1.0):
		_problems.append("a mature plant no longer reads as finished")


func _check_the_rest() -> void:
	if _app_state.get_settings().theme_mode != "dark":
		_problems.append("settings did not come across with the garden")
	if not _app_state.data.in_flight_session.is_empty():
		_problems.append("an in-flight session travelled between machines")
	if _app_state.data.profile.total_xp < 0:
		_problems.append("the profile did not come across")


# --- Building the probe garden ------------------------------------------------

func _pick_species() -> StringName:
	var all: Array = _content.get_all_species()
	return all[0].id if not all.is_empty() else &""


## A plant with `minutes` of credited focus actually recorded against it, so its
## progress is real rather than asserted onto the instance.
func _grow(species_id: StringName, minutes: float, date_key: String) -> PlantInstance:
	var plant := PlantInstance.create(species_id, "probe_project")
	plant.pot_id = _content.DEFAULT_POT_ID
	_app_state.data.plants.append(plant)
	if minutes > 0.0:
		plant.accumulated_focus_minutes = minutes
		_record(plant.uid, minutes, date_key)
		var species: PlantSpecies = _content.get_species(species_id)
		PlantGrowthService.apply_growth(
			plant, species, _statistics.build_plant_context(plant.uid)
		)
	return plant


## Records a session with a PINNED date key, so the shard it lands in and the
## day it counts toward do not depend on the clock this runs under.
func _record(plant_uid: String, minutes: float, date_key: String) -> void:
	var session := FocusSession.create(FocusSession.Kind.FOCUS, minutes, "probe_project", plant_uid)
	session.date_key = date_key
	session.actual_focus_minutes = minutes
	session.completion = FocusSession.Completion.COMPLETED
	session.awards_applied = true
	_app_state.record_session(session)


## Removes everything the probe wrote. Scoped to PROBE_ROOT and nothing else —
## the one guard that makes a wrong path here harmless rather than catastrophic.
func _cleanup() -> void:
	_purge_tree(PROBE_ROOT)


func _purge_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub_name: String in DirAccess.get_directories_at(path):
		_purge_tree(path.path_join(sub_name))
	_purge_dir(path)


func _purge_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
