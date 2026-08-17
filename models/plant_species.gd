class_name PlantSpecies
extends Resource
## A species definition — authored content, identical for every player (§13).
##
## Static content, authored as .tres in data/plants/. Never written to a save.
## What the player OWNS is a PlantInstance that points at one of these by id.
##
## §13 lists `required_focus_minutes` as a field. It is deliberately NOT stored
## here: the maturity rule lives in `growth_requirement` so that §47's varied
## patterns (100 minutes, 4 sessions, 5 separate days, morning sessions) all work
## through one mechanism. A plain minute count is just the most common shape of
## that requirement, and `get_display_focus_minutes()` derives it for the UI.
## Storing both would be two sources of truth for one threshold (§14, §38).

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

@export_group("Identity")
@export var id: StringName = &""
@export var display_name: String = ""
@export var scientific_name: String = ""
@export_multiline var description: String = ""

@export_group("Classification")
@export var rarity: Rarity = Rarity.COMMON
## Free-form id matching a biome definition, not an enum — §77 expects hundreds of
## plants and new biomes without an engine-side enum edit.
@export var biome_id: StringName = &"houseplant"
@export var tags: Array[StringName] = []

@export_group("Growth")
## The maturity rule. Also drives the growth-stage progress ratio.
@export var growth_requirement: Requirement
## Stage artwork, seed first, mature last. Stage COUNT is derived from this array
## so a species can never claim more stages than it has art for (§14).
@export var stage_textures: Array[Texture2D] = []
@export var catalogue_texture: Texture2D
@export var icon_texture: Texture2D

@export_group("Presentation")
@export var botanical: BotanicalInfo
@export var preferred_pot_ids: Array[StringName] = []
## Cosmetic mutations this species can roll (§20). Cosmetic only, never a
## productivity modifier.
@export var allowed_mutation_ids: Array[StringName] = []

@export_group("Availability")
## Hidden species show as silhouettes in the catalogue until first discovered (§16).
@export var hidden_until_discovered: bool = false
## Condition to make this species selectable. Null means available from the start.
@export var unlock_requirement: Requirement
## Empty means available year-round.
@export var seasonal_months: Array[int] = []

## Fallback used when a species has no authored art yet, so the catalogue renders
## a deliberate placeholder instead of an empty rect (§73).
const FALLBACK_STAGE_COUNT: int = 5


## Number of visual growth stages, minimum 2 (a seed and a mature form).
func get_stage_count() -> int:
	return maxi(2, stage_textures.size()) if not stage_textures.is_empty() else FALLBACK_STAGE_COUNT


func get_rarity_name() -> String:
	return RARITY_NAMES[clampi(int(rarity), 0, RARITY_NAMES.size() - 1)]


## Texture for a stage index, or null when art has not been authored yet.
## Callers must handle null and substitute a placeholder — see ASSET_PLACEHOLDERS.md.
func get_stage_texture(stage: int) -> Texture2D:
	if stage_textures.is_empty():
		return null
	return stage_textures[clampi(stage, 0, stage_textures.size() - 1)]


## Approximate focus minutes to maturity, for catalogue and selection screens
## (§18). Derived from the requirement, never stored separately.
## Returns -1 when the requirement is not minute-shaped (e.g. "focus on 5 separate
## days"), so the UI can show the requirement's own wording instead of a fake
## minute figure. §18 forbids implying a precision we do not have.
func get_display_focus_minutes() -> float:
	if growth_requirement == null:
		return -1.0
	if growth_requirement.type == Requirement.Type.TOTAL_FOCUS_MINUTES:
		return DictUtil.get_float(growth_requirement.params, "amount", -1.0)
	return -1.0


func is_seasonal() -> bool:
	return not seasonal_months.is_empty()


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty()
