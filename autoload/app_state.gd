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

	_ensure_seed_data()

	GameLog.info(
		GameLog.Category.APP,
		"Loaded %d plants, %d sessions, %d projects."
		% [data.plants.size(), sessions.size(), data.projects.size()]
	)

	# Emitted from here, not from SaveManager, because only now are `data` and
	# `sessions` both the loaded ones. Screens refresh straight off this signal, so
	# firing it any earlier renders whatever is being replaced — which is what made
	# an import look like it had done nothing. `reset_to_new_game` emits it at the
	# same point, for the same reason.
	EventBus.save_loaded.emit()


## Starter project categories, so a brand-new player can start a session
## immediately instead of being made to invent a taxonomy first (§9).
##
## These are ordinary categories: deletable, renamable, and not special-cased
## anywhere. They are seeded only when the player has none at all, so a player
## who deletes every category does not get them silently pushed back.
const SEED_PROJECTS: Array[Dictionary] = [
	{"name": "Studying", "color": "moss", "icon": "book"},
	{"name": "Work", "color": "sky", "icon": "briefcase"},
	{"name": "Reading", "color": "amber", "icon": "page"},
	{"name": "Programming", "color": "terracotta", "icon": "code"},
	{"name": "Personal", "color": "clay", "icon": "heart"},
]


func _ensure_seed_data() -> void:
	if not data.projects.is_empty():
		return

	for entry: Dictionary in SEED_PROJECTS:
		data.projects.append(
			ProjectCategory.create(entry["name"], entry["color"], entry["icon"])
		)

	# Selecting the first one means the Focus screen opens ready to go rather
	# than in an error state on a fresh save.
	if data.profile.active_project_id.is_empty():
		data.profile.active_project_id = data.projects[0].id

	GameLog.info(GameLog.Category.APP, "Seeded %d starter projects." % data.projects.size())


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


## Projects the player can currently pick, in creation order.
## Archived categories stay in the save forever: their id is referenced by every
## session ever recorded against them, and deleting one would orphan history.
func get_active_projects() -> Array[ProjectCategory]:
	var out: Array[ProjectCategory] = []
	for project: ProjectCategory in data.projects:
		if not project.archived:
			out.append(project)
	return out


func add_project(name: String, color_token: String, icon_id: String = "leaf") -> ProjectCategory:
	var project := ProjectCategory.create(name, color_token, icon_id)
	data.projects.append(project)
	save_now()
	return project


## Hides a category from the picker without destroying the sessions that
## reference it. There is deliberately no hard delete.
func archive_project(project_id: String) -> void:
	var project := get_project(project_id)
	if project == null:
		return
	project.archived = true

	# The archived category cannot remain selected, or the Focus screen would
	# open pointing at something the player can no longer see.
	if data.profile.active_project_id == project_id:
		var remaining := get_active_projects()
		data.profile.active_project_id = remaining[0].id if not remaining.is_empty() else ""
	save_now()


## Display name for a project id, including archived ones, so session history
## never renders a bare id. Returns a readable fallback for an unknown id (§54:
## a category removed by a future update must not break the journal).
func get_project_name(project_id: String) -> String:
	var project := get_project(project_id)
	if project != null:
		return project.display_name
	return "Unsorted" if project_id.is_empty() else "Removed project"


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


## Begins growing a new plant of `species_id` and makes it the active target.
##
## A PlantInstance is created per plant grown, never reused, so §22's permanent
## per-plant history stays intact: growing a second monstera does not overwrite
## the record of the first.
func start_growing(species_id: StringName) -> PlantInstance:
	var species := ContentDB.get_species(species_id)
	if species == null:
		GameLog.error(GameLog.Category.PLANT, "Cannot grow unknown species '%s'." % species_id)
		return null

	var plant := PlantInstance.create(species_id, data.profile.active_project_id)
	plant.pot_id = ContentDB.DEFAULT_POT_ID
	data.plants.append(plant)
	data.profile.active_plant_uid = plant.uid

	# Seeing a species in your own pot counts as discovering it (§16). Growing it
	# to maturity is what fills in the rest of its catalogue statistics.
	var entry := ensure_catalogue_entry(species_id)
	if entry.discover():
		EventBus.catalogue_entry_discovered.emit(String(species_id))

	add_journal_entry(
		JournalEntry.create(
			JournalEntry.Kind.SEED_PLANTED,
			"Planted %s" % species.display_name,
			"Started while working on %s." % get_project_name(plant.primary_project_id),
			plant.uid
		)
	)

	save_now()
	EventBus.active_plant_changed.emit(plant.uid)
	GameLog.info(GameLog.Category.PLANT, "Started growing %s (%s)." % [species.display_name, plant.uid])
	return plant


## Switches the growth target to an existing plant.
func set_active_plant(plant_uid: String) -> void:
	if data.profile.active_plant_uid == plant_uid:
		return
	data.profile.active_plant_uid = plant_uid
	save_now()
	EventBus.active_plant_changed.emit(plant_uid)


## Plants still growing, newest first. These are what the player can switch to.
func get_growing_plants() -> Array[PlantInstance]:
	var out: Array[PlantInstance] = []
	for plant: PlantInstance in data.plants:
		if not plant.is_mature():
			out.append(plant)
	out.reverse()
	return out


func get_mature_plants() -> Array[PlantInstance]:
	var out: Array[PlantInstance] = []
	for plant: PlantInstance in data.plants:
		if plant.is_mature():
			out.append(plant)
	return out


## 0..1 progress of a plant toward maturity, via the one growth service.
func get_plant_progress(plant: PlantInstance) -> float:
	if plant == null:
		return 0.0
	var species := ContentDB.get_species(plant.species_id)
	if species == null:
		return 0.0
	return PlantGrowthService.progress_ratio(
		plant, species, StatisticsManager.build_plant_context(plant.uid)
	)


## Species the player is allowed to start growing, honouring unlock requirements.
func get_available_species() -> Array[PlantSpecies]:
	var context := StatisticsManager.build_context()
	var out: Array[PlantSpecies] = []
	for species: PlantSpecies in ContentDB.get_all_species():
		if species.unlock_requirement == null:
			out.append(species)
		elif RequirementEvaluator.is_met(species.unlock_requirement, context):
			out.append(species)
	return out


## Wipes progress and starts a fresh garden (§35).
##
## Deliberately keeps the settings the player has configured: resetting progress
## is about the garden, not about forgetting that they prefer 45-minute sessions
## and reduced motion. §35 requires strong confirmation, which is the caller's
## job — by the time this runs the decision has been made twice.
func reset_to_new_game() -> void:
	var preserved := data.settings

	# Session shards are removed too. Leaving them would mean a "new" garden that
	# silently inherits years of history the moment statistics recompute.
	SessionStore.clear(SaveManager.get_save_dir())

	data = SaveData.create_new()
	data.settings = preserved
	sessions = []
	_ensure_seed_data()
	save_now()

	StatisticsManager.invalidate()
	EventBus.save_loaded.emit()
	GameLog.warn(GameLog.Category.APP, "Progress was reset at the player's request.")


func get_settings() -> GameSettings:
	return data.settings


func add_journal_entry(entry: JournalEntry) -> void:
	data.journal.append(entry)
	EventBus.journal_entry_added.emit(entry.id)
