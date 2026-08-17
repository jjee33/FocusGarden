class_name GardenExpansion
extends Resource
## One unlockable step in the garden's growth (§23).
##
## §23 asks for the expansion system to be data-driven and warns against granting
## everything early. Each step carries its own Requirement, evaluated by the same
## engine as everything else (§48), so the milestone ladder is content rather
## than a hardcoded table of hour thresholds.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Plot size once this expansion is active. Expansions are cumulative: the
## garden takes the largest granted size, so unlocking out of order or
## re-evaluating cannot shrink it.
@export var grid_size: Vector2i = Vector2i(4, 3)
## Decoration ids this step makes placeable.
@export var unlocks_decorations: Array[StringName] = []
@export var requirement: Requirement


static func make(
	expansion_id: String,
	name: String,
	description_text: String,
	size: Vector2i,
	hours: float,
	decorations: Array[StringName] = []
) -> GardenExpansion:
	var expansion := GardenExpansion.new()
	expansion.id = StringName(expansion_id)
	expansion.display_name = name
	expansion.description = description_text
	expansion.grid_size = size
	expansion.unlocks_decorations = decorations
	expansion.requirement = Requirement.make(
		Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": hours * 60.0}
	)
	return expansion


func is_valid() -> bool:
	return id != &"" and requirement != null
