extends SceneTree
## Proves player data survives an actual process restart.
##
## Run it TWICE. The first run writes a known save and exits; the second run
## reads it back through the normal load path, asserts every value, and cleans up.
##
##     ... --headless --path . --script res://tools/verify_save_roundtrip.gd
##     ... --headless --path . --script res://tools/verify_save_roundtrip.gd
##
## A unit test cannot cover this. `test_atomic_file.gd` proves the file layer
## round-trips within one process, but only a real second launch proves that
## autoload wiring, migration and deserialization work together on a cold start —
## which is the only path a player ever takes.
##
## Exits non-zero on any mismatch.

const MARKER_NAME: String = "SaveRoundtripProbe"
const EXPECTED_XP: int = 4242
const EXPECTED_MINUTES: float = 87.5
const EXPECTED_SPECIES: StringName = &"probe_fern"
const PROBE_PROJECT_NAME: String = "Probe Project"

# Autoloads are fetched from the tree rather than referenced by name. A script
# run via --script is COMPILED BEFORE autoloads are registered, so writing
# `AppState` directly here is a compile error ("Identifier not found"). Inside
# the game itself the names resolve normally — this applies only to standalone
# tool scripts.
var _app_state: Node
var _save_manager: Node


func _init() -> void:
	# Autoloads also initialise after this script is constructed, so their data
	# is not loaded until at least one frame has passed.
	await process_frame

	_app_state = root.get_node("/root/AppState")
	_save_manager = root.get_node("/root/SaveManager")
	if _app_state == null or _save_manager == null:
		printerr("Autoloads are not available; cannot verify.")
		quit(1)
		return

	if _app_state.data.profile.display_name == MARKER_NAME:
		_verify()
	else:
		_write()


func _write() -> void:
	var profile: PlayerProfile = _app_state.data.profile
	profile.display_name = MARKER_NAME
	profile.total_xp = EXPECTED_XP
	profile.current_streak = 3
	profile.grant_unlock("probe_unlock")

	var plant := PlantInstance.create(EXPECTED_SPECIES, "probe_project")
	plant.accumulated_focus_minutes = EXPECTED_MINUTES
	plant.growth_stage = 2
	plant.move_to_shelf(5)
	_app_state.data.plants.append(plant)
	_app_state.data.profile.active_plant_uid = plant.uid

	_app_state.data.projects.append(ProjectCategory.create(PROBE_PROJECT_NAME))

	var session := FocusSession.create(FocusSession.Kind.FOCUS, 25.0, "probe_project", plant.uid)
	session.actual_focus_minutes = EXPECTED_MINUTES
	session.awards_applied = true
	_app_state.record_session(session)

	if not _app_state.save_now():
		printerr("PASS 1 FAILED: could not write the save.")
		quit(1)
		return

	print("PASS 1: wrote save. Run this script again to verify.")
	quit(0)


func _verify() -> void:
	var problems := PackedStringArray()
	# Explicit types throughout: values read off a dynamically-fetched Node have
	# no static type, and Godot treats inferring from that as an error.
	var profile: PlayerProfile = _app_state.data.profile

	if profile.total_xp != EXPECTED_XP:
		problems.append("total_xp: expected %d, got %d" % [EXPECTED_XP, profile.total_xp])
	if profile.current_streak != 3:
		problems.append("current_streak: expected 3, got %d" % profile.current_streak)
	if not profile.has_unlock("probe_unlock"):
		problems.append("unlock 'probe_unlock' was not persisted")

	if _app_state.data.plants.size() != 1:
		problems.append("plants: expected 1, got %d" % _app_state.data.plants.size())
	else:
		var plant: PlantInstance = _app_state.data.plants[0]
		if plant.species_id != EXPECTED_SPECIES:
			problems.append("species_id: got %s" % plant.species_id)
		if not is_equal_approx(plant.accumulated_focus_minutes, EXPECTED_MINUTES):
			problems.append("accumulated minutes: got %f" % plant.accumulated_focus_minutes)
		if plant.growth_stage != 2:
			problems.append("growth_stage: expected 2, got %d" % plant.growth_stage)
		if plant.location != PlantInstance.Location.SHELF or plant.shelf_slot != 5:
			problems.append("shelf placement was not persisted")
		if profile.active_plant_uid != plant.uid:
			problems.append("active plant reference was not persisted")

	# Checks that the probe's OWN project survived, rather than asserting a total.
	# A count assertion here broke the moment starter projects were seeded on
	# first launch — the probe should verify what it wrote, not what else exists.
	var found_project := false
	for project: ProjectCategory in _app_state.data.projects:
		if project.display_name == PROBE_PROJECT_NAME:
			found_project = true
			break
	if not found_project:
		problems.append("the probe's project was not persisted")

	# Sessions live in their own year-sharded file, so this also proves the
	# session store round-trips independently of profile.json.
	if _app_state.sessions.size() != 1:
		problems.append("sessions: expected 1, got %d" % _app_state.sessions.size())
	elif not _app_state.sessions[0].awards_applied:
		problems.append("the awards_applied guard was lost — a reload could double-award")

	_cleanup()

	if problems.is_empty():
		print("PASS 2: save survived a full restart. Verified and cleaned up.")
		quit(0)
		return

	printerr("PASS 2 FAILED:")
	for problem: String in problems:
		printerr("  - %s" % problem)
	quit(1)


## Removes the probe save so the check can be run again and no test data is left
## in the real user save directory.
func _cleanup() -> void:
	var save_dir: String = _save_manager.get_save_dir()
	_purge_dir(_save_manager.get_backup_dir())
	_purge_dir(SessionStore.sessions_dir(save_dir))
	_purge_dir(save_dir)


func _purge_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
