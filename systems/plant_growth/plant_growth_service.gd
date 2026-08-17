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
	if species.growth_requirement == null:
		# A species with no authored requirement would otherwise be instantly
		# mature. Treat it as un-growable and log loudly rather than silently
		# handing the player a free plant.
		return 0.0
	return RequirementEvaluator.evaluate(species.growth_requirement, context)


## Stage index for a progress ratio. The final stage is reached only at a full
## 1.0 ratio, so a plant cannot appear mature while still growing.
static func stage_for_ratio(ratio: float, stage_count: int) -> int:
	var stages := maxi(2, stage_count)
	if ratio >= 1.0:
		return stages - 1
	return clampi(int(floor(clampf(ratio, 0.0, 1.0) * float(stages - 1))), 0, stages - 2)


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
