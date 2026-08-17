extends Node
## Registry for authored static content (§40, an addition to §39's autoload list).
##
## Owns: loading and indexing the .tres content that ships with the game —
## species, achievements, expeditions, decorations.
## Must never: touch player data. Everything here is identical for every player.
##
## Kept separate from AppState deliberately: merging "the content the game ships"
## with "what this player owns" is exactly how a narrow manager turns into the
## god-object §40 warns against.

const PLANTS_DIR: String = "res://data/plants"
const ACHIEVEMENTS_DIR: String = "res://data/achievements"
const POTS_DIR: String = "res://data/pots"
const EXPEDITIONS_DIR: String = "res://data/expeditions"
const DECORATIONS_DIR: String = "res://data/decorations"

## The pot every plant starts in. Must exist in POTS_DIR.
const DEFAULT_POT_ID: StringName = &"terracotta_basic"

var _species: Dictionary = {}      ## StringName -> PlantSpecies
var _achievements: Dictionary = {} ## StringName -> AchievementDef
var _pots: Dictionary = {}         ## StringName -> PotStyle
## Insertion-ordered id lists, so catalogue and achievement screens have a stable
## default order that does not depend on filesystem enumeration order.
var _species_order: Array[StringName] = []
var _achievement_order: Array[StringName] = []
var _pot_order: Array[StringName] = []


func _ready() -> void:
	reload()


func reload() -> void:
	_species.clear()
	_achievements.clear()
	_pots.clear()
	_species_order.clear()
	_achievement_order.clear()
	_pot_order.clear()

	for resource: Resource in _load_dir(PLANTS_DIR):
		var species := resource as PlantSpecies
		if species == null or not species.is_valid():
			GameLog.warn(GameLog.Category.DATA, "Skipped an invalid plant species resource.")
			continue
		if _species.has(species.id):
			GameLog.warn(GameLog.Category.DATA, "Duplicate species id '%s'; keeping the first." % species.id)
			continue
		_species[species.id] = species
		_species_order.append(species.id)

	for resource: Resource in _load_dir(ACHIEVEMENTS_DIR):
		var achievement := resource as AchievementDef
		if achievement == null or not achievement.is_valid():
			GameLog.warn(GameLog.Category.DATA, "Skipped an invalid achievement resource.")
			continue
		if _achievements.has(achievement.id):
			GameLog.warn(
				GameLog.Category.DATA,
				"Duplicate achievement id '%s'; keeping the first." % achievement.id
			)
			continue
		_achievements[achievement.id] = achievement
		_achievement_order.append(achievement.id)

	for resource: Resource in _load_dir(POTS_DIR):
		var pot := resource as PotStyle
		if pot == null or not pot.is_valid():
			GameLog.warn(GameLog.Category.DATA, "Skipped an invalid pot resource.")
			continue
		if _pots.has(pot.id):
			GameLog.warn(GameLog.Category.DATA, "Duplicate pot id '%s'; keeping the first." % pot.id)
			continue
		_pots[pot.id] = pot
		_pot_order.append(pot.id)

	GameLog.info(
		GameLog.Category.DATA,
		"Content loaded: %d species, %d achievements, %d pots."
		% [_species.size(), _achievements.size(), _pots.size()]
	)


func get_species(id: StringName) -> PlantSpecies:
	return _species.get(id)


## True when a species id in a save no longer exists in this build (§54: "plant
## definition removed in future update"). Callers must keep the PlantInstance and
## render a graceful placeholder rather than deleting the player's plant.
func is_species_missing(id: StringName) -> bool:
	return not _species.has(id)


func get_all_species() -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	for id: StringName in _species_order:
		out.append(_species[id])
	return out


func get_species_count() -> int:
	return _species.size()


func get_achievement(id: StringName) -> AchievementDef:
	return _achievements.get(id)


func get_all_achievements() -> Array[AchievementDef]:
	var out: Array[AchievementDef] = []
	for id: StringName in _achievement_order:
		out.append(_achievements[id])
	return out


## A pot by id, falling back to the default so a plant whose saved pot was
## removed in an update still renders (§54) instead of losing its container.
func get_pot(id: StringName) -> PotStyle:
	if _pots.has(id):
		return _pots[id]
	return _pots.get(DEFAULT_POT_ID)


func get_all_pots() -> Array[PotStyle]:
	var out: Array[PotStyle] = []
	for id: StringName in _pot_order:
		out.append(_pots[id])
	return out


## Loads every resource in a directory.
##
## Handles the exported-build cases that trip up naive directory scans: text
## resources are converted to binary (.tres becomes .res) and remapped files
## appear as "<name>.tres.remap". Loading the un-suffixed path works for all
## three, so the suffix is stripped before loading.
func _load_dir(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		GameLog.debug(GameLog.Category.DATA, "Content directory not present yet: %s" % dir_path)
		return out

	var seen := {}
	for file_name: String in DirAccess.get_files_at(dir_path):
		var name := file_name
		if name.ends_with(".remap"):
			name = name.trim_suffix(".remap")
		if not (name.ends_with(".tres") or name.ends_with(".res")):
			continue

		var path := dir_path.path_join(name)
		if seen.has(path):
			continue
		seen[path] = true

		var resource := ResourceLoader.load(path)
		if resource == null:
			GameLog.error(GameLog.Category.DATA, "Failed to load content resource: %s" % path)
			continue
		out.append(resource)
	return out
