class_name PlantGrowthService
extends RefCounted
## The one authoritative plant growth implementation (§14, §38).
##
## §14 requires a single growth service and forbids duplicating stage thresholds
## across scenes. Nothing else in the codebase may decide what stage a plant is
## in — UI asks this class and renders the answer.
##
## Stages are derived, never stored as a threshold table: a plant's progress ratio
## comes from its species' `growth_requirement` through RequirementEvaluator, and
## the stage is that ratio quantized to the species' stage count. Change a
## species' requirement and every stage boundary moves with it automatically.

## Outcome of applying growth, so callers know exactly which one-time events to
## fire. Returning this instead of emitting signals directly keeps the service
## testable without a scene tree.
class GrowthResult extends RefCounted:
	var previous_stage: int = 0
	var new_stage: int = 0
	var progress_ratio: float = 0.0
	var stage_changed: bool = false
	## True only on the transition into maturity, so "plant matured" fires once
	## and a mature plant can never re-mature (§60).
	var just_matured: bool = false


## 0..1 progress toward maturity for a plant.
static func progress_ratio(
	plant: PlantInstance, species: PlantSpecies, context: RequirementContext
) -> float:
	if plant == null or species == null:
		return 0.0
	if plant.is_mature():
		# A plant that already finished is finished, whatever the requirement says
		# today. §60 requires maturity to be permanent, and a content update that
		# retunes a species upward would otherwise re-open every specimen the
		# player already grew — and visibly shrink them back down on the shelf.
		return 1.0
	# A species with no authored requirement would otherwise be instantly mature.
	# It counts as un-growable rather than silently handing the player a free
	# plant — but the floor below still applies, because a content update that
	# drops a requirement is a bug and must not retroactively un-grow a plant
	# somebody watched grow. The floor can never reach 1.0, so "un-growable" is
	# still exactly what it means: no maturity from nothing.
	var evaluated := (
		0.0 if species.growth_requirement == null
		else RequirementEvaluator.evaluate(species.growth_requirement, context)
	)

	# A plant is never DRAWN below the stage it has already reached.
	#
	# `apply_growth` has always refused to let a stored stage regress (§3: progress
	# must feel permanent), but this function — which is what every screen actually
	# renders — had no such floor, so the two could disagree. They did: an imported
	# save whose session history had not come with it evaluated to 0.0 here, and a
	# garden of half-grown plants redrew itself as a tray of seeds while each one
	# still carried the right stage in the file.
	#
	# The floor is the LOWER EDGE of the reached band, so it can only ever restore
	# a plant to where it already was: `stage_for_ratio` maps it straight back to
	# the same stage, and because the highest stage index is one below the count it
	# can never reach 1.0 and hand out a maturity nothing earned.
	#
	# THE CLAMP IS LOAD-BEARING. `PlantInstance.from_dict` only floors growth_stage
	# at zero, so a hand-edited or foreign save can carry stage 99 — unclamped that
	# would return 33.0, `apply_growth` would see a full ratio, and every plant in
	# the file would mature on load. It also covers a species whose stage art
	# SHRANK in a content update below a stage some plant had already reached.
	var stages := maxi(2, species.get_stage_count())
	var reached := float(clampi(plant.growth_stage, 0, stages - 1)) / float(stages)
	return maxf(evaluated, reached)


## Names for the three default stages, in order. Used wherever a stage is shown
## to the player, so "Young" never becomes "stage 2" on one screen and
## "half-grown" on another.
const STAGE_NAMES: Array[String] = ["Seedling", "Young", "Mature"]

## The stage at which a plant may be put on the shelf or planted out.
##
## One, not zero: a seed in a pot is not a thing to display, and the point of the
## gate is that reaching it means something. With three equal stages that is a
## third of the way — one hour for a common species.
const DISPLAY_STAGE: int = 1


## Stage index for a progress ratio, in equal bands.
##
## Each stage occupies the same share of the requirement, so three stages really
## are thirds. An earlier version reserved the last stage for a full 1.0 ratio,
## which was fine at five stages and degenerate at three: the only boundary
## landed at 50% and the plant jumped straight from seedling to finished.
##
## Reaching the last band is NOT maturity — `apply_growth` still sets that only at
## a full ratio. The final third is the plant filling out and coming into flower,
## which is the difference the player watches for.
static func stage_for_ratio(ratio: float, stage_count: int) -> int:
	var stages := maxi(2, stage_count)
	return clampi(int(floor(clampf(ratio, 0.0, 1.0) * float(stages))), 0, stages - 1)


## Human-readable name for a stage index. Falls back to a numbered form for a
## species with authored art and more stages than the default three.
static func stage_name(stage: int, stage_count: int) -> String:
	if stage_count == STAGE_NAMES.size():
		return STAGE_NAMES[clampi(stage, 0, STAGE_NAMES.size() - 1)]
	return "Stage %d" % (clampi(stage, 0, maxi(1, stage_count) - 1) + 1)


## Recomputes a plant's stage and maturity from its contributing sessions and
## writes the result onto the instance.
##
## Idempotent: calling it twice with the same context produces the same stage and
## reports `stage_changed`/`just_matured` only on the real transition. That is
## what satisfies §60's "stage changes occur exactly once" and "mature plants
## remain mature" — maturity is never revoked, even if a requirement is later
## retuned downward in a content update.
static func apply_growth(
	plant: PlantInstance, species: PlantSpecies, context: RequirementContext
) -> GrowthResult:
	var result := GrowthResult.new()
	if plant == null or species == null:
		return result

	result.previous_stage = plant.growth_stage
	result.progress_ratio = progress_ratio(plant, species, context)

	var stage_count := species.get_stage_count()
	var computed_stage := stage_for_ratio(result.progress_ratio, stage_count)

	# Growth never runs backwards. A plant that reached a stage keeps it, so a
	# retuned requirement or a recovered session cannot visibly shrink a plant
	# the player already watched grow (§3: progress must feel permanent).
	result.new_stage = maxi(plant.growth_stage, computed_stage)
	result.stage_changed = result.new_stage != result.previous_stage
	plant.growth_stage = result.new_stage

	if not plant.is_mature() and result.progress_ratio >= 1.0:
		plant.maturity = PlantInstance.Maturity.MATURE
		plant.matured_at_utc = Time.get_unix_time_from_system()
		result.just_matured = true

	return result


## Sessions still needed at the player's usual session length (§18).
## Returns -1 when the requirement is not minute-shaped, because §18 forbids
## implying a precision we do not have — "5 separate days" has no honest session
## estimate.
static func estimated_sessions_remaining(
	plant: PlantInstance, species: PlantSpecies, typical_session_minutes: float
) -> int:
	if plant == null or species == null or typical_session_minutes <= 0.0:
		return -1
	var required := species.get_display_focus_minutes()
	if required < 0.0:
		return -1
	var remaining := required - plant.accumulated_focus_minutes
	if remaining <= 0.0:
		return 0
	return int(ceil(remaining / typical_session_minutes))
