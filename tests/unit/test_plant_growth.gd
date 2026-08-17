extends TestCase
## PlantGrowthService (§53, §14).
##
## §60's acceptance criteria are the spec here: stage changes must occur exactly
## once, and mature plants must stay mature. Both are properties of this class,
## so both are asserted directly rather than being left to manual play-testing.

var _species: PlantSpecies


func before_each() -> void:
	_species = PlantSpecies.new()
	_species.id = &"test_fern"
	_species.display_name = "Test Fern"
	_species.growth_requirement = Requirement.make(
		Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 100.0}, Requirement.Scope.ACTIVE_PLANT
	)


func test_stage_quantization() -> void:
	# Five stages means four growth steps: 0.00-0.24 -> 0, 0.25-0.49 -> 1, etc.
	assert_eq(PlantGrowthService.stage_for_ratio(0.0, 5), 0, "no progress is the seed stage")
	assert_eq(PlantGrowthService.stage_for_ratio(0.3, 5), 1, "a third of the way")
	assert_eq(PlantGrowthService.stage_for_ratio(0.99, 5), 3, "almost there is not mature")
	assert_eq(PlantGrowthService.stage_for_ratio(1.0, 5), 4, "full progress is the final stage")


func test_final_stage_requires_full_progress() -> void:
	# A plant must never LOOK mature while still growing.
	for stage_count in range(2, 8):
		assert_true(
			PlantGrowthService.stage_for_ratio(0.999, stage_count) < stage_count - 1,
			"99.9%% is not the final stage with %d stages" % stage_count
		)


func test_growth_applies_and_matures() -> void:
	var plant := PlantInstance.create(&"test_fern")
	var context := _context_with_minutes(100.0)

	var result := PlantGrowthService.apply_growth(plant, _species, context)
	assert_almost_eq(result.progress_ratio, 1.0, "requirement satisfied")
	assert_true(result.just_matured, "maturity is reported on the transition")
	assert_true(plant.is_mature(), "the plant is mature")
	assert_gt(float(plant.matured_at_utc), 0.0, "the maturity date was stamped")


func test_maturity_is_reported_only_once() -> void:
	# §60: stage changes occur exactly once. A second pass over the same state
	# must not re-fire the celebration or re-add a journal entry.
	var plant := PlantInstance.create(&"test_fern")
	var context := _context_with_minutes(150.0)

	var first := PlantGrowthService.apply_growth(plant, _species, context)
	var second := PlantGrowthService.apply_growth(plant, _species, context)
	assert_true(first.just_matured, "the first pass matures the plant")
	assert_false(second.just_matured, "the second pass does not re-mature it")


func test_mature_plants_stay_mature() -> void:
	# §60: mature plants remain mature — even if a content update later retunes
	# the requirement upward, which would otherwise un-mature a finished plant.
	var plant := PlantInstance.create(&"test_fern")
	PlantGrowthService.apply_growth(plant, _species, _context_with_minutes(100.0))
	assert_true(plant.is_mature(), "matured")

	_species.growth_requirement = Requirement.make(
		Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 100_000.0}, Requirement.Scope.ACTIVE_PLANT
	)
	PlantGrowthService.apply_growth(plant, _species, _context_with_minutes(100.0))
	assert_true(plant.is_mature(), "a retuned requirement cannot revoke maturity")


func test_growth_never_runs_backwards() -> void:
	# §3: progress must feel permanent. A plant the player watched grow must not
	# visibly shrink because a recovered session changed the totals.
	var plant := PlantInstance.create(&"test_fern")
	PlantGrowthService.apply_growth(plant, _species, _context_with_minutes(75.0))
	var reached := plant.growth_stage
	assert_gt(float(reached), 0.0, "the plant grew")

	PlantGrowthService.apply_growth(plant, _species, _context_with_minutes(0.0))
	assert_eq(plant.growth_stage, reached, "the stage did not regress")


func test_stage_changed_only_on_transition() -> void:
	var plant := PlantInstance.create(&"test_fern")
	var context := _context_with_minutes(50.0)
	var first := PlantGrowthService.apply_growth(plant, _species, context)
	var second := PlantGrowthService.apply_growth(plant, _species, context)
	assert_true(first.stage_changed, "the first application changed the stage")
	assert_false(second.stage_changed, "an unchanged ratio reports no stage change")


func test_species_without_a_requirement_cannot_grow() -> void:
	# Otherwise a content authoring mistake would hand the player a free mature
	# plant, silently.
	_species.growth_requirement = null
	var plant := PlantInstance.create(&"test_fern")
	var result := PlantGrowthService.apply_growth(plant, _species, _context_with_minutes(999.0))
	assert_almost_eq(result.progress_ratio, 0.0, "no requirement means no progress")
	assert_false(plant.is_mature(), "and certainly not instant maturity")


func test_null_arguments_are_safe() -> void:
	var result := PlantGrowthService.apply_growth(null, _species, RequirementContext.new())
	assert_false(result.just_matured, "a null plant does not crash or mature")


func test_session_estimate_refuses_to_guess() -> void:
	# §18 forbids implying a precision we do not have. "Focus on 5 separate days"
	# has no honest session-count estimate.
	var plant := PlantInstance.create(&"test_fern")
	_species.growth_requirement = Requirement.make(
		Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 5}, Requirement.Scope.ACTIVE_PLANT
	)
	assert_eq(
		PlantGrowthService.estimated_sessions_remaining(plant, _species, 25.0), -1,
		"a non-minute requirement returns 'unknown' rather than a fabricated number"
	)


func test_session_estimate_for_minute_requirements() -> void:
	var plant := PlantInstance.create(&"test_fern")
	plant.accumulated_focus_minutes = 50.0
	assert_eq(
		PlantGrowthService.estimated_sessions_remaining(plant, _species, 25.0), 2,
		"50 of 100 minutes left is two 25-minute sessions"
	)


func test_stage_count_has_a_floor() -> void:
	# A species with no authored art still needs a sane stage count, or the
	# quantizer would divide by zero.
	assert_true(_species.get_stage_count() >= 2, "there are always at least two stages")


func _context_with_minutes(minutes: float) -> RequirementContext:
	var context := RequirementContext.new()
	context.plant_focus_minutes = minutes
	return context
