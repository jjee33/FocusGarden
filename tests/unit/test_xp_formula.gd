extends TestCase
## XpFormula: the single authoritative XP and level math (§53, §38).


func test_level_one_at_zero_xp() -> void:
	assert_eq(XpFormula.level_for_xp(0), 1, "a new player is level 1")
	assert_eq(XpFormula.level_for_xp(-50), 1, "negative XP cannot drop below level 1")


func test_cumulative_and_inverse_agree() -> void:
	# The closed-form inverse must land on exactly the same boundary the forward
	# formula defines, at every level — this is the property that keeps a player
	# from seeing their level flicker across a threshold.
	for level in range(1, XpFormula.MAX_LEVEL + 1):
		var required := XpFormula.cumulative_xp_for_level(level)
		assert_eq(
			XpFormula.level_for_xp(required), level,
			"exactly the XP for level %d gives level %d" % [level, level]
		)
		if level > 1:
			assert_eq(
				XpFormula.level_for_xp(required - 1), level - 1,
				"one XP short of level %d is still level %d" % [level, level - 1]
			)


func test_levels_never_decrease_with_more_xp() -> void:
	var previous := 1
	for xp in range(0, 40_000, 137):
		var level := XpFormula.level_for_xp(xp)
		assert_true(level >= previous, "level is monotonic at %d XP" % xp)
		previous = level


func test_level_is_capped() -> void:
	assert_eq(
		XpFormula.level_for_xp(999_999_999), XpFormula.MAX_LEVEL,
		"level cannot exceed the cap"
	)


func test_progress_ratio_stays_in_range() -> void:
	for xp in range(0, 20_000, 97):
		var ratio := XpFormula.level_progress_ratio(xp)
		assert_true(ratio >= 0.0 and ratio <= 1.0, "progress ratio in range at %d XP" % xp)


func test_max_level_shows_a_full_bar() -> void:
	# At the cap the level span is zero; the bar must read full, not divide by it.
	var capped := XpFormula.cumulative_xp_for_level(XpFormula.MAX_LEVEL)
	assert_almost_eq(
		XpFormula.level_progress_ratio(capped), 1.0, "a maxed player shows a full bar"
	)


func test_focus_session_earns_xp() -> void:
	var session := _session(FocusSession.Kind.FOCUS, 25.0)
	assert_eq(
		XpFormula.xp_for_session(session), int(25.0 * XpFormula.XP_PER_FOCUS_MINUTE),
		"a 25-minute focus session earns the flat per-minute rate"
	)


func test_breaks_earn_less_than_focus() -> void:
	# §25: resting is rewarded, but it must never compete with focusing.
	var focus := _session(FocusSession.Kind.FOCUS, 10.0)
	var rest := _session(FocusSession.Kind.SHORT_BREAK, 10.0)
	assert_true(
		XpFormula.xp_for_session(rest) < XpFormula.xp_for_session(focus),
		"a break earns less than the same minutes of focus"
	)


func test_cancelled_session_earns_nothing() -> void:
	var session := _session(FocusSession.Kind.FOCUS, 25.0)
	session.completion = FocusSession.Completion.CANCELLED
	assert_eq(XpFormula.xp_for_session(session), 0, "a cancelled session earns no XP")


func test_zero_length_session_earns_nothing() -> void:
	# §54 lists the zero-minute session as a case that must be defined.
	var session := _session(FocusSession.Kind.FOCUS, 0.0)
	assert_eq(XpFormula.xp_for_session(session), 0, "a zero-minute session earns no XP")


func _session(kind: FocusSession.Kind, minutes: float) -> FocusSession:
	var session := FocusSession.new()
	session.kind = kind
	session.actual_focus_minutes = minutes
	session.completion = FocusSession.Completion.COMPLETED
	return session
