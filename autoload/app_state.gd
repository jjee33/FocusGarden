extends Node
## High-level runtime state and player profile references (§40).
##
## Owns: the in-memory SaveData and session list, the lookups over them, and the
## application lifecycle points where saving must happen.
## Must never: render UI, know file formats (that is SaveManager), or compute
## gameplay formulas (those live in systems/).
##
## Every other system reads player data from here rather than passing SaveData
## around, so there is exactly one live copy and no chance of two systems
## mutating different instances.

var data: SaveData = SaveData.create_new()
## Full session history, loaded once at startup. Sessions are appended to disk
## individually but kept in memory as one list for aggregation (§37).
var sessions: Array[FocusSession] = []

var is_loaded: bool = false
## Set when the save on disk must not be overwritten (future version or failed
## migration). Every write path checks this first (§36).
var save_blocked: bool = false


func _ready() -> void:
	# We must save before the window closes (§36 "save on clean application
	# exit"), which means intercepting the close instead of letting Godot quit
	# immediately.
	get_tree().auto_accept_quit = false
	load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameLog.info(GameLog.Category.APP, "Close requested; saving before exit.")
		save_now()
		get_tree().quit()


func load_game() -> void:
	data = SaveManager.load_game()
	sessions = SaveManager.load_sessions()
	save_blocked = SaveManager.is_save_write_blocked()
	is_loaded = true

	if save_blocked:
		GameLog.error(
			GameLog.Category.APP,
			"Save writes are blocked to protect the existing file: %s" % SaveManager.last_error_detail
		)

	GameLog.info(
		GameLog.Category.APP,
		"Loaded %d plants, %d sessions, %d projects."
		% [data.plants.size(), sessions.size(), data.projects.size()]
	)


## Persists the profile. No-op when writes are blocked, so a corrupted or
## future-version save on disk is never clobbered by an autosave.
func save_now() -> bool:
	if not is_loaded:
		return false
	if save_blocked:
		GameLog.warn(GameLog.Category.APP, "Skipped save: writes are blocked.")
		return false
	return SaveManager.save_game(data)


## Records a session to disk and adds it to the in-memory list.
## Replaces an existing entry with the same id rather than appending a duplicate,
## matching SessionStore's behaviour so memory and disk stay consistent.
func record_session(session: FocusSession) -> void:
	var existing_index := -1
	for i in sessions.size():
		if sessions[i].id == session.id:
			existing_index = i
			break
	if existing_index >= 0:
		sessions[existing_index] = session
	else:
		sessions.append(session)

	if not save_blocked:
		SaveManager.append_session(session)


# --- Lookups -----------------------------------------------------------------

func get_plant(uid: String) -> PlantInstance:
	for plant: PlantInstance in data.plants:
		if plant.uid == uid:
			return plant
	return null


func get_active_plant() -> PlantInstance:
	return get_plant(data.profile.active_plant_uid)


func get_project(id: String) -> ProjectCategory:
	for project: ProjectCategory in data.projects:
		if project.id == id:
			return project
	return null


func get_catalogue_entry(species_id: StringName) -> CatalogueEntry:
	for entry: CatalogueEntry in data.catalogue:
		if entry.species_id == species_id:
			return entry
	return null


## Catalogue entry for a species, creating it on first request. Every species the
## player encounters gets a row, discovered or not.
func ensure_catalogue_entry(species_id: StringName) -> CatalogueEntry:
	var entry := get_catalogue_entry(species_id)
	if entry != null:
		return entry
	entry = CatalogueEntry.create(species_id)
	data.catalogue.append(entry)
	return entry


func get_achievement_state(achievement_id: StringName) -> AchievementState:
	for state: AchievementState in data.achievements:
		if state.achievement_id == achievement_id:
			return state
	return null


func ensure_achievement_state(achievement_id: StringName) -> AchievementState:
	var state := get_achievement_state(achievement_id)
	if state != null:
		return state
	state = AchievementState.create(achievement_id)
	data.achievements.append(state)
	return state


## Sessions that contributed to one plant, for plant-scoped requirements and the
## §22 plant history.
func get_sessions_for_plant(plant_uid: String) -> Array[FocusSession]:
	var out: Array[FocusSession] = []
	for session: FocusSession in sessions:
		if session.plant_uid == plant_uid:
			out.append(session)
	return out


func get_settings() -> GameSettings:
	return data.settings


func add_journal_entry(entry: JournalEntry) -> void:
	data.journal.append(entry)
	EventBus.journal_entry_added.emit(entry.id)
