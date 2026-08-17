class_name AchievementDef
extends Resource
## An achievement definition (§26). Static content, authored as .tres.
##
## The unlock condition is a plain Requirement, so achievements share the one
## evaluation engine with plant unlocks, expeditions, and garden upgrades (§48).
## Adding an achievement is authoring data, never writing code.

enum Category { FOCUS, COLLECTION, CONSISTENCY, GARDEN, EXPLORATION }

const CATEGORY_NAMES: Array[String] = [
	"Focus", "Collection", "Consistency", "Garden", "Exploration",
]

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.FOCUS
@export var rarity: PlantSpecies.Rarity = PlantSpecies.Rarity.COMMON
@export var icon_texture: Texture2D

## Hidden achievements show as "???" until unlocked (§26).
@export var hidden: bool = false
## Shows a progress bar (7/10 plants) rather than just locked/unlocked (§26).
@export var track_progress: bool = true

@export var requirement: Requirement


func get_category_name() -> String:
	return CATEGORY_NAMES[clampi(int(category), 0, CATEGORY_NAMES.size() - 1)]


func is_valid() -> bool:
	return id != &"" and not title.is_empty() and requirement != null
