class_name GardenLayout
extends RefCounted
## The expandable garden (§23, §24). Player data — JSON.
##
## As with the shelf, plant placement lives on PlantInstance.garden_cell, not
## here. This holds the plot size, which expansions have been unlocked, and where
## decorations sit.
##
## Expansions are recorded by id rather than by a plot size number so that
## "unlock is deterministic" (§65): re-evaluating the cumulative-focus milestones
## can only ever add ids that are already there, never double-grant.

var environment_id: StringName = &"cottage_garden"
var grid_size: Vector2i = Vector2i(4, 3)
var unlocked_expansion_ids: PackedStringArray = PackedStringArray()
## Decorations keyed by "x,y" cell string: { "2,1" -> decoration_id: String }.
## String keys because JSON object keys cannot be Vector2i.
var decorations: Dictionary = {}


static func create() -> GardenLayout:
	return GardenLayout.new()


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func key_to_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func has_expansion(expansion_id: String) -> bool:
	return unlocked_expansion_ids.has(expansion_id)


## True only on first grant, so the expansion celebration fires once (§65).
func grant_expansion(expansion_id: String) -> bool:
	if expansion_id.is_empty() or unlocked_expansion_ids.has(expansion_id):
		return false
	unlocked_expansion_ids.append(expansion_id)
	return true


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func to_dict() -> Dictionary:
	return {
		"environment_id": String(environment_id),
		"grid_size_x": grid_size.x,
		"grid_size_y": grid_size.y,
		"unlocked_expansion_ids": unlocked_expansion_ids,
		"decorations": decorations.duplicate(true),
	}


static func from_dict(data: Dictionary) -> GardenLayout:
	var layout := GardenLayout.new()
	layout.environment_id = StringName(
		DictUtil.get_string(data, "environment_id", "cottage_garden")
	)
	layout.grid_size = Vector2i(
		clampi(DictUtil.get_int(data, "grid_size_x", 4), 1, 64),
		clampi(DictUtil.get_int(data, "grid_size_y", 3), 1, 64),
	)
	layout.unlocked_expansion_ids = DictUtil.get_string_array(data, "unlocked_expansion_ids")
	layout.decorations = DictUtil.get_dict(data, "decorations")
	return layout
