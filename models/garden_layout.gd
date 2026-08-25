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
## Decorations keyed by "x,y" cell string:
##     { "2,1" -> { "id": "stone_bench", "rotation": 2 } }
## String keys because JSON object keys cannot be Vector2i.
##
## Save format 1 stored the id alone as a bare String. `from_dict` still accepts
## that shape and reads it as rotation 0, so a hand-kept old save opens without
## the migration having to have run.
var decorations: Dictionary = {}

## Quarter turns an ornament can take.
const ROTATIONS: int = 4


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


## Places an ornament, replacing whatever was on the cell.
func set_decoration(cell: Vector2i, decoration_id: String, rotation: int = 0) -> void:
	decorations[cell_key(cell)] = {
		"id": decoration_id,
		"rotation": posmod(rotation, ROTATIONS),
	}


func clear_decoration(cell: Vector2i) -> void:
	decorations.erase(cell_key(cell))


func has_decoration(cell: Vector2i) -> bool:
	return decorations.has(cell_key(cell))


## The ornament on a cell, or "" for an empty one.
func get_decoration_id(cell: Vector2i) -> String:
	return _entry_id(decorations.get(cell_key(cell)))


func get_decoration_rotation(cell: Vector2i) -> int:
	return _entry_rotation(decorations.get(cell_key(cell)))


## Turns an ornament a quarter turn. Returns false when the cell is empty, so a
## caller can fall through to whatever else a rotate gesture might mean.
func rotate_decoration(cell: Vector2i, steps: int = 1) -> bool:
	var key := cell_key(cell)
	if not decorations.has(key):
		return false
	var entry: Variant = decorations[key]
	decorations[key] = {
		"id": _entry_id(entry),
		"rotation": posmod(_entry_rotation(entry) + steps, ROTATIONS),
	}
	return true


## Accepts both the format-1 bare string and the format-2 dictionary.
static func _entry_id(entry: Variant) -> String:
	if entry is String:
		return entry
	if entry is Dictionary:
		return DictUtil.get_string(entry, "id")
	return ""


static func _entry_rotation(entry: Variant) -> int:
	if entry is Dictionary:
		return posmod(DictUtil.get_int(entry, "rotation"), ROTATIONS)
	return 0


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
	# Normalised on the way in, so nothing downstream has to know that two shapes
	# ever existed. Entries with no id at all are dropped rather than kept as
	# invisible occupants of a cell the player cannot then use.
	var raw := DictUtil.get_dict(data, "decorations")
	for key: String in raw:
		var id := _entry_id(raw[key])
		if id.is_empty():
			continue
		layout.decorations[key] = {"id": id, "rotation": _entry_rotation(raw[key])}
	return layout
