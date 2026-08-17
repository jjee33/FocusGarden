class_name PlantInstance
extends RefCounted
## A plant the player actually owns (§13). Player data — JSON, never .tres.
##
## Strictly separate from PlantSpecies: the species is the shared definition, this
## is one player's individual plant with its own history. The pairing is what
## makes §22's "Grown while studying Network+, 14h 25m, planted Aug 4" possible.
##
## PLACEMENT INVARIANT: a plant is in exactly one place, expressed by a single
## `location` field. Shelf and garden positions are not independent booleans, so
## "placed in two spots at once" (§62) cannot be represented at all.

enum Location { INVENTORY, SHELF, GARDEN }

enum Maturity { GROWING, MATURE }

var uid: String = ""
var species_id: StringName = &""
var nickname: String = ""
var planted_at_utc: float = 0.0
var matured_at_utc: float = 0.0

## Credited focus minutes grown into THIS plant. Authoritative for its progress.
var accumulated_focus_minutes: float = 0.0
var growth_stage: int = 0
var maturity: Maturity = Maturity.GROWING

## Sessions that contributed, for the §22 plant history and for plant-scoped
## requirements like "focus on 5 separate days".
var contributing_session_ids: PackedStringArray = PackedStringArray()
## Project the plant was mostly grown under, recomputed as sessions accrue.
var primary_project_id: String = ""

## Cosmetic only (§20). Never affects growth rate or focus productivity.
var mutation_ids: Array[StringName] = []
var pot_id: StringName = &"terracotta_basic"
var favorite: bool = false

var location: Location = Location.INVENTORY
## Shelf slot index when location == SHELF, else -1.
var shelf_slot: int = -1
## Garden cell when location == GARDEN, else (-1, -1).
var garden_cell: Vector2i = Vector2i(-1, -1)

## Mystery seed support (§19). While unrevealed the UI must not show species_id.
var is_mystery: bool = false
var mystery_revealed: bool = false


static func create(species: StringName, project: String = "") -> PlantInstance:
	var plant := PlantInstance.new()
	plant.uid = Uid.generate("pl")
	plant.species_id = species
	plant.primary_project_id = project
	plant.planted_at_utc = Time.get_unix_time_from_system()
	return plant


## True when the species identity should be hidden from the player (§19).
func is_species_hidden() -> bool:
	return is_mystery and not mystery_revealed


func is_mature() -> bool:
	return maturity == Maturity.MATURE


## Moves the plant, clearing whatever placement it previously had. The only
## supported way to change location — assigning the fields directly is what
## would reintroduce the duplicate-placement bug.
func move_to_inventory() -> void:
	location = Location.INVENTORY
	shelf_slot = -1
	garden_cell = Vector2i(-1, -1)


func move_to_shelf(slot: int) -> void:
	location = Location.SHELF
	shelf_slot = slot
	garden_cell = Vector2i(-1, -1)


func move_to_garden(cell: Vector2i) -> void:
	location = Location.GARDEN
	garden_cell = cell
	shelf_slot = -1


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"species_id": String(species_id),
		"nickname": nickname,
		"planted_at_utc": planted_at_utc,
		"matured_at_utc": matured_at_utc,
		"accumulated_focus_minutes": accumulated_focus_minutes,
		"growth_stage": growth_stage,
		"maturity": int(maturity),
		"contributing_session_ids": contributing_session_ids,
		"primary_project_id": primary_project_id,
		"mutation_ids": _string_names_to_array(mutation_ids),
		"pot_id": String(pot_id),
		"favorite": favorite,
		"location": int(location),
		"shelf_slot": shelf_slot,
		"garden_cell_x": garden_cell.x,
		"garden_cell_y": garden_cell.y,
		"is_mystery": is_mystery,
		"mystery_revealed": mystery_revealed,
	}


static func from_dict(data: Dictionary) -> PlantInstance:
	var plant := PlantInstance.new()
	plant.uid = DictUtil.get_string(data, "uid")
	plant.species_id = StringName(DictUtil.get_string(data, "species_id"))
	plant.nickname = DictUtil.get_string(data, "nickname")
	plant.planted_at_utc = DictUtil.get_float(data, "planted_at_utc")
	plant.matured_at_utc = DictUtil.get_float(data, "matured_at_utc")
	plant.accumulated_focus_minutes = maxf(
		0.0, DictUtil.get_float(data, "accumulated_focus_minutes")
	)
	plant.growth_stage = maxi(0, DictUtil.get_int(data, "growth_stage"))
	var raw_maturity := DictUtil.get_int(data, "maturity", int(Maturity.GROWING))
	plant.maturity = (
		raw_maturity as Maturity
		if raw_maturity >= 0 and raw_maturity <= int(Maturity.MATURE)
		else Maturity.GROWING
	)
	plant.contributing_session_ids = DictUtil.get_string_array(data, "contributing_session_ids")
	plant.primary_project_id = DictUtil.get_string(data, "primary_project_id")
	for mutation: String in DictUtil.get_string_array(data, "mutation_ids"):
		plant.mutation_ids.append(StringName(mutation))
	plant.pot_id = StringName(DictUtil.get_string(data, "pot_id", "terracotta_basic"))
	plant.favorite = DictUtil.get_bool(data, "favorite")

	var raw_location := DictUtil.get_int(data, "location", int(Location.INVENTORY))
	plant.location = (
		raw_location as Location
		if raw_location >= 0 and raw_location <= int(Location.GARDEN)
		else Location.INVENTORY
	)
	plant.shelf_slot = DictUtil.get_int(data, "shelf_slot", -1)
	plant.garden_cell = Vector2i(
		DictUtil.get_int(data, "garden_cell_x", -1), DictUtil.get_int(data, "garden_cell_y", -1)
	)
	plant.is_mystery = DictUtil.get_bool(data, "is_mystery")
	plant.mystery_revealed = DictUtil.get_bool(data, "mystery_revealed")

	# Re-assert the placement invariant. A save hand-edited or written by a buggy
	# build could carry a shelf slot AND a garden cell; `location` wins.
	match plant.location:
		Location.INVENTORY:
			plant.shelf_slot = -1
			plant.garden_cell = Vector2i(-1, -1)
		Location.SHELF:
			plant.garden_cell = Vector2i(-1, -1)
		Location.GARDEN:
			plant.shelf_slot = -1
	return plant


static func _string_names_to_array(values: Array[StringName]) -> Array:
	var out: Array = []
	for value: StringName in values:
		out.append(String(value))
	return out
