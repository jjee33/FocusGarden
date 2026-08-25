class_name PlantStageText
extends RefCounted
## How a plant's growth is worded, in one place (§14, §74).
##
## Four screens show a plant's progress — the shelf, the garden, the plant picker
## and the plant history dialog — and before this they each phrased it their own
## way: "62% grown" here, "Still growing" there, a bare duration somewhere else.
## §74 asks that the app read as one product, and a number the player is watching
## climb is exactly the wrong thing to name three ways.
##
## Wording only. The stage itself comes from PlantGrowthService, which stays the
## single authority on what stage a plant is in.


## The full phrase: stage name, and the percentage while there is still one to
## show. A finished plant says so instead of saying "Mature · 100%", which reads
## as a progress bar that never went away.
static func describe(plant: PlantInstance) -> String:
	if plant == null:
		return ""
	if plant.is_mature():
		return "Mature"
	return "%s · %d%%" % [stage_label(plant), percent(plant)]


## Just the stage name — "Seedling", "Young", "Mature".
static func stage_label(plant: PlantInstance) -> String:
	if plant == null:
		return ""
	if plant.is_mature():
		return PlantGrowthService.STAGE_NAMES[PlantGrowthService.STAGE_NAMES.size() - 1]
	var species := ContentDB.get_species(plant.species_id)
	var stages := species.get_stage_count() if species != null else PlantSpecies.DEFAULT_STAGE_COUNT
	return PlantGrowthService.stage_name(plant.growth_stage, stages)


static func percent(plant: PlantInstance) -> int:
	return int(AppState.get_plant_progress(plant) * 100.0)


## Why a plant cannot be displayed yet, phrased as what to do about it rather
## than as a refusal (§74's empty states, applied to a disabled state).
static func display_requirement(plant: PlantInstance) -> String:
	if plant == null or plant.can_be_displayed():
		return ""
	var species := ContentDB.get_species(plant.species_id)
	if species == null:
		return "Not far enough along to display yet."
	var total := species.get_display_focus_minutes()
	if total < 0.0:
		return "Reaches its first stage part-way through growing."
	var needed := total / float(species.get_stage_count())
	return "Ready for the shelf after %s of focus." % TimeUtil.format_duration(needed)
