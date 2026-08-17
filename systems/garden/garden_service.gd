class_name GardenService
extends RefCounted
## The authoritative garden expansion logic (§23, §38).
##
## §65 requires expansion unlocks to be DETERMINISTIC. That is achieved by making
## this a convergence pass rather than an event handler: `reconcile` recomputes
## which expansions are earned from the player's total focus and grants any that
## are missing. Running it twice changes nothing, running it after a content
## update picks up new steps, and it cannot double-grant because GardenLayout
## refuses an id it already holds.
##
## The plot never shrinks. Grid size is the largest earned size, so retuning a
## threshold downward in a future version cannot take ground away from a player
## who already had it — and cannot strand a plant outside the new bounds.
##
## Content is passed IN rather than read from ContentDB, exactly as
## RequirementEvaluator takes a context. That keeps this a pure function of its
## arguments — testable with a handful of fabricated expansions, and usable from
## tool scripts, which compile before autoloads exist.

class Result extends RefCounted:
	var newly_unlocked: Array[GardenExpansion] = []
	var grid_size: Vector2i = Vector2i(4, 3)


## Grants every earned expansion. Returns what changed, so the caller can
## celebrate exactly the new ones.
static func reconcile(
	layout: GardenLayout, context: RequirementContext, expansions: Array[GardenExpansion]
) -> Result:
	var result := Result.new()
	if layout == null:
		return result

	var largest := layout.grid_size
	for expansion: GardenExpansion in expansions:
		if not RequirementEvaluator.is_met(expansion.requirement, context):
			continue
		if layout.grant_expansion(String(expansion.id)):
			result.newly_unlocked.append(expansion)
		# Applied whether or not it was newly granted, so a save that recorded
		# the id but not the size still converges to the right plot.
		largest.x = maxi(largest.x, expansion.grid_size.x)
		largest.y = maxi(largest.y, expansion.grid_size.y)

	layout.grid_size = largest
	result.grid_size = largest
	return result


## The next expansion the player has not earned, or null when all are unlocked.
static func next_expansion(
	layout: GardenLayout, context: RequirementContext, expansions: Array[GardenExpansion]
) -> GardenExpansion:
	for expansion: GardenExpansion in expansions:
		if layout.has_expansion(String(expansion.id)):
			continue
		if not RequirementEvaluator.is_met(expansion.requirement, context):
			return expansion
	return null


## 0..1 progress toward the next expansion, for the progress bar.
static func next_expansion_progress(
	layout: GardenLayout, context: RequirementContext, expansions: Array[GardenExpansion]
) -> float:
	var next := next_expansion(layout, context, expansions)
	if next == null:
		return 1.0
	return RequirementEvaluator.evaluate(next.requirement, context)


## Decorations the player may place, given which expansions they hold.
static func available_decorations(
	layout: GardenLayout, decorations: Array[DecorationDef]
) -> Array[DecorationDef]:
	var out: Array[DecorationDef] = []
	for decoration: DecorationDef in decorations:
		if decoration.unlock_expansion_id == &"":
			out.append(decoration)
		elif layout.has_expansion(String(decoration.unlock_expansion_id)):
			out.append(decoration)
	return out


## Plants whose saved cell now falls outside the plot. Should always be empty,
## since the plot only ever grows — but a hand-edited save could contain one, and
## §54 requires the case be defined rather than left to corrupt the view.
static func find_out_of_bounds(layout: GardenLayout, plants: Array[PlantInstance]) -> Array[PlantInstance]:
	var out: Array[PlantInstance] = []
	for plant: PlantInstance in plants:
		if plant.location != PlantInstance.Location.GARDEN:
			continue
		if not layout.is_cell_in_bounds(plant.garden_cell):
			out.append(plant)
	return out
