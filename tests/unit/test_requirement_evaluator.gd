extends TestCase
## RequirementEvaluator: the one condition engine (§53, §48).
##
## Covers every requirement type. §48 routes plant unlocks, achievements,
## expeditions and garden upgrades through this class, so a gap here is a gap in
## four features at once.

var _context: RequirementContext


func before_each() -> void:
	_context = RequirementContext.new()


func test_total_focus_minutes() -> void:
	_context.total_focus_minutes = 50.0
	var requirement := Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 100.0})
	assert_almost_eq(RequirementEvaluator.evaluate(requirement, _context), 0.5, "half way")
	assert_false(RequirementEvaluator.is_met(requirement, _context), "not met at half")

	_context.total_focus_minutes = 120.0
	assert_almost_eq(RequirementEvaluator.evaluate(requirement, _context), 1.0, "ratio is capped at 1")
	assert_true(RequirementEvaluator.is_met(requirement, _context), "met once exceeded")


func test_plant_scope_reads_plant_totals() -> void:
	# The scope switch is what lets "Monstera needs 250 minutes" mean 250 minutes
	# grown into THAT plant, not 250 minutes overall.
	_context.total_focus_minutes = 1000.0
	_context.plant_focus_minutes = 25.0
	var requirement := Requirement.make(
		Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 100.0}, Requirement.Scope.ACTIVE_PLANT
	)
	assert_almost_eq(
		RequirementEvaluator.evaluate(requirement, _context), 0.25,
		"plant scope ignores the global total"
	)


func test_completed_sessions() -> void:
	_context.completed_focus_sessions = 3
	var requirement := Requirement.make(Requirement.Type.COMPLETED_SESSIONS, {"count": 4})
	assert_almost_eq(RequirementEvaluator.evaluate(requirement, _context), 0.75, "three of four")


func test_unique_focus_days() -> void:
	# §47's Orchid: focus on 5 separate days.
	_context.unique_focus_days = PackedStringArray(["2026-01-01", "2026-01-05", "2026-02-09"])
	var requirement := Requirement.make(Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 5})
	assert_almost_eq(RequirementEvaluator.evaluate(requirement, _context), 0.6, "three of five days")


func test_consecutive_days_counts_the_longest_run() -> void:
	_context.unique_focus_days = PackedStringArray([
		"2026-03-01", "2026-03-02", "2026-03-03", "2026-03-09", "2026-03-10",
	])
	var requirement := Requirement.make(Requirement.Type.CONSECUTIVE_DAYS, {"count": 3})
	assert_true(
		RequirementEvaluator.is_met(requirement, _context),
		"a 3-day run satisfies a 3-consecutive-day requirement"
	)

	var harder := Requirement.make(Requirement.Type.CONSECUTIVE_DAYS, {"count": 4})
	assert_false(RequirementEvaluator.is_met(harder, _context), "the longest run is only 3")


func test_sessions_in_time_window() -> void:
	# §26's Early Bird: sessions before 9 AM.
	_context.sessions_by_start_hour[6] = 2
	_context.sessions_by_start_hour[8] = 3
	_context.sessions_by_start_hour[14] = 9
	var requirement := Requirement.make(
		Requirement.Type.SESSIONS_IN_TIME_WINDOW, {"count": 5, "start_hour": 0, "end_hour": 8}
	)
	assert_true(RequirementEvaluator.is_met(requirement, _context), "five morning sessions counted")


func test_time_window_wraps_past_midnight() -> void:
	# §47's Moon Cactus: evening sessions. A naive range(start, end) would count
	# nothing at all for a 20:00-02:00 window.
	_context.sessions_by_start_hour[22] = 2
	_context.sessions_by_start_hour[1] = 2
	_context.sessions_by_start_hour[12] = 50
	var requirement := Requirement.make(
		Requirement.Type.SESSIONS_IN_TIME_WINDOW, {"count": 4, "start_hour": 20, "end_hour": 2}
	)
	assert_true(RequirementEvaluator.is_met(requirement, _context), "the wrapped window counts both ends")


func test_session_length_at_least() -> void:
	# §26's Deep Work: complete a 90-minute focus session.
	_context.focus_session_lengths = PackedFloat32Array([25.0, 50.0, 95.0])
	var requirement := Requirement.make(
		Requirement.Type.SESSION_LENGTH_AT_LEAST, {"minutes": 90.0, "count": 1}
	)
	assert_true(RequirementEvaluator.is_met(requirement, _context), "one long session qualifies")


func test_break_sessions() -> void:
	_context.completed_break_sessions = 40
	var requirement := Requirement.make(Requirement.Type.BREAK_SESSIONS, {"count": 100})
	assert_almost_eq(RequirementEvaluator.evaluate(requirement, _context), 0.4, "40 of 100 breaks")


func test_plants_matured_and_species_discovered() -> void:
	_context.plants_matured = 10
	_context.species_discovered = 25
	assert_true(
		RequirementEvaluator.is_met(
			Requirement.make(Requirement.Type.PLANTS_MATURED, {"count": 10}), _context
		),
		"ten matured plants"
	)
	assert_false(
		RequirementEvaluator.is_met(
			Requirement.make(Requirement.Type.SPECIES_DISCOVERED, {"count": 50}), _context
		),
		"25 of 50 species is not complete"
	)


func test_player_level() -> void:
	_context.player_level = 8
	assert_true(
		RequirementEvaluator.is_met(
			Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 5}), _context
		),
		"level 8 satisfies a level 5 gate"
	)


func test_catalogue_completion() -> void:
	_context.species_discovered = 6
	_context.species_total = 12
	var requirement := Requirement.make(Requirement.Type.CATALOGUE_COMPLETION, {"ratio": 0.5})
	assert_true(RequirementEvaluator.is_met(requirement, _context), "half the catalogue")


func test_catalogue_completion_with_no_content() -> void:
	# Guards a divide-by-zero that would produce NaN and poison a progress bar.
	_context.species_total = 0
	var requirement := Requirement.make(Requirement.Type.CATALOGUE_COMPLETION, {"ratio": 0.5})
	assert_almost_eq(
		RequirementEvaluator.evaluate(requirement, _context), 0.0,
		"an empty catalogue is 0%, not NaN"
	)


func test_achievement_and_expedition_gates() -> void:
	_context.unlocked_achievement_ids = PackedStringArray(["first_sprout"])
	_context.completed_expedition_ids = PackedStringArray(["amazon"])
	assert_true(
		RequirementEvaluator.is_met(
			Requirement.make(
				Requirement.Type.ACHIEVEMENT_UNLOCKED, {"achievement_id": "first_sprout"}
			),
			_context
		),
		"an unlocked achievement satisfies its gate"
	)
	assert_false(
		RequirementEvaluator.is_met(
			Requirement.make(Requirement.Type.EXPEDITION_COMPLETED, {"expedition_id": "desert"}),
			_context
		),
		"an incomplete expedition does not"
	)


func test_null_requirement_is_safe() -> void:
	assert_almost_eq(RequirementEvaluator.evaluate(null, _context), 0.0, "null evaluates to zero")


func test_zero_target_is_already_met() -> void:
	# Avoids 0/0. A requirement of "focus 0 minutes" is trivially satisfied.
	var requirement := Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 0.0})
	assert_almost_eq(RequirementEvaluator.evaluate(requirement, _context), 1.0, "zero target is met")


func test_all_met_requires_every_condition() -> void:
	_context.total_focus_minutes = 100.0
	_context.player_level = 2
	var requirements: Array[Requirement] = [
		Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 50.0}),
		Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 9}),
	]
	assert_false(RequirementEvaluator.all_met(requirements, _context), "one unmet fails the set")

	var empty: Array[Requirement] = []
	assert_true(RequirementEvaluator.all_met(empty, _context), "no requirements means available")


func test_every_type_produces_a_description() -> void:
	# §74 forbids blank UI. Every requirement must render as readable text.
	for type_value in Requirement.Type.values():
		var requirement := Requirement.make(type_value, {})
		assert_ne(
			RequirementEvaluator.describe(requirement), "",
			"type %d has a description" % type_value
		)


func test_description_override_wins() -> void:
	var requirement := Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 60.0})
	requirement.description_override = "Tend it for an hour"
	assert_eq(
		RequirementEvaluator.describe(requirement), "Tend it for an hour",
		"authored copy replaces the generated text"
	)
