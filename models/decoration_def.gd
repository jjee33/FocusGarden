class_name DecorationDef
extends Resource
## A placeable garden ornament (§23's bench, pond, lanterns, path).
##
## Drawn by GardenView from `shape` and colours, matching how plants and pots are
## handled: parameters rather than sprites, so the set can grow without art.

enum Shape { BENCH, POND, LANTERN, PATH, FENCE, BIRDBATH, PLANTER, STONE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var shape: Shape = Shape.STONE
@export var primary_color: Color = Color("#C69A63")
@export var accent_color: Color = Color("#A2743F")
## Ornaments the player has not unlocked are listed but not placeable.
@export var unlock_expansion_id: StringName = &""


static func make(
	decoration_id: String, name: String, shape_kind: Shape, primary: String, accent: String,
	unlocked_by: String = ""
) -> DecorationDef:
	var decoration := DecorationDef.new()
	decoration.id = StringName(decoration_id)
	decoration.display_name = name
	decoration.shape = shape_kind
	decoration.primary_color = Color(primary)
	decoration.accent_color = Color(accent)
	decoration.unlock_expansion_id = StringName(unlocked_by)
	return decoration


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty()
