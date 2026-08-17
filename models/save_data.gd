class_name SaveData
extends RefCounted
## The complete player save, minus session records (§36).
##
## Sessions live in their own year-sharded files and are NOT part of this object.
## §37 forbids storing only aggregates, so the session history grows without
## bound; keeping it here would mean rewriting years of history on every save.
## Sharding is in the format from day one because adding it later would cost a
## migration (see SAVE_FORMAT.md).

## Bump this whenever the on-disk shape changes, and add a matching step to
## SaveMigrations. Never reuse a version number.
const CURRENT_VERSION: int = 1

var save_version: int = CURRENT_VERSION
var profile: PlayerProfile = PlayerProfile.new()
var settings: GameSettings = GameSettings.new()
var plants: Array[PlantInstance] = []
var projects: Array[ProjectCategory] = []
var catalogue: Array[CatalogueEntry] = []
var achievements: Array[AchievementState] = []
var journal: Array[JournalEntry] = []
var shelf: ShelfLayout = ShelfLayout.create()
var garden: GardenLayout = GardenLayout.create()
## Expedition id -> progress dictionary. Shape owned by the expedition system;
## kept opaque here so SaveData does not need to change when expeditions do.
var expeditions: Dictionary = {}
## Last completed session id, used to detect a session interrupted by a crash.
var in_flight_session: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"save_version": save_version,
		"player": profile.to_dict(),
		"settings": settings.to_dict(),
		"plants": _to_dicts(plants),
		"projects": _to_dicts(projects),
		"catalogue": _to_dicts(catalogue),
		"achievements": _to_dicts(achievements),
		"journal": _to_dicts(journal),
		"shelf": shelf.to_dict(),
		"garden": garden.to_dict(),
		"expeditions": expeditions.duplicate(true),
		"in_flight_session": in_flight_session.duplicate(true),
	}


static func from_dict(data: Dictionary) -> SaveData:
	var save := SaveData.new()
	save.save_version = DictUtil.get_int(data, "save_version", 1)
	save.profile = PlayerProfile.from_dict(DictUtil.get_dict(data, "player"))
	save.settings = GameSettings.from_dict(DictUtil.get_dict(data, "settings"))
	save.shelf = ShelfLayout.from_dict(DictUtil.get_dict(data, "shelf"))
	save.garden = GardenLayout.from_dict(DictUtil.get_dict(data, "garden"))
	save.expeditions = DictUtil.get_dict(data, "expeditions")
	save.in_flight_session = DictUtil.get_dict(data, "in_flight_session")

	# Entries that fail to deserialize are skipped rather than aborting the whole
	# load: losing one malformed plant is recoverable, losing the save is not.
	for entry: Variant in DictUtil.get_array(data, "plants"):
		if entry is Dictionary:
			var plant := PlantInstance.from_dict(entry)
			if not plant.uid.is_empty():
				save.plants.append(plant)
	for entry: Variant in DictUtil.get_array(data, "projects"):
		if entry is Dictionary:
			var project := ProjectCategory.from_dict(entry)
			if not project.id.is_empty():
				save.projects.append(project)
	for entry: Variant in DictUtil.get_array(data, "catalogue"):
		if entry is Dictionary:
			var catalogue_entry := CatalogueEntry.from_dict(entry)
			if catalogue_entry.species_id != &"":
				save.catalogue.append(catalogue_entry)
	for entry: Variant in DictUtil.get_array(data, "achievements"):
		if entry is Dictionary:
			var achievement := AchievementState.from_dict(entry)
			if achievement.achievement_id != &"":
				save.achievements.append(achievement)
	for entry: Variant in DictUtil.get_array(data, "journal"):
		if entry is Dictionary:
			save.journal.append(JournalEntry.from_dict(entry))

	save._drop_duplicate_ids()
	return save


## Fresh save for a brand-new player. Content seeding (starter projects, starter
## plant) is AppState's job, not this one — SaveData only owns shape.
static func create_new() -> SaveData:
	var save := SaveData.new()
	save.save_version = CURRENT_VERSION
	save.profile = PlayerProfile.create("Gardener")
	return save


## §54 lists duplicated IDs as a case that must not be left undefined. A dupe
## would make lookups nondeterministic, so the first occurrence wins and the rest
## are dropped at the boundary.
func _drop_duplicate_ids() -> void:
	plants = _dedupe(plants, func(item: PlantInstance) -> String: return item.uid)
	projects = _dedupe(projects, func(item: ProjectCategory) -> String: return item.id)
	catalogue = _dedupe(
		catalogue, func(item: CatalogueEntry) -> String: return String(item.species_id)
	)
	achievements = _dedupe(
		achievements, func(item: AchievementState) -> String: return String(item.achievement_id)
	)
	journal = _dedupe(journal, func(item: JournalEntry) -> String: return item.id)


func _dedupe(items: Array, key_of: Callable) -> Array:
	var seen := {}
	var out := []
	for item: Variant in items:
		var key: String = key_of.call(item)
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		out.append(item)
	# Rebuild as the original typed array so static typing survives the round trip.
	var typed: Array = items.duplicate()
	typed.clear()
	typed.assign(out)
	return typed


static func _to_dicts(items: Array) -> Array:
	var out: Array = []
	for item: Variant in items:
		out.append(item.to_dict())
	return out
